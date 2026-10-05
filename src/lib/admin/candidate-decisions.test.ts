/**
 * Faz 35 / UI-P2A — karar türetme mantığı testleri.
 *
 * Kapsanan sözleşmeler:
 * - Karar listesi migration 130 ile birebir aynı (approve/request_changes/reject).
 * - Gerekçe zorunluluğu karara bağlı (request_changes/reject zorunlu).
 * - staging_status -> karar uygunluğu eşlemesi, bilinmeyen durumda fail-closed.
 * - approve dalı readiness kapılarını birebir yansıtır.
 * - Girdi doğrulaması (uuid, karar, gerekçe).
 */

import { describe, expect, it } from "vitest"
import {
  CANDIDATE_DECISIONS,
  isCandidateDecision,
  isCandidateStagingStatus,
  isDecisionAvailable,
  isRationaleRequired,
  normalizeRationale,
  parseStagingQuestionUuid,
  RATIONALE_MAX_LENGTH,
  readFinalReviewHistory,
  readReadinessSummary,
  summarizeCandidateDecision,
  validateDecisionInput,
  deriveCandidateDecisionAvailability,
  type CandidateDecision,
} from "./candidate-decisions"
import type { CandidateRecord } from "./candidate-batches"

const STAGING_UUID = "11111111-2222-4333-8444-555555555555"

type GateFieldValue = string | number | boolean | string[] | null

function makeCandidate(
  overrides: Partial<CandidateRecord> & {
    stagingStatus?: string | null
    readinessFields?: Array<{ key: string; value: GateFieldValue }>
    finalReviewFields?: Array<{ key: string; value: GateFieldValue }>
  } = {}
): CandidateRecord {
  const {
    stagingStatus = "needs_review",
    readinessFields,
    finalReviewFields,
    ...rest
  } = overrides

  return {
    candidateIndex: 0,
    clientQuestionId: "c-1",
    validationStatus: "passed",
    validationErrors: [],
    validationWarnings: [],
    stagingQuestionId: STAGING_UUID,
    preview: {
      stagingStatus,
      questionText: "2+2 kaçtır?",
      options: { A: "3", B: "4", C: "5", D: null, E: null },
      proposedCorrectAnswer: "B",
      proposedDifficulty: "medium",
      proposedCognitiveType: "aritmetik",
      proposedSolveTimeSeconds: 30,
      gradeLevel: 5,
      subjectId: "math-1",
      subjectName: "Matematik",
      outcomeCode: "MAT.5.3.1",
      proposedCurriculumVersionId: null,
      proposedTopicId: null,
      proposedSubtopicId: null,
      lowConfidence: false,
      ownershipStatus: "ai_generated",
      licenseStatus: "cleared",
      commercialUseAllowed: "true",
      copyrightRiskLevel: "low",
      solution: {
        method: "Toplama",
        steps: [{ title: "Adım 1", content: "2+2 toplamı 4 eder." }],
        result: "4",
        correctAnswerJustification: "İki artı iki dört eder.",
        commonMistakes: ["Cevaba 3 demek"],
      },
    },
    validationResults: [],
    reviewQueue: [],
    gates: {
      answerVerification: null,
      curriculumFit: null,
      solveTimeVerification: null,
      originalityVerification: null,
      questionQuality: null,
      readiness: readinessFields ? { fields: readinessFields } : null,
      finalReview: finalReviewFields ? { fields: finalReviewFields } : null,
    },
    ...rest,
  }
}

/** Migration 130 approve kapısını geçen aday. */
function readyCandidate(
  overrides: Partial<CandidateRecord> & { stagingStatus?: string | null } = {}
): CandidateRecord {
  const { stagingStatus = "needs_review", ...rest } = overrides
  return makeCandidate({
    ...rest,
    stagingStatus,
    readinessFields: [
      { key: "readiness_status", value: "ready_for_human_review" },
      { key: "readiness_score", value: 1 },
      { key: "blocking_reasons", value: [] },
    ],
  })
}

describe("karar sözleşmesi", () => {
  it("migration 130 kararları ile birebir aynı", () => {
    expect([...CANDIDATE_DECISIONS]).toEqual([
      "approve",
      "request_changes",
      "reject",
    ])
  })

  it("sözleşme dışı karar kabul edilmez", () => {
    for (const value of ["publish", "delete", "APPROVE", "", "activate", null, 1]) {
      expect(isCandidateDecision(value)).toBe(false)
    }
    expect(isCandidateDecision("approve")).toBe(true)
    expect(isCandidateDecision("request_changes")).toBe(true)
    expect(isCandidateDecision("reject")).toBe(true)
  })

  it("gerekçe yalnız request_changes ve reject için zorunlu", () => {
    expect(isRationaleRequired("approve")).toBe(false)
    expect(isRationaleRequired("request_changes")).toBe(true)
    expect(isRationaleRequired("reject")).toBe(true)
  })

  it("staging_status CHECK listesini tanır, bilinmeyeni reddeder", () => {
    for (const value of [
      "draft",
      "extracted",
      "validating",
      "needs_review",
      "approved",
      "rejected",
      "promoted",
    ]) {
      expect(isCandidateStagingStatus(value)).toBe(true)
    }
    expect(isCandidateStagingStatus("staged")).toBe(false)
    expect(isCandidateStagingStatus(null)).toBe(false)
  })
})

describe("validating adayda üç karar da kapalı (P2A fail-closed kuralı)", () => {
  it.each(["draft", "extracted", "validating"] as const)(
    "%s durumunda hiçbir karar açılmaz",
    (stagingStatus) => {
      const availability = deriveCandidateDecisionAvailability(
        makeCandidate({ stagingStatus }),
      )

      expect(availability.approve.enabled).toBe(false)
      expect(availability.request_changes.enabled).toBe(false)
      expect(availability.reject.enabled).toBe(false)
      expect(availability.approve.reason).toBe("validationIncomplete")
      expect(availability.request_changes.reason).toBe("validationIncomplete")
      expect(availability.reject.reason).toBe("validationIncomplete")
    },
  )

  it("migration 130'un aksine request_changes/reject de kapalı (bilinçli sapma)", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({ stagingStatus: "validating" }),
    )
    // Migration 130 bu iki dalda staging kapisı koymaz; panel bilinçli olarak
    // daha katıdır. Bu, gerçek veri durumunda sıfır yazma yolu garantisi verir.
    expect(summarizeCandidateDecision(availability).canDecide).toBe(false)
    expect(summarizeCandidateDecision(availability).enabledDecisions).toEqual([])
  })

  it("needs_review + hazır olmayan readiness => approve kapalı, diğerleri açık", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({
        stagingStatus: "needs_review",
        readinessFields: [
          { key: "readiness_status", value: "human_review_required" },
          { key: "readiness_score", value: 0 },
        ],
      }),
    )

    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("readinessNotComplete")
    expect(availability.request_changes.enabled).toBe(true)
    expect(availability.reject.enabled).toBe(true)
    expect(summarizeCandidateDecision(availability).canDecide).toBe(true)
  })
})

describe("terminal durumlar", () => {
  it.each(["rejected", "promoted"] as const)(
    "%s durumunda karar yeniden verilemez",
    (stagingStatus) => {
      const availability = deriveCandidateDecisionAvailability(
        makeCandidate({ stagingStatus }),
      )
      for (const decision of CANDIDATE_DECISIONS) {
        expect(availability[decision].enabled).toBe(false)
        expect(availability[decision].reason).toBe("alreadyDecided")
      }
    },
  )
})

describe("approve dalı readiness kapıları (migration 130:1903-1938)", () => {
  it("hazır durum + tam puan + engelsiz => approve açık", () => {
    const availability = deriveCandidateDecisionAvailability(readyCandidate())
    expect(availability.approve.enabled).toBe(true)
    expect(availability.approve.reason).toBeNull()
    expect(isDecisionAvailable(readyCandidate(), "approve")).toBe(true)
  })

  it("readiness kaydı yoksa approve kapalı", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({ stagingStatus: "needs_review" }),
    )
    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("readinessMissing")
  })

  it("puan 1.0 değilse approve kapalı", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({
        readinessFields: [
          { key: "readiness_status", value: "ready_for_human_review" },
          { key: "readiness_score", value: 0.9 },
        ],
      }),
    )
    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("readinessScoreLow")
  })

  it("puan 1.0'den büyükse de approve kapalı (migration tam eşitlik ister)", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({
        readinessFields: [
          { key: "readiness_status", value: "ready_for_human_review" },
          { key: "readiness_score", value: 1.1 },
          { key: "blocking_reasons", value: [] },
        ],
      }),
    )
    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("readinessScoreLow")
    // reject/request_changes bu durumda da açık kalır (yalnız approve kapılı).
    expect(availability.reject.enabled).toBe(true)
    expect(availability.request_changes.enabled).toBe(true)
  })

  it("blocking_reasons doluysa approve kapalı", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({
        readinessFields: [
          { key: "readiness_status", value: "ready_for_human_review" },
          { key: "readiness_score", value: 1 },
          { key: "blocking_reasons", value: ["copyright_high"] },
        ],
      }),
    )
    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("readinessBlocked")
  })

  it("staging zaten approved ise approve gereksiz, diğerleri açık", () => {
    const availability = deriveCandidateDecisionAvailability(
      readyCandidate({ stagingStatus: "approved" }),
    )
    expect(availability.approve.enabled).toBe(false)
    expect(availability.approve.reason).toBe("alreadyApproved")
    expect(availability.request_changes.enabled).toBe(true)
    expect(availability.reject.enabled).toBe(true)
  })
})

describe("fail-closed kenarlar", () => {
  it("staging kaydı yoksa hiçbir karar açılmaz", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({ stagingQuestionId: null }),
    )
    for (const decision of CANDIDATE_DECISIONS) {
      expect(availability[decision].enabled).toBe(false)
      expect(availability[decision].reason).toBe("noStagingQuestion")
    }
  })

  it("preview yoksa (staging durumu bilinmiyor) hiçbir karar açılmaz", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({ preview: null }),
    )
    for (const decision of CANDIDATE_DECISIONS) {
      expect(availability[decision].enabled).toBe(false)
    }
    expect(summarizeCandidateDecision(availability).canDecide).toBe(false)
  })

  it("migration CHECK listesinde olmayan durum da kapalı (staged gibi)", () => {
    const availability = deriveCandidateDecisionAvailability(
      makeCandidate({ stagingStatus: "staged" }),
    )
    for (const decision of CANDIDATE_DECISIONS) {
      expect(availability[decision].enabled).toBe(false)
    }
  })
})

describe("girdi doğrulama", () => {
  it("geçerli approve + boş gerekçe kabul edilir", () => {
    const result = validateDecisionInput({
      stagingQuestionId: STAGING_UUID,
      decision: "approve",
      rationale: "",
    })
    expect(result.ok).toBe(true)
    if (result.ok) expect(result.rationale).toBe("")
  })

  it.each(["request_changes", "reject"] as const)(
    "%s için gerekçesiz giriş reddedilir",
    (decision: CandidateDecision) => {
      const result = validateDecisionInput({
        stagingQuestionId: STAGING_UUID,
        decision,
        rationale: "   ",
      })
      expect(result.ok).toBe(false)
      if (!result.ok) expect(result.error).toBe("rationaleRequired")
    },
  )

  it("geçersiz uuid reddedilir", () => {
    const result = validateDecisionInput({
      stagingQuestionId: "not-a-uuid",
      decision: "approve",
      rationale: "",
    })
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toBe("invalidStagingId")
  })

  it("sözleşme dışı karar reddedilir", () => {
    const result = validateDecisionInput({
      stagingQuestionId: STAGING_UUID,
      decision: "publish",
      rationale: "x",
    })
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.error).toBe("invalidDecision")
  })

  it("gerekçe kırpılır ve normalize edilir", () => {
    const long = "x".repeat(RATIONALE_MAX_LENGTH + 50)
    expect(normalizeRationale(long)).toHaveLength(RATIONALE_MAX_LENGTH)
    expect(normalizeRationale("  gerekçe  ")).toBe("gerekçe")
    expect(normalizeRationale(undefined)).toBe("")
    expect(parseStagingQuestionUuid(`  ${STAGING_UUID}  `)).toBe(STAGING_UUID)
    expect(parseStagingQuestionUuid("bozuk")).toBeUndefined()
  })
})

describe("readiness ve karar geçmişi okuma (allowlist'li DTO)", () => {
  it("readiness özeti yalnız izinli alanları taşır", () => {
    const summary = readReadinessSummary(
      makeCandidate({
        readinessFields: [
          { key: "readiness_status", value: "ready_for_human_review" },
          { key: "readiness_score", value: 1 },
          { key: "blocking_reasons", value: ["telif_yuksek"] },
          { key: "commercial_clearance_status", value: "cleared" },
        ],
      }),
    )
    expect(summary).toEqual({
      readinessStatus: "ready_for_human_review",
      readinessScore: 1,
      commercialClearanceStatus: "cleared",
      blockingReasons: ["telif_yuksek"],
    })
  })

  it("blocking_reasons tek metin olarak gelirse de çalışır", () => {
    const summary = readReadinessSummary(
      makeCandidate({
        readinessFields: [{ key: "blocking_reasons", value: "copyright_high" }],
      }),
    )
    expect(summary.blockingReasons).toEqual(["copyright_high"])
  })

  it("karar geçmişi yoksa alanlar boş döner", () => {
    expect(readFinalReviewHistory(makeCandidate())).toEqual({
      decision: null,
      reviewNotes: null,
      reviewedBy: null,
      reviewedAt: null,
    })
  })

  it("karar geçmişi allowlist alanlarından okunur", () => {
    const history = readFinalReviewHistory(
      makeCandidate({
        finalReviewFields: [
          { key: "decision", value: "reject" },
          { key: "review_notes", value: "çözüm hatalı" },
          { key: "reviewed_by", value: "admin-1" },
          { key: "reviewed_at", value: "2026-09-01T10:00:00.000Z" },
        ],
      }),
    )
    expect(history.decision).toBe("reject")
    expect(history.reviewNotes).toBe("çözüm hatalı")
    expect(history.reviewedBy).toBe("admin-1")
    expect(history.reviewedAt).toBe("2026-09-01T10:00:00.000Z")
  })
})