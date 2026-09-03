// @vitest-environment node
/**
 * Soru düzenleme/yayın doğrulama + hata çevirisi + DB sözleşme testleri.
 *
 * - Girdi doğrulaması RPC'ye gitmeden reddedilmelidir.
 * - RPC hata metinleri Türkçeye çevrilir; ham DB mesajı sızmaz.
 * - 089 audit deseni kaynak düzeyinde doğrulanır: mutation +
 *   admin_audit_log INSERT AYNI fonksiyonda (AYNI transaction) ve
 *   audit_id döndürülür; izin questions.edit'tir.
 * - 040 yayın RPC sözleşmeleri kaynak düzeyinde doğrulanır.
 */

import { describe, expect, it } from "vitest"
import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"

import {
  QUESTION_EDIT_ERROR_MESSAGES,
  QUESTION_EDIT_INPUT_MESSAGES,
  QUESTION_PUBLICATION_MESSAGES,
  formatBlockerFlash,
  mapBlockerMessage,
  mapQuestionEditError,
  validateActivateReason,
  validateDeactivateReason,
  validateQuestionEditInput,
} from "./question-edit-errors"

const UUID = "aaaaaaaa-1111-4000-8000-000000000001"

function validRawInput() {
  return {
    questionId: UUID,
    questionText: "  2 + 2 kaçtır?  ",
    optionA: " 3 ",
    optionB: "4",
    optionC: "5",
    optionD: "6",
    optionE: "   ",
    correctAnswer: "b",
  }
}

describe("validateQuestionEditInput", () => {
  it("geçerli girdiyi kırpıp normalize eder; boş E seçeneği temizlenir", () => {
    const result = validateQuestionEditInput(validRawInput())
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.value.questionId).toBe(UUID)
    expect(result.value.questionText).toBe("2 + 2 kaçtır?")
    expect(result.value.optionA).toBe("3")
    expect(result.value.correctAnswer).toBe("B")
    expect(result.value.optionE).toBe("")
  })

  it("geçersiz UUID reddedilir", () => {
    const invalid = validateQuestionEditInput({
      ...validRawInput(),
      questionId: "not-a-uuid",
    })
    expect(invalid).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.questionIdInvalid,
    })
  })

  it("boş soru metni RPC'ye gitmeden reddedilir", () => {
    const result = validateQuestionEditInput({
      ...validRawInput(),
      questionText: "   ",
    })
    expect(result).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.questionTextRequired,
    })
  })

  it("çok uzun soru metni reddedilir", () => {
    const result = validateQuestionEditInput({
      ...validRawInput(),
      questionText: "x".repeat(10_001),
    })
    expect(result).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.questionTextTooLong,
    })
  })

  it("boş A-D seçeneği reddedilir; E boş bırakılabilir", () => {
    const missingD = validateQuestionEditInput({
      ...validRawInput(),
      optionD: "",
    })
    expect(missingD).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.optionRequired,
    })

    const emptyE = validateQuestionEditInput({
      ...validRawInput(),
      optionE: "",
    })
    expect(emptyE.ok).toBe(true)
  })

  it("çok uzun seçenek reddedilir", () => {
    const result = validateQuestionEditInput({
      ...validRawInput(),
      optionB: "y".repeat(2_001),
    })
    expect(result).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.optionTooLong,
    })
  })

  it("A-E dışı doğru cevap reddedilir", () => {
    for (const answer of ["F", "", "AB", "1"]) {
      const result = validateQuestionEditInput({
        ...validRawInput(),
        correctAnswer: answer,
      })
      expect(result).toEqual({
        ok: false,
        message: QUESTION_EDIT_INPUT_MESSAGES.correctAnswerInvalid,
      })
    }
  })
})

describe("validateDeactivateReason / validateActivateReason", () => {
  it("boş geri çekme sebebi reddedilir", () => {
    const result = validateDeactivateReason("   ")
    expect(result).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.deactivateReasonRequired,
    })
  })

  it("uzun sebep reddedilir; geçerli sebep kırpılır", () => {
    expect(validateDeactivateReason("x".repeat(501))).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.reasonTooLong,
    })
    const ok = validateDeactivateReason("  telif ihlali  ")
    expect(ok).toEqual({ ok: true, value: "telif ihlali" })
  })

  it("yayın sebebi opsiyoneldir; boş -> null", () => {
    expect(validateActivateReason("  ")).toEqual({ ok: true, value: null })
    const ok = validateActivateReason(" dönem ortası yayın ")
    expect(ok).toEqual({ ok: true, value: "dönem ortası yayın" })
    expect(validateActivateReason("x".repeat(501))).toEqual({
      ok: false,
      message: QUESTION_EDIT_INPUT_MESSAGES.reasonTooLong,
    })
  })
})

describe("mapQuestionEditError", () => {
  it("089 izin hatası Türkçe yetki mesajına çevrilir", () => {
    expect(
      mapQuestionEditError({ message: "Question edit permission required." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.forbidden)
  })

  it("040 yayın izin hatası yayına özel mesaja çevrilir", () => {
    expect(
      mapQuestionEditError({
        message: "Question approval permission required.",
      })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.publishForbidden)
    expect(
      mapQuestionEditError({ message: "Admin permission required." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.publishForbidden)
  })

  it("bulunamadı / oturum / girdi hataları ayrı mesajlara çevrilir", () => {
    expect(
      mapQuestionEditError({ message: "Question not found." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.notFound)
    expect(
      mapQuestionEditError({ message: "Human authentication required." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.sessionRequired)
    expect(
      mapQuestionEditError({ message: "Invalid correct answer." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.invalidInput)
    expect(
      mapQuestionEditError({ message: "Deactivation reason is required." })
    ).toBe(QUESTION_EDIT_ERROR_MESSAGES.invalidInput)
  })

  it("bilinmeyen hata genel mesaja düşer; ham DB metni sızmaz", () => {
    const raw = "internal error: pg_catalog secret xyz"
    const mapped = mapQuestionEditError({ message: raw })
    expect(mapped).toBe(QUESTION_EDIT_ERROR_MESSAGES.generic)
    expect(mapped).not.toContain("pg_catalog")
    expect(mapped).not.toContain(raw)
  })
})

describe("mapBlockerMessage", () => {
  it("040 bloker kodları Türkçe açıklamaya çevrilir", () => {
    expect(mapBlockerMessage("question_not_approved")).toContain("onaylı değil")
    expect(mapBlockerMessage("missing_required_options")).toContain(
      "A, B, C ve D"
    )
    expect(mapBlockerMessage("commercial_clearance_missing")).toContain(
      "ticari"
    )
  })

  it("bilinmeyen bloker kodu genel mesaja düşer; 040'ın İngilizce mesajı sızmaz", () => {
    const mapped = mapBlockerMessage("unknown_future_code")
    expect(mapped).toBe(QUESTION_PUBLICATION_MESSAGES.unknownBlocker)
    expect(mapped).not.toContain("activation readiness")
  })
})

describe("formatBlockerFlash", () => {
  it("ilk 3 bloker + kalan sayısı; URL taşmayacak biçimde kırpılır", () => {
    const formatted = formatBlockerFlash([
      "engel bir",
      "engel iki",
      "engel üç",
      "engel dört",
      "engel beş",
    ])
    expect(formatted).toContain("engel bir")
    expect(formatted).toContain("engel üç")
    expect(formatted).toContain("ve 2 yayın engeli daha.")
    expect(formatted).not.toContain("engel dört")
  })

  it("3 ve altı blokerde kırpma/kalan mesajı olmaz", () => {
    expect(formatBlockerFlash(["a"])).toBe("a")
    expect(formatBlockerFlash(["a", "b", "c"])).toBe("a b c")
    expect(formatBlockerFlash([])).toBe("")
  })
})

describe("migration 089 audit sözleşmesi (kaynak düzeyi)", () => {
  const repoRoot = fileURLToPath(new URL("../../../", import.meta.url))
  const source089 = readFileSync(
    `${repoRoot}supabase/migrations/089_admin_audit_and_question_edit.sql`,
    "utf8"
  )

  it("admin_question_edit questions.edit izni ister (SECURITY DEFINER guard)", () => {
    const privateFn = source089.slice(
      source089.indexOf("CREATE OR REPLACE FUNCTION private.admin_question_edit"),
      source089.indexOf("CREATE OR REPLACE FUNCTION public.admin_question_edit")
    )
    expect(privateFn).toContain("SECURITY DEFINER")
    expect(privateFn).toContain(
      "private.current_user_has_admin_permission('questions.edit')"
    )
  })

  it("mutation + admin_audit_log INSERT AYNI fonksiyonda (aynı transaction, atomik audit)", () => {
    const privateFn = source089.slice(
      source089.indexOf("CREATE OR REPLACE FUNCTION private.admin_question_edit"),
      source089.indexOf("CREATE OR REPLACE FUNCTION public.admin_question_edit")
    )
    expect(privateFn).toContain("UPDATE public.questions")
    expect(privateFn).toContain("INSERT INTO public.admin_audit_log")
    // INSERT'ten sonra UPDATE gelmez: audit atomiktir ve audit_id döner.
    const auditPos = privateFn.indexOf("INSERT INTO public.admin_audit_log")
    const updatePos = privateFn.indexOf("UPDATE public.questions")
    expect(auditPos).toBeGreaterThan(updatePos)
    expect(privateFn.slice(auditPos)).toContain("'question.edit'")
    expect(privateFn.slice(auditPos)).toContain("'audit_id'")
  })

  it("public INVOKER sarmalayıcı authenticated'a açık, private PUBLIC'e kapalıdır", () => {
    expect(source089).toContain(
      "CREATE OR REPLACE FUNCTION public.admin_question_edit"
    )
    expect(source089).toContain("SECURITY INVOKER")
    const grants = source089.slice(
      source089.indexOf("REVOKE ALL\nON FUNCTION private.admin_question_edit")
    )
    expect(grants).toContain("FROM PUBLIC")
    expect(grants).toContain("GRANT EXECUTE")
    expect(grants).toContain("TO authenticated")
  })
})

describe("migration 040 yayın RPC sözleşmesi (kaynak düzeyi)", () => {
  const repoRoot = fileURLToPath(new URL("../../../", import.meta.url))
  const source040 = readFileSync(
    `${repoRoot}supabase/migrations/040_controlled_question_activation.sql`,
    "utf8"
  )

  it("check_question_activation_readiness can_activate/blocking_reasons döndürür", () => {
    expect(source040).toContain("check_question_activation_readiness")
    expect(source040).toContain("'can_activate'")
    expect(source040).toContain("'blocking_reasons'")
  })

  it("activate RPC readiness PASS olmadan aktivasyona izin vermez", () => {
    const activateFn = source040.slice(
      source040.indexOf(
        "CREATE OR REPLACE FUNCTION private.activate_question_for_students"
      ),
      source040.indexOf(
        "CREATE OR REPLACE FUNCTION public.activate_question_for_students"
      )
    )
    expect(activateFn).toContain("check_question_activation_readiness")
    expect(activateFn).toContain("IF NOT v_can_activate THEN")
  })

  it("deactivate RPC sebep zorunluluğu uygular ve audit event yazar", () => {
    const deactivateFn = source040.slice(
      source040.indexOf(
        "CREATE OR REPLACE FUNCTION private.deactivate_question_for_students"
      ),
      source040.indexOf(
        "CREATE OR REPLACE FUNCTION public.deactivate_question_for_students"
      )
    )
    expect(deactivateFn).toContain("Deactivation reason is required.")
    expect(deactivateFn).toContain("INSERT INTO public.question_publication_events")
  })
})
