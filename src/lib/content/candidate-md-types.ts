/**
 * Markdown aday soru paketi sözleşmesi v1.1 (Faz 22).
 *
 * Tek bir Markdown dokümanını deterministik bir "aday soru paketine"
 * dönüştürür. Bu sözleşme v1.0'dan (candidate-batch-types.ts) DAHA
 * katıdır ve yalnız sunucu katmanında kullanılır:
 *
 *  - Yalnız `### AK-...` başlığındaki bloklar aday olarak çıkarılır.
 *  - Metadata etiketleri allowlist ile sınırlıdır; bilinmeyen etiket,
 *    tablo satırı, görev/PER satırı, blok dışı serbest metin "paket-dışı
 *    içerik" bulgusu olarak sayılır (içerik asla taşınmaz, yalnız sayı).
 *  - PDF referansı, kaynak soru metni, görsel ham verisi, kaynak-türetme
 *    alanı YOKTUR (005-v1.0 FORBIDDEN listesi aynen korunur).
 *  - Otomatik yayın ASLA mümkün değildir: publication_allowed=false ve
 *    is_active=false değişmezleridir; yayın yasağı kalıcıdır.
 *  - Ders çözümlemesi DB tarafında kanonik yolla yapılır (subject_ref →
 *    subjects.name eşleşmesi; çözülemeyen aday reddedilir). Hard-code uuid
 *    yoktur.
 *
 * Bu dosya yalnız iç yapıdır; doğrudan istemciye verilmez.
 */

import type { SolutionStep } from "./solution-types"

/** v1.1 Markdown paket şema sürümü. */
export const CANDIDATE_MD_SCHEMA_VERSION = "1.1" as const

/** Markdown'dan muhtemel zorluk etiketleri → AI worker şeması eşlemesi. */
export const MD_DIFFICULTY_ALIASES: Record<string, "easy" | "medium" | "hard"> = {
  kolay: "easy",
  easy: "easy",
  orta: "medium",
  medium: "medium",
  zor: "hard",
  hard: "hard",
} as const

/** Paket-dışı içerik bulgusu türleri (yalnız tür + satır numarası). */
export const MD_OUT_OF_PACKAGE_KINDS = [
  "unknown_heading",
  "table_row",
  "task_or_per_line",
  "free_text_outside_block",
  "unknown_metadata_line",
  "unparsed_question_content",
  "invalid_option_letter",
] as const

export type MdOutOfPackageKind = (typeof MD_OUT_OF_PACKAGE_KINDS)[number]

/** v1.0 (A-D zorunlu, E opsiyonel) kısıtı v1.1'de beş seçeneğe çıkar. */
export const MD_REQUIRED_OPTION_KEYS = ["A", "B", "C", "D", "E"] as const

export const MD_MIN_QUESTION_TEXT_LENGTH = 10

/** markdown paketinde durum: yalnız inceleme/pending kabul edilir. */
export const MD_ACCEPTED_VALIDATION_STATUSES = ["needs_review", "pending"] as const

export type MdValidationStatus = (typeof MD_ACCEPTED_VALIDATION_STATUSES)[number]

// ============================================================
// MARKDOWN ADALET PAKETİ (v1.1)
// ============================================================

/**
 * Tek Markdown aday soru (parser deterministik olarak çıkarır).
 * `subject_id` parser tarafından ASLA üretilmez; yalnız DB tarafında
 * subject_ref üzerinden çözülebilir olan adaylar geçer.
 */
export interface CandidateQuestionMdV11 {
  client_question_id: string
  grade_level: number | null
  subject_ref: string | null
  subject_id: string | null
  outcome_code: string | null
  /** Kapsam satırında birden fazla kazanım bulunduysa bloklayıcı. */
  additional_outcome_codes: string[]
  editorial_subtopic: string | null
  has_visual: boolean | null
  question_text: string
  options: Partial<Record<string, string>>
  correct_answer: string | null
  difficulty: string | null
  cognitive_type: string | null
  estimated_solve_time_seconds: number | null
  solution: {
    method: string | null
    steps: SolutionStep[]
    result: string | null
    correctAnswerJustification: string | null
    commonMistakes: string[]
  }
  /** `**Durum:**` etiketi: needs_review/pending Kabul, diğerleri red. */
  validation_requested_status: string | null
}

export interface CandidateMdPackageV11 {
  schema_version: typeof CANDIDATE_MD_SCHEMA_VERSION
  origin: "curriculum_original"
  producer: { id: string; model?: string } | null
  subject_ref: string | null
  validation_requested_status: string | null
  publication_allowed: boolean
  is_active: boolean
  questions: CandidateQuestionMdV11[]
  /** Parser paket-dışı içerik özeti (raw içerik değil, yalnız sayaç). */
  metadata: {
    out_of_package_count: number
    out_of_package_kinds: string[]
  }
}

/** Tek paket-dışı bulgu: tür + döküman satır numarası (içerik YOK). */
export interface MdOutOfPackageItem {
  kind: MdOutOfPackageKind
  line: number
}

/** Parser çıktısı. */
export interface CandidateMdParseResult {
  ok: boolean
  root_errors: string[]
  package: CandidateMdPackageV11 | null
  out_of_package: MdOutOfPackageItem[]
  out_of_package_count: number
  parse_notes: string[]
}

// ============================================================
// PREFLIGHT RESULT (deterministik doğrulama çıktısı)
// ============================================================

export type MdCandidateStatus = "valid" | "invalid" | "duplicate"

export interface MdCandidateResult {
  index: number
  client_question_id: string | null
  status: MdCandidateStatus
  errors: string[]
  warnings: string[]
}

export type MdBatchStatus = "accepted" | "rejected" | "partially_accepted"

export interface MdPreflightResult {
  status: MdBatchStatus
  root_valid: boolean
  schema_version_valid: boolean
  origin_valid: boolean
  producer_valid: boolean
  publication_blocked: boolean
  review_required: boolean
  question_count: number
  valid_count: number
  invalid_count: number
  duplicate_count: number
  out_of_package_count: number
  out_of_package_kinds: string[]
  candidates: MdCandidateResult[]
  root_errors: string[]
}

// ============================================================
// INTAKE SONUCU
// ============================================================

export interface MdIntakeSubmitResult {
  ok: boolean
  status: "submitted" | "already_received" | "forbidden" | "rejected" | "error"
  batch_id: string | null
  batch_key: string | null
  batch_status: string | null
  counts: {
    totalItems: number
    validItems: number
    invalidItems: number
    duplicateItems: number
    insertedItems: number
  } | null
  staging_ids: string[]
  publication_allowed: boolean
  review_required: boolean
  error: string | null
  root_errors: string[]
}