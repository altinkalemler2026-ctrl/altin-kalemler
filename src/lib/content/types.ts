/**
 * İçerik hattı güvenli veri türleri (kaynak kaydı / müfredat eşleme /
 * denetim orkestrasyonu).
 *
 * Bu dosyadaki türler yalnız sunucu katmanında kullanılan ve istemciye
 * izinli DTO'lara dönüştürülen ham sözleşmeleri tanımlar. Soru gizli
 * alanları (correct_answer, solution) bu katmandan öğrenciye ASLA geçmez.
 */

export const SOURCE_TYPES = ["book", "pdf", "excel", "manual", "ai_generated", "other"] as const

export type SourceType = (typeof SOURCE_TYPES)[number]

/**
 * question_sources.ownership_status — 004_questions_foundation CHECK
 * değerleriyle birebir aynıdır.
 */
export const OWNERSHIP_STATUSES = ["owned", "licensed", "third_party", "ai_original", "unknown"] as const

export type OwnershipStatus = (typeof OWNERSHIP_STATUSES)[number]

/**
 * question_sources.license_status — 004_questions_foundation CHECK
 * değerleriyle birebir aynıdır.
 */
export const LICENSE_STATUSES = ["unknown", "pending", "approved", "restricted"] as const

export type LicenseStatus = (typeof LICENSE_STATUSES)[number]

export function isSourceType(value: unknown): value is SourceType {
  return typeof value === "string" && (SOURCE_TYPES as readonly string[]).includes(value)
}

export function isOwnershipStatus(value: unknown): value is OwnershipStatus {
  return (
    typeof value === "string" &&
    (OWNERSHIP_STATUSES as readonly string[]).includes(value)
  )
}

export function isLicenseStatus(value: unknown): value is LicenseStatus {
  return (
    typeof value === "string" &&
    (LICENSE_STATUSES as readonly string[]).includes(value)
  )
}

/** Aynı dosyanın tekrar kaydında mükerrer oluşmaması için sonuç. */
export interface RegisterSourceResult {
  status: "ok" | "duplicate"
  sourceId: string
  /** duplicate ise var olan kaydın id'si. */
  existingSourceId: string | null
}

export interface SourceDocumentInput {
  sourceType: SourceType
  title: string
  publisher: string | null
  author: string | null
  publicationYear: number | null
  fileName: string | null
  sourceReference: string | null
  ownershipStatus: OwnershipStatus
  licenseStatus: LicenseStatus
  commercialUseAllowed: boolean
  notes: string | null
}

/** Kaynak doküman kayıt künyesi — istemciye verilebilir DTO değildir. */
export interface SourceDocumentRecord {
  id: string
  sourceType: SourceType
  title: string
  publisher: string | null
  author: string | null
  publicationYear: number | null
  fileName: string | null
  sourceReference: string | null
  ownershipStatus: OwnershipStatus
  licenseStatus: LicenseStatus
  commercialUseAllowed: boolean
  notes: string | null
  createdAt: string
  updatedAt: string
}

/** Kaynak sayfa/konum bağlama girdisi. */
export interface SourceLocationInput {
  questionId: string
  sourceId: string
  pageNumber: number | null
  testNumber: number | null
  testCode: string | null
  questionNumber: number | null
  sourceQuestionCode: string | null
  cropReference: string | null
  extractionConfidence: number | null
}

// ============================================================
// MÜFREDAT EŞLEME
// ============================================================

export const MAPPING_REVIEW_STATUSES = ["pending", "approved", "rejected"] as const

export type MappingReviewStatus = (typeof MAPPING_REVIEW_STATUSES)[number]

export const MAPPING_SOURCES = ["manual", "ai_suggested", "auto_matched"] as const

export type MappingSource = (typeof MAPPING_SOURCES)[number]

export function isMappingReviewStatus(value: unknown): value is MappingReviewStatus {
  return (
    typeof value === "string" &&
    (MAPPING_REVIEW_STATUSES as readonly string[]).includes(value)
  )
}

export interface CurriculumMappingTarget {
  topicId: string | null
  outcomeId: string | null
  confidenceScore: number | null
  mappingSource: MappingSource
  reviewStatus: MappingReviewStatus
  notes: string | null
}

/**
 * Belirsiz eşleme incelemesi. Dosya adı veya AI tahmini tek başına kesin
 * eşleme sayılmaz; ambiguityDetected=true ise insan incelemesine gider.
 */
export interface AmbiguousMapping {
  questionId: string
  candidates: CurriculumMappingTarget[]
  ambiguityDetected: true
  reason: string
}

export type MappingResult = {
  status: "approved" | "ambiguous" | "no_candidates"
  mapping: CurriculumMappingTarget | null
  ambiguity: AmbiguousMapping | null
}