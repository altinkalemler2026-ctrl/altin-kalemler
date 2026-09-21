/**
 * Markdown aday paketi deterministik v1.1 preflight doğrulayıcısı (Faz 22).
 *
 * v1.0 validatörünün (candidate-batch-validator.ts) KATI bir üst kümesidir:
 *
 *  v1.0 zorunlu alanlara ek olarak v1.1 şunları dayatır:
 *  - Beş seçenek (A-E) zorunlu ve benzersiz (v1.0'ta E opsiyoneldi).
 *  - client_question_id zorunlu.
 *  - Durum (validation_requested_status) yalnız needs_review/pending;
 *    approved / active / published girişimleri bloklanır.
 *  - publication_allowed=false ve is_active=false kalıcı değişmezi.
 *  - Çözüm zorunlu: yöntem, en az iki adım, sonuç, gerekçe ve çeldirici
 *    gerekçesi (solution-validator kurallarıyla çakışır).
 *  - Ders adı (subject_ref) veya UUID (subject_id) zorunlu.
 *  - Birden fazla kazanım kodu varsa otomatik seçim YAPILMAZ, bloklanır.
 *
 * DB erişimi YOKTUR; yalnız yapı/kural kontrolü. Hata kodları kalıcıdır.
 */

import type {
  MdCandidateResult,
  MdBatchStatus,
  MdPreflightResult,
  MdOutOfPackageItem,
} from "./candidate-md-types"

import {
  CANDIDATE_MD_SCHEMA_VERSION,
  MD_ACCEPTED_VALIDATION_STATUSES,
  MD_MIN_QUESTION_TEXT_LENGTH,
  MD_REQUIRED_OPTION_KEYS,
} from "./candidate-md-types"

import { FORBIDDEN_QUESTION_FIELDS } from "./candidate-batch-types"
import { validateWrittenSolution } from "./solution-validator"
import type { WrittenSolution } from "./solution-types"

const VALID_OPTION_KEYS = ["A", "B", "C", "D", "E"]
const VALID_DIFFICULTIES = ["easy", "medium", "hard"]
const VALID_COGNITIVE_TYPES = ["learning", "comprehension", "application"]
const OUTCOME_CODE_RE = /^[A-Za-z0-9._-]+$/
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function trim(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function isUuid(value: string): boolean {
  return UUID_RE.test(value)
}

function hasDuplicateOptions(options: Record<string, unknown>): boolean {
  const values = VALID_OPTION_KEYS.map((k) => trim(options[k]))
    .filter((v) => v.length > 0)
    .map((v) => v.toLowerCase())
  return values.length !== new Set(values).size
}

function normalized(text: string): string {
  return text.trim().toLowerCase()
}

interface CandidateCheckResult {
  errors: string[]
  warnings: string[]
}

function checkCandidate(question: unknown): CandidateCheckResult {
  const errors: string[] = []
  const warnings: string[] = []

  if (question === null || typeof question !== "object" || Array.isArray(question)) {
    return { errors: ["soru_json_object_olmali"], warnings }
  }

  const q = question as Record<string, unknown>
  const clientId = trim(q["client_question_id"])
  if (clientId.length === 0) errors.push("client_question_id_zorunlu")

  // -- Yasaklı alanlar (kaynak-türetme/PDF/görsel ham verisi)
  for (const field of FORBIDDEN_QUESTION_FIELDS) {
    if (field in q) {
      errors.push(`yasakli_alan:${field}`)
    }
  }

  // -- Durum girişimi: approved/active/published/asallar bloklanır.
  const requestedStatus = trim(q["validation_requested_status"]).toLowerCase()
  if (requestedStatus.length > 0) {
    if (
      !(MD_ACCEPTED_VALIDATION_STATUSES as readonly string[]).includes(requestedStatus)
    ) {
      errors.push("candidate_durum_not_importable")
    }
  }

  // -- Kalıcı yayın yasağı değişmezleri (aday seviyesinde de kontrol).
  if (q["publication_allowed"] === true) errors.push("publication_allowed_false_olmali")
  if (q["is_active"] === true) errors.push("is_active_false_olmali")

  // -- Birden fazla kazanım kodu: otomatik seçim yok, blokla.
  const additional = q["additional_outcome_codes"]
  if (Array.isArray(additional) && additional.length > 0) {
    errors.push("birden_fazla_kazanim_kodu")
  }

  // -- grade_level
  const gradeLevel = q["grade_level"]
  if (
    typeof gradeLevel !== "number" ||
    !Number.isInteger(gradeLevel) ||
    gradeLevel < 1 ||
    gradeLevel > 12
  ) {
    errors.push("grade_level_1_12_olmali")
  }

  // -- subject: subject_id (UUID) VEYA subject_ref (ad) zorunlu.
  const subjectId = trim(q["subject_id"])
  const subjectRef = trim(q["subject_ref"])
  if (subjectId.length > 0 && !isUuid(subjectId)) {
    errors.push("subject_id_gecerli_bir_uuid_olmali")
  }
  if (subjectId.length === 0 && subjectRef.length === 0) {
    errors.push("subject_id_veya_subject_ref_zorunlu")
  }

  // -- outcome_code
  const outcomeCode = trim(q["outcome_code"])
  if (outcomeCode.length === 0) {
    errors.push("outcome_code_bos_olamaz")
  } else if (!OUTCOME_CODE_RE.test(outcomeCode)) {
    errors.push("outcome_code_formati_gecersiz")
  }

  // -- question_text
  const questionText = trim(q["question_text"])
  if (questionText.length < MD_MIN_QUESTION_TEXT_LENGTH) {
    errors.push("question_text_en_az_10_karakter_olmali")
  }

  // -- options (A-E zorunlu + benzersiz)
  const options = q["options"]
  if (options === null || typeof options !== "object" || Array.isArray(options)) {
    errors.push("options_bir_json_object_olmali")
  } else {
    const opt = options as Record<string, unknown>
    for (const key of MD_REQUIRED_OPTION_KEYS) {
      if (typeof opt[key] !== "string" || trim(opt[key]).length === 0) {
        errors.push(`option_${key}_eksik`)
      }
    }
    if (hasDuplicateOptions(opt)) {
      errors.push("ayni_secenek_metni_tekrar_eden_bulundu")
    }
  }

  // -- correct_answer (boş seçeneği gösteremez)
  const correctAnswer = trim(q["correct_answer"]).toUpperCase()
  if (!VALID_OPTION_KEYS.includes(correctAnswer)) {
    errors.push("correct_answer_A_E_arasi_olmali")
  } else {
    const opt = q["options"] as Record<string, unknown> | undefined
    if (!opt || trim(opt[correctAnswer]).length === 0) {
      errors.push(`correct_answer_bos_secenek:${correctAnswer}`)
    }
  }

  // -- difficulty / cognitive_type (opsiyonel ama varlıklarında kısıtlı)
  const difficulty = trim(q["difficulty"]).toLowerCase()
  if (difficulty.length > 0 && !VALID_DIFFICULTIES.includes(difficulty)) {
    errors.push("difficulty_easy_medium_hard_olmali")
  }
  const cognitiveType = trim(q["cognitive_type"]).toLowerCase()
  if (cognitiveType.length > 0 && !VALID_COGNITIVE_TYPES.includes(cognitiveType)) {
    errors.push("cognitive_type_learning_comprehension_application_olmali")
  }

  // -- estimated_solve_time_seconds
  if (
    q["estimated_solve_time_seconds"] !== undefined &&
    q["estimated_solve_time_seconds"] !== null
  ) {
    const solveTime = Number(q["estimated_solve_time_seconds"])
    if (!Number.isFinite(solveTime) || solveTime <= 0 || !Number.isInteger(solveTime)) {
      errors.push("estimated_solve_time_seconds_pozitif_tamsayi_olmali")
    }
  }

  // -- solution (v1.1'de zorunludur) — solution-validator kuralları
  const solution = q["solution"]
  if (solution === undefined || solution === null) {
    errors.push("solution_zorunlu")
  } else if (typeof solution !== "object" || Array.isArray(solution)) {
    errors.push("solution_bir_json_object_olmali")
  } else {
    const s = solution as WrittenSolution
    const steps = Array.isArray(s.steps) ? s.steps : []
    if (steps.length < 2) {
      errors.push("solution_en_az_iki_adim_olmali")
    }
    const written: WrittenSolution = {
      method: trim(s.method),
      steps,
      result: trim(s.result),
      correctAnswerJustification: trim(s.correctAnswerJustification),
      wrongOptionExplanations: s.wrongOptionExplanations,
      commonMistakes: Array.isArray(s.commonMistakes) ? s.commonMistakes : [],
    }
    const solutionValidation = validateWrittenSolution(written, "A")
    for (const reason of solutionValidation.reasons) {
      errors.push(`solution_${reason}`)
    }
    const commonMistakes = Array.isArray(s.commonMistakes) ? s.commonMistakes : []
    if (
      commonMistakes.length === 0 ||
      commonMistakes.some((c) => typeof c !== "string" || trim(c).length === 0)
    ) {
      errors.push("solution_common_mistakes_eksik")
    }
  }

  return { errors, warnings }
}

/**
 * v1.1 aday paketini deterministik olarak doğrular.
 * DB erişimi YOKTUR. Paket-dışı içerik bilgisi (opsiyonel) özete geçer.
 */
export function preflightCandidateMdPackage(
  payload: unknown,
  outOfPackageItems: MdOutOfPackageItem[] = []
): MdPreflightResult {
  const rootErrors: string[] = []
  const candidates: MdCandidateResult[] = []

  const outOfPackageKinds = [...new Set(outOfPackageItems.map((i) => i.kind))]

  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return {
      status: "rejected",
      root_valid: false,
      schema_version_valid: false,
      origin_valid: false,
      producer_valid: false,
      publication_blocked: true,
      review_required: true,
      question_count: 0,
      valid_count: 0,
      invalid_count: 0,
      duplicate_count: 0,
      out_of_package_count: outOfPackageItems.length,
      out_of_package_kinds: outOfPackageKinds,
      candidates: [],
      root_errors: ["payload_json_object_olmali"],
    }
  }

  const p = payload as Record<string, unknown>

  // -- schema_version
  const schemaVersionValid = p["schema_version"] === CANDIDATE_MD_SCHEMA_VERSION
  if (!schemaVersionValid) {
    rootErrors.push("schema_version_1_1_olmali")
  }

  // -- origin
  const originValid = p["origin"] === "curriculum_original"
  if (!originValid) {
    rootErrors.push("origin_yalnizca_curriculum_original_olmali")
  }

  // -- paket düzeyi kalıcı yayın yasağı değişmezleri
  if (p["publication_allowed"] === true) {
    rootErrors.push("publication_allowed_false_olmali")
  }
  if (p["is_active"] === true) {
    rootErrors.push("is_active_false_olmali")
  }

  // -- paket durumu girişimi
  const packageStatus = trim(p["validation_requested_status"]).toLowerCase()
  if (packageStatus.length > 0) {
    if (!(MD_ACCEPTED_VALIDATION_STATUSES as readonly string[]).includes(packageStatus)) {
      rootErrors.push("paket_durum_not_importable")
    }
  }

  // -- producer
  const producer = p["producer"]
  const producerValid =
    producer !== null &&
    typeof producer === "object" &&
    !Array.isArray(producer) &&
    trim((producer as Record<string, unknown>)["id"]).length > 0
  if (!producerValid) {
    rootErrors.push("producer_id_bos_olamaz")
  }

  // -- questions
  const questions = p["questions"]
  if (!Array.isArray(questions)) {
    rootErrors.push("questions_bir_array_olmali")
  } else if (questions.length === 0) {
    rootErrors.push("questions_bos_olamaz")
  }

  if (rootErrors.length > 0) {
    return {
      status: "rejected",
      root_valid: false,
      schema_version_valid: schemaVersionValid,
      origin_valid: originValid,
      producer_valid: producerValid,
      publication_blocked: true,
      review_required: true,
      question_count: Array.isArray(questions) ? questions.length : 0,
      valid_count: 0,
      invalid_count: 0,
      duplicate_count: 0,
      out_of_package_count: outOfPackageItems.length,
      out_of_package_kinds: outOfPackageKinds,
      candidates: [],
      root_errors: rootErrors,
    }
  }

  // -- per-candidate yapısal kontrol
  const list = questions as unknown[]
  list.forEach((question, index) => {
    const check = checkCandidate(question)
    const clientId =
      typeof (question as Record<string, unknown>)["client_question_id"] === "string"
        ? trim((question as Record<string, unknown>)["client_question_id"]) || null
        : null
    candidates.push({
      index,
      client_question_id: clientId,
      status: check.errors.length === 0 ? "valid" : "invalid",
      errors: check.errors,
      warnings: check.warnings,
    })
  })

  // -- paket-içi duplicate (normalize question_text + client_question_id)
  const textCounts = new Map<string, number>()
  const clientCounts = new Map<string, number>()
  candidates.forEach((c) => {
    if (c.status === "invalid") return
    const q = list[c.index] as Record<string, unknown>
    const text = normalized(trim(q["question_text"]))
    if (text.length > 0) textCounts.set(text, (textCounts.get(text) ?? 0) + 1)
    const clientId = trim(q["client_question_id"])
    if (clientId.length > 0) {
      clientCounts.set(
        normalized(clientId),
        (clientCounts.get(normalized(clientId)) ?? 0) + 1
      )
    }
  })
  candidates.forEach((c) => {
    if (c.status === "invalid") return
    const q = list[c.index] as Record<string, unknown>
    const text = normalized(trim(q["question_text"]))
    const clientId = trim(q["client_question_id"])
    const textDup = text.length > 0 && (textCounts.get(text) ?? 0) > 1
    const clientDup =
      clientId.length > 0 && (clientCounts.get(normalized(clientId)) ?? 0) > 1
    if (textDup || clientDup) {
      c.status = "duplicate"
      c.errors.push(
        textDup ? "ayni_normalized_soru_metni_tekrar" : "ayni_client_question_id_tekrar"
      )
    }
  })

  const validCount = candidates.filter((c) => c.status === "valid").length
  const invalidCount = candidates.filter((c) => c.status === "invalid").length
  const duplicateCount = candidates.filter((c) => c.status === "duplicate").length

  let status: MdBatchStatus = "rejected"
  if (validCount > 0 && invalidCount === 0 && duplicateCount === 0) {
    status = "accepted"
  } else if (validCount > 0 || duplicateCount > 0) {
    status = "partially_accepted"
  }

  const statusIsNeedsReview =
    packageStatus === "needs_review" ||
    candidates.some(
      (c) =>
        trim((list[c.index] as Record<string, unknown>)["validation_requested_status"]).toLowerCase() ===
        "needs_review"
    )

  return {
    status,
    root_valid: true,
    schema_version_valid: schemaVersionValid,
    origin_valid: originValid,
    producer_valid: producerValid,
    publication_blocked: true,
    review_required: statusIsNeedsReview || invalidCount > 0,
    question_count: list.length,
    valid_count: validCount,
    invalid_count: invalidCount,
    duplicate_count: duplicateCount,
    out_of_package_count: outOfPackageItems.length,
    out_of_package_kinds: outOfPackageKinds,
    candidates,
    root_errors: [],
  }
}