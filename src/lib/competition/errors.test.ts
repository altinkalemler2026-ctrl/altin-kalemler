import { describe, expect, it } from "vitest"

import {
  mapCompetitionError,
  COMPETITION_ERROR_MESSAGES,
  SESSION_EXPIRED_MESSAGE,
} from "./errors"

describe("mapCompetitionError — Turkce mesajlar", () => {
  it("oturum hatasi Turkce mesaja cevrilir", () => {
    const message = mapCompetitionError(
      new Error("Kimlik dogrulamasi gerekli.")
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.authRequired)
    expect(message).toContain("Oturumunuz")
  })

  it("rate limit hatasi Turkce mesaja cevrilir", () => {
    const message = mapCompetitionError(
      new Error("Cok fazla istek gonderildi; lutfen kisa bir sure sonra tekrar deneyin.")
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.rateLimit)
    expect(message).toContain("Cok hizli")
  })

  it("ders bulunamadi hatasi Turkce mesaja cevrilir", () => {
    expect(mapCompetitionError(new Error("Ders bulunamadi veya pasif."))).toBe(
      COMPETITION_ERROR_MESSAGES.subjectNotFound
    )
  })

  it("profil eksik hatasi Turkce mesaja cevrilir", () => {
    expect(
      mapCompetitionError(new Error("Ogrenci profili bulunamadi; kuyruğa girilemez."))
    ).toBe(COMPETITION_ERROR_MESSAGES.profileMissing)
  })

  it("RLS/izin hatalari oturum mesajina duser", () => {
    expect(
      mapCompetitionError(new Error("permission denied for function join_matchmaking_queue"))
    ).toBe(COMPETITION_ERROR_MESSAGES.authRequired)
  })

  it("bilinmeyen hata genel mesaja duser, ham metin sizmaz", () => {
    expect(mapCompetitionError(new Error("totally unknown failure"))).toBe(
      COMPETITION_ERROR_MESSAGES.generic
    )
    expect(mapCompetitionError(new Error("internal error code=XYZ"))).toBe(
      COMPETITION_ERROR_MESSAGES.generic
    )
  })

  it("PostgrestError seklinde duz nesne hatalari da eslenir", () => {
    const postgrestError = {
      message: "Kimlik dogrulamasi gerekli.",
      details: null,
      hint: null,
      code: "42501",
    }
    expect(mapCompetitionError(postgrestError)).toBe(
      COMPETITION_ERROR_MESSAGES.authRequired
    )
  })

  it("SESSION_EXPIRED_MESSAGE kullaniciya uygun", () => {
    expect(SESSION_EXPIRED_MESSAGE).toContain("Oturumunuz sona erdi")
  })

  it("cevap zaten gonderildi hatasi Turkce mesaja cevrilir", () => {
    expect(
      mapCompetitionError(new Error("Answer already submitted for this question."))
    ).toBe(COMPETITION_ERROR_MESSAGES.answerAlreadySubmitted)
  })

  it("soru henuz baslamadi hatasi Turkce mesaja cevrilir", () => {
    expect(
      mapCompetitionError(new Error("Soru henuz baslamadi."))
    ).toBe(COMPETITION_ERROR_MESSAGES.questionNotStarted)
  })

  it("yarisma sona erdi hatasi Turkce mesaja cevrilir", () => {
    expect(
      mapCompetitionError(new Error("Yarisma sona erdi."))
    ).toBe(COMPETITION_ERROR_MESSAGES.competitionCompleted)
  })

  it("skor tablosu mevcut degil hatasi Turkce mesaja cevrilir", () => {
    expect(
      mapCompetitionError(
        new Error("Detailed scoreboard is available after the competition ends.")
      )
    ).toBe(COMPETITION_ERROR_MESSAGES.scoreboardNotAvailable)
  })
})
