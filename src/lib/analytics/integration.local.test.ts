// @vitest-environment node
/**
 * LOCAL INTEGRATION: get_student_dimension_summary (085).
 *
 * Gerçek yerel Supabase'e bağlanır (Docker zorunlu). student_dimension_metrics
 * fakt tablosuna yalnızca FİXTÜR kullanıcı satırları seed edilir; gerçek/
 * mevcut kullanıcı verisine dokunulmaz ve test sonunda tüm fixture verisi
 * silinir. RPC çağrıları gerçek servis katmanı + oturumlu istemciyle yapılır.
 */

import { execFileSync, spawnSync } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

import { createClient, type Session } from "@supabase/supabase-js"
import { afterAll, beforeAll, describe, expect, it } from "vitest"

import {
  fetchStudentAttemptTrend,
  fetchStudentDimensionSummary,
} from "./service"
import type { Database } from "@/lib/supabase/types"

const CONTAINER = "supabase_db_yarisma-programi"

// Fixture kimlikleri — TUI (99999999-*) ile çakışmaz.
const USER_A = "88888888-7777-4000-8000-000000000001"
const USER_B = "88888888-7777-4000-8000-000000000002"
const VERSION_ID = "00000000-0000-4000-8000-000000000011"
const SUBJECT_ID = "bbbbbbb1-0000-4000-8000-000000000001"
const TOPIC_ID = "bbbbbbb2-0000-4000-8000-000000000002"
const SUBTOPIC_ID = "bbbbbbb3-0000-4000-8000-000000000003"
const SUBTOPIC_ZERO_ID = "bbbbbbb4-0000-4000-8000-000000000004"
const OUTCOME_ID = "bbbbbbb5-0000-4000-8000-000000000005"
// UUID biçiminde AMA karşılığı topics'te olmayan (stale) bir anahtar.
const STALE_TOPIC_KEY = "bbbbbbba-0000-4000-8000-00000000000a"
// Trend fixture'ı için tek kullanımlık soru + deneme satırları.
const QUESTION_TREND_ID = "ccccc111-0000-4000-8000-000000000001"
const QUESTION_TREND_CODE = "ANA-Q-TREND"

/** UTC takvim günü farkını taşıyan tarih (RPC'nin UTC penceresiyle aynı eksen). */
function utcDate(offsetDays: number): string {
  const date = new Date()
  date.setUTCDate(date.getUTCDate() + offsetDays)
  return date.toISOString().slice(0, 10)
}

let apiUrl = ""
let publishableKey = ""
let serviceKey = ""
let session: Session | null = null

function readLocalConfig(): void {
  const raw = execFileSync("npx", ["supabase", "status", "-o", "env"], {
    cwd: process.cwd(),
    encoding: "utf8",
    shell: true,
  })

  const values = new Map<string, string>()
  for (const line of raw.split(/\r?\n/)) {
    const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim())
    if (match) values.set(match[1], match[2])
  }

  apiUrl = values.get("API_URL") ?? ""
  publishableKey =
    values.get("PUBLISHABLE_KEY") ?? values.get("ANON_KEY") ?? ""
  serviceKey = values.get("SERVICE_ROLE_KEY") ?? ""

  if (!apiUrl || !publishableKey || !serviceKey) {
    throw new Error("Yerel Supabase yapılandırması okunamadı.")
  }
}

function runSql(label: string, sql: string): void {
  const dir = mkdtempSync(path.join(tmpdir(), "ana-int-"))
  const file = path.join(dir, `${label}.sql`)
  writeFileSync(file, sql, "utf8")

  const copied = spawnSync(
    "docker",
    ["cp", file, `${CONTAINER}:/tmp/${label}.sql`],
    { encoding: "utf8" }
  )
  if (copied.status !== 0) {
    rmSync(dir, { recursive: true, force: true })
    throw new Error(`docker cp başarısız (${label})`)
  }

  const executed = spawnSync(
    "docker",
    [
      "exec",
      CONTAINER,
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-f",
      `/tmp/${label}.sql`,
    ],
    { encoding: "utf8" }
  )
  rmSync(dir, { recursive: true, force: true })

  if (executed.status !== 0) {
    throw new Error(
      `psql ${label} başarısız:\n${executed.stdout}\n${executed.stderr}`
    )
  }
}

function cleanupFixtures(): void {
  runSql(
    "ana_cleanup",
    `
delete from public.student_question_attempts
 where user_id in ('${USER_A}', '${USER_B}');
delete from public.questions where question_code = '${QUESTION_TREND_CODE}';
delete from public.student_dimension_metrics
 where user_id in ('${USER_A}', '${USER_B}');
delete from public.curriculum_outcomes where id = '${OUTCOME_ID}' or subject_id = '${SUBJECT_ID}';
delete from public.subtopics where id in ('${SUBTOPIC_ID}', '${SUBTOPIC_ZERO_ID}');
delete from public.topics where id = '${TOPIC_ID}' or subject_id = '${SUBJECT_ID}';
delete from public.subjects where id = '${SUBJECT_ID}' or slug like 'ana-%';
delete from public.curriculum_versions where id = '${VERSION_ID}';
delete from public.student_profiles where id in ('${USER_A}', '${USER_B}');
delete from auth.users where id in ('${USER_A}', '${USER_B}');
`
  )
}

async function adminCreateUser(
  id: string,
  email: string,
  password: string
): Promise<void> {
  const response = await fetch(`${apiUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      id,
      email,
      password,
      email_confirm: true,
      user_metadata: { nickname: `ANA-NICK-${id.slice(-4)}`, grade_level: 12 },
    }),
  })
  if (!response.ok) {
    throw new Error(`admin kullanıcı oluşturulamadı: ${await response.text()}`)
  }
}

function insertFixtures(): void {
  runSql(
    "ana_fixture",
    `
-- Müfredat satırları (join hedefleri).
insert into public.curriculum_versions (id, academic_year, framework, is_active)
values ('${VERSION_ID}', '2025-2026', 'ANA-MEB', true);

insert into public.subjects (id, name, slug, sort_order, is_active)
values ('${SUBJECT_ID}', 'ANA-Ders', 'ana-ders', 1, true);

insert into public.topics (id, subject_id, grade_level, name, slug, curriculum_version_id)
values ('${TOPIC_ID}', '${SUBJECT_ID}', 12, 'ANA-Konu', 'ana-konu', '${VERSION_ID}');

insert into public.subtopics (id, topic_id, name, slug)
values ('${SUBTOPIC_ID}', '${TOPIC_ID}', 'ANA-Alt', 'ana-alt'),
       ('${SUBTOPIC_ZERO_ID}', '${TOPIC_ID}', 'ANA-Sifir', 'ana-sifir');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, grade_level, subject_id, outcome_text)
values ('${OUTCOME_ID}', '${VERSION_ID}', 12,
        '${SUBJECT_ID}', 'ANA-kazanim');

-- Öğrenci A: subject (gerçek + malformed/key).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_A}', 'subject', '${SUBJECT_ID}', 10, 7, 2, 1, 0, 4, 3,
   60000, '2026-08-01T10:00:00.000Z'),
  ('${USER_A}', 'subject', 'bozuk-key', 5, 5, 0, 0, 0, 2, 2,
   30000, '2026-08-02T10:00:00.000Z');

-- Öğrenci A: topic (gerçek + stale — joined olmayan uuid anahtarı).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_A}', 'topic', '${TOPIC_ID}', 8, 6, 1, 1, 0, 2, 1,
   40000, '2026-08-03T10:00:00.000Z'),
  ('${USER_A}', 'topic', '${STALE_TOPIC_KEY}', 3, 1, 1, 1, 0, 0, 0,
   9000, '2026-08-04T10:00:00.000Z');

-- Öğrenci A: subtopic (gerçek + sıfır payda).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_A}', 'subtopic', '${SUBTOPIC_ID}', 6, 4, 2, 0, 0, 3, 2,
   24000, '2026-08-05T10:00:00.000Z'),
  ('${USER_A}', 'subtopic', '${SUBTOPIC_ZERO_ID}', 0, 0, 0, 0, 0, 0, 0,
   0, '2026-08-06T10:00:00.000Z');

-- Öğrenci A: outcome (gerçek).
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_A}', 'outcome', '${OUTCOME_ID}', 4, 4, 0, 0, 0, 1, 1,
   12000, '2026-08-07T10:00:00.000Z');

-- RPC taramaması gereken: difficulty scope satırı.
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_A}', 'difficulty', 'easy', 99, 99, 0, 0, 0, 0, 0, 99000, null);

-- Öğrenci B: sızıntı sınayıcı satır.
insert into public.student_dimension_metrics
  (user_id, metric_scope, scope_key, total_attempts, correct_count,
   wrong_count, blank_count, pass_timeout_count, repeat_total,
   repeat_correct, total_time_ms, last_attempted_at)
values
  ('${USER_B}', 'subject', '${SUBJECT_ID}', 999, 500, 400, 99, 0, 0, 0,
   111000, null);

-- Trend fixture: tek soru + A için UTC tarih bağımlı deneme olayları.
insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type,
   question_text, option_a, option_b, option_c, option_d, option_e,
   correct_answer, estimated_solve_time_seconds, legacy_question_key)
values
  ('${QUESTION_TREND_ID}', '${QUESTION_TREND_CODE}', 12, '${SUBJECT_ID}',
   'approved', true, 'easy', 'learning', 'coktan_secmeli',
   'ANA-TREND: 1+1 kactir?', '1', '2', '3', '4', '5',
   'B', 30, null);

insert into public.student_question_attempts
  (user_id, question_id, subject_id, attempt_context, result,
   attempt_number, time_ms, academic_year, week, answered_at)
values
  -- Bugün: 4 deneme (2 doğru, 1 yanlış, 1 pas). NULL time_ms 0 sayılır.
  -- UTC gün sınırı: 00:10 bu güne, önceki gün 23:50 önceki güne düşer.
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'correct',
   1, 2500, 'ANA-YR', 1, '${utcDate(0)} 00:10:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'correct',
   1, 2000, 'ANA-YR', 1, '${utcDate(0)} 10:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'wrong',
   1, 4000, 'ANA-YR', 1, '${utcDate(0)} 11:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'pass',
   1, null, 'ANA-YR', 1, '${utcDate(0)} 12:00:00+00'),
  -- Dün: 2 deneme (1 boş, 1 zaman-aşımı).
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'blank',
   1, 500, 'ANA-YR', 1, '${utcDate(-1)} 23:50:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'timeout',
   1, 1500, 'ANA-YR', 1, '${utcDate(-1)} 10:00:00+00'),
  -- Sınırlar: today-6 (7 günlük pencerede), today-7 (yalnız 30'da),
  -- today-29 (30'da), today-30 (dışarıda), today+1 (gelecek, dışarıda).
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'correct',
   1, 1000, 'ANA-YR', 1, '${utcDate(-6)} 09:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'wrong',
   1, 1000, 'ANA-YR', 1, '${utcDate(-7)} 09:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'correct',
   1, 900, 'ANA-YR', 1, '${utcDate(-29)} 09:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'wrong',
   1, 800, 'ANA-YR', 1, '${utcDate(-30)} 09:00:00+00'),
  ('${USER_A}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'correct',
   1, 1000, 'ANA-YR', 1, '${utcDate(1)} 09:00:00+00'),
  -- Öğrenci B: A'nın penceresine SIZMAMASI gereken bugünkü satır.
  ('${USER_B}', '${QUESTION_TREND_ID}', '${SUBJECT_ID}', 'training', 'wrong',
   1, 99999, 'ANA-YR', 1, '${utcDate(0)} 15:00:00+00');
`
  )
}

beforeAll(async () => {
  readLocalConfig()
  cleanupFixtures()
  await adminCreateUser(USER_A, "ana-student-a@test.local", "Ana-Test-A-1234!")
  await adminCreateUser(USER_B, "ana-student-b@test.local", "Ana-Test-B-1234!")
  insertFixtures()

  const authClient = createClient<Database>(apiUrl, publishableKey)
  const { data, error } = await authClient.auth.signInWithPassword({
    email: "ana-student-a@test.local",
    password: "Ana-Test-A-1234!",
  })
  if (error || !data.session) {
    throw new Error(`test girişi başarısız: ${error?.message ?? "oturum yok"}`)
  }
  session = data.session
})

afterAll(() => {
  cleanupFixtures()
})

function authenticatedServiceClient() {
  if (!session) throw new Error("oturum yok")
  const client = createClient<Database>(apiUrl, publishableKey, {
    global: { headers: { Authorization: `Bearer ${session.access_token}` } },
  })
  return client
}

describe("get_student_dimension_summary — gerçek RPC", () => {
  it(
    "oturumlu öğrenci yalnızca kendi 4 kapsam satırlarını alır, sızıntı/sarmalama yok",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      // difficulty scope + Y kullanıcısı satırı dışarıda; subject 2,
      // topic 2, subtopic 2, outcome 1.
      expect(rows).toHaveLength(7)
      // Runtime drift koruması: tip garanti etse de "difficulty" kapsamı
      // satırının gerçek cevapta OLMADIĞINI doğrula.
      expect(
        rows.some((r) => (r.scopeType as string) === "difficulty")
      ).toBe(false)
      expect(rows.some((r) => r.total === 999)).toBe(false)
    }
  )

  it(
    "subject join + oran hesapları (0..100)",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      const real = rows.find(
        (r) => r.scopeType === "subject" && r.scopeKey === SUBJECT_ID
      )
      expect(real).toMatchObject({
        displayName: "ANA-Ders",
        subjectId: SUBJECT_ID,
        subjectName: "ANA-Ders",
        total: 10,
        correct: 7,
        wrong: 2,
        blank: 1,
        passTimeout: 0,
        repeatTotal: 4,
        repeatCorrect: 3,
        totalTimeMs: 60000,
        successRate: 70,
        repeatSuccessRate: 75,
        avgTimeMs: 6000,
        lastAttemptedAt: "2026-08-01T10:00:00.000Z",
      })
    }
  )

  it(
    "malformed scope_key RPC'yi düşürmez, fallback display_name ile döner",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      const malformed = rows.find(
        (r) => r.scopeType === "subject" && r.scopeKey === "bozuk-key"
      )
      expect(malformed).toMatchObject({
        displayName: "bozuk-key",
        subjectId: null,
        subjectName: null,
        successRate: 100,
      })
    }
  )

  it(
    "stale uuid scope_key tüm sonucu düşürmez, fallback ile döner",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      const stale = rows.find(
        (r) => r.scopeType === "topic" && r.scopeKey === STALE_TOPIC_KEY
      )
      expect(stale).toMatchObject({
        displayName: STALE_TOPIC_KEY,
        subjectId: null,
        subjectName: null,
        successRate: 33.3,
        avgTimeMs: 3000,
      })
    }
  )

  it(
    "topic / subtopic / outcome join'leri subject adını doğru çözer",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      const topic = rows.find(
        (r) => r.scopeType === "topic" && r.scopeKey === TOPIC_ID
      )
      expect(topic?.displayName).toBe("ANA-Konu")
      expect(topic?.subjectName).toBe("ANA-Ders")

      const subtopic = rows.find(
        (r) => r.scopeType === "subtopic" && r.scopeKey === SUBTOPIC_ID
      )
      expect(subtopic?.displayName).toBe("ANA-Alt")
      expect(subtopic?.subjectName).toBe("ANA-Ders")
      expect(subtopic?.successRate).toBe(66.7)

      const outcome = rows.find(
        (r) => r.scopeType === "outcome" && r.scopeKey === OUTCOME_ID
      )
      expect(outcome?.displayName).toBe("ANA-kazanim")
      expect(outcome?.subjectName).toBe("ANA-Ders")
      expect(outcome?.successRate).toBe(100)
    }
  )

  it(
    "sıfır payda deterministik 0 döner (RPC çökmez)",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentDimensionSummary(
        authenticatedServiceClient()
      )

      const zero = rows.find(
        (r) =>
          r.scopeType === "subtopic" && r.scopeKey === SUBTOPIC_ZERO_ID
      )
      expect(zero).toMatchObject({
        displayName: "ANA-Sifir",
        total: 0,
        successRate: 0,
        repeatSuccessRate: 0,
        avgTimeMs: 0,
      })
    }
  )
})

describe("get_student_dimension_summary — güvenlik", () => {
  it(
    "kimliksiz (anon) erişim güvenli AnalyticsError'a düşer",
    { timeout: 120_000 },
    async () => {
      const anonClient = createClient<Database>(apiUrl, publishableKey)
      await expect(
        fetchStudentDimensionSummary(anonClient)
      ).rejects.toThrow("Oturumunuz doğrulanamadı")
    }
  )

  it(
    "başka kullanıcı verisi değişmez (yalnızca okuma, sızıntı yok)",
    { timeout: 120_000 },
    async () => {
      await fetchStudentDimensionSummary(authenticatedServiceClient())

      // Öğrenci B'nin satırı hâlâ aynı ve dokunulmadı.
      runSql(
        "ana_b_intact",
        `
do $$
declare v_total integer;
begin
  select total_attempts into v_total
    from public.student_dimension_metrics
   where user_id = '${USER_B}' and metric_scope = 'subject'
     and scope_key = '${SUBJECT_ID}';
  if v_total <> 999 then raise exception 'B verisi değişti: %', v_total; end if;
end $$;
`
      )
    }
  )
})

describe("get_student_attempt_trend — gerçek RPC", () => {
  it(
    "7 gün kesintisiz 7 satır; bugün dahil; günlük gruplama + oranlar",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        7
      )

      expect(rows).toHaveLength(7)
      // Azalana doğru: today, today-1, ..., today-6.
      expect(rows[0]?.day).toBe(utcDate(0))
      expect(rows[1]?.day).toBe(utcDate(-1))
      expect(rows[6]?.day).toBe(utcDate(-6))

      expect(rows[0]).toMatchObject({
        day: utcDate(0),
        total: 4,
        correct: 2,
        wrong: 1,
        blank: 0,
        passTimeout: 1,
        successRate: 50,
      })
      expect(rows[1]).toMatchObject({
        day: utcDate(-1),
        total: 2,
        blank: 1,
        passTimeout: 1,
        successRate: 0,
      })
      expect(rows[6]).toMatchObject({
        day: utcDate(-6),
        total: 1,
        correct: 1,
        successRate: 100,
      })
    }
  )

  it(
    "7 gün sınırları: today-6 dahil, today-7 / today-30 / today+1 hariç",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        7
      )
      const days = rows.map((r) => r.day)
      expect(days).toContain(utcDate(-6))
      expect(days).not.toContain(utcDate(-7))
      expect(days).not.toContain(utcDate(-30))
      expect(days).not.toContain(utcDate(1))
    }
  )

  it(
    "30 gün kesintisiz 30 satır; today-29 dahil, today-30 / today+1 hariç",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        30
      )

      expect(rows).toHaveLength(30)
      expect(rows[0]?.day).toBe(utcDate(0))
      expect(rows[29]?.day).toBe(utcDate(-29))

      const days = rows.map((r) => r.day)
      expect(days).not.toContain(utcDate(-30))
      expect(days).not.toContain(utcDate(1))

      // Pencere içindeki dengeli günler (today-7, today-29) doğru sayılır.
      expect(rows[7]).toMatchObject({
        day: utcDate(-7),
        total: 1,
        wrong: 1,
        successRate: 0,
      })
      expect(rows[29]).toMatchObject({
        day: utcDate(-29),
        total: 1,
        correct: 1,
        successRate: 100,
      })
    }
  )

  it(
    "UTC gün sınırı: 23:50 önceki güne, 00:10 bu güne düşer",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        7
      )
      // Dünün UTC sonuna yakın blank, dünün bucket'ında (dün total 2).
      expect(rows[1]).toMatchObject({
        day: utcDate(-1),
        total: 2,
        blank: 1,
        passTimeout: 1,
      })
      // Bugün 00:10'daki correct bugünün bucket'ında (bugün total 4, c 2).
      expect(rows[0]).toMatchObject({
        day: utcDate(0),
        total: 4,
        correct: 2,
      })
    }
  )

  it(
    "NULL time_ms 0 sayılır; günlük avg_time_ms doğru",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        30
      )

      const today = rows.find((r) => r.day === utcDate(0))
      // (2500 + 2000 + 4000 + 0) / 4 = 2125; pas NULL'ü 0 sayıldı.
      expect(today?.avgTimeMs).toBe(2125)

      const yesterday = rows.find((r) => r.day === utcDate(-1))
      // (500 + 1500) / 2 = 1000.
      expect(yesterday?.avgTimeMs).toBe(1000)

      const edge = rows.find((r) => r.day === utcDate(-29))
      expect(edge?.avgTimeMs).toBe(900)
    }
  )

  it(
    "öğrenci verisi sızıntısı yok: B'nin bugünkü satırı A'da görünmez",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        30
      )
      // B eklenseydi bugün total 5 olurdu; A yalnız kendi satırlarını görür.
      expect(rows[0]?.total).toBe(4)
      expect(rows.some((r) => r.total >= 5)).toBe(false)
    }
  )

  it(
    "sıfır günler 0-satır döner (grafik boşluksuz çizer)",
    { timeout: 120_000 },
    async () => {
      const rows = await fetchStudentAttemptTrend(
        authenticatedServiceClient(),
        7
      )
      // today-2 → today-5 arası hiç deneme yok; hepsi 0-satır.
      for (const offset of [-2, -3, -4, -5]) {
        const row = rows.find((r) => r.day === utcDate(offset))
        expect(row).toMatchObject({
          day: utcDate(offset),
          total: 0,
          correct: 0,
          wrong: 0,
          blank: 0,
          passTimeout: 0,
          successRate: 0,
          avgTimeMs: 0,
        })
      }
    }
  )
})

describe("get_student_attempt_trend — güvenlik", () => {
  it(
    "kimliksiz (anon) erişim güvenli AnalyticsError'a düşer",
    { timeout: 120_000 },
    async () => {
      const anonClient = createClient<Database>(apiUrl, publishableKey)
      await expect(
        fetchStudentAttemptTrend(anonClient, 7)
      ).rejects.toThrow("Oturumunuz doğrulanamadı")
    }
  )
})