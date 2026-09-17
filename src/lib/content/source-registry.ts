/**
 * Kaynak doküman kaydı servisi.
 *
 * - PDF/Excel/manuel kaynakları mevcut kaynak sistemiyle (question_sources /
 *   question_source_locations) kaydeder. Şema sözleşmesi 004_questions_foundation
 *   migration'ındaki gerçek kolonlardır (hayali alan içermez).
 * - Aynı kaynak tekrar kaydedilmek istenirse mükerrer kayıt oluşturmaz:
 *   `file_name` benzersizlik anahtarı olarak okunur (DB'de bu kolonda unique
 *   kısıt yoktur; servis önce okur). Teker teker eşleşen kayıt varsa
 *   duplicate durumu döner.
 * - Lisans/sahiplik alanları DB CHECK allowlist'iyle sınırlanır
 *   (ownership_status / license_status / commercial_use_allowed).
 *   "unknown / commercial_use_allowed=false" olan bir kaynak asla içerik
 *   üretim girdisi gibi imzalanmaz; üretim hattı 036 telif/orijinallik
 *   kapısından geçer ve bu servis içerik girişi yapmaz.
 * - Soru ile kaynak sayfası bağlaması 039 promotion deseniyle uyumludur:
 *   (question_id, source_id) ikilisi tekrar bağlanmak istenirse mevcut kayıt
 *   korunur, yeni satır açılmaz (idempotent, ON CONFLICT DO NOTHING karşılığı).
 * - Test edilebilirlik için istemci DI olarak verilir; RPC yok, tablo insert/kısıtlı
 *   insert kullanılır. aynı dosya hash'i kavramı DB'de YOKTUR — bu servis
 *   yalnızca DB'de gerçekten var olan alanlarla çalışır.
 */

import type { SupabaseClient } from "@supabase/supabase-js"

import type { Database } from "@/lib/supabase/types"

import {
  isLicenseStatus,
  isOwnershipStatus,
  isSourceType,
  type RegisterSourceResult,
  type SourceDocumentInput,
  type SourceDocumentRecord,
  type SourceLocationInput,
} from "./types"

export type ContentClient = SupabaseClient<Database>

export class SourceValidationError extends Error {}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function assertUuid(value: string, label: string): string {
  if (!UUID_PATTERN.test(value)) {
    throw new SourceValidationError(`${label} geçerli bir UUID değil.`)
  }
  return value
}

function trimToNullable(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null
}

function toNullableNumber(value: unknown): number | null {
  if (typeof value === "number" && value > 0) return Math.trunc(value)
  if (typeof value === "string") {
    const parsed = Number(value)
    if (Number.isFinite(parsed) && parsed > 0) return Math.trunc(parsed)
  }
  return null
}

/** Geçerli ve eksiksiz kaynak girdi doğrulaması. */
export function validateSourceInput(input: SourceDocumentInput): void {
  if (!isSourceType(input.sourceType)) {
    throw new SourceValidationError("Geçersiz kaynak türü.")
  }
  const title = trimToNullable(input.title)
  if (!title) {
    throw new SourceValidationError("Kaynak başlığı boş olamaz.")
  }
  if (!isOwnershipStatus(input.ownershipStatus)) {
    throw new SourceValidationError("Geçersiz sahiplik durumu.")
  }
  if (!isLicenseStatus(input.licenseStatus)) {
    throw new SourceValidationError("Geçersiz lisans durumu.")
  }
}

/**
 * Kaynak dokümanı kaydeder. Aynı `file_name` daha önce kaydedilmişse mükerrer
 * kayıt oluşturmaz ve duplicate durumu döner. `file_name` boşsa kayıt yine
 * oluşturulur (önbellek benzersizlik anahtarı gerektirmeyen adaylar).
 */
export async function registerSourceDocument(
  client: ContentClient,
  input: SourceDocumentInput
): Promise<RegisterSourceResult> {
  validateSourceInput(input)

  const fileName = trimToNullable(input.fileName)
  if (fileName) {
    const { data: existing, error: lookupError } = await client
      .from("question_sources")
      .select("id")
      .eq("file_name", fileName)
      .maybeSingle()

    if (lookupError) throw lookupError
    if (existing) {
      return {
        status: "duplicate",
        sourceId: existing.id as string,
        existingSourceId: existing.id as string,
      }
    }
  }

  const { data, error } = await client
    .from("question_sources")
    .insert({
      source_type: input.sourceType,
      title: trimToNullable(input.title) as string,
      publisher: trimToNullable(input.publisher),
      author: trimToNullable(input.author),
      publication_year: toNullableNumber(input.publicationYear),
      file_name: fileName,
      source_reference: trimToNullable(input.sourceReference),
      ownership_status: input.ownershipStatus,
      license_status: input.licenseStatus,
      commercial_use_allowed: input.commercialUseAllowed,
      notes: trimToNullable(input.notes),
    })
    .select(
      "id, source_type, title, publisher, author, publication_year, file_name, source_reference, ownership_status, license_status, commercial_use_allowed, notes, created_at, updated_at"
    )
    .single()

  if (error) throw error

  return {
    status: "ok",
    sourceId: data.id as string,
    existingSourceId: null,
  }
}

/**
 * Kaynak künyesini DB satırından okur. DB CHECK allowlist'ine uymayan değerler
 * dahil edilmez (fail-open değildir; ele alınmayan değer null döner).
 */
export function toSourceDocumentRecord(row: unknown): SourceDocumentRecord | null {
  if (row === null || typeof row !== "object") return null
  const r = row as Record<string, unknown>

  const sourceType = r["source_type"]
  const ownershipStatus = r["ownership_status"]
  const licenseStatus = r["license_status"]
  const id = typeof r["id"] === "string" ? r["id"] : null

  if (!id || !isSourceType(sourceType) || !isOwnershipStatus(ownershipStatus) || !isLicenseStatus(licenseStatus)) {
    return null
  }

  const createdAt = typeof r["created_at"] === "string" ? r["created_at"] : null
  const updatedAt = typeof r["updated_at"] === "string" ? r["updated_at"] : null
  if (!createdAt || !updatedAt) return null

  return {
    id,
    sourceType,
    title: trimToNullable(r["title"]) as string,
    publisher: trimToNullable(r["publisher"]),
    author: trimToNullable(r["author"]),
    publicationYear: toNullableNumber(r["publication_year"]),
    fileName: trimToNullable(r["file_name"]),
    sourceReference: trimToNullable(r["source_reference"]),
    ownershipStatus,
    licenseStatus,
    commercialUseAllowed: r["commercial_use_allowed"] === true,
    notes: trimToNullable(r["notes"]),
    createdAt,
    updatedAt,
  }
}

/**
 * Soru ile kaynak sayfası arasında bağlama kaydı oluşturur. (question_id,
 * source_id) ikilisi daha önce bağlanmışsa yeni satır açılmaz — mevcut kayıt
 * korunur ve idempotent biçimde döner (039 promotion'daki
 * UNIQUE(question_id, source_id) + ON CONFLICT DO NOTHING deseniyle birebir
 * uyumlu). Soru yalnız "referans" amaçlıdır; bu servis soru içeriğini
 * DEĞİŞTİRMEZ.
 */
export async function linkQuestionToSource(
  client: ContentClient,
  input: SourceLocationInput
): Promise<{ id: string; duplicate: boolean }> {
  assertUuid(input.questionId, "Soru id")
  assertUuid(input.sourceId, "Kaynak id")

  const confidenceScore = clampConfidence(input.extractionConfidence)

  const { data, error } = await client
    .from("question_source_locations")
    .insert({
      question_id: input.questionId,
      source_id: input.sourceId,
      page_number: toNullableNumber(input.pageNumber),
      test_number: toNullableNumber(input.testNumber),
      test_code: trimToNullable(input.testCode),
      question_number: toNullableNumber(input.questionNumber),
      source_question_code: trimToNullable(input.sourceQuestionCode),
      crop_reference: trimToNullable(input.cropReference),
      extraction_confidence: confidenceScore,
    })
    .select("id")
    .single()

  if (error) {
    // UNIQUE(question_id, source_id) ihlali — yarış içi mükerrer bağlama:
    // mevcut kaydı bul ve değişiklik yapmadan dön (039 ON CONFLICT DO NOTHING
    // davranışı).
    const isUniqueViolation =
      typeof error === "object" && error !== null && "code" in error && error.code === "23505"

    if (!isUniqueViolation) throw error

    const { data: existing, error: lookupError } = await client
      .from("question_source_locations")
      .select("id")
      .eq("question_id", input.questionId)
      .eq("source_id", input.sourceId)
      .maybeSingle()

    if (lookupError) throw lookupError
    if (!existing) throw error

    return { id: existing.id as string, duplicate: true }
  }

  return { id: data.id as string, duplicate: false }
}

function clampConfidence(value: number | null): number | null {
  if (value === null || value === undefined) return null
  return Math.min(1, Math.max(0, value))
}