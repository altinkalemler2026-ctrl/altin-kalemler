/**
 * Faz 35 / UI-P2A — karar hata/mesaj sözleşmesi testleri.
 *
 * Kritik kural: ham DB mesajı ASLA istemciye taşınmaz. Her migration 130
 * hatası güvenli bir Türkçe mesaja eşlenir; eşleşmeyen her şey `generic`
 * döner (fail-closed).
 */

import { describe, expect, it } from "vitest"
import {
  CANDIDATE_DECISION_ERROR_MESSAGES,
  CANDIDATE_DECISION_INPUT_MESSAGES,
  DECISION_BLOCKED_MESSAGES,
  blockedReasonMessage,
  candidateDecisionErrorKind,
  decisionOutcomeMessage,
  isCandidateDecisionOutcomeStatus,
  mapCandidateDecisionError,
  mapDecisionInputError,
} from "./candidate-decisions-errors"
import type { DecisionBlockedReason } from "./candidate-decisions"

describe("migration 130 hata mesajları -> güvenli Türkçe sınıf", () => {
  const cases: Array<[string, string]> = [
    ["Human authentication required.", "authRequired"],
    ["Question approval permission required.", "forbidden"],
    ["Invalid final review decision.", "invalidDecision"],
    ["Staging question not found.", "notFound"],
    ["Rejected staging question cannot be promoted.", "alreadyRejected"],
    ["Final readiness evaluation not found.", "readinessMissing"],
    [
      "Question is not ready for final human approval. Current readiness status: human_review_required",
      "notReady",
    ],
    [
      "All mandatory AI quality gates must pass before promotion.",
      "gatesFailed",
    ],
    [
      'Question cannot be promoted: blocking promotion gates failed: ["copyright_high"]',
      "promotionBlocked",
    ],
    ["Grade level is required.", "incompleteQuestion"],
    ["Subject is required.", "incompleteQuestion"],
    ["Question text is required.", "incompleteQuestion"],
    ["A valid correct answer is required.", "incompleteQuestion"],
    ["At least options A, B, C and D are required.", "incompleteQuestion"],
  ]

  it.each(cases)("%s -> %s", (rawMessage, expectedKind) => {
    expect(candidateDecisionErrorKind(new Error(rawMessage))).toBe(expectedKind)
  })

  it.each(cases)("%s -> tanımlı sabit mesaj, ham metin sızmaz", (rawMessage) => {
    const mapped = mapCandidateDecisionError(new Error(rawMessage))
    // Eşlenen metin, tanımlı sabitlerden BİRİ olmalı. Bu, ham metin sızıntısını
    // ve tanımsız çıktıyı birlikte engeller.
    expect(Object.values(CANDIDATE_DECISION_ERROR_MESSAGES)).toContain(mapped)
    expect(mapped).not.toContain(rawMessage)
    expect(mapped.length).toBeGreaterThan(0)
  })

  it("PostgREST/veritabanı hata nesnelerini de okur", () => {
    expect(candidateDecisionErrorKind({ message: "Human authentication required." })).toBe(
      "authRequired"
    )
    expect(candidateDecisionErrorKind("Question approval permission required.")).toBe(
      "forbidden"
    )
  })

  it("eşleşmeyen hata generic'e düşer (fail-closed)", () => {
    for (const value of [
      new Error("connection refused"),
      new Error(""),
      "bilinmeyen",
      null,
      undefined,
      42,
      {},
    ]) {
      expect(candidateDecisionErrorKind(value)).toBe("generic")
      expect(mapCandidateDecisionError(value)).toBe(
        CANDIDATE_DECISION_ERROR_MESSAGES.generic
      )
    }
  })

  it("eşleşmeyen hata tanımlı sabite düşer, alışılmadık içerik taşımaz", () => {
    const mapped = mapCandidateDecisionError(new Error("PGSSL error 0x1234"))
    expect(Object.values(CANDIDATE_DECISION_ERROR_MESSAGES)).toContain(mapped)
    expect(mapped).not.toMatch(/0x1234/)
  })
})

describe("girdi doğrulama mesajları", () => {
  it("girdi doğrulama hataları tanımlı sabitlere eşlenir", () => {
    const inputs = Object.values(CANDIDATE_DECISION_INPUT_MESSAGES)
    expect(mapDecisionInputError("invalidStagingId")).toBe(
      CANDIDATE_DECISION_INPUT_MESSAGES.invalidStagingId
    )
    expect(mapDecisionInputError("invalidDecision")).toBe(
      CANDIDATE_DECISION_INPUT_MESSAGES.invalidDecision
    )
    expect(mapDecisionInputError("rationaleRequired")).toBe(
      CANDIDATE_DECISION_INPUT_MESSAGES.rationaleRequired
    )
    for (const value of inputs) {
      expect(value.length).toBeGreaterThan(10)
    }
  })

  it("bilinmeyen girdi hatası güvenli varsayılana düşer", () => {
    expect(mapDecisionInputError("bilinmeyen")).toBe(
      mapDecisionInputError("invalidStagingId")
    )
  })
})

describe("devre dışı nedeni mesajları", () => {
  it("her neden sınıfı tanımlı ve açıklayıcı", () => {
    const reasons: DecisionBlockedReason[] = [
      "noStagingQuestion",
      "alreadyDecided",
      "validationIncomplete",
      "readinessMissing",
      "readinessNotComplete",
      "readinessScoreLow",
      "readinessBlocked",
      "alreadyApproved",
    ]
    for (const reason of reasons) {
      expect(Object.values(DECISION_BLOCKED_MESSAGES)).toContain(
        blockedReasonMessage(reason)
      )
      expect(blockedReasonMessage(reason).length).toBeGreaterThan(10)
    }
    // Tanımsız neden sınıfı güvenli varsayılana düşer.
    expect(blockedReasonMessage("bilinmeyen" as DecisionBlockedReason)).toBe(
      DECISION_BLOCKED_MESSAGES.validationIncomplete
    )
  })

  it("validating nedeni karar verilemez diye açıklar", () => {
    expect(blockedReasonMessage("validationIncomplete")).toMatch(
      /Doğrulama ve hazırlık değerlendirmesi tamamlanmadan insan kararı verilemez/
    )
  })
})

describe("karar sonucu mesajları (migration 130 status değerleri)", () => {
  it("beklenen status değerlerini tanır", () => {
    for (const status of [
      "promoted",
      "already_promoted",
      "changes_requested",
      "rejected",
      "idempotent_replay",
    ]) {
      expect(isCandidateDecisionOutcomeStatus(status)).toBe(true)
    }
  })

  it("beklenmeyen status değerini reddeder", () => {
    for (const value of ["published", "ok", "", null, undefined, 1]) {
      expect(isCandidateDecisionOutcomeStatus(value)).toBe(false)
    }
  })

  it("her sonuç 'yayınlanmadı' sınırını vurgular", () => {
    const messages = [
      decisionOutcomeMessage("promoted"),
      decisionOutcomeMessage("already_promoted"),
      decisionOutcomeMessage("changes_requested"),
      decisionOutcomeMessage("rejected"),
      decisionOutcomeMessage("idempotent_replay"),
    ]
    for (const message of messages) {
      expect(message).toMatch(
        /yayınlanmadı|Yeni bir kayıt oluşturulmadı|yazılmadı/i
      )
    }
  })

  it("promoted sonucu soru bankasına taşındığını, yayınlamadığını söyler", () => {
    expect(decisionOutcomeMessage("promoted")).toMatch(
      /soru bankasına taşındı.*Öğrenciye yayınlanmadı/
    )
  })
})