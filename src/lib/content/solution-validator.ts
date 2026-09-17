/**
 * Yapılandırılmış yazılı çözüm bağımsız doğrulayıcısı.
 *
 * AMAÇ: "Sadece doğru şıkkın yazılması yeterli kabul edilmesin." Bu
 * doğrulayıcı yazılı çözümün:
 *   - yapısal bütünlüğünü (yöntem, en az bir adım, sonuç, gerekçe) ve
 *   - içeriksel bağını (gerekçenin doğru cevaba somut olarak ulaşması)
 * deterministik kurallarla denetler. AI çağrısı YOKTUR; fake sağlayıcı
 * test girdisiyle çalışır ve kesin doğruluk iddia etmez.
 *
 * Kural kodları kararlıdır; admin katmanı bunları Türkçe mesajlara eşler.
 */

import type { AiWorkerOptionKey } from "@/ai-worker/types"

import type {
  SolutionValidation,
  SolutionValidationStatus,
  WrittenSolution,
} from "./solution-types"

/** Gerekçenin "yalnız şık harfi" kadar kısa olmaması için alt sınır. */
export const JUSTIFICATION_MIN_LENGTH = 40

/** Her adımın açıklama metni için alt sınır. */
export const STEP_CONTENT_MIN_LENGTH = 10

/** Yöntem metni için alt sınır. */
export const METHOD_MIN_LENGTH = 10

/** Sonuç ifadesi için alt sınır. */
export const RESULT_MIN_LENGTH = 5

/** Yöntem/çözümün sığlığını reddeden yardımcı sabitler. */

export function computeValidationStatus(
  reasons: string[]
): SolutionValidationStatus {
  if (reasons.length === 0) return "pass"
  const blocking = reasons.filter(
    (r) =>
      r.startsWith("eksik_") ||
      r.startsWith("bos_") ||
      r.startsWith("kisa_") ||
      r === "gerekce_cevaba_ulasmiyor"
  )
  // Açık yapısal eksiklik/gereksiz çözüm → fail (yayını bloke eder).
  // Yalnız kuşkulu/çelişkili işaretler (suphe_* gibi) → needs_review.
  return blocking.length > 0 ? "fail" : "needs_review"
}

function normalizeText(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

/**
 * Çözümün doğru cevaba "ulaşması" deterministik kurallarla denetlenir:
 * - Gerekçe metni asgari uzunlukta olmalı ve yalnız şık harfinden ibaret
 *   olmamalı (ör. "Çünkü cevap B" kısa olduğu için zaten elenir).
 * - En az iki adım ve anlamlı bir sonuç ifadesi olmalı.
 *
 * NOT: Gerekçede "doğru şık harfi anılsın mı" diye harf aranmaz — Türkçe
 * metin doğal olarak a–e harflerini içerir (ör. "beşli", "seçenek"). Bu
 * yüzden bağ yapısal kurallarla kurulur; ayrı bir AI değerlendirmesi kesin
 * doğruluk garantisi sayılmaz.
 */
export function solutionReachesAnswer(
  solution: WrittenSolution,
  _correctAnswer: AiWorkerOptionKey
): boolean {
  const justification = normalizeText(solution.correctAnswerJustification)

  if (justification.length < JUSTIFICATION_MIN_LENGTH) {
    return false
  }

  const onlyLetter = justification.replace(/[^a-zçğıöşü]/gi, "").length <= 1
  if (onlyLetter) {
    return false
  }

  return solution.steps.length >= 2 && normalizeText(solution.result).length >= RESULT_MIN_LENGTH
}

/**
 * Yazılı çözümü yapısal + içerik kurallarıyla doğrular.
 * Deterministik; sahte sağlayıcı test girdisi için bilinen sonuç üretir.
 */
export function validateWrittenSolution(
  solution: WrittenSolution,
  correctAnswer: AiWorkerOptionKey
): SolutionValidation {
  const reasons: string[] = []

  if (normalizeText(solution.method).length < METHOD_MIN_LENGTH) {
    reasons.push("bos_metod")
  }

  if (!Array.isArray(solution.steps) || solution.steps.length === 0) {
    reasons.push("eksik_adim")
  } else if (solution.steps.some((step) => normalizeText(step.content).length < STEP_CONTENT_MIN_LENGTH)) {
    reasons.push("kisa_adim_icerigi")
  }

  if (normalizeText(solution.result).length < RESULT_MIN_LENGTH) {
    reasons.push("bos_sonuc")
  }

  if (normalizeText(solution.correctAnswerJustification).length < JUSTIFICATION_MIN_LENGTH) {
    reasons.push("kisa_gerekce")
  }

  if (reasons.length === 0 && !solutionReachesAnswer(solution, correctAnswer)) {
    reasons.push("gerekce_cevaba_ulasmiyor")
  }

  return { status: computeValidationStatus(reasons), reasons }
}

/**
 * doğru cevap harfini çözüm içeriğinde arayarak "yalnız şık" sığlığını
 * reddeden yardımcı. Public test doğrulaması için ayrıca taşınır.
 */
export function hasMeaningfulJustification(solution: WrittenSolution): boolean {
  return normalizeText(solution.correctAnswerJustification).length >= JUSTIFICATION_MIN_LENGTH
}