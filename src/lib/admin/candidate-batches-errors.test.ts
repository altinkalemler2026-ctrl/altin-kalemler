// @vitest-environment node
/**
 * Faz 19 — Aday Yükleme Paketleri hata sınıflandırması testleri.
 *
 * - Kimlik doğrulaması / yetki / zorunlu / bulunamadı desenleri doğru
 *   sınıflara düşer.
 * - Eşleşmeyen hata "generic"e düşer; ham mesaj asla taşınmaz.
 * - parseBatchUuid geçersiz girdileri reddeder.
 */

import { describe, expect, it } from "vitest"
import {
  candidateBatchErrorKind,
  mapCandidateBatchError,
  parseBatchUuid,
  CANDIDATE_BATCH_ERROR_MESSAGES as E,
} from "./candidate-batches-errors"

describe("candidateBatchErrorKind", () => {
  it("kimlik doğrulama hatası authRequired olarak sınıflandırılır", () => {
    expect(
      candidateBatchErrorKind({ message: "Kimlik dogrulamasi gerekli." })
    ).toBe("authRequired")
  })

  it("liste yetki hatası forbidden olarak sınıflandırılır", () => {
    expect(
      candidateBatchErrorKind({
        message:
          "Aday paket listesi icin ai.manage veya questions.approve yetkisi gerekli.",
      })
    ).toBe("forbidden")
  })

  it("detay yetki hatası forbidden olarak sınıflandırılır", () => {
    expect(
      candidateBatchErrorKind({
        message:
          "Aday paket detayi icin ai.manage veya questions.approve yetkisi gerekli.",
      })
    ).toBe("forbidden")
  })

  it("işlem durumu yetki hatası forbidden olarak sınıflandırılır (Faz 20)", () => {
    expect(
      candidateBatchErrorKind({
        message:
          "Iislem durumu icin ai.manage veya questions.approve yetkisi gerekli.",
      })
    ).toBe("forbidden")
  })

  it("zorunlu parametre hatası required olarak sınıflandırılır", () => {
    expect(candidateBatchErrorKind({ message: "p_batch_id zorunludur." })).toBe(
      "required"
    )
  })

  it("bulunamadı hatası notFound olarak sınıflandırılır", () => {
    expect(candidateBatchErrorKind({ message: "Aday paketi bulunamadi." })).toBe(
      "notFound"
    )
  })

  it("eşleşmeyen hata generic'e düşer", () => {
    expect(candidateBatchErrorKind({ message: "connection reset" })).toBe(
      "generic"
    )
    expect(candidateBatchErrorKind(new Error("timeout"))).toBe("generic")
    expect(candidateBatchErrorKind("")).toBe("generic")
    expect(candidateBatchErrorKind(null)).toBe("generic")
  })

  it("Error nesnesi de sonuç üretir (ham metin taşınmaz)", () => {
    const kind = candidateBatchErrorKind(
      new Error("Aday paketi bulunamadi.")
    )
    expect(kind).toBe("notFound")
  })
})

describe("mapCandidateBatchError", () => {
  it("her sınıf için sabit Türkçe mesaj döndürür", () => {
    expect(
      mapCandidateBatchError({ message: "Kimlik dogrulamasi gerekli." })
    ).toBe(E.authRequired)
    expect(
      mapCandidateBatchError({
        message: "Aday paket listesi icin ai.manage veya questions.approve yetkisi gerekli.",
      })
    ).toBe(E.forbidden)
    expect(mapCandidateBatchError({ message: "p_batch_id zorunludur." })).toBe(
      E.required
    )
    expect(mapCandidateBatchError({ message: "Aday paketi bulunamadi." })).toBe(
      E.notFound
    )
    expect(mapCandidateBatchError({ message: "boom" })).toBe(E.generic)
  })
})

describe("parseBatchUuid", () => {
  it("geçerli uuid'i kabuklanmış haliyle döndürür (trim uygular)", () => {
    expect(
      parseBatchUuid("  7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3  ")
    ).toBe("7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3")
  })

  it("geçersiz/eksik girdide undefined döndürür", () => {
    expect(parseBatchUuid(undefined)).toBeUndefined()
    expect(parseBatchUuid("")).toBeUndefined()
    expect(parseBatchUuid("abc")).toBeUndefined()
    expect(parseBatchUuid("7ea1ff55")).toBeUndefined()
  })
})