// @vitest-environment node
/**
 * Faz 3.5 takvim hata eşleme testleri.
 *
 * - Bilinen ASCII DB mesajları Türkçe UI mesajına çevrilir.
 * - Ham DB mesajı ASLA döndürülmez (bilinmeyen → generic).
 */

import { describe, expect, it } from "vitest"
import {
  CALENDAR_ERROR_MESSAGES,
  mapCalendarError,
} from "./academic-calendar-errors"

describe("mapCalendarError", () => {
  it("yetki hatası özel Türkçe mesaja çevrilir", () => {
    expect(
      mapCalendarError(
        "Akademik takvimi duzenlemek icin calendar.manage yetkisi gerekli."
      )
    ).toBe(CALENDAR_ERROR_MESSAGES.forbidden)
  })

  it("aynı yıl çakışması ayrı mesaj döner", () => {
    expect(
      mapCalendarError("Ayni akademik yilda mevcut bir haftayla cakisiyor.")
    ).toBe(CALENDAR_ERROR_MESSAGES.sameYearOverlap)
  })

  it("farklı yıl çakışması ayrı mesaj döner", () => {
    expect(
      mapCalendarError("Farkli bir akademik yilin takvimiyle cakisiyor.")
    ).toBe(CALENDAR_ERROR_MESSAGES.crossYearOverlap)
  })

  it("074 eşzamanlılık yakalama mesajı concurrentOverlap döner", () => {
    expect(
      mapCalendarError(
        "Tarih araligi mevcut bir akademik haftayla cakisiyor; eszamanli guncelleme algilandi."
      )
    ).toBe(CALENDAR_ERROR_MESSAGES.concurrentOverlap)
  })

  it("ham 23P01 İngilizce mesajı da concurrentOverlap'e düşer ve constraint adı sızmaz", () => {
    const raw =
      'conflicting key value violates exclusion constraint "academic_weeks_no_cross_year_overlap"'
    const mapped = mapCalendarError(raw)
    expect(mapped).toBe(CALENDAR_ERROR_MESSAGES.concurrentOverlap)
    expect(mapped).not.toContain("academic_weeks_no_cross_year_overlap")
  })

  it("başlamış hafta güncelleme/silme ayrı mesajlar döner", () => {
    expect(
      mapCalendarError("Baslamis veya gecmis akademik hafta degistirilemez.")
    ).toBe(CALENDAR_ERROR_MESSAGES.startedUpdate)
    expect(
      mapCalendarError("Baslamis veya gecmis akademik hafta silinemez.")
    ).toBe(CALENDAR_ERROR_MESSAGES.startedDelete)
  })

  it("attempt referansı silme mesajı özel döner", () => {
    expect(
      mapCalendarError(
        "Bu hafta ogrenci deneme kayitlari tarafindan referans aliniyor; silinemez."
      )
    ).toBe(CALENDAR_ERROR_MESSAGES.referencedDelete)
  })

  it("bulunamadı mesajı özel döner", () => {
    expect(mapCalendarError("Silinecek akademik hafta bulunamadi.")).toBe(
      CALENDAR_ERROR_MESSAGES.notFound
    )
  })

  it("girdi hataları invalidInput'a düşer", () => {
    expect(mapCalendarError("Hafta numarasi 0 ile 52 arasinda olmali.")).toBe(
      CALENDAR_ERROR_MESSAGES.invalidInput
    )
  })

  it("PostgrestError nesnesi (Error değil) işlenir", () => {
    const error = { message: "Farkli bir akademik yilin takvimiyle cakisiyor." }
    expect(mapCalendarError(error)).toBe(CALENDAR_ERROR_MESSAGES.crossYearOverlap)
  })

  it("bilinmeyen hatada ham mesaj SIZMAZ", () => {
    const raw = "relation public.x does not exist; secret=abc"
    const mapped = mapCalendarError(raw)
    expect(mapped).toBe(CALENDAR_ERROR_MESSAGES.generic)
    expect(mapped).not.toContain("secret")
    expect(mapped).not.toContain("does not exist")
  })
})
