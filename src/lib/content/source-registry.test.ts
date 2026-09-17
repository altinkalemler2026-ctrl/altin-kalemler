/**
 * source-registry testleri.
 *
 * - Aynı file_name ile mükerrer kayıt oluşmaz (duplicate döner).
 * - Yazılan alanlar 004_questions_foundation gerçek DB kolon setidir; hayali
 *   alan içermez.
 * - Lisans/sahiplik allowlist doğrulaması sıkıdır.
 * - (question_id, source_id) tekrar bağlaması idempotenttir (039 deseni).
 * - Oradaydı diye hash/metadata/section_name vb. alanlar MOCK'ta tanımlanmaz.
 */

import { describe, expect, it } from "vitest"

import {
  linkQuestionToSource,
  registerSourceDocument,
  toSourceDocumentRecord,
  validateSourceInput,
  SourceValidationError,
  type ContentClient,
} from "./source-registry"

const UUID = "11111111-1111-4111-8111-111111111111"

/**
 * Gerçek DB kolonlarını taşıyan mock satır — kaynak künyesi.
 */
function sourceRow(overrides: Record<string, unknown> = {}) {
  return {
    id: UUID,
    source_type: "pdf",
    title: "matematik.pdf",
    publisher: null,
    author: null,
    publication_year: null,
    file_name: "matematik.pdf",
    source_reference: "D:\\kaynak\\matematik.pdf",
    ownership_status: "unknown",
    license_status: "unknown",
    commercial_use_allowed: false,
    notes: null,
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    ...overrides,
  }
}

/** Süreç-akışı için jest-benzeri zincir mock (yalnız kullanılan kolonlar). */
function buildChain(slots: {
  lookup?: { data?: unknown; error?: { message?: string; code?: string } | null }
  insert?: { data?: unknown; error?: { message?: string; code?: string } | null }
} = {}) {
  const state = { queriedFileName: "", inserted: [] as unknown[], linked: false }

  const selectChain = {
    select() {
      return selectChain
    },
    eq(_col: string, value: string) {
      if (_col === "file_name") state.queriedFileName = value
      return selectChain
    },
    maybeSingle() {
      return Promise.resolve({
        data: slots.lookup?.data === undefined ? null : slots.lookup.data,
        error: slots.lookup?.error ?? null,
      })
    },
    single() {
      return Promise.resolve({
        data: slots.insert?.data === undefined ? null : slots.insert.data,
        error: slots.insert?.error ?? null,
      })
    },
  }

  const client = {
    from(table: string) {
      if (table === "question_sources" || table === "question_source_locations") {
        return {
          ...selectChain,
          insert(payload: unknown) {
            state.inserted.push(payload)
            if (table === "question_source_locations") state.linked = true
            return {
              select() {
                return {
                  single() {
                    return Promise.resolve({
                      data: slots.insert?.data === undefined ? { id: UUID } : slots.insert.data,
                      error: slots.insert?.error ?? null,
                    })
                  },
                }
              },
            }
          },
        }
      }
      return selectChain
    },
  }

  return { client: client as unknown as ContentClient, state }
}

describe("validateSourceInput", () => {
  const base = {
    sourceType: "pdf" as const,
    title: "matematik.pdf",
    publisher: null,
    author: null,
    publicationYear: null,
    fileName: "matematik.pdf",
    sourceReference: null,
    ownershipStatus: "unknown" as const,
    licenseStatus: "unknown" as const,
    commercialUseAllowed: false,
    notes: null,
  }

  it("geçerli girdiyi kabul eder", () => {
    expect(() => validateSourceInput(base)).not.toThrow()
  })

  it("geçersiz tür/başlık/sahiplik/lisansı reddeder", () => {
    expect(() => validateSourceInput({ ...base, sourceType: "exe" as never })).toThrow(
      SourceValidationError
    )
    expect(() => validateSourceInput({ ...base, title: " " })).toThrow(
      /Kaynak başlığı/
    )
    expect(() =>
      validateSourceInput({ ...base, ownershipStatus: "belirsiz" as never })
    ).toThrow(/sahiplik/)
    expect(() =>
      validateSourceInput({ ...base, licenseStatus: "free" as never })
    ).toThrow(/lisans/)
  })
})

describe("registerSourceDocument — mükerrer koruması (file_name anahtarı)", () => {
  it("file_name önceden kayıtlıysa duplicate döner ve yeni insert YOKTUR", async () => {
    const { client, state } = buildChain({ lookup: { data: sourceRow() } })
    const result = await registerSourceDocument(client, {
      sourceType: "pdf",
      title: "matematik.pdf",
      publisher: null,
      author: null,
      publicationYear: null,
      fileName: "matematik.pdf",
      sourceReference: "D:\\kaynak\\matematik.pdf",
      ownershipStatus: "unknown",
      licenseStatus: "unknown",
      commercialUseAllowed: false,
      notes: null,
    })

    expect(result.status).toBe("duplicate")
    expect(result.existingSourceId).toBe(UUID)
    expect(state.inserted).toHaveLength(0)
    expect(state.queriedFileName).toBe("matematik.pdf")
  })

  it("file_name yoksa kaydı oluşturur ve sourceId döner", async () => {
    const { client, state } = buildChain({ lookup: { data: null } })
    const result = await registerSourceDocument(client, {
      sourceType: "pdf",
      title: "tyt-matematik.pdf",
      publisher: null,
      author: null,
      publicationYear: null,
      fileName: "tyt-matematik.pdf",
      sourceReference: "D:\\kaynak\\tyt-matematik.pdf",
      ownershipStatus: "unknown",
      licenseStatus: "unknown",
      commercialUseAllowed: false,
      notes: null,
    })

    expect(result.status).toBe("ok")
    expect(result.sourceId).toBe(UUID)
    expect(state.inserted).toHaveLength(1)
  })

  it("insert payload'ı yalnız gerçek DB kolonlarını içerir", async () => {
    const { client, state } = buildChain({ lookup: { data: null } })
    await registerSourceDocument(client, {
      sourceType: "book",
      title: "Kitap A",
      publisher: "Yayıncı X",
      author: "Yazar Y",
      publicationYear: 2024,
      fileName: "kitap-a.pdf",
      sourceReference: "raflar/kitap-a.pdf",
      ownershipStatus: "licensed",
      licenseStatus: "approved",
      commercialUseAllowed: true,
      notes: "onaylı",
    })

    const payload = state.inserted[0] as Record<string, unknown>
    expect(Object.keys(payload).sort()).toEqual([
      "author",
      "commercial_use_allowed",
      "file_name",
      "license_status",
      "notes",
      "ownership_status",
      "publication_year",
      "publisher",
      "source_reference",
      "source_type",
      "title",
    ])
    expect(payload).not.toHaveProperty("file_hash")
    expect(payload).not.toHaveProperty("source_name")
    expect(payload).not.toHaveProperty("metadata")
    expect(payload).not.toHaveProperty("process_status")
    expect(payload).not.toHaveProperty("needs_ocr")
  })
})

describe("toSourceDocumentRecord — DB satırından künye", () => {
  it("geçerli satırı künyeye çevirir", () => {
    const record = toSourceDocumentRecord(sourceRow())
    expect(record).not.toBeNull()
    expect(record?.title).toBe("matematik.pdf")
    expect(record?.ownershipStatus).toBe("unknown")
    expect(record?.licenseStatus).toBe("unknown")
    expect(record?.commercialUseAllowed).toBe(false)
  })

  it("tanımayan sahiplik/lisans değeri veya eksik zaman damgası null döner", () => {
    expect(toSourceDocumentRecord(sourceRow({ ownership_status: "yok" }))).toBeNull()
    expect(toSourceDocumentRecord(sourceRow({ license_status: "yok" }))).toBeNull()
    expect(toSourceDocumentRecord(sourceRow({ created_at: null }))).toBeNull()
    expect(toSourceDocumentRecord(null)).toBeNull()
  })
})

describe("linkQuestionToSource — idempotent bağlama (039 deseni)", () => {
  it("geçerli bağlantı kaydı oluşturur; istenen kolonlar yazılır", async () => {
    const { client, state } = buildChain()
    const id = await linkQuestionToSource(client, {
      questionId: "11111111-1111-4111-8111-000000000001",
      sourceId: "11111111-1111-4111-8111-000000000002",
      pageNumber: 3,
      testNumber: 1,
      testCode: "TEST1",
      questionNumber: 5,
      sourceQuestionCode: "KY-A-1",
      cropReference: null,
      extractionConfidence: 0.9,
    })

    expect(id).toEqual({ id: UUID, duplicate: false })
    expect(state.linked).toBe(true)
  })

  it("extraction_confidence 0..1 aralığına kıstırılır", async () => {
    const { client, state } = buildChain()
    await linkQuestionToSource(client, {
      questionId: "11111111-1111-4111-8111-000000000001",
      sourceId: "11111111-1111-4111-8111-000000000002",
      pageNumber: null,
      testNumber: null,
      testCode: null,
      questionNumber: null,
      sourceQuestionCode: null,
      cropReference: null,
      extractionConfidence: 1.4,
    })

    const payload = state.inserted[0] as { extraction_confidence?: number }
    expect(payload.extraction_confidence).toBe(1)
  })

  it("UNIQUE ihlali (23505) mevcut kaydı döner, idempotent", async () => {
    const { client, state } = buildChain({
      insert: { error: { message: "duplicate key value violates unique constraint", code: "23505" } },
      lookup: { data: { id: UUID } },
    })
    const result = await linkQuestionToSource(client, {
      questionId: "11111111-1111-4111-8111-000000000001",
      sourceId: "11111111-1111-4111-8111-000000000002",
      pageNumber: null,
      testNumber: null,
      testCode: null,
      questionNumber: null,
      sourceQuestionCode: null,
      cropReference: null,
      extractionConfidence: null,
    })

    expect(result).toEqual({ id: UUID, duplicate: true })
    expect(state.linked).toBe(true)
  })

  it("geçersiz UUID reddedilir; kayıt oluşmaz", async () => {
    const { client, state } = buildChain()
    await expect(
      linkQuestionToSource(client, {
        questionId: "bozuk",
        sourceId: "11111111-1111-4111-8111-000000000002",
        pageNumber: null,
        testNumber: null,
        testCode: null,
        questionNumber: null,
        sourceQuestionCode: null,
        cropReference: null,
        extractionConfidence: null,
      })
    ).rejects.toBeInstanceOf(SourceValidationError)
    expect(state.linked).toBe(false)
  })
})