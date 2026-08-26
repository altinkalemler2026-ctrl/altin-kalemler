// @vitest-environment node
/**
 * LOCAL INTEGRATION: giriş yapan öğrenci -> ders -> soru -> cevap -> özet.
 *
 * Gerçek yerel Supabase'e bağlanır (Docker zorunlu). Akış servis katmanı
 * üzerinden GERÇEK RPC'lerle yürütülür; test sonunda tüm veri SİLİNİR.
 */

import { execFileSync, spawnSync } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

import { createClient, type Session } from "@supabase/supabase-js"
import { afterAll, beforeAll, expect, it } from "vitest"

import {
  fetchWeeklyUsage,
  listTrainingSubjects,
  selectTrainingQuestions,
  submitTrainingAttempt,
} from "./service"
import type { Database } from "@/lib/supabase/types"

const CONTAINER = "supabase_db_yarisma-programi"
const YEAR = "TUI-Y-2098"
const SECRET_SENTINEL = "TUI-GIZLI-DOGRU-CEVAP"

const USER_ID = "99999999-8888-4000-8000-000000000901"
const SUBJECT_ID = "aaaaaaa1-0000-4000-8000-000000000001"
const VERSION_ID = "aaaaaaa2-0000-4000-8000-000000000002"
const PROFILE_ID = "aaaaaaa3-0000-4000-8000-000000000003"
const TOPIC_ID = "aaaaaaa4-0000-4000-8000-000000000004"
const SUBTOPIC_ID = "aaaaaaa5-0000-4000-8000-000000000005"
const OUTCOME_ID = "aaaaaaa6-0000-4000-8000-000000000006"
const VAULT_ID = "aaaaaaa7-0000-4000-8000-000000000007"
const QUESTION_IDS = [
  "aaaaaaa9-0000-4000-8000-000000000001",
  "aaaaaaa9-0000-4000-8000-000000000002",
  "aaaaaaa9-0000-4000-8000-000000000003",
  "aaaaaaa9-0000-4000-8000-000000000004",
  "aaaaaaa9-0000-4000-8000-000000000005",
]

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
  const dir = mkdtempSync(path.join(tmpdir(), "tui-int-"))
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
    "tui_cleanup",
    `
delete from public.student_question_attempts where user_id = '${USER_ID}';
delete from public.student_question_exposures where user_id = '${USER_ID}';
delete from public.student_pack_exposures where user_id = '${USER_ID}';
delete from public.student_dimension_metrics where user_id = '${USER_ID}';
delete from public.student_weekly_counters where user_id = '${USER_ID}';
delete from public.question_outcome_mappings where question_id::text like 'aaaaaaa9%';
delete from public.question_curriculum_mappings where question_id::text like 'aaaaaaa9%';
delete from public.question_vault_memberships where vault_id = '${VAULT_ID}';
delete from public.question_vaults where id = '${VAULT_ID}' or vault_code like 'TUI-%';
delete from public.questions where question_code like 'TUI-%';
delete from public.curriculum_schedule_items where schedule_profile_id = '${PROFILE_ID}';
delete from public.subtopics where id = '${SUBTOPIC_ID}';
delete from public.topics where id = '${TOPIC_ID}';
delete from public.curriculum_outcomes where id = '${OUTCOME_ID}';
delete from public.academic_weeks where academic_year = '${YEAR}';
delete from public.student_profiles where id = '${USER_ID}';
delete from public.curriculum_schedule_profiles where id = '${PROFILE_ID}';
delete from public.curriculum_versions where id = '${VERSION_ID}';
delete from public.subjects where id = '${SUBJECT_ID}' or slug like 'tui-%';
delete from auth.users where id = '${USER_ID}';
`
  )
}

async function adminCreateUser(email: string, password: string): Promise<void> {
  const response = await fetch(`${apiUrl}/auth/v1/admin/users`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      id: USER_ID,
      email,
      password,
      email_confirm: true,
      user_metadata: { nickname: "TUI-NICK", grade_level: 12 },
    }),
  })
  if (!response.ok) {
    throw new Error(`admin kullanıcı oluşturulamadı: ${await response.text()}`)
  }
}

async function insertFixtures(): Promise<void> {
  const q = QUESTION_IDS
  runSql(
    "tui_fixture",
    `
insert into public.subjects (id, name, slug, sort_order, is_active)
values ('${SUBJECT_ID}', 'TUI Ders', 'tui-ders', 1, true);

insert into public.curriculum_versions (id, academic_year, framework, is_active)
values ('${VERSION_ID}', '${YEAR}', 'TUI-MEB', true);

insert into public.curriculum_schedule_profiles
  (id, code, name, curriculum_version_id, is_default, is_active)
values ('${PROFILE_ID}', 'TUI-SCHED', 'TUI Profil', '${VERSION_ID}', true, true);

insert into public.student_profiles (id, grade_level, nickname)
values ('${USER_ID}', 12, 'TUI-NICK')
on conflict (id) do nothing;

insert into public.academic_weeks (academic_year, week, starts_at, ends_at)
values ('${YEAR}', 5, current_date - 3, current_date + 4);

insert into public.topics (id, subject_id, grade_level, name, slug, curriculum_version_id)
values ('${TOPIC_ID}', '${SUBJECT_ID}', 12, 'TUI Konu', 'tui-konu', '${VERSION_ID}');

insert into public.subtopics (id, topic_id, name, slug)
values ('${SUBTOPIC_ID}', '${TOPIC_ID}', 'TUI Alt', 'tui-alt');

insert into public.curriculum_outcomes
  (id, curriculum_version_id, grade_level, subject_id, outcome_text)
values ('${OUTCOME_ID}', '${VERSION_ID}', 12, '${SUBJECT_ID}', 'TUI kazanim');

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, topic_id, start_week, end_week) values
  ('${PROFILE_ID}', 12, '${SUBJECT_ID}', '${TOPIC_ID}', 1, 3);

insert into public.curriculum_schedule_items
  (schedule_profile_id, grade_level, subject_id, outcome_id, start_week) values
  ('${PROFILE_ID}', 12, '${SUBJECT_ID}', '${OUTCOME_ID}', 2);

insert into public.questions
  (id, question_code, grade_level, subject_id, approval_status, is_active,
   difficulty, cognitive_type, primary_question_type,
   question_text, option_a, option_b, option_c, option_d, option_e,
   correct_answer, estimated_solve_time_seconds, legacy_question_key)
values
  ('${q[0]}', 'TUI-Q1', 12, '${SUBJECT_ID}', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   'TUI: Türkiye''nin başkenti hangisidir?',
   'İstanbul', 'Ankara', 'İzmir', 'Bursa', 'Adana',
   'B', 30, '${SECRET_SENTINEL}-Q1'),
  ('${q[1]}', 'TUI-Q2', 12, '${SUBJECT_ID}', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   'TUI: 2+2 kaçtır?', '3', '4', '5', '6', '7',
   'B', 20, '${SECRET_SENTINEL}-Q2'),
  ('${q[2]}', 'TUI-Q3', 12, '${SUBJECT_ID}', 'approved', true,
   'medium', 'application', 'coktan_secmeli',
   'TUI: en büyük gezegen?', 'Merkür', 'Venüs', 'Jüpiter', 'Mars', 'Dünya',
   'C', 25, '${SECRET_SENTINEL}-Q3'),
  ('${q[3]}', 'TUI-Q4', 12, '${SUBJECT_ID}', 'approved', true,
   'hard', 'comprehension', 'dogru_yanlis',
   'TUI: boş soru denemesi', 'a', 'b', 'c', 'd', 'e',
   'A', 15, '${SECRET_SENTINEL}-Q4'),
  ('${q[4]}', 'TUI-Q5', 12, '${SUBJECT_ID}', 'approved', true,
   'easy', 'learning', 'coktan_secmeli',
   'TUI: pas sorusu', '1', '2', '3', '4', '5',
   'E', 10, '${SECRET_SENTINEL}-Q5');

insert into public.question_curriculum_mappings
  (question_id, curriculum_version_id, topic_id, subtopic_id, review_status)
select x.qid, '${VERSION_ID}', '${TOPIC_ID}',
       case when x.qid = '${q[0]}' then '${SUBTOPIC_ID}'::uuid else null::uuid end,
       'approved'
from unnest(array['${q[0]}','${q[1]}','${q[2]}','${q[3]}','${q[4]}']::uuid[]) as x(qid);

insert into public.question_outcome_mappings (question_id, outcome_id, review_status)
values ('${q[4]}', '${OUTCOME_ID}', 'approved');

insert into public.question_vaults
  (id, vault_code, name, vault_type, grade_level, subject_id)
values ('${VAULT_ID}', 'TUI-V-PRACTICE', 'TUI Kasa', 'practice', 12, '${SUBJECT_ID}');

insert into public.question_vault_memberships
  (vault_id, question_id, membership_status, practice_eligible)
select '${VAULT_ID}', x.qid, 'active', true
from unnest(array['${q[0]}','${q[1]}','${q[2]}','${q[3]}','${q[4]}']::uuid[]) as x(qid);
`
  )
}

beforeAll(async () => {
  readLocalConfig()
  cleanupFixtures()
  await adminCreateUser("tui-student@test.local", "Tui-Test-1234!")
  await insertFixtures()

  const authClient = createClient<Database>(apiUrl, publishableKey)
  const { data, error } = await authClient.auth.signInWithPassword({
    email: "tui-student@test.local",
    password: "Tui-Test-1234!",
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

it(
  "girişli öğrenci -> ders -> soru -> cevap -> özet akışı (gerçek RPC)",
  { timeout: 120_000 },
  async () => {
    const client = authenticatedServiceClient()

    // 1) Ders seçimi: aktif ders listelensin.
    const subjects = await listTrainingSubjects(client)
    expect(subjects.some((s) => s.id === SUBJECT_ID)).toBe(true)

    // 2) Soru kuyruğu: gerçek RPC; gizli alan sızmaz.
    const selection = await selectTrainingQuestions(client, SUBJECT_ID, 10)
    expect(selection.questions).toHaveLength(5)
    expect(selection.weekly.newQuestionsUsed).toBe(5)
    expect(selection.reason).toBeNull()
    const serialized = JSON.stringify(selection)
    expect(serialized).not.toContain(SECRET_SENTINEL)
    expect(serialized).not.toContain("correct_answer")

    // 3) Doğru cevap: Q2'nin doğrusu B (fikstürde biliyoruz).
    const q2 = selection.questions.find((item) => item.questionCode === "TUI-Q2")
    expect(q2).toBeDefined()
    const clientKeyQ2 = crypto.randomUUID()
    const first = await submitTrainingAttempt(client, {
      questionId: q2!.id,
      choice: "B",
      timeMs: 12_345,
      clientKey: clientKeyQ2,
    })
    expect(first).toMatchObject({
      result: "correct",
      duplicate: false,
      attemptNumber: 1,
    })

    // 4) Aynı key ile yeniden gönderim: duplicate:true, attempt değişmez.
    const retry = await submitTrainingAttempt(client, {
      questionId: q2!.id,
      choice: "B",
      timeMs: 15_000,
      clientKey: clientKeyQ2,
    })
    expect(retry.duplicate).toBe(true)
    expect(retry.attemptId).toBe(first.attemptId)
    expect(retry.attemptNumber).toBe(1)

    // 5) Yanlış cevap ayrı soruda 'wrong' döner.
    const q3 = selection.questions.find((item) => item.questionCode === "TUI-Q3")
    const wrong = await submitTrainingAttempt(client, {
      questionId: q3!.id,
      choice: "A",
      timeMs: 5_000,
      clientKey: crypto.randomUUID(),
    })
    expect(wrong.result).toBe("wrong")
    expect(wrong.duplicate).toBe(false)

    // 6) pas / boş / timeout aksiyonları.
    const pass = await submitTrainingAttempt(client, {
      questionId: selection.questions[0]!.id,
      action: "pass",
      timeMs: 1_000,
      clientKey: crypto.randomUUID(),
    })
    expect(pass.result).toBe("pass")

    const blank = await submitTrainingAttempt(client, {
      questionId: selection.questions[3]!.id,
      action: "blank",
      timeMs: 2_000,
      clientKey: crypto.randomUUID(),
    })
    expect(blank.result).toBe("blank")

    const timedOut = await submitTrainingAttempt(client, {
      questionId: selection.questions[4]!.id,
      action: "timeout",
      timeMs: 30_000,
      clientKey: crypto.randomUUID(),
    })
    expect(timedOut.result).toBe("timeout")

    // 7) Haftalık kullanım görünümü gerçek sayaçları gösterir.
    const usage = await fetchWeeklyUsage(client)
    expect(usage.academicYear).toBe(YEAR)
    const subjectUsage = usage.subjects.find(
      (item) => item.subjectId === SUBJECT_ID
    )
    expect(subjectUsage?.newQuestionsUsed).toBe(5)

    // 8) Özet: 5 deneme kaydedilmiş olmalı (duplicate ikinci attempt yaratmadı).
    runSql(
      "tui_assert",
      `
do $$
declare v_count integer;
begin
  select count(*) into v_count from public.student_question_attempts
   where user_id = '${USER_ID}';
  if v_count <> 5 then raise exception 'beklenen 5 attempt, bulunan %', v_count; end if;
end $$;
`
    )
  }
)

it("test verisi temizlenir — kalıntı sıfır", async () => {
  cleanupFixtures()

  // FK kaskadları / auth silme işlemleri eşzamansız yayılabilir; kısa bir
  // yeniden deneme penceresi ile nihai durumu doğrula.
  let residue = ""
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const check = spawnSync(
      "docker",
      [
        "exec",
        CONTAINER,
        "psql",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-tA",
        "-c",
        `select
          (select count(*) from public.student_question_attempts where user_id='${USER_ID}') +
          (select count(*) from public.student_question_exposures where user_id='${USER_ID}') +
          (select count(*) from public.student_weekly_counters where user_id='${USER_ID}') +
          (select count(*) from public.questions where question_code like 'TUI-%') +
          (select count(*) from public.subjects where slug like 'tui-%') +
          (select count(*) from public.academic_weeks where academic_year='${YEAR}') +
          (select count(*) from auth.users where id='${USER_ID}');`,
      ],
      { encoding: "utf8" }
    )
    expect(check.status).toBe(0)
    residue = check.stdout.trim()
    if (residue === "0") break
    await new Promise((resolve) => setTimeout(resolve, 500))
  }
  expect(residue).toBe("0")
})
