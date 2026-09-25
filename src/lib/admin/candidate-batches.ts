import { createClient } from "@/lib/supabase/server"
import type { ListPageResult, DetailResult } from "./question-bank"
import { candidateBatchErrorKind } from "./candidate-batches-errors"

/**
 * Faz 19 — Aday Yükleme Paketleri (yalnızca okuma, veri kıyısı).
 *
 * - 120 migration'ının iki SECURITY DEFINER okuma RPC'sini sarmalar:
 *     • list_candidate_question_batches(p_limit, p_offset)
 *     • get_candidate_question_batch_detail(p_batch_id)
 * - Yetki: RPC tarafı kimlik + (ai.manage VEYA questions.approve) VEYA
 *   service_role olarak fail-closed doğrular. Bu modüldeki
 *   hasCandidateBatchReadPermission() yalnız UI gating içindir; gerçek
 *   yetki yalnız RPC içinde denetlenir (fail-closed, kapatılamaz).
 * - DTO allowlist: RPC jsonb çıktısından yalnızca izinli alanlar okunur;
 *   keyfi JSON alanı asla taşınmaz. YAZMA YOK: bu modül veri üretmez,
 *   tetiklemez, değiştirmez; paket künyesi + sayaç + aday özeti + gate
 *   özeti sunar. Ham RPC hatası dışarı sızmaz; not-found özel eşlenir.
 */

/** Liste sayfasının güvenli sabit sayfa boyutu (RPC üst sınırı 100). */
export const CANDIDATE_BATCH_PAGE_SIZE = 25

export interface CandidateBatchCounts {
  totalItems: number | null
  validItems: number | null
  invalidItems: number | null
  insertedItems: number | null
  duplicateItems: number | null
}

/**
 * Faz 22 — v1.1 markdown paketi preflight özeti (yalnız izinli alanlar).
 * validation_summary.preflight nesnesinin allowlist'e dayalı okumasıdır;
 * ham JSON asla taşınmaz.
 */
export interface CandidateBatchPreflightSummary {
  adapter: string | null
  schemaVersion: string | null
  rootValid: boolean | null
  outOfPackageCount: number | null
  outOfPackageKinds: string[]
  reviewRequired: boolean | null
  publicationAllowed: boolean | null
  isActive: boolean | null
}

/** Liste/detay ortak paket künyesi (yalnız izinli alanlar). */
export interface CandidateBatchListItem {
  batchId: string
  batchKey: string
  schemaVersion: string | null
  origin: string | null
  producerId: string | null
  producerModel: string | null
  status: string | null
  counts: CandidateBatchCounts
  validationSummary: string | null
  preflightSummary: CandidateBatchPreflightSummary | null
  createdAt: string | null
  updatedAt: string | null
}

/**
 * Faz 24 — aday çözümü (metadata->solution jsonb object). Yalnız
 * allowlist anahtarları okunur; ham JSON asla taşınmaz. Adımlar
 * DTO'da düz dizidir (title/content allowlist).
 */
export interface CandidateSolutionStep {
  title: string | null
  content: string | null
}

export interface CandidateSolution {
  method: string | null
  steps: CandidateSolutionStep[]
  result: string | null
  correctAnswerJustification: string | null
  commonMistakes: string[]
}

/** Soru önizlemesi — yalnız sayfa yetkisi açıkken gösterilir. */
export interface CandidatePreview {
  stagingStatus: string | null
  questionText: string | null
  options: Partial<Record<"A" | "B" | "C" | "D" | "E", string | null>>
  proposedCorrectAnswer: string | null
  proposedDifficulty: string | null
  proposedCognitiveType: string | null
  proposedSolveTimeSeconds: number | null
  gradeLevel: number | null
  subjectId: string | null
  subjectName: string | null
  outcomeCode: string | null
  lowConfidence: boolean | null
  proposedCurriculumVersionId: string | null
  proposedTopicId: string | null
  proposedSubtopicId: string | null
  ownershipStatus: string | null
  licenseStatus: string | null
  commercialUseAllowed: string | null
  copyrightRiskLevel: string | null
  solution: CandidateSolution | null
}

export interface ValidationResultItem {
  validatorType: string | null
  validationType: string | null
  result: string | null
  score: number | null
  summary: string | null
  providerName: string | null
  modelName: string | null
  promptVersion: string | null
  createdAt: string | null
}

export interface ReviewQueueEntry {
  reasonCode: string | null
  reasonDetails: string | null
  priority: string | null
  status: string | null
  createdAt: string | null
}

/** Gate/run özeti alanı; yalnız allowlist anahtarları taşınır. */
export interface GateField {
  key: string
  value: string | number | boolean | string[] | null
}

export interface CandidateGateRun {
  fields: GateField[]
}

export interface CandidateGates {
  answerVerification: CandidateGateRun | null
  curriculumFit: CandidateGateRun | null
  solveTimeVerification: CandidateGateRun | null
  originalityVerification: CandidateGateRun | null
  questionQuality: CandidateGateRun | null
  readiness: CandidateGateRun | null
  finalReview: CandidateGateRun | null
}

export interface CandidateRecord {
  candidateIndex: number
  clientQuestionId: string | null
  validationStatus: string | null
  validationErrors: string[]
  validationWarnings: string[]
  stagingQuestionId: string | null
  preview: CandidatePreview | null
  validationResults: ValidationResultItem[]
  reviewQueue: ReviewQueueEntry[]
  gates: CandidateGates
}

export interface CandidateBatchDetail {
  batch: CandidateBatchListItem
  candidates: CandidateRecord[]
}

export interface OperationGateCounts {
  total: number | null
  waitingReviewer1: number | null
  waitingReviewer2: number | null
  waitingSolver1: number | null
  waitingSolver2: number | null
  needsHumanReview: number | null
  verified: number | null
  blocked: number | null
  rejected: number | null
  readyForHumanReview: number | null
  humanReviewRequired: number | null
  notReady: number | null
  alreadyPromoted: number | null
  approve: number | null
  requestChanges: number | null
  other: number | null
}

/** Faz 20 — üretim/denetim işlem durumu (yalnız izinli alanlar). */
export interface CandidateBatchOperationStatus {
  batch: {
    batchId: string
    batchKey: string
    status: string | null
    counts: CandidateBatchCounts
    createdAt: string | null
    updatedAt: string | null
  }
  phase: {
    candidateCounts: {
      pending: number | null
      valid: number | null
      invalid: number | null
      duplicate: number | null
      inserted: number | null
      failed: number | null
    }
  }
  gates: {
    answerVerification: OperationGateCounts
    curriculumFit: OperationGateCounts
    solveTimeVerification: OperationGateCounts
    originalityVerification: OperationGateCounts
    questionQuality: OperationGateCounts
    readiness: OperationGateCounts
    finalReview: OperationGateCounts
  }
  provider: {
    hasBatchErrorData: boolean
    candidateValidationErrorCount: number | null
  }
  retry: {
    supported: boolean
    reasonKey: string | null
  }
}

export type CandidateBatchListResult = ListPageResult<CandidateBatchListItem>
export type CandidateBatchDetailResult = DetailResult<CandidateBatchDetail>
export type CandidateBatchOperationStatusResult = DetailResult<CandidateBatchOperationStatus>

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: { p_permission_code: string },
) => Promise<{ data: boolean | null; error: { message: string } | null }>

type ListBatchesRpc = (
  functionName: "list_candidate_question_batches",
  args: { p_limit: number; p_offset: number },
) => Promise<{
  data: {
    items?: unknown[]
    total?: unknown
    limit?: unknown
    offset?: unknown
  } | null
  error: { message: string } | null
}>

type BatchDetailRpc = (
  functionName: "get_candidate_question_batch_detail",
  args: { p_batch_id: string },
) => Promise<{ data: unknown | null; error: { message: string } | null }>

type BatchOperationStatusRpc = (
  functionName: "get_candidate_question_batch_operation_status",
  args: { p_batch_id: string },
) => Promise<{ data: unknown | null; error: { message: string } | null }>

/**
 * Aday paket verisi okuma yetkisi (UI gating): ai.manage VEYA
 * questions.approve. Her ikisinde de hata/false → yetki YOK (fail-closed).
 */
export async function hasCandidateBatchReadPermission(): Promise<boolean> {
  const supabase = await createClient()
  const rpc = supabase.rpc.bind(supabase) as unknown as PermissionRpc
  const [aiResult, approveResult] = await Promise.all([
    rpc("teacher_review_admin_has_permission", {
      p_permission_code: "ai.manage",
    }),
    rpc("teacher_review_admin_has_permission", {
      p_permission_code: "questions.approve",
    }),
  ])
  return (
    (aiResult.error === null && aiResult.data === true) ||
    (approveResult.error === null && approveResult.data === true)
  )
}

// ---------------------------------------------------------------------------
// allowlist okuyucular
// ---------------------------------------------------------------------------

function asString(value: unknown): string | null {
  return typeof value === "string" ? value : null
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((v): v is string => typeof v === "string")
}

function asOptionalBoolean(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null
}

/**
 * validation_summary.preflight → izinli özet. validation_summary RPC
 * tarafında jsonb (object) veya text (string) dönebilir; ikisi de kabul
 * edilir. preflight anahtarı yoksa null (paket v1.0 olabilir).
 */
export function mapCandidateBatchPreflightSummary(
  raw: unknown
): CandidateBatchPreflightSummary | null {
  let value = raw
  if (typeof value === "string") {
    try {
      value = JSON.parse(value) as unknown
    } catch {
      return null
    }
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  const obj = value as Record<string, unknown>
  const preflightRaw = obj.preflight
  if (
    !preflightRaw ||
    typeof preflightRaw !== "object" ||
    Array.isArray(preflightRaw)
  ) {
    return null
  }
  const p = preflightRaw as Record<string, unknown>
  return {
    adapter: asString(p.adapter),
    schemaVersion: asString(p.schema_version),
    rootValid: asOptionalBoolean(p.root_valid),
    outOfPackageCount: asNumber(p.out_of_package_count),
    outOfPackageKinds: asStringArray(p.out_of_package_kinds),
    reviewRequired: asOptionalBoolean(p.review_required),
    publicationAllowed: asOptionalBoolean(p.publication_allowed),
    isActive: asOptionalBoolean(p.is_active),
  }
}

/** Paket künyesi → izinli DTO (keyfi alan okunmaz). */
export function mapCandidateBatchListItem(
  row: Record<string, unknown>
): CandidateBatchListItem {
  const countsRaw =
    row.counts && typeof row.counts === "object"
      ? (row.counts as Record<string, unknown>)
      : {}
  return {
    batchId: asString(row.batch_id) ?? "",
    batchKey: asString(row.batch_key) ?? "",
    schemaVersion: asString(row.schema_version),
    origin: asString(row.origin),
    producerId: asString(row.producer_id),
    producerModel: asString(row.producer_model),
    status: asString(row.status),
    counts: {
      totalItems: asNumber(countsRaw.total_items),
      validItems: asNumber(countsRaw.valid_items),
      invalidItems: asNumber(countsRaw.invalid_items),
      insertedItems: asNumber(countsRaw.inserted_items),
      duplicateItems: asNumber(countsRaw.duplicate_items),
    },
    validationSummary: asString(row.validation_summary),
    preflightSummary: mapCandidateBatchPreflightSummary(row.validation_summary),
    createdAt: asString(row.created_at),
    updatedAt: asString(row.updated_at),
  }
}

const OPTION_LETTERS = ["A", "B", "C", "D", "E"] as const

/**
 * Faz 24 — çözüm jsonb object → izinli DTO. Yalnız bilinen anahtarlar
 * okunur; steps/commonMistakes dizileri eleman-tipi filtrelenir.
 */
export function mapCandidateSolution(raw: unknown): CandidateSolution | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  const obj = raw as Record<string, unknown>
  const stepsRaw = Array.isArray(obj.steps) ? obj.steps : []
  const mistakesRaw = Array.isArray(obj.commonMistakes) ? obj.commonMistakes : []
  return {
    method: asString(obj.method),
    steps: stepsRaw
      .filter((s): s is Record<string, unknown> =>
        Boolean(s) && typeof s === "object" && !Array.isArray(s)
      )
      .map((s) => ({
        title: asString(s.title),
        content: asString(s.content),
      })),
    result: asString(obj.result),
    correctAnswerJustification: asString(obj.correctAnswerJustification),
    commonMistakes: mistakesRaw.filter(
      (m): m is string => typeof m === "string"
    ),
  }
}

/** Önizleme → izinli DTO; seçenekler yalnız A–E okunur. */
export function mapCandidatePreview(row: Record<string, unknown>): CandidatePreview {
  const optionsRaw =
    row.options && typeof row.options === "object"
      ? (row.options as Record<string, unknown>)
      : {}
  const options: Partial<Record<"A" | "B" | "C" | "D" | "E", string | null>> = {}
  for (const letter of OPTION_LETTERS) {
    options[letter] = asString(optionsRaw[letter])
  }
  return {
    stagingStatus: asString(row.staging_status),
    questionText: asString(row.question_text),
    options,
    proposedCorrectAnswer: asString(row.proposed_correct_answer),
    proposedDifficulty: asString(row.proposed_difficulty),
    proposedCognitiveType: asString(row.proposed_cognitive_type),
    proposedSolveTimeSeconds: asNumber(row.proposed_solve_time_seconds),
    gradeLevel: asNumber(row.grade_level),
    subjectId: asString(row.subject_id),
    subjectName: asString(row.subject_name),
    outcomeCode: asString(row.outcome_code),
    lowConfidence:
      typeof row.low_confidence === "boolean" ? row.low_confidence : null,
    proposedCurriculumVersionId: asString(row.proposed_curriculum_version_id),
    proposedTopicId: asString(row.proposed_topic_id),
    proposedSubtopicId: asString(row.proposed_subtopic_id),
    ownershipStatus: asString(row.ownership_status),
    licenseStatus: asString(row.license_status),
    commercialUseAllowed: asString(row.commercial_use_allowed),
    copyrightRiskLevel: asString(row.copyright_risk_level),
    solution: mapCandidateSolution(row.solution),
  }
}

/** Validation sonucu → izinli DTO. */
export function mapValidationResultItem(
  row: Record<string, unknown>
): ValidationResultItem {
  return {
    validatorType: asString(row.validator_type),
    validationType: asString(row.validation_type),
    result: asString(row.result),
    score: asNumber(row.score),
    summary: asString(row.summary),
    providerName: asString(row.provider_name),
    modelName: asString(row.model_name),
    promptVersion: asString(row.prompt_version),
    createdAt: asString(row.created_at),
  }
}

/** Review kuyruğu girişi → izinli DTO. */
export function mapReviewQueueEntry(
  row: Record<string, unknown>
): ReviewQueueEntry {
  return {
    reasonCode: asString(row.reason_code),
    reasonDetails: asString(row.reason_details),
    priority: asString(row.priority),
    status: asString(row.status),
    createdAt: asString(row.created_at),
  }
}

/**
 * Gate/run nesnesinden yalnız allowlist anahtarları okur; listelenmeyen
 * hiçbir alan özete girmez. Değer tipi anahtar grubuna göre sınırlanır.
 */
const GATE_ALLOWLISTS: Record<keyof CandidateGates, readonly string[]> = {
  answerVerification: [
    "consensus_status",
    "consensus_answer",
    "minimum_confidence",
    "solver_1_confidence",
    "solver_2_confidence",
    "human_decision",
    "human_reviewed_at",
  ],
  curriculumFit: [
    "status",
    "expected_grade_level",
    "expected_subject_id",
    "expected_topic_id",
    "minimum_confidence",
    "human_decision",
    "human_reviewed_at",
  ],
  solveTimeVerification: [
    "status",
    "consensus_total_seconds",
    "recommended_race_limit_seconds",
    "minimum_confidence",
    "human_decision",
    "human_total_seconds",
    "human_reviewed_at",
  ],
  originalityVerification: [
    "status",
    "consensus_originality_score",
    "highest_similarity_type",
    "copyright_risk_level",
    "human_decision",
    "human_reviewed_at",
  ],
  questionQuality: [
    "status",
    "consensus_quality_score",
    "minimum_confidence",
    "human_decision",
    "human_reviewed_at",
  ],
  readiness: [
    "readiness_status",
    "readiness_score",
    "blocking_reasons",
    "commercial_clearance_status",
    "evaluated_at",
  ],
  finalReview: [
    "decision",
    "review_notes",
    "reviewed_by",
    "reviewed_at",
  ],
}

const STRING_OR_NUMBER_KEYS: ReadonlySet<string> = new Set([
  "minimum_confidence",
  "solver_1_confidence",
  "solver_2_confidence",
  "consensus_total_seconds",
  "recommended_race_limit_seconds",
  "human_total_seconds",
  "consensus_originality_score",
  "readiness_score",
])

const STRING_ARRAY_KEYS: ReadonlySet<string> = new Set(["blocking_reasons"])

function mapGateFieldValue(key: string, value: unknown): GateField["value"] {
  if (STRING_ARRAY_KEYS.has(key)) return asStringArray(value)
  if (STRING_OR_NUMBER_KEYS.has(key)) return asNumber(value)
  return asString(value)
}

/** Gate/run nesnesi → izinli özet (allowlist; eksik alanlar atlanır). */
export function mapCandidateGateRun(
  key: keyof CandidateGates,
  raw: unknown
): CandidateGateRun | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  const obj = raw as Record<string, unknown>
  const allowlist = GATE_ALLOWLISTS[key]
  const fields: GateField[] = []
  for (const allowKey of allowlist) {
    if (!(allowKey in obj)) continue
    fields.push({
      key: allowKey,
      value: mapGateFieldValue(allowKey, obj[allowKey]),
    })
  }
  if (fields.length === 0) return null
  return { fields }
}

/** Gates nesnesi → izinli özet; bilinmeyen gate adları taşınmaz. */
export function mapCandidateGates(raw: unknown): CandidateGates {
  const obj =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? (raw as Record<string, unknown>)
      : {}
  return {
    answerVerification: mapCandidateGateRun("answerVerification", obj.answer_verification),
    curriculumFit: mapCandidateGateRun("curriculumFit", obj.curriculum_fit),
    solveTimeVerification: mapCandidateGateRun(
      "solveTimeVerification",
      obj.solve_time_verification
    ),
    originalityVerification: mapCandidateGateRun(
      "originalityVerification",
      obj.originality_verification
    ),
    questionQuality: mapCandidateGateRun("questionQuality", obj.question_quality),
    readiness: mapCandidateGateRun("readiness", obj.readiness),
    finalReview: mapCandidateGateRun("finalReview", obj.final_review),
  }
}

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {}

function asRecordArray(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value)) return []
  return value.filter((v) => v && typeof v === "object" && !Array.isArray(v)) as Record<
    string,
    unknown
  >[]
}

/** Aday nesnesi → izinli DTO. */
export function mapCandidate(row: Record<string, unknown>): CandidateRecord {
  const previewRaw = row.preview
  return {
    candidateIndex:
      typeof row.candidate_index === "number" ? row.candidate_index : 0,
    clientQuestionId: asString(row.client_question_id),
    validationStatus: asString(row.validation_status),
    validationErrors: asStringArray(row.validation_errors),
    validationWarnings: asStringArray(row.validation_warnings),
    stagingQuestionId: asString(row.staging_question_id),
    preview:
      previewRaw && typeof previewRaw === "object" && !Array.isArray(previewRaw)
        ? mapCandidatePreview(asRecord(previewRaw))
        : null,
    validationResults: asRecordArray(row.validation_results).map(
      mapValidationResultItem
    ),
    reviewQueue: asRecordArray(row.review_queue).map(mapReviewQueueEntry),
    gates: mapCandidateGates(row.gates),
  }
}

// ---------------------------------------------------------------------------
// RPC sarmalayıcıları
// ---------------------------------------------------------------------------

/** Aday paketlerini sayfalı künye listesi olarak okur. */
export async function listCandidateQuestionBatches(
  page: number
): Promise<CandidateBatchListResult> {
  const supabase = await createClient()
  const safePage = page < 1 ? 1 : page
  const offset = (safePage - 1) * CANDIDATE_BATCH_PAGE_SIZE

  const { data, error } = await (
    supabase.rpc.bind(supabase) as unknown as ListBatchesRpc
  )("list_candidate_question_batches", {
    p_limit: CANDIDATE_BATCH_PAGE_SIZE,
    p_offset: offset,
  })

  if (error) {
    return { status: "error", items: [], total: 0, page: safePage, totalPages: 1 }
  }

  const items = asRecordArray(data?.items).map(mapCandidateBatchListItem)
  const total =
    typeof data?.total === "number" && data.total >= 0 ? data.total : items.length
  const totalPages = Math.max(1, Math.ceil(total / CANDIDATE_BATCH_PAGE_SIZE))

  return { status: "ok", items, total, page: safePage, totalPages }
}

/** Tek paketin ayrıntılı özetini okur; bulunamayan paket ok+null döner. */
export async function getCandidateBatchDetail(
  batchId: string
): Promise<CandidateBatchDetailResult> {
  const supabase = await createClient()
  const { data, error } = await (
    supabase.rpc.bind(supabase) as unknown as BatchDetailRpc
  )("get_candidate_question_batch_detail", {
    p_batch_id: batchId,
  })

  if (error) {
    const kind = candidateBatchErrorKind(error)
    if (kind === "notFound") return { status: "ok", item: null }
    return { status: "error", item: null }
  }

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return { status: "error", item: null }
  }

  const obj = data as Record<string, unknown>
  const batchRaw = obj.batch
  if (!batchRaw || typeof batchRaw !== "object" || Array.isArray(batchRaw)) {
    return { status: "error", item: null }
  }

  return {
    status: "ok",
    item: {
      batch: mapCandidateBatchListItem(asRecord(batchRaw)),
      candidates: asRecordArray(obj.candidates).map(mapCandidate),
    },
  }
}

// ---------------------------------------------------------------------------
// Faz 20 — üretim/denetim işlem durumu (yalnızca okuma)
// ---------------------------------------------------------------------------

const OPERATION_GATE_KEYS: Readonly<Record<keyof OperationGateCounts, string>> = {
  total: "total",
  waitingReviewer1: "waiting_reviewer_1",
  waitingReviewer2: "waiting_reviewer_2",
  waitingSolver1: "waiting_solver_1",
  waitingSolver2: "waiting_solver_2",
  needsHumanReview: "needs_human_review",
  verified: "verified",
  blocked: "blocked",
  rejected: "rejected",
  readyForHumanReview: "ready_for_human_review",
  humanReviewRequired: "human_review_required",
  notReady: "not_ready",
  alreadyPromoted: "already_promoted",
  approve: "approve",
  requestChanges: "request_changes",
  other: "other",
}

/** Gate durum sayaçları → izinli DTO (yalnızallowlist anahtarları). */
export function mapOperationGateCounts(raw: unknown): OperationGateCounts {
  const obj = asRecord(raw)
  const out: OperationGateCounts = {
    total: null,
    waitingReviewer1: null,
    waitingReviewer2: null,
    waitingSolver1: null,
    waitingSolver2: null,
    needsHumanReview: null,
    verified: null,
    blocked: null,
    rejected: null,
    readyForHumanReview: null,
    humanReviewRequired: null,
    notReady: null,
    alreadyPromoted: null,
    approve: null,
    requestChanges: null,
    other: null,
  }
  for (const key of Object.keys(OPERATION_GATE_KEYS) as (keyof OperationGateCounts)[]) {
    out[key] = asNumber(obj[OPERATION_GATE_KEYS[key]])
  }
  return out
}

/**
 * İşlem durumu jsonb → izinli DTO. Ham error_data / raw_payload asla
 * taşınmaz; yalnız provider boolean'ı ve sayılar okunur.
 */
export function mapCandidateBatchOperationStatus(
  row: Record<string, unknown>
): CandidateBatchOperationStatus | null {
  const batchRaw = asRecord(row.batch)
  const phaseRaw = asRecord(row.phase)
  const candidateCountsRaw = asRecord(phaseRaw.candidate_counts)
  const gatesRaw = asRecord(row.gates)
  const providerRaw = asRecord(row.provider)
  const retryRaw = asRecord(row.retry)

  if (!batchRaw.batch_id) return null

  const countsRaw = asRecord(batchRaw.counts)

  return {
    batch: {
      batchId: asString(batchRaw.batch_id) ?? "",
      batchKey: asString(batchRaw.batch_key) ?? "",
      status: asString(batchRaw.status),
      counts: {
        totalItems: asNumber(countsRaw.total_items),
        validItems: asNumber(countsRaw.valid_items),
        invalidItems: asNumber(countsRaw.invalid_items),
        insertedItems: asNumber(countsRaw.inserted_items),
        duplicateItems: asNumber(countsRaw.duplicate_items),
      },
      createdAt: asString(batchRaw.created_at),
      updatedAt: asString(batchRaw.updated_at),
    },
    phase: {
      candidateCounts: {
        pending: asNumber(candidateCountsRaw.pending),
        valid: asNumber(candidateCountsRaw.valid),
        invalid: asNumber(candidateCountsRaw.invalid),
        duplicate: asNumber(candidateCountsRaw.duplicate),
        inserted: asNumber(candidateCountsRaw.inserted),
        failed: asNumber(candidateCountsRaw.failed),
      },
    },
    gates: {
      answerVerification: mapOperationGateCounts(gatesRaw.answer_verification),
      curriculumFit: mapOperationGateCounts(gatesRaw.curriculum_fit),
      solveTimeVerification: mapOperationGateCounts(
        gatesRaw.solve_time_verification
      ),
      originalityVerification: mapOperationGateCounts(
        gatesRaw.originality_verification
      ),
      questionQuality: mapOperationGateCounts(gatesRaw.question_quality),
      readiness: mapOperationGateCounts(gatesRaw.readiness),
      finalReview: mapOperationGateCounts(gatesRaw.final_review),
    },
    provider: {
      hasBatchErrorData:
        typeof providerRaw.has_batch_error_data === "boolean"
          ? providerRaw.has_batch_error_data
          : false,
      candidateValidationErrorCount: asNumber(
        providerRaw.candidate_validation_error_count
      ),
    },
    retry: {
      supported:
        typeof retryRaw.supported === "boolean" ? retryRaw.supported : false,
      reasonKey: asString(retryRaw.reason_key),
    },
  }
}

/**
 * Paketin üretim/denetim işlem durumunu okur; bulunamayan paket
 * ok+null döner. Ham RPC hatası dışarı sızmaz (fail-closed).
 */
export async function getCandidateBatchOperationStatus(
  batchId: string
): Promise<CandidateBatchOperationStatusResult> {
  const supabase = await createClient()
  const { data, error } = await (
    supabase.rpc.bind(supabase) as unknown as BatchOperationStatusRpc
  )("get_candidate_question_batch_operation_status", {
    p_batch_id: batchId,
  })

  if (error) {
    const kind = candidateBatchErrorKind(error)
    if (kind === "notFound") return { status: "ok", item: null }
    return { status: "error", item: null }
  }

  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return { status: "error", item: null }
  }

  const item = mapCandidateBatchOperationStatus(asRecord(data))
  return item ? { status: "ok", item } : { status: "error", item: null }
}