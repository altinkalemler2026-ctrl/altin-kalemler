/**
 * Aday soru toplu paketi deterministik doğrulaması.
 *
 * Bu modül yalnız yapısal/şema kontrolleri yapar. Akademik doğruluk
 * (cevap DOĞRULUĞU, müfredat uygunluğu, özgünlük, benzerlik) bağımsız
 * gate'ler (033-039) tarafından sonraki aşamalarda denetlenir.
 *
 * Hata mesajları Türkçe'dir (kullanıcıya dönük raporlama için).
 */

import type {
  CandidateValidationResult,
  CandidateValidationStatus,
  BatchValidationResult,
  BatchValidationStatus,
} from "./candidate-batch-types"

import {
  CANDIDATE_BATCH_SCHEMA_VERSION,
  FORBIDDEN_QUESTION_FIELDS,
  ALLOWED_ORIGINS,
} from "./candidate-batch-types"

const VALID_DIFFICULTIES = ["easy", "medium", "hard"]
const VALID_COGNITIVE_TYPES = ["learning", "comprehension", "application"]
const VALID_OPTION_KEYS = ["A", "B", "C", "D", "E"]
const REQUIRED_OPTION_KEYS = ["A", "B", "C", "D"]
const MIN_QUESTION_TEXT_LENGTH = 10
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// ============================================================
// YARDIMCI FONKSİYONLAR
// ============================================================

function trim(value: unknown): string {
  return typeof value === "string" ? value.trim() : ""
}

function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value)
}

function optionValues(options: Record<string, unknown>): string[] {
  return VALID_OPTION_KEYS.map((k) => trim(options[k]))
}

function hasDuplicateOptions(options: Record<string, unknown>): boolean {
  const vals = optionValues(options)
    .filter((v) => v.length > 0)
    .map((v) => v.toLowerCase())
  return vals.length !== new Set(vals).size
}

function hasForbiddenFields(question: Record<string, unknown>): string[] {
  return FORBIDDEN_QUESTION_FIELDS.filter((f) => f in question)
}

// ============================================================
// TEK SORU DOĞRULAMASI
// ============================================================

function validateCandidate(
  question: unknown,
  index: number
): CandidateValidationResult {
  const errors: string[] = []
  const warnings: string[] = []

  if (question === null || typeof question !== "object") {
    return {
      index,
      client_question_id: null,
      status: "invalid",
      errors: ["soru_json_object_olmali"],
      warnings,
    }
  }

  const q = question as Record<string, unknown>
  const clientQuestionId =
    typeof q["client_question_id"] === "string" && q["client_question_id"].trim().length > 0
      ? q["client_question_id"].trim()
      : null

  // -- Yasaklı alanlar
  const forbidden = hasForbiddenFields(q)
  if (forbidden.length > 0) {
    errors.push(`yasakli_alanlar_tespit_edildi: ${forbidden.join(", ")}`)
  }

  // -- grade_level
  const gradeLevel = Number(q["grade_level"])
  if (!Number.isInteger(gradeLevel) || gradeLevel < 1 || gradeLevel > 12) {
    errors.push("grade_level_1_12_olmali")
  }

  // -- subject_id
  const subjectId = trim(q["subject_id"])
  if (!isUuid(subjectId)) {
    errors.push("subject_id_gecerli_bir_uuid_olmali")
  }

  // -- outcome_code
  const outcomeCode = trim(q["outcome_code"])
  if (outcomeCode.length === 0) {
    errors.push("outcome_code_bos_olamaz")
  } else if (!/^[A-Za-z0-9._-]+$/.test(outcomeCode)) {
    errors.push("outcome_code_sadece_harf_rakam_nokta_ayrac_icerebilir")
  }

  // -- question_text
  const questionText = trim(q["question_text"])
  if (questionText.length < MIN_QUESTION_TEXT_LENGTH) {
    errors.push("question_text_en_az_10_karakter_olmali")
  }

  // -- options
  const options = q["options"]
  if (options === null || typeof options !== "object" || Array.isArray(options)) {
    errors.push("options_bir_json_object_olmali")
  } else {
    const opt = options as Record<string, unknown>
    for (const key of REQUIRED_OPTION_KEYS) {
      if (typeof opt[key] !== "string" || trim(opt[key]).length === 0) {
        errors.push(`option_${key}_eksik`)
      }
    }
    if (hasDuplicateOptions(opt)) {
      errors.push("ayni_secenek_metni_tekrar_eden_bulundu")
    }
  }

  // -- correct_answer
  const correctAnswer = trim(q["correct_answer"]).toUpperCase()
  if (!VALID_OPTION_KEYS.includes(correctAnswer)) {
    errors.push("correct_answer_A_E_arasi_olmali")
  } else if (correctAnswer === "E") {
    const opt = q["options"] as Record<string, unknown> | undefined
    if (!opt || trim(opt["E"]).length === 0) {
      errors.push("correct_answer_E_ama_secenek_E_bos")
    }
  }

  // -- difficulty (opsiyonel)
  const difficulty = trim(q["difficulty"]).toLowerCase()
  if (difficulty.length > 0 && !VALID_DIFFICULTIES.includes(difficulty)) {
    errors.push("difficulty_easy_medium_hard_olmali")
  }

  // -- cognitive_type (opsiyonel)
  const cognitiveType = trim(q["cognitive_type"]).toLowerCase()
  if (cognitiveType.length > 0 && !VALID_COGNITIVE_TYPES.includes(cognitiveType)) {
    errors.push("cognitive_type_learning_comprehension_application_olmali")
  }

  // -- estimated_solve_time_seconds (opsiyonel)
  if (q["estimated_solve_time_seconds"] !== undefined && q["estimated_solve_time_seconds"] !== null) {
    const solveTime = Number(q["estimated_solve_time_seconds"])
    if (!Number.isFinite(solveTime) || solveTime <= 0 || !Number.isInteger(solveTime)) {
      errors.push("estimated_solve_time_seconds_pozitif_tamsayi_olmali")
    }
  }

  // -- solution (opsiyonel ama varsa kontrolleri)
  const solution = q["solution"]
  if (solution !== undefined && solution !== null) {
    if (typeof solution !== "object" || Array.isArray(solution)) {
      errors.push("solution_bir_json_object_olmali")
    } else {
      const s = solution as Record<string, unknown>
      if (typeof s["method"] !== "string" || trim(s["method"]).length === 0) {
        errors.push("solution_method_bos_olamaz")
      }
      if (!Array.isArray(s["steps"]) || s["steps"].length === 0) {
        errors.push("solution_steps_en_az_bir_adim_icerirmeli")
      }
      if (typeof s["result"] !== "string" || trim(s["result"]).length === 0) {
        errors.push("solution_result_bos_olamaz")
      }
      if (typeof s["correctAnswerJustification"] !== "string" || trim(s["correctAnswerJustification"]).length === 0) {
        errors.push("solution_correctAnswerJustification_bos_olamaz")
      }
    }
  }

  const status: CandidateValidationStatus = errors.length === 0 ? "valid" : "invalid"

  return {
    index,
    client_question_id: clientQuestionId,
    status,
    errors,
    warnings,
  }
}

// ============================================================
// PAKET DOĞRULAMASI
// ============================================================

/**
 * Aday soru paketini deterministik olarak doğrular.
 * DB erişimi YOKTUR; yalnız yapı kontrolü.
 *
 * @returns BatchValidationResult — root-level ve aday-level hatalar dahil.
 */
export function validateCandidateQuestionBatch(
  payload: unknown
): BatchValidationResult {
  const rootErrors: string[] = []
  const candidates: CandidateValidationResult[] = []

  if (payload === null || typeof payload !== "object" || Array.isArray(payload)) {
    return {
      status: "rejected",
      schema_version_valid: false,
      origin_valid: false,
      producer_valid: false,
      question_count: 0,
      valid_count: 0,
      invalid_count: 0,
      duplicate_count: 0,
      candidates: [],
      root_errors: ["payload_json_object_olmali"],
    }
  }

  const p = payload as Record<string, unknown>

  // -- schema_version
  const schemaVersionValid = p["schema_version"] === CANDIDATE_BATCH_SCHEMA_VERSION
  if (!schemaVersionValid) {
    rootErrors.push("schema_version_1_0_olmali")
  }

  // -- origin
  const originValue = p["origin"]
  const originValid =
    typeof originValue === "string" &&
    (ALLOWED_ORIGINS as readonly string[]).includes(originValue)
  if (!originValid) {
    rootErrors.push("origin_yalnizca_curriculum_original_olmali")
  }

  // -- producer
  const producer = p["producer"]
  let producerValid = false
  if (producer !== null && typeof producer === "object" && !Array.isArray(producer)) {
    const pr = producer as Record<string, unknown>
    const id = trim(pr["id"])
    if (id.length > 0) {
      producerValid = true
    } else {
      rootErrors.push("producer_id_bos_olamaz")
    }
  } else {
    rootErrors.push("producer_bir_json_object_olmali")
  }

  // -- questions array
  const questions = p["questions"]
  if (!Array.isArray(questions)) {
    rootErrors.push("questions_bir_array_olmali")
    return {
      status: "rejected",
      schema_version_valid: schemaVersionValid,
      origin_valid: originValid,
      producer_valid: producerValid,
      question_count: 0,
      valid_count: 0,
      invalid_count: 0,
      duplicate_count: 0,
      candidates: [],
      root_errors: rootErrors,
    }
  }

  if (questions.length === 0) {
    rootErrors.push("questions_bos_olamaz")
    return {
      status: "rejected",
      schema_version_valid: schemaVersionValid,
      origin_valid: originValid,
      producer_valid: producerValid,
      question_count: 0,
      valid_count: 0,
      invalid_count: 0,
      duplicate_count: 0,
      candidates: [],
      root_errors: rootErrors,
    }
  }

  // -- Her soru için yapısal doğrulama
  for (let i = 0; i < questions.length; i++) {
    candidates.push(validateCandidate(questions[i], i))
  }

  // -- Duplicate kontrolü (normalized question_text içinde tekrar)
  const textCounts = new Map<string, number>()
  for (const c of candidates) {
    if (c.status === "invalid") continue
    const q = questions[c.index] as Record<string, unknown>
    const normalized = trim(q["question_text"]).toLowerCase()
    if (normalized.length === 0) continue
    textCounts.set(normalized, (textCounts.get(normalized) ?? 0) + 1)
  }

  for (const c of candidates) {
    if (c.status === "invalid") continue
    const q = questions[c.index] as Record<string, unknown>
    const normalized = trim(q["question_text"]).toLowerCase()
    if ((textCounts.get(normalized) ?? 0) > 1) {
      c.status = "duplicate"
      c.errors.push("ayni_normalized_soru_metni_tekrar")
    }
  }

  const validCount = candidates.filter((c) => c.status === "valid").length
  const invalidCount = candidates.filter((c) => c.status === "invalid").length
  const duplicateCount = candidates.filter((c) => c.status === "duplicate").length

  let status: BatchValidationStatus = "rejected"
  if (rootErrors.length === 0) {
    if (validCount > 0 && invalidCount === 0 && duplicateCount === 0) {
      status = "accepted"
    } else if (validCount > 0 || duplicateCount > 0) {
      status = "partially_accepted"
    }
  }

  return {
    status,
    schema_version_valid: schemaVersionValid,
    origin_valid: originValid,
    producer_valid: producerValid,
    question_count: questions.length,
    valid_count: validCount,
    invalid_count: invalidCount,
    duplicate_count: duplicateCount,
    candidates,
    root_errors: rootErrors,
  }
}
