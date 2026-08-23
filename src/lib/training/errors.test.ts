import { describe, expect, it } from "vitest"

import {
  mapTrainingError,
  SESSION_EXPIRED_MESSAGE,
  TRAINING_ERROR_MESSAGES,
} from "./errors"

describe("mapTrainingError — Türkçe mesajlar", () => {
  it("fail-closed dönem hatası anlaşılır Türkçe mesaja çevrilir", () => {
    const message = mapTrainingError(
      new Error(
        "Gecerli akademik donem bulunamadi; soru akisi fail-closed olarak durduruldu."
      )
    )

    expect(message).toBe(TRAINING_ERROR_MESSAGES.periodClosed)
    expect(message).toContain("akademik dönem")
    expect(message).toContain("durduruldu")
  })

  it("oturum ve bağlam hataları ayrışır", () => {
    expect(mapTrainingError(new Error("Kimlik dogrulamasi gerekli."))).toBe(
      TRAINING_ERROR_MESSAGES.authRequired
    )
    expect(
      mapTrainingError(new Error("Ogrenci baglami cozulemedi (profil/mufredat)."))
    ).toBe(TRAINING_ERROR_MESSAGES.contextMissing)
  })

  it("RLS/izin hataları oturum mesajına düşer", () => {
    expect(
      mapTrainingError(new Error("permission denied for table questions"))
    ).toBe(TRAINING_ERROR_MESSAGES.authRequired)
  })

  it("PostgrestError şeklinde düz nesne hataları da eşlenir", () => {
    const postgrestError = {
      message: "Gecerli akademik donem bulunamadi.",
      details: null,
      hint: null,
      code: "P0001",
    }
    expect(mapTrainingError(postgrestError)).toBe(
      TRAINING_ERROR_MESSAGES.periodClosed
    )

    expect(
      mapTrainingError({
        message: "permission denied for function submit_training_attempt",
      })
    ).toBe(TRAINING_ERROR_MESSAGES.authRequired)
  })

  it("bilinmeyen veya gizli bilgi içeren hata genel mesaja düşer, ham metin sızmaz", () => {
    expect(mapTrainingError(new Error("correct_answer=42 internal"))).toBe(
      TRAINING_ERROR_MESSAGES.generic
    )
    expect(mapTrainingError(new Error("totally unknown failure"))).toBe(
      TRAINING_ERROR_MESSAGES.generic
    )
    expect(SESSION_EXPIRED_MESSAGE).toContain("Oturumunuz sona erdi")
  })

  it("Faz 4 rate limit hatası beklemeye yönlendiren Türkçe mesaja çevrilir", () => {
    const message = mapTrainingError(
      new Error(
        "Cok fazla istek gonderildi; lutfen kisa bir sure sonra tekrar deneyin."
      )
    )

    expect(message).toBe(TRAINING_ERROR_MESSAGES.rateLimit)
    expect(message).toContain("Çok hızlı")
    expect(message).toContain("bekleyip")

    const postgrestError = {
      message: "Cok fazla istek gonderildi.",
      details: null,
      hint: null,
      code: "P0001",
    }
    expect(mapTrainingError(postgrestError)).toBe(
      TRAINING_ERROR_MESSAGES.rateLimit
    )
  })

  it("Faz 4 iç yapılandırma hatası kullanıcıya sızmaz, genel mesaja düşer", () => {
    expect(
      mapTrainingError(new Error("Rate limit yapilandirmasi gecersiz (p_limit)."))
    ).toBe(TRAINING_ERROR_MESSAGES.generic)
  })
})
