// @vitest-environment node
/**
 * LOCAL INTEGRATION: UI-P2C — aday karar RPC uçtan uca kanıtı.
 *
 * Gerçek yerel Supabase'e bağlanır (Docker zorunlu). UI-P2A action
 * katmanının gerçek migration 130 sözleşmesiyle uyumu şunları kanıtlar:
 *
 *  C  Yalnız doğrulanmış public giriş noktası kullanılır
 *     (public.review_and_promote_ai_question); private şema REST'te
 *     görünmez; istemci akışı service_role İÇERMEZ.
 *  C  Gerçek detay RPC'si + gerçek üretim eşleyicisi
 *     (mapCandidate) + gerçek türetme (deriveCandidateDecisionAvailability)
 *     validating adayda ÜÇ kararı da kapatır; sunucu yeniden türetmesi
 *     istemciden sahte veriyle atlatılamaz (client yalnız kimlik/karar/gerekçe
 *     gönderir; uygunluk DB'den yeniden okunur).
 *  A  readiness tamamlanmış adayda approve gerçek sözleşmeye göre promoted
 *     döner; questions'a is_active=false ile yazılır (publish YOK); tam olarak
 *     1 final_review + 1 audit; ikinci approve already_promoted + yeni audit YOK.
 *  A  request_changes boş gerekçeyle DB'den kabul edilir (UI katmanı daha
 *     katidir ve RPC'ye hiç gitmez); tekrar çağrı idempotent_replay=true,
 *     AYNI final_review_id, YENİ audit YOK.
 *  A  reject gerekçeyle rejected döner; terminal durumda approve P0001.
 *  B  oturumsuz/öğrenci/yetersiz admin/geçersiz karar/olmayan aday —
 *     hepsi fail-closed; gerçek PostgREST hata nesnesi Türkçe eşleyiciye
 *     verildiğinde ham DB metni KULLANICI MESAJINA SIZMAZ.
 *
 * Ortam: E2E_DB_CONTAINER + E2E_API_URL/E2E_ANON_KEY/E2E_SERVICE_KEY
 * (disposable) veya ana yerel stack (CI). Test verileri suite'in kendi
 * UUID uzayındadır ve afterAll'da silinir.
 */

import { execFileSync, spawnSync } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

import { createClient, type Session } from "@supabase/supabase-js"
import { afterAll, beforeAll, expect, it } from "vitest"

import { deriveCandidateDecisionAvailability, validateDecisionInput } from "./candidate-decisions"
import { mapCandidate, mapCandidateBatchListItem } from "./candidate-batches"
import { mapCandidateDecisionError } from "./candidate-decisions-errors"

const CONTAINER = process.env.E2E_DB_CONTAINER ?? "supabase_db_yarisma-programi"

// Sabit UUID uzayı: bu suite'e özgü (qa_faz35 'b35...' uzayından ayrık).
const ADMIN_UID = "b35c0000-0000-0000-0000-000000000001"
const WRONG_UID = "b35c0000-0000-0000-0000-000000000002"
const STUDENT_UID = "b35c0000-0000-0000-0000-000000000003"
const SUBJECT_ID = "71191e01-220a-4682-9351-3d62631308d2" // migration zincirinde yüklü (biyoloji)
const BATCH_ID = "b35c0000-0000-0000-0000-000000000010"

// Adaylar:
//   VAL   validating + kapılar verified, readiness YOK  -> UI: üç karar kapalı
//   READY validating + kapılar verified + readiness OK + needs_review -> UI: approve açık; RPC: promoted
//   RC    needs_review + readiness OK -> request_changes + idempotency
//   RJ    needs_review + readiness OK -> reject + terminal
const SID_VAL = "b35c0000-0000-0000-0000-0000000000a1"
const SID_READY = "b35c0000-0000-0000-0000-0000000000a2"
const SID_RC = "b35c0000-0000-0000-0000-0000000000a3"
const SID_RJ = "b35c0000-0000-0000-0000-0000000000a4"
const SID_NONEXISTENT = "b35c0000-0000-0000-0000-0000000000ef"

let apiUrl = ""
let publishableKey = ""
let serviceKey = ""
let shouldSkip = false

let adminSession: Session | null = null
let studentSession: Session | null = null

function supabaseStatusEnv(): string {
  try {
    return execFileSync("supabase", ["status", "-o", "env"], {
      cwd: process.cwd(),
      encoding: "utf8",
      timeout: 60_000,
    })
  } catch {
    return execFileSync(
      "npx",
      ["supabase", "status", "-o", "env"],
      { cwd: process.cwd(), encoding: "utf8", shell: true, timeout: 60_000 }
    )
  }
}

function readLocalConfig(): void {
  if (
    process.env.E2E_API_URL &&
    process.env.E2E_ANON_KEY &&
    process.env.E2E_SERVICE_KEY
  ) {
    apiUrl = process.env.E2E_API_URL
    publishableKey = process.env.E2E_ANON_KEY
    serviceKey = process.env.E2E_SERVICE_KEY
    return
  }
  try {
    const raw = supabaseStatusEnv()
    const values = new Map<string, string>()
    for (const line of raw.split(/\r?\n/)) {
      const match = /^([A-Z_]+)="?(.*?)"?$/.exec(line.trim())
      if (match) values.set(match[1], match[2])
    }
    apiUrl = values.get("API_URL") ?? ""
    publishableKey =
      values.get("PUBLISHABLE_KEY") ?? values.get("ANON_KEY") ?? ""
    serviceKey = values.get("SERVICE_ROLE_KEY") ?? ""
  } catch {
    shouldSkip = true
    apiUrl = ""
    return
  }
  if (!apiUrl || !publishableKey || !serviceKey) shouldSkip = true
}

function runSql(label: string, sql: string): void {
  const dir = mkdtempSync(path.join(tmpdir(), "p2c-int-"))
  const file = path.join(dir, `${label}.sql`)
  writeFileSync(file, sql, "utf8")

  const copied = spawnSync(
    "docker",
    ["cp", file, `${CONTAINER}:/tmp/${label}.sql`],
    { encoding: "utf8" }
  )
  rmSync(dir, { recursive: true, force: true })
  if (copied.status !== 0) {
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

  if (executed.status !== 0) {
    throw new Error(
      `psql ${label} başarısız:\n${executed.stdout}\n${executed.stderr}`
    )
  }
  return
}

/** psql sorgusunun tek satırlık (tA) çıktısını döndürür. */
function querySql(sql: string): string {
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
      "-A",
      "-t",
      "-c",
      sql,
    ],
    { encoding: "utf8" }
  )
  if (executed.status !== 0) {
    throw new Error(`psql sorgu başarısız: ${executed.stderr}`)
  }
  return executed.stdout.trim()
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
    body: JSON.stringify({ id, email, password, email_confirm: true }),
  })
  if (!response.ok) {
    throw new Error(`admin kullanıcı oluşturulamadı: ${await response.text()}`)
  }
}

/** qa_faz35 fixture kalıbı: staging + 5 zorunlu doğrulama kapısı verified. */
function stagingFixtureSql(sid: string, withGates = true): string {
  return `
insert into public.ai_question_staging (
  id, staging_source, staging_status, grade_level, subject_id,
  question_text, option_a, option_b, option_c, option_d,
  proposed_correct_answer, proposed_difficulty, proposed_cognitive_type,
  proposed_quality_level, ownership_status, license_status,
  commercial_use_allowed, copyright_risk_level, metadata
) values (
  '${sid}', 'ai_generated', 'validating', 12, '${SUBJECT_ID}',
  'P2C aday sorusu ${sid}', 'A1', 'B1', 'C1', 'D1',
  'A', 'medium', 'application', 'medium', 'unknown', 'unknown',
  false, 'low', '{}'::jsonb
);
${
  withGates
    ? `
insert into public.ai_answer_verification_runs
  (staging_question_id, proposed_answer, consensus_status, created_at, updated_at)
values ('${sid}', 'A', 'verified', now(), now());
insert into public.ai_curriculum_fit_runs
  (staging_question_id, expected_grade_level, expected_subject_id, status, created_at, updated_at)
values ('${sid}', 12, '${SUBJECT_ID}', 'verified', now(), now());
insert into public.ai_solve_time_verification_runs
  (staging_question_id, status, created_at, updated_at)
values ('${sid}', 'verified', now(), now());
insert into public.ai_originality_verification_runs
  (staging_question_id, status, created_at, updated_at)
values ('${sid}', 'verified', now(), now());
insert into public.ai_question_quality_runs
  (staging_question_id, status, created_at, updated_at)
values ('${sid}', 'verified', now(), now());
`
    : ""
}
`
}

/** READY/RC/RJ: readiness hesaplanır ve staging needs_review'a alınır.
 *  evaluate guard'ı admin izni ister (130:446-463) — qa_faz35 M4a kalıbıyla
 *  admin kimliği altında çağrılır. */
function readyNeedsReviewFixtureSql(sid: string): string {
  return `
${stagingFixtureSql(sid)}
begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub','${ADMIN_UID}','role','authenticated')::text, true);
select set_config('request.jwt.claim.sub', '${ADMIN_UID}', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select private.evaluate_ai_question_readiness('${sid}');
commit;
update public.ai_question_staging set staging_status = 'needs_review' where id = '${sid}';
`
}

function insertFixtures(): void {
  runSql(
    "p2c_roles",
    `
insert into public.admin_user_roles (user_id, role_id)
select '${ADMIN_UID}', (select id from public.admin_roles where role_code = 'question_reviewer');
insert into public.admin_user_roles (user_id, role_id)
select '${WRONG_UID}', (select id from public.admin_roles where role_code = 'copyright_reviewer');
`
  )
  runSql("p2c_staging_val", stagingFixtureSql(SID_VAL))
  runSql("p2c_staging_ready", readyNeedsReviewFixtureSql(SID_READY))
  runSql("p2c_staging_rc", readyNeedsReviewFixtureSql(SID_RC))
  runSql("p2c_staging_rj", readyNeedsReviewFixtureSql(SID_RJ))
  runSql(
    "p2c_batch",
    `
insert into public.candidate_question_batches (
  id, batch_key, schema_version, origin, producer_id, producer_model,
  status, total_items, valid_items, invalid_items, inserted_items, duplicate_items,
  validation_summary, error_data, raw_payload, metadata
) values (
  '${BATCH_ID}', 'P2C-BATCH', '1.0', 'curriculum_original', 'p2c_suite', 'deterministic',
  'ingested', 4, 4, 0, 4, 0,
  '{"received":4,"valid":4,"invalid":0,"inserted":4,"duplicates":0}'::jsonb,
  '[]'::jsonb, '{"batch":"P2C"}'::jsonb, '{}'::jsonb
);
insert into public.candidate_batch_candidate_results
  (batch_id, candidate_index, client_question_id, validation_status,
   validation_errors, validation_warnings, staging_question_id)
values
  ('${BATCH_ID}', 0, 'P2C-C-0', 'inserted', '[]'::jsonb, '[]'::jsonb, '${SID_VAL}'),
  ('${BATCH_ID}', 1, 'P2C-C-1', 'inserted', '[]'::jsonb, '[]'::jsonb, '${SID_READY}'),
  ('${BATCH_ID}', 2, 'P2C-C-2', 'inserted', '[]'::jsonb, '[]'::jsonb, '${SID_RC}'),
  ('${BATCH_ID}', 3, 'P2C-C-3', 'inserted', '[]'::jsonb, '[]'::jsonb, '${SID_RJ}');
`
  )
}

function cleanupFixtures(): void {
  runSql(
    "p2c_cleanup",
    `
delete from public.ai_question_final_reviews where staging_question_id in ('${SID_VAL}','${SID_READY}','${SID_RC}','${SID_RJ}');
delete from public.ai_validation_results where staging_question_id in ('${SID_VAL}','${SID_READY}','${SID_RC}','${SID_RJ}');
delete from public.ai_question_readiness_runs where staging_question_id in ('${SID_VAL}','${SID_READY}','${SID_RC}','${SID_RJ}');
delete from public.ai_question_staging where id in ('${SID_VAL}','${SID_READY}','${SID_RC}','${SID_RJ}');
delete from public.questions where question_code like 'AK-AI-B35C%';
delete from public.admin_audit_log where entity_id in ('${SID_VAL}','${SID_READY}','${SID_RC}','${SID_RJ}');
delete from public.candidate_batch_candidate_results where batch_id = '${BATCH_ID}';
delete from public.candidate_question_batches where id = '${BATCH_ID}';
delete from public.admin_user_roles where user_id in ('${ADMIN_UID}','${WRONG_UID}','${STUDENT_UID}');
delete from auth.users where id in ('${ADMIN_UID}','${WRONG_UID}','${STUDENT_UID}');
`
  )
}

type DecisionRpc = (
  fn: "review_and_promote_ai_question",
  args: {
    p_staging_question_id: string
    p_decision: string
    p_review_notes?: string
  }
) => Promise<{
  data: Record<string, unknown> | null
  error: { message?: string; code?: string; details?: string } | null
}>

function clientWith(session: Session | null) {
  const client = createClient(apiUrl, publishableKey, {
    global: session
      ? { headers: { Authorization: `Bearer ${session.access_token}` } }
      : undefined,
  })
  return {
    rpc: client.rpc.bind(client) as unknown as DecisionRpc,
  }
}

async function signIn(email: string, password: string): Promise<Session> {
  const { data, error } = await createClient(apiUrl, publishableKey).auth.signInWithPassword({
    email,
    password,
  })
  if (error || !data.session) {
    throw new Error(`test girişi başarısız: ${error?.message ?? "oturum yok"}`)
  }
  return data.session
}

/** Gerçek detay RPC + gerçek üretim eşleyicisi + gerçek türetme. */
async function deriveFromRealDetail(): Promise<Record<string, { enabled: boolean; reason: string | null }>> {
  const client = createClient(apiUrl, publishableKey, {
    global: {
      headers: { Authorization: `Bearer ${adminSession!.access_token}` },
    },
  })
  const { data, error } = await client.rpc("get_candidate_question_batch_detail", {
    p_batch_id: BATCH_ID,
  })
  expect(error).toBeNull()
  const obj = data as Record<string, unknown>
  const detail = {
    batch: mapCandidateBatchListItem(obj.batch as Record<string, unknown>),
    candidates: (obj.candidates as Array<Record<string, unknown>>).map(mapCandidate),
  }

  const result: Record<string, { enabled: boolean; reason: string | null }> = {}
  for (const candidate of detail.candidates) {
    const availability = deriveCandidateDecisionAvailability(candidate)
    result[candidate.stagingQuestionId ?? ""] = {
      enabled: availability.approve.enabled && availability.request_changes.enabled && availability.reject.enabled,
      reason: availability.approve.reason ?? availability.reject.reason,
    }
    ;(result as Record<string, unknown>)[`detail_${candidate.stagingQuestionId}`] = availability
  }
  ;(result as Record<string, unknown>)["__detail"] = detail
  return result
}

// Skip guard'ı TOPLAMA anında işlevsel olmalıdır: it.skipIf değeri modül
// yüklemesinde okunur; bu yüzden config okuma üst düzeyde yapılır (Docker
// yoksa/stack yoksa tüm suite tasarım gereği atlanır — training
// integration kalıbının amaçlanan davranışı).
readLocalConfig()

beforeAll(async () => {
  if (shouldSkip) return
  try {
    const probe = await fetch(`${apiUrl}/rest/v1/`, {
      method: "HEAD",
      signal: AbortSignal.timeout(5_000),
    })
    if (!probe.ok) throw new Error(`probe ${probe.status}`)
  } catch {
    shouldSkip = true
    return
  }
  cleanupFixtures()
  await adminCreateUser(ADMIN_UID, "p2c-admin@test.local", "P2c-Admin-1234!")
  await adminCreateUser(WRONG_UID, "p2c-wrong@test.local", "P2c-Wrong-1234!")
  await adminCreateUser(STUDENT_UID, "p2c-student@test.local", "P2c-Student-1234!")
  insertFixtures()
  adminSession = await signIn("p2c-admin@test.local", "P2c-Admin-1234!")
  studentSession = await signIn("p2c-student@test.local", "P2c-Student-1234!")
}, 240_000)

afterAll(() => {
  if (shouldSkip) return
  cleanupFixtures()
})

it.skipIf(shouldSkip)(
  "C: private şema REST yüzeyinde görünmez; public köprü authenticated'a açıktır",
  { timeout: 120_000 },
  async () => {
    // private şema PostgREST schemas listesinde değil (PGRST_DB_SCHEMAS=public,graphql_public):
    // private fonksiyona REST yoluyla ulaşmak 404 PGRST202 döner.
    const res = await fetch(
      `${apiUrl}/rest/v1/rpc/ai_question_promotion_blockers`,
      {
        method: "POST",
        headers: {
          apikey: publishableKey,
          Authorization: `Bearer ${adminSession!.access_token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_staging_question_id: SID_VAL }),
      }
    )
    const body = (await res.json()) as { code?: string; message?: string }
    expect(res.status).toBe(404)
    expect(body.code).toBe("PGRST202")

    // service_role anahtarı public köprüde REVOKE edilmiştir (039:974-980).
    // Ölçülen gerçek PostgREST davranışı: fonksiyon görünürlüğü service_role
    // için hâlâ özet tabloda olduğundan çağrı 42501 ile 403 döner —
    // güvenlik özelliği aynıdır: yürütme ZORUNLU olarak reddedilir.
    const svcRes = await fetch(
      `${apiUrl}/rest/v1/rpc/review_and_promote_ai_question`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_staging_question_id: SID_VAL,
          p_decision: "approve",
        }),
      }
    )
    const svcBody = (await svcRes.json()) as { code?: string; message?: string }
    expect(svcRes.status).toBe(403)
    expect(svcBody.code).toBe("42501")
    expect(svcBody.message).toMatch(/permission denied for function review_and_promote_ai_question/)
  }
)

it.skipIf(shouldSkip)(
  "C: validating adayda gerçek veriden türetme üç kararı da kapatır (sunucu yeniden türetme atlatılamaz)",
  { timeout: 120_000 },
  async () => {
    const result = await deriveFromRealDetail()

    // VAL: gerçek DB'de validating + readiness yok -> üç karar kapalı.
    const val = result[`detail_${SID_VAL}`] as unknown as Record<
      "approve" | "request_changes" | "reject",
      { enabled: boolean; reason: string | null }
    >
    expect(val.approve.enabled).toBe(false)
    expect(val.request_changes.enabled).toBe(false)
    expect(val.reject.enabled).toBe(false)
    expect(val.approve.reason).toBe("validationIncomplete")

    // READY: needs_review + readiness tam -> approve AÇIK (UI sözleşmesi).
    const ready = result[`detail_${SID_READY}`] as unknown as Record<
      "approve" | "request_changes" | "reject",
      { enabled: boolean; reason: string | null }
    >
    expect(ready.approve.enabled).toBe(true)
    expect(ready.approve.reason).toBeNull()
    expect(ready.request_changes.enabled).toBe(true)
    expect(ready.reject.enabled).toBe(true)

    // İstemcinin gönderebileceği tek alanlar: kimlik + karar + gerekçe.
    // Uygunluk bu veriden SUNUCUDA yeniden türetilir; girdi doğrulaması
    // üretim fonksiyonuyla birebir ölçülür.
    expect(validateDecisionInput({
      stagingQuestionId: SID_VAL,
      decision: "approve",
      rationale: "",
    })).toEqual({
      ok: true,
      stagingQuestionId: SID_VAL,
      decision: "approve",
      rationale: "",
    })
  }
)

it.skipIf(shouldSkip)(
  "A: readiness tamamlanmış adayda approve gerçek migration 130 sözleşmesine göre promoted döner; publish YOK",
  { timeout: 120_000 },
  async () => {
    const admin = clientWith(adminSession)
    const res = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_READY,
      p_decision: "approve",
      p_review_notes: "P2C approve kanıtı",
    })
    expect(res.error).toBeNull()
    const result = res.data as Record<string, unknown>
    expect(result).toMatchObject({
      status: "promoted",
      approval_status: "approved",
      is_active: false,
      student_visible: false,
      automatic_publication_allowed: false,
      commercial_use_allowed: false,
    })
    expect(result.question_id).toBeTruthy()
    expect(result.audit_id).toBeTruthy()
    expect(result.final_review_id).toBeTruthy()

    // questions'a yazıldı ama is_active=false: öğrenciye yayın YOK.
    const q = querySql(
      `select approval_status || '|' || is_active::text from public.questions where id = '${result.question_id}'`
    )
    expect(q).toBe("approved|false")

    // Tam olarak 1 final_review + 1 audit; aktör admin.
    expect(
      querySql(
        `select count(*) from public.ai_question_final_reviews where staging_question_id = '${SID_READY}' and decision = 'approve'`
      )
    ).toBe("1")
    const audit = querySql(
      `select action_code || '|' || actor_user_id || '|' || (after_data->>'student_visible') || '|' || (after_data->>'automatic_publication_allowed')
         from public.admin_audit_log where entity_id = '${SID_READY}'`
    )
    expect(audit).toBe(
      `staging_question.approve|${ADMIN_UID}|false|false`
    )

    // staging promoted.
    expect(
      querySql(
        `select staging_status from public.ai_question_staging where id = '${SID_READY}'`
      )
    ).toBe("promoted")

    // İkinci approve: already_promoted + YENİ audit YOK.
    const second = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_READY,
      p_decision: "approve",
    })
    expect(second.error).toBeNull()
    expect((second.data as Record<string, unknown>).status).toBe("already_promoted")
    expect((second.data as Record<string, unknown>).audit_id ?? null).toBeNull()
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id = '${SID_READY}'`
      )
    ).toBe("1")
  }
)

it.skipIf(shouldSkip)(
  "A: request_changes boş gerekçe DB'den kabul edilir (UI daha katı); tekrar idempotent_replay + YENİ audit YOK",
  { timeout: 120_000 },
  async () => {
    const admin = clientWith(adminSession)

    // UI katmanı: boş gerekçe RPC'ye GİTMEZ (üretim fonksiyonuyla ölçülür).
    const ui = validateDecisionInput({
      stagingQuestionId: SID_RC,
      decision: "request_changes",
      rationale: "   ",
    })
    expect(ui).toEqual({ ok: false, error: "rationaleRequired" })

    // DB katmanı (doğrudan): boş gerekçe kabul edilir — ölçülen sözleşme farkı.
    const first = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_RC,
      p_decision: "request_changes",
      p_review_notes: "",
    })
    expect(first.error).toBeNull()
    const firstData = first.data as Record<string, unknown>
    expect(firstData.status).toBe("changes_requested")
    expect(firstData.idempotent_replay ?? null).toBeNull()
    expect(firstData.final_review_id).toBeTruthy()

    // İkinci çağrı (gerekçeli): idempotent_replay=true, AYNI final_review_id.
    const second = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_RC,
      p_decision: "request_changes",
      p_review_notes: "P2C ikinci çağrı",
    })
    expect(second.error).toBeNull()
    const secondData = second.data as Record<string, unknown>
    expect(secondData.status).toBe("changes_requested")
    expect(secondData.idempotent_replay).toBe(true)
    expect(secondData.final_review_id).toBe(firstData.final_review_id)

    // Yalnız TEK final_review + TEK audit yazıldı.
    expect(
      querySql(
        `select count(*) from public.ai_question_final_reviews where staging_question_id = '${SID_RC}'`
      )
    ).toBe("1")
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id = '${SID_RC}' and action_code = 'staging_question.request_changes'`
      )
    ).toBe("1")

    // staging needs_review olarak kaldı.
    expect(
      querySql(
        `select staging_status from public.ai_question_staging where id = '${SID_RC}'`
      )
    ).toBe("needs_review")
  }
)

it.skipIf(shouldSkip)(
  "A: reject gerekçeyle rejected döner; terminal durumda approve P0001",
  { timeout: 120_000 },
  async () => {
    const admin = clientWith(adminSession)
    const res = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_RJ,
      p_decision: "reject",
      p_review_notes: "P2C reject kanıtı",
    })
    expect(res.error).toBeNull()
    expect(res.data).toMatchObject({
      status: "rejected",
      production_publication: false,
    })

    // staging rejected + commercial_use_allowed=false + 1 audit.
    expect(
      querySql(
        `select staging_status || '|' || commercial_use_allowed::text from public.ai_question_staging where id = '${SID_RJ}'`
      )
    ).toBe("rejected|false")
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id = '${SID_RJ}' and action_code = 'staging_question.reject'`
      )
    ).toBe("1")

    // Terminal durumda approve reddedilir.
    const again = await admin.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_RJ,
      p_decision: "approve",
    })
    expect(again.error).not.toBeNull()
    expect(again.error!.message).toMatch(/Rejected staging question cannot be promoted/)
  }
)

it.skipIf(shouldSkip)(
  "B: öğrenci ve yetersiz admin fail-closed; ham DB metni Türkçe mesaja sızdırılmadan eşlenir",
  { timeout: 120_000 },
  async () => {
    // Öğrenci: permission reddi.
    const student = clientWith(studentSession)
    const studentRes = await student.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_VAL,
      p_decision: "approve",
    })
    expect(studentRes.error).not.toBeNull()
    expect(studentRes.data).toBeNull()
    expect(studentRes.error!.message).toMatch(/Question approval permission required/)

    // Gerçek hata nesnesi -> Türkçe eşleyici: ham metin kullanıcı mesajına sızmaz.
    const studentMapped = mapCandidateDecisionError(studentRes.error)
    expect(studentMapped).toMatch(/yetkiniz yok/i)
    expect(studentMapped).not.toContain("Question approval permission required")

    // Yazma olmadığını kanıtla: VAL aday hâlâ validating, kayıt yok.
    expect(
      querySql(
        `select staging_status from public.ai_question_staging where id = '${SID_VAL}'`
      )
    ).toBe("validating")
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id = '${SID_VAL}'`
      )
    ).toBe("0")
  }
)

it.skipIf(shouldSkip)(
  "B: yetersiz admin (questions.approve yok) fail-closed; yazma olmaz",
  { timeout: 120_000 },
  async () => {
    const wrongSession = await signIn("p2c-wrong@test.local", "P2c-Wrong-1234!")
    const wrong = clientWith(wrongSession)
    const res = await wrong.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_VAL,
      p_decision: "request_changes",
      p_review_notes: "yetersiz admin denemesi",
    })
    expect(res.error).not.toBeNull()
    expect(res.error!.message).toMatch(/Question approval permission required/)
    expect(mapCandidateDecisionError(res.error)).toMatch(/yetkiniz yok/i)
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id = '${SID_VAL}'`
      )
    ).toBe("0")
  }
)

it.skipIf(shouldSkip)(
  "B: oturumsuz (anon) istek fail-closed; beklenmeyen karar ve olmayan aday P0001",
  { timeout: 120_000 },
  async () => {
    // Oturumsuz: anon EXECUTE yok -> PostgREST fonksiyonu bulamaz (404).
    const anon = clientWith(null)
    const res = await anon.rpc("review_and_promote_ai_question", {
      p_staging_question_id: SID_VAL,
      p_decision: "approve",
    })
    expect(res.error).not.toBeNull()
    expect(res.data).toBeNull()

    // Beklenmeyen karar değeri.
    const invalid = await clientWith(adminSession).rpc(
      "review_and_promote_ai_question",
      {
        p_staging_question_id: SID_VAL,
        p_decision: "publish_now",
      }
    )
    expect(invalid.error!.message).toMatch(/Invalid final review decision/)

    // Olmayan aday.
    const missing = await clientWith(adminSession).rpc(
      "review_and_promote_ai_question",
      {
        p_staging_question_id: SID_NONEXISTENT,
        p_decision: "reject",
        p_review_notes: "olmayan aday",
      }
    )
    expect(missing.error!.message).toMatch(/Staging question not found/)

    // Bu üç negatifte de hiçbir yazma olmamıştır: VAL hâlâ validating, audit yok.
    expect(
      querySql(
        `select staging_status from public.ai_question_staging where id = '${SID_VAL}'`
      )
    ).toBe("validating")
    expect(
      querySql(
        `select count(*) from public.admin_audit_log where entity_id in ('${SID_VAL}','${SID_NONEXISTENT}')`
      )
    ).toBe("0")
  }
)

it.skipIf(shouldSkip)(
  "A/B: batch özet sayaçları kararlarla DEĞİŞMEZ; human_final_review özeti ayrı alanda",
  { timeout: 120_000 },
  async () => {
    const summary = querySql(
      `select validation_summary::text from public.candidate_question_batches where id = '${BATCH_ID}'`
    )
    const parsed = JSON.parse(summary) as Record<string, unknown>
    const human = parsed.human_final_review as Record<string, unknown>

    // Intake sayaçları hiçbir karara dokunulmadığı için korunur.
    expect(parsed.received).toBe(4)
    expect(parsed.valid).toBe(4)
    expect(parsed.inserted).toBe(4)

    // Karar özeti ayrı alanda: 1 promoted (READY) + 1 changes_requested_pending (RC).
    expect(human.promoted).toBe(1)
    expect(human.changes_requested_pending).toBe(1)
    expect(human.total_candidates).toBe(4)
    expect(human.source).toBe("ai_question_staging.staging_status")

    // Hiçbir akış publish/activate çağırmadı: promoted soru is_active=false
    // ve aktif soru sayısı değişmedi.
    expect(
      querySql(
        `select count(*) from public.questions where question_code like 'AK-AI-B35C%' and is_active = true`
      )
    ).toBe("0")
  }
)
