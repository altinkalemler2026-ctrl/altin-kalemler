/**
 * Faz 22 — Markdown aday paketi v1.1: parser + preflight + intake testleri.
 *
 * DB erişimi YOKTUR. Parser/preflight deterministik çıktıları ve intake
 * facade'ın mock RPC client üzerinden eşleme davranışı test edilir.
 * "Yayınlanabilir" banner'ı dahil her senaryoda otomatik yayın ASLA
 * mümkün değildir; preflight publication_allowed=true paketleri reddeder.
 */

import { describe, expect, it, vi } from "vitest"

import {
  parseCandidateMd,
} from "./candidate-md-parser"

import {
  preflightCandidateMdPackage,
} from "./candidate-md-preflight"

import {
  submitCandidateMdBatch,
  type MdIntakeOptions,
} from "./candidate-md-intake"

import type { CandidateMdPackageV11 } from "./candidate-md-types"

// ============================================================
// FIXTURES
// ============================================================

const VALID_DOCUMENT = `**Ders:** Matematik
**Üretici:** producer-md-1
**Durum:** needs_review

## 9. sınıf

### AK-ibal-2711

**Kapsam:** MAT.9.1.1 · Kesirler

1/2 ile 3/4'ün toplamı kaçtır?

A. 5/4
B. 4/4
C. 5/8
D. 4/8
E. 6/8

**Tahmin:** kolay · 75 saniye
**Doğru Cevap:** A

**Çözüm:**
1. Paydaları eşitle: 1/2'yi 2/4 yap
2. Topla: 2/4 + 3/4 = 5/4 bul

**Yöntem:** Kesirlerde payda eşitleme yöntemi
**Sonuç:** 5/4 = 1,25
**Gerekçe:** Paydalar eşitlendiğinde 2/4 ile 3/4 toplanır ve 5/4 sonucu elde edilir; A seçeneği bu sonucu gösterdiği için doğru cevaptır
**Çeldirici odağı:** B seçeneği payları toplayıp paydayı koruyan yaklaşımı yansıtır
**Durum:** needs_review

### AK-ibal-2712

**Kapsam:** MAT.9.2.2 · Kesirlerde toplama

3/8 ile 1/8'in toplamı kaçtır?

A. 1/2
B. 4/16
C. 3/16
D. 5/8
E. 2/8

**Tahmin:** zor · 90 saniye
**Doğru Cevap:** A

**Çözüm:**
1. Paydalar aynı olduğundan payları topla
2. Sonucu sadeleştir: 4/8 = 1/2 yap

**Yöntem:** Paydaları eşit kesirleri toplama yöntemi
**Sonuç:** 1/2 = 0,5
**Gerekçe:** 3/8 ile 1/8 toplamı 4/8 eder, sadeleştirince 1/2 çıkar; A seçeneği 1/2 olduğu için doğru cevaptır
**Çeldirici odağı:** B seçeneği paydaları çarpan bir yaklaşımı yansıtır
**Durum:** needs_review
`

function validQuestionJson(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    client_question_id: "AK-ibal-2711",
    grade_level: 9,
    subject_ref: "Matematik",
    subject_id: null,
    outcome_code: "MAT.9.1.1",
    additional_outcome_codes: [],
    editorial_subtopic: "Kesirler",
    has_visual: null,
    question_text: "1/2 ile 3/4'ün toplamı kaçtır?",
    options: {
      A: "5/4",
      B: "4/4",
      C: "5/8",
      D: "4/8",
      E: "6/8",
    },
    correct_answer: "A",
    difficulty: "easy",
    cognitive_type: null,
    estimated_solve_time_seconds: 75,
    solution: {
      method: "Kesirlerde payda eşitleme yöntemi",
      steps: [
        {
          title: "Adım 1",
          content: "1/2'yi 2/4 olarak eşitle",
        },
        {
          title: "Adım 2",
          content: "2/4 ile 3/4'ü topla",
        },
      ],
      result: "5/4 = 1,25",
      correctAnswerJustification:
        "Paydalar eşitlendiğinde 2/4 ile 3/4 toplanır ve 5/4 sonucu elde edilir; A seçeneği bu sonucu gösterdiği için doğru cevaptır",
      commonMistakes: [
        "B seçeneği payları toplayıp paydayı koruyan yaklaşımı yansıtır",
      ],
    },
    validation_requested_status: "needs_review",
    ...overrides,
  }
}

function validPackageJson(
  questionOverrides: Record<string, unknown>[] = [{}]
): CandidateMdPackageV11 {
  return {
    schema_version: "1.1",
    origin: "curriculum_original",
    producer: { id: "producer-md-1", model: "model-x" },
    subject_ref: "Matematik",
    validation_requested_status: "needs_review",
    publication_allowed: false,
    is_active: false,
    questions: questionOverrides.map((o) =>
      validQuestionJson(o)
    ) as unknown as CandidateMdPackageV11["questions"],
    metadata: {
      out_of_package_count: 0,
      out_of_package_kinds: [],
    },
  }
}

/** Minimal mock client; yalnız rpc yakalanır. */
function mockClient(handler: (args: unknown) => Promise<{ data: unknown; error: { message: string } | null }>) {
  const rpc = vi.fn(async (_fn: string, args: { p_payload: Record<string, unknown> }) =>
    handler(args)
  )
  return {
    client: { rpc } as never,
    rpc,
  }
}

// ============================================================
// PARSER
// ============================================================

describe("parseCandidateMd", () => {
  it("geçerli dökümanı iki aday + paket meta ile ayrıştırır", () => {
    const result = parseCandidateMd(VALID_DOCUMENT)

    expect(result.ok).toBe(true)
    expect(result.root_errors).toEqual([])
    expect(result.package).not.toBeNull()

    const pkg = result.package!
    expect(pkg.schema_version).toBe("1.1")
    expect(pkg.origin).toBe("curriculum_original")
    expect(pkg.producer).toEqual({ id: "producer-md-1" })
    expect(pkg.subject_ref).toBe("Matematik")
    expect(pkg.validation_requested_status).toBe("needs_review")
    expect(pkg.publication_allowed).toBe(false)
    expect(pkg.is_active).toBe(false)

    expect(pkg.questions).toHaveLength(2)

    const [q1, q2] = pkg.questions
    expect(q1.client_question_id).toBe("ibal-2711")
    expect(q1.grade_level).toBe(9)
    expect(q1.subject_ref).toBe("Matematik")
    expect(q1.outcome_code).toBe("MAT.9.1.1")
    expect(q1.editorial_subtopic).toBe("Kesirler")
    expect(q1.question_text).toContain("1/2 ile 3/4")
    expect(q1.options.A).toBe("5/4")
    expect(q1.options.E).toBe("6/8")
    expect(q1.correct_answer).toBe("A")
    expect(q1.difficulty).toBe("easy")
    expect(q1.estimated_solve_time_seconds).toBe(75)
    expect(q1.solution.method).toContain("payda eşitleme")
    expect(q1.solution.steps).toHaveLength(2)
    expect(q1.solution.result).toContain("1,25")
    expect(q1.solution.correctAnswerJustification!.length).toBeGreaterThan(40)
    expect(q1.solution.commonMistakes).toHaveLength(1)
    expect(q1.validation_requested_status).toBe("needs_review")

    expect(q2.client_question_id).toBe("ibal-2712")
    expect(q2.grade_level).toBe(9)
    expect(q2.outcome_code).toBe("MAT.9.2.2")
    expect(q2.difficulty).toBe("hard")
    expect(q2.estimated_solve_time_seconds).toBe(90)
  })

  it("paket-dışı içerikleri SAYAR; içeriği taşımaz", () => {
    const doc = `${VALID_DOCUMENT}

| A | B |
|---|---|

## Bilinmeyen Bölüm

**Bilinmeyen Etiket:** değer

Dışarıda kalan serbest metin.
`
    const result = parseCandidateMd(doc)

    expect(result.ok).toBe(true)
    // açık blok sonrası: tablo satırı(2: başlık + ayraç) + bilinmeyen başlık(1)
    // + bilinmeyen etiket(1) + başlık sonrası serbest metin(1)
    expect(result.out_of_package.length).toBe(5)

    const kinds = new Set(result.out_of_package.map((i) => i.kind))
    expect(kinds.has("free_text_outside_block")).toBe(true)
    expect(kinds.has("table_row")).toBe(true)
    expect(kinds.has("unknown_heading")).toBe(true)
    expect(kinds.has("unknown_metadata_line")).toBe(true)

    const pkg = result.package!
    expect(pkg.metadata.out_of_package_count).toBe(5)
    expect(pkg.metadata.out_of_package_kinds.length).toBeGreaterThan(0)

    // içerik hiçbir adaya sızmaz
    expect(pkg.questions).toHaveLength(2)
    expect(pkg.questions[0].question_text).not.toContain("Dışarıda kalan")
  })

  it("hiç AK bloğu yoksa ok=false + root hata", () => {
    const result = parseCandidateMd("# Başlık\n\nBir şeyler var\n")

    expect(result.ok).toBe(false)
    expect(result.root_errors).toContain("no_candidate_blocks_found")
    expect(result.package!.questions).toHaveLength(0)
  })

  it("deterministiktir: aynı girdi aynı çıktı", () => {
    const a = parseCandidateMd(VALID_DOCUMENT)
    const b = parseCandidateMd(VALID_DOCUMENT)

    expect(JSON.parse(JSON.stringify(a.package))).toEqual(
      JSON.parse(JSON.stringify(b.package))
    )
    expect(a.out_of_package).toEqual(b.out_of_package)
    expect(a.parse_notes).toEqual(b.parse_notes)
  })

  it("Yayınlanabilir banner'ı publication_allowed=true yapar", () => {
    const doc = `**Üretici:** producer-md-1

**Yayınlanabilir** (onaylandı)

${VALID_DOCUMENT}
`
    const result = parseCandidateMd(doc)

    expect(result.package!.publication_allowed).toBe(true)
  })
})

// ============================================================
// PREFLIGHT
// ============================================================

describe("preflightCandidateMdPackage", () => {
  it("geçerli paketi accepted yapar", () => {
    const result = preflightCandidateMdPackage(validPackageJson())

    expect(result.status).toBe("accepted")
    expect(result.root_valid).toBe(true)
    expect(result.root_errors).toEqual([])
    expect(result.question_count).toBe(1)
    expect(result.valid_count).toBe(1)
    expect(result.invalid_count).toBe(0)
    expect(result.duplicate_count).toBe(0)
    expect(result.review_required).toBe(true)
  })

  it("üretici yoksa rejected (uydurma yok)", () => {
    const pkg = validPackageJson()
    pkg.producer = null

    const result = preflightCandidateMdPackage(pkg)

    expect(result.status).toBe("rejected")
    expect(result.root_valid).toBe(false)
    expect(result.root_errors).toContain("producer_id_bos_olamaz")
  })

  it("Yayınlanabilir paketi root'ta bloklar", () => {
    const pkg = validPackageJson()
    pkg.publication_allowed = true

    const result = preflightCandidateMdPackage(pkg)

    expect(result.status).toBe("rejected")
    expect(result.root_errors).toContain("publication_allowed_false_olmali")
    expect(result.review_required).toBe(true)
  })

  it("yanlış şema sürümü ve origin reddedilir", () => {
    const pkg = validPackageJson() as unknown as Record<string, unknown>
    pkg.schema_version = "1.0"
    pkg.origin = "external_producer"

    const result = preflightCandidateMdPackage(pkg)

    expect(result.root_errors).toContain("schema_version_1_1_olmali")
    expect(result.root_errors).toContain("origin_yalnizca_curriculum_original_olmali")
    expect(result.status).toBe("rejected")
  })

  it("E seçeneği eksikse candidate invalid + option_E_eksik", () => {
    const pkg = validPackageJson([
      {
        options: {
          A: "5/4",
          B: "4/4",
          C: "5/8",
          D: "4/8",
        },
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    // Tek aday geçersiz ve geçerli/duplicate yok → paket düzeyi rejected.
    expect(result.status).toBe("rejected")
    expect(result.valid_count).toBe(0)
    expect(result.invalid_count).toBe(1)
    expect(result.candidates[0].errors).toContain("option_E_eksik")
    expect(result.review_required).toBe(true)
  })

  it("çözüm eksik alanlarda ilgili hataları üretir", () => {
    const pkg = validPackageJson([
      {
        solution: {
          method: "k",
          steps: [{ title: "x", content: "tek adım kısa" }],
          result: "x",
          correctAnswerJustification: "kısa",
          commonMistakes: [],
        },
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    const errors = result.candidates[0].errors
    expect(errors).toContain("solution_bos_metod")
    expect(errors).toContain("solution_en_az_iki_adim_olmali")
    expect(errors).toContain("solution_bos_sonuc")
    expect(errors).toContain("solution_kisa_gerekce")
    expect(errors).toContain("solution_common_mistakes_eksik")
  })

  it("birden fazla kazanım kodu bloklanır, otomatik seçim yapılmaz", () => {
    const pkg = validPackageJson([
      { additional_outcome_codes: ["MAT.9.1.2"] },
    ])

    const result = preflightCandidateMdPackage(pkg)

    expect(result.candidates[0].errors).toContain("birden_fazla_kazanim_kodu")
    expect(result.valid_count).toBe(0)
  })

  it("geçersiz grade ve eksik subject hatalarını üretir", () => {
    const pkg = validPackageJson([
      {
        grade_level: 0,
        subject_ref: null,
        subject_id: null,
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    const errors = result.candidates[0].errors
    expect(errors).toContain("grade_level_1_12_olmali")
    expect(errors).toContain("subject_id_veya_subject_ref_zorunlu")
  })

  it("yasaklı alan taşıyan aday reddedilir", () => {
    const pkg = validPackageJson([
      {
        source_question_text: "kaynak",
        pdf_reference: "s.12",
        image_data: "x",
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    const errors = result.candidates[0].errors
    expect(errors.some((e) => e.startsWith("yasakli_alan:"))).toBe(true)
  })

  it("paket-içi tekrar soru metni → her iki aday da duplicate", () => {
    const pkg = validPackageJson([
      {},
      {
        client_question_id: "AK-other",
        question_text: "  1/2 ile 3/4'ün toplamı kaçtır?  ",
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    expect(result.status).toBe("partially_accepted")
    expect(result.valid_count).toBe(0)
    expect(result.duplicate_count).toBe(2)
    const dups = result.candidates.filter((c) => c.status === "duplicate")
    expect(dups).toHaveLength(2)
    for (const dup of dups) {
      expect(dup.errors).toContain("ayni_normalized_soru_metni_tekrar")
    }
  })

  it("tekrar client_question_id (farklı metin) → duplicate", () => {
    const pkg = validPackageJson([
      {},
      {
        client_question_id: "AK-ibal-2711",
        question_text: "3/8 ile 1/8'in toplamı kaçtır?",
      },
    ])

    const result = preflightCandidateMdPackage(pkg)

    const dups = result.candidates.filter((c) => c.status === "duplicate")
    expect(dups).toHaveLength(2)
    for (const dup of dups) {
      expect(dup.errors).toContain("ayni_client_question_id_tekrar")
    }
  })
})

// ============================================================
// INTAKE FACADE
// ============================================================

describe("submitCandidateMdBatch", () => {
  it("geçerli dökümanı RPC'ye iletir ve sonucu eşler", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {
        batch_id: "11111111-1111-4111-8111-111111111111",
        batch_key: "producer-md-1:md:abc123",
        status: "ingested",
        total_items: 2,
        valid_items: 2,
        invalid_items: 0,
        duplicate_items: 0,
        inserted_items: 2,
        staging_ids: ["44444444-4444-4444-8444-444444444444"],
      },
      error: null,
    }))

    const result = await submitCandidateMdBatch(
      client as never,
      VALID_DOCUMENT,
      { producer: { id: "fallback-producer" } } as MdIntakeOptions
    )

    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0][0]).toBe("register_candidate_md_batch")

    const payload = rpc.mock.calls[0][1].p_payload as Record<string, unknown>
    expect(payload.schema_version).toBe("1.1")
    expect((payload as { producer: { id: string } }).producer.id).toBe(
      "producer-md-1"
    )
    expect(payload.publication_allowed).toBe(false)
    expect(payload.is_active).toBe(false)

    expect(result.ok).toBe(true)
    expect(result.status).toBe("submitted")
    expect(result.batch_id).toBe("11111111-1111-4111-8111-111111111111")
    expect(result.counts).toEqual({
      totalItems: 2,
      validItems: 2,
      invalidItems: 0,
      duplicateItems: 0,
      insertedItems: 2,
    })
    expect(result.staging_ids).toEqual(["44444444-4444-4444-8444-444444444444"])
    expect(result.review_required).toBe(true)
  })

  it("root hatası olan paket (paket durumu published) RPC'ye İLETİLMEZ", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {},
      error: null,
    }))

    const doc = VALID_DOCUMENT.replace(
      "**Durum:** needs_review",
      "**Durum:** published"
    )
    const result = await submitCandidateMdBatch(client as never, doc)

    expect(result.ok).toBe(false)
    expect(result.status).toBe("forbidden")
    expect(result.root_errors).toContain("paket_durum_not_importable")
    expect(rpc).not.toHaveBeenCalled()
  })

  it("üretici etiketi yoksa ve seçenek de yoksa forbidden (RPC yok)", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {},
      error: null,
    }))

    const doc = VALID_DOCUMENT.replace("**Üretici:** producer-md-1\n", "")
    const result = await submitCandidateMdBatch(client as never, doc)

    expect(result.status).toBe("forbidden")
    expect(result.ok).toBe(false)
    expect(result.root_errors).toContain("producer_id_bos_olamaz")
    expect(rpc).not.toHaveBeenCalled()
  })

  it("RPC hatasını status=error olarak eşler", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: null,
      error: { message: "Permission denied" },
    }))

    const result = await submitCandidateMdBatch(client as never, VALID_DOCUMENT)

    expect(rpc).toHaveBeenCalledTimes(1)
    expect(result.ok).toBe(false)
    expect(result.status).toBe("error")
    expect(result.error).toBe("Permission denied")
  })

  it("already_received yanıtını işler", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {
        batch_id: "22222222-2222-4222-8222-222222222222",
        status: "already_received",
        total_items: 2,
        valid_items: 2,
        invalid_items: 0,
        duplicate_items: 0,
        inserted_items: 2,
        staging_ids: ["55555555-5555-4555-8555-555555555555"],
      },
      error: null,
    }))

    const result = await submitCandidateMdBatch(client as never, VALID_DOCUMENT)

    expect(rpc).toHaveBeenCalledTimes(1)
    expect(result.ok).toBe(true)
    expect(result.status).toBe("already_received")
    expect(result.batch_status).toBe("already_received")
  })

  it("checkUniverseDuplicate kancası valid adayı duplicate yapar", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {
        batch_id: "33333333-3333-4333-8333-333333333333",
        status: "partially_valid",
        total_items: 2,
        valid_items: 1,
        invalid_items: 0,
        duplicate_items: 1,
        inserted_items: 1,
        staging_ids: [],
      },
      error: null,
    }))

    const result = await submitCandidateMdBatch(client as never, VALID_DOCUMENT, {
      checkUniverseDuplicate: async (text) => text.includes("3/8"),
    } as MdIntakeOptions)

    expect(rpc).toHaveBeenCalledTimes(1)
    expect(result.status).toBe("submitted")
    expect(result.counts!.duplicateItems).toBe(1)
  })

  it("parse ok değilse (blok yok) rejected döner; RPC yok", async () => {
    const { client, rpc } = mockClient(async () => ({
      data: {},
      error: null,
    }))

    const result = await submitCandidateMdBatch(client as never, "# başlık")

    expect(result.ok).toBe(false)
    expect(result.status).toBe("rejected")
    expect(rpc).not.toHaveBeenCalled()
  })
})