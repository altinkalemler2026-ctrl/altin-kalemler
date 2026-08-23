import { describe, expect, it } from "vitest"

import {
  clampQuestionLimit,
  clampTimeMs,
  mapQuestionPayload,
  mapSubmitResult,
  mapWeeklyUsage,
  selectTrainingQuestions,
  submitTrainingAttempt,
  TrainingValidationError,
  type TrainingClient,
} from "./service"

const SECRET_SENTINEL = "TUI-GIZLI-DOGRU-CEVAP"

/** Gizli alanlar bilinçli olarak eklenmiş ham RPC satırı. */
function rawQuestion(overrides: Record<string, unknown> = {}) {
  return {
    id: "33333333-3333-3333-3333-000000000001",
    question_code: "TQ-01",
    grade_level: 12,
    subject_id: "430903f3-527e-4e12-b7e8-ac0afdb784aa",
    question_text: "Türkiye'nin başkenti hangisidir?",
    option_a: "İstanbul",
    option_b: "Ankara",
    option_c: "İzmir",
    option_d: "Bursa",
    option_e: "Adana",
    difficulty: "easy",
    has_visual: false,
    estimated_solve_time_seconds: 45,
    correct_answer: SECRET_SENTINEL,
    solution: SECRET_SENTINEL + "-cozum",
    explanation: SECRET_SENTINEL + "-aciklama",
    review_status: "approved",
    internal_note: SECRET_SENTINEL + "-not",
    ...overrides,
  }
}

describe("mapQuestionPayload — allowlist", () => {
  it("izinli alanları taşır ve seçenekleri A-E haritalar", () => {
    const mapped = mapQuestionPayload(rawQuestion())

    expect(mapped?.id).toBe("33333333-3333-3333-3333-000000000001")
    expect(mapped?.questionCode).toBe("TQ-01")
    expect(mapped?.options.A).toBe("İstanbul")
    expect(mapped?.options.E).toBe("Adana")
    expect(Object.keys(mapped?.options ?? {})).toHaveLength(5)
    expect(mapped?.estimatedSolveTimeSeconds).toBe(45)
  })

  it("gizli alanların hiçbirini içermez", () => {
    const mapped = mapQuestionPayload(
      rawQuestion()
    ) as unknown as Record<string, unknown>

    expect(JSON.stringify(mapped)).not.toContain(SECRET_SENTINEL)
    for (const forbidden of [
      "correct_answer",
      "solution",
      "explanation",
      "review_status",
      "internal_note",
    ]) {
      expect(Object.keys(mapped)).not.toContain(forbidden)
    }
    expect(Object.keys(mapped).sort()).toEqual(
      [
        "difficulty",
        "estimatedSolveTimeSeconds",
        "hasVisual",
        "id",
        "options",
        "questionCode",
        "questionText",
      ].sort()
    )
  })

  it("boş/boşluk seçenekleri düşürür", () => {
    const mapped = mapQuestionPayload(
      rawQuestion({ option_c: "  ", option_e: null })
    )

    expect(mapped?.options.C).toBeUndefined()
    expect(mapped?.options.E).toBeUndefined()
    expect(Object.keys(mapped?.options ?? {})).toHaveLength(3)
  })

  it("geçersiz id içeren satırda null döner (fail-closed)", () => {
    expect(mapQuestionPayload({ ...rawQuestion(), id: "not-a-uuid" })).toBeNull()
    expect(mapQuestionPayload(null)).toBeNull()
  })
})

describe("mapWeeklyUsage / mapSubmitResult", () => {
  it("haftalık kullanımı güvenli DTO'ya çevirir", () => {
    const usage = mapWeeklyUsage({
      academic_year: "QA-Y-2099",
      week: 5,
      subjects: [
        { subject_id: "s1", new_questions_used: 7, limit: 500 },
        { broken: true },
      ],
    })

    expect(usage.academicYear).toBe("QA-Y-2099")
    expect(usage.week).toBe(5)
    expect(usage.subjects).toEqual([
      { subjectId: "s1", newQuestionsUsed: 7, limit: 500 },
    ])
  })

  it("duplicate:true aynen taşınır; bilinmeyen sonuç 'wrong'a düşer", () => {
    const duplicate = mapSubmitResult({
      attempt_id: "a1",
      attempt_number: 3,
      result: "correct",
      duplicate: true,
    })
    expect(duplicate.duplicate).toBe(true)
    expect(duplicate.result).toBe("correct")
    expect(duplicate.attemptNumber).toBe(3)

    expect(mapSubmitResult({ result: "hacker_input" }).result).toBe("wrong")
    expect(mapSubmitResult(null).duplicate).toBe(false)
  })
})

describe("girdi sınırlama", () => {
  it("limit 1..50 aralığına sıkıştırılır", () => {
    expect(clampQuestionLimit(0)).toBe(1)
    expect(clampQuestionLimit(-10)).toBe(1)
    expect(clampQuestionLimit(51)).toBe(50)
    expect(clampQuestionLimit(Number.NaN)).toBe(10)
    expect(clampQuestionLimit(7)).toBe(7)
  })

  it("süre ms 0..3600000 aralığına sıkıştırılır", () => {
    expect(clampTimeMs(-5)).toBe(0)
    expect(clampTimeMs(4_000_000)).toBe(3_600_000)
    expect(clampTimeMs(1234)).toBe(1234)
  })
})

function createRpcCaptureClient(result: {
  data?: unknown
  error?: { message: string } | null
}) {
  const calls: Array<{ fn: string; args?: Record<string, unknown> }> = []

  const client = {
    rpc(fnName: string, args?: Record<string, unknown>) {
      calls.push({ fn: fnName, args })
      return Promise.resolve({
        data: result.data ?? null,
        error: result.error ?? null,
      })
    },
  }

  return { client: client as unknown as TrainingClient, calls }
}

describe("submitTrainingAttempt — RPC sözleşmesi", () => {
  it("user_id ASLA gönderilmez; yalnız RPC imzasındaki anahtarlar kullanılır", async () => {
    const { client, calls } = createRpcCaptureClient({
      data: { attempt_id: "a1", attempt_number: 1, result: "correct", duplicate: false },
    })

    const outcome = await submitTrainingAttempt(client, {
      questionId: "33333333-3333-3333-3333-000000000001",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 12_345,
      choice: "B",
    })

    expect(outcome.result).toBe("correct")
    expect(outcome.duplicate).toBe(false)

    expect(calls).toHaveLength(1)
    expect(calls[0].fn).toBe("submit_training_attempt")
    expect(Object.keys(calls[0].args ?? {}).sort()).toEqual(
      ["p_action", "p_choice", "p_client_key", "p_question_id", "p_time_ms"].sort()
    )
    expect(calls[0].args?.p_user_id).toBeUndefined()
    expect(JSON.stringify(calls[0].args)).not.toContain("user_id")
    expect(calls[0].args?.p_choice).toBe("B")
    expect(calls[0].args?.p_action).toBeNull()
  })

  it("negatif süre 0'a sıkıştırılır", async () => {
    const { client, calls } = createRpcCaptureClient({ data: {} })

    await submitTrainingAttempt(client, {
      questionId: "33333333-3333-3333-3333-000000000002",
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: -100,
      action: "timeout",
    })

    expect(calls[0].args?.p_time_ms).toBe(0)
  })

  it("doğrulama hataları Türkçe mesajlı TrainingValidationError fırlatır", async () => {
    const { client } = createRpcCaptureClient({ data: {} })
    const base = {
      clientKey: "cccccccc-cccc-cccc-cccc-cccccccccccc",
      timeMs: 1000,
    }
    const qid = "33333333-3333-3333-3333-000000000001"

    await expect(
      submitTrainingAttempt(client, { ...base, questionId: qid })
    ).rejects.toThrow("Cevap gönderimi için seçenek veya işlem gereklidir.")

    await expect(
      submitTrainingAttempt(client, { ...base, questionId: qid, choice: "F" as never })
    ).rejects.toThrow("Geçersiz seçenek. A, B, C, D veya E seçin.")

    await expect(
      submitTrainingAttempt(client, { ...base, questionId: qid, action: "hack" as never })
    ).rejects.toThrow("Geçersiz işlem.")

    await expect(
      submitTrainingAttempt(client, { ...base, questionId: "gecersiz", choice: "A" })
    ).rejects.toBeInstanceOf(TrainingValidationError)

    await expect(
      submitTrainingAttempt(client, { ...base, clientKey: "gecersiz", questionId: qid, choice: "A" })
    ).rejects.toBeInstanceOf(TrainingValidationError)
  })
})

describe("selectTrainingQuestions", () => {
  it("payload'ı allowlist ile eşler; gizli değer sızdırır mı test edilir", async () => {
    const { client, calls } = createRpcCaptureClient({
      data: {
        questions: [rawQuestion()],
        new_count: 1,
        repeat_count: 0,
        reason: null,
        weekly: {
          academic_year: "QA-Y-2099",
          week: 5,
          subject_id: "s1",
          new_questions_used: 2,
          limit: 500,
        },
      },
    })

    const selection = await selectTrainingQuestions(
      client,
      "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      25
    )

    expect(calls[0].fn).toBe("select_training_questions")
    expect(calls[0].args?.p_limit).toBe(25)
    expect(selection.questions).toHaveLength(1)
    expect(selection.questions[0]?.questionCode).toBe("TQ-01")
    expect(selection.weekly.week).toBe(5)
    expect(JSON.stringify(selection)).not.toContain(SECRET_SENTINEL)
  })

  it("RPC hatasını olduğu gibi fırlatır (dönem kapalı vb.)", async () => {
    const { client } = createRpcCaptureClient({
      error: {
        message:
          "Gecerli akademik donem bulunamadi; soru akisi fail-closed olarak durduruldu.",
      },
    })

    await expect(
      selectTrainingQuestions(client, "430903f3-527e-4e12-b7e8-ac0afdb784aa")
    ).rejects.toThrow(/akademik donem bulunamadi/i)
  })
})
