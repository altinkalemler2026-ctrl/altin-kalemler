/**
 * 165 ders bazli kota aktivasyon bayragi testleri (AK-QUOTA-SUBJECT-01).
 *
 * Güvenlik sözleşmesi: bayrak varsayilan KAPALIDIR — 165 canliya
 * uygulanmadan yeni RPC'ye hicbir production yolundan dokunulmaz.
 */

import { describe, expect, it } from "vitest"

import { isSubjectQuotaEnabled } from "./quota-mode"

describe("isSubjectQuotaEnabled — 165 aktivasyon bayragi", () => {
  it("varsayilan kapali (bos env)", () => {
    expect(isSubjectQuotaEnabled({})).toBe(false)
  })

  it("process.env'de tanimsizsa kapali", () => {
    expect(isSubjectQuotaEnabled()).toBe(false)
  })

  it('QUOTA_PER_SUBJECT_ENABLED="1" → acik', () => {
    expect(isSubjectQuotaEnabled({ QUOTA_PER_SUBJECT_ENABLED: "1" })).toBe(true)
  })

  it('QUOTA_PER_SUBJECT_ENABLED="true" → acik', () => {
    expect(isSubjectQuotaEnabled({ QUOTA_PER_SUBJECT_ENABLED: "true" })).toBe(
      true
    )
  })

  it('gevsek degerler ("0", "false", "yes", bos) → kapali', () => {
    for (const value of ["0", "false", "yes", ""]) {
      expect(isSubjectQuotaEnabled({ QUOTA_PER_SUBJECT_ENABLED: value })).toBe(
        false
      )
    }
  })

  it("NEXT_PUBLIC_ karsiligi okunmaz (istemciye sizmaz)", () => {
    expect(
      isSubjectQuotaEnabled({
        NEXT_PUBLIC_QUOTA_PER_SUBJECT_ENABLED: "1",
      })
    ).toBe(false)
  })
})
