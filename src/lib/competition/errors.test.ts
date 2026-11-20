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

  // ------------------------------------------------------------
  // 163 haftalik kota — ogrenci bilgilendirme mesaji (AK-MEB-VAULT-42-19)
  // ------------------------------------------------------------

  const QUOTA_40_MESSAGE =
    "KOTA_163: haftalik yarisma kotasi doldu (40/40) — yeni yarisma olusamiyor."
  const QUOTA_200_MESSAGE =
    "KOTA_163: haftalik yeni soru kotasi asilirdi (198+5>200) — paket dagitilamiyor."

  it("KOTA_163 40/40 kota hatasi kullanici kuralindaki mesaja cevrilir", () => {
    const message = mapCompetitionError(new Error(QUOTA_40_MESSAGE))
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.weeklyQuota)
    expect(message).toBe(
      "Haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte tekrar yarışmalara katılabilirsiniz."
    )
  })

  it("KOTA_163 200 yeni soru asimi ayni kota mesajina cevrilir", () => {
    expect(mapCompetitionError(new Error(QUOTA_200_MESSAGE))).toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuota
    )
  })

  it("KOTA_163 donem teknik hatasi kota mesaji DEĞIL genel mesaja duser", () => {
    const message = mapCompetitionError(
      new Error("KOTA_163: gecerli akademik donem yok; kota fail-closed.")
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.generic)
    expect(message).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuota)
  })

  it("soru stoku yetersizligi kota mesaji DEĞIL farkli mesaja duser", () => {
    const message = mapCompetitionError(
      new Error("Uygulanabilir ortak gorulmemis paket kasa yok.")
    )
    expect(message).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuota)
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.generic)
  })

  it("YETKI_163 kota mesaji DEĞIL oturum mesajina duser", () => {
    const message = mapCompetitionError(
      new Error("YETKI_163: kimlik dogrulamasi gerekli.")
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.authRequired)
    expect(message).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuota)
  })

  it("PostgrestError govdesindeki KOTA_163 mesaji da kota mesajina cevrilir", () => {
    const postgrestError = {
      message: QUOTA_200_MESSAGE,
      details: null,
      hint: null,
      code: "P0001",
    }
    expect(mapCompetitionError(postgrestError)).toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuota
    )
  })

  // ------------------------------------------------------------
  // 165 ders bazli kota — ders-ozel ogrenci mesajlari (AK-QUOTA-SUBJECT-01)
  // ------------------------------------------------------------

  const SUBJECT_QUOTA_40_MESSAGE =
    "KOTA_165: bu ders icin haftalik yarisma kotasi doldu (40/40) — yeni yarisma olusamiyor."
  const SUBJECT_QUOTA_200_MESSAGE =
    "KOTA_165: bu ders icin haftalik yeni soru kotasi asilirdi (198+5>200) — paket dagitilamiyor."

  it("KOTA_165 40/40 dersi tam urun karari ders mesajina cevrilir", () => {
    const message = mapCompetitionError(new Error(SUBJECT_QUOTA_40_MESSAGE))
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject)
    expect(message).toBe(
      "Bu ders için haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte bu derste tekrar yarışabilirsiniz."
    )
  })

  it("KOTA_165 200 yeni soru asimi ders-ozel soru mesajina cevrilir", () => {
    const message = mapCompetitionError(new Error(SUBJECT_QUOTA_200_MESSAGE))
    expect(message).toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject
    )
    expect(message).toContain("Bu ders için haftalık yeni soru hakkınız tükendi.")
  })

  it("KOTA_165 ders mesajlari kuresel 163 mesajiyla AYNI degildir (karistirma yok)", () => {
    expect(COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject).not.toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuota
    )
    expect(mapCompetitionError(new Error(SUBJECT_QUOTA_40_MESSAGE))).not.toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuota
    )
    // KOTA_163 kuresel hatasi da ders mesajina dusmez (gecis dogrulugu).
    expect(mapCompetitionError(new Error(QUOTA_40_MESSAGE))).not.toBe(
      COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject
    )
  })

  it("KOTA_165 donem/ders kimligi teknik hatalari kota mesaji DEĞIL (karistirma yok)", () => {
    expect(
      mapCompetitionError(
        new Error("KOTA_165: gecerli akademik donem yok; kota fail-closed.")
      )
    ).toBe(COMPETITION_ERROR_MESSAGES.generic)
    const teknik = mapCompetitionError(
      new Error(
        "KOTA_165: yarisma bulunamadi veya ders kimligi cozulemedi — kota fail-closed."
      )
    )
    // Mevcut desen "yarisma bulunamadi" ile genel yarisma-hata mesajina
    // duser; ONEMLI olan: HICBIR kota/hafta mesajina dusmez (urun karari).
    expect(teknik).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuota)
    expect(teknik).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject)
    expect(teknik).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject)
  })

  it("KOTA_165_DEPRECATED teknik hatasi kota mesaji DEĞIL genel mesaja duser", () => {
    const message = mapCompetitionError(
      new Error(
        "KOTA_165_DEPRECATED: haftalik kota artik ders bazlidir; weekly_quota_status_per_subject() kullanin."
      )
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.generic)
    expect(message).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject)
  })

  it("YETKI_165 kota mesaji DEĞIL oturum mesajina duser", () => {
    const message = mapCompetitionError(
      new Error("YETKI_165: kimlik dogrulamasi gerekli.")
    )
    expect(message).toBe(COMPETITION_ERROR_MESSAGES.authRequired)
    expect(message).not.toBe(COMPETITION_ERROR_MESSAGES.weeklyQuotaSubject)
  })
})
