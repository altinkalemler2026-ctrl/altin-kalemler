/**
 * Faz UI-P4C — admin menü izin eşlemesi testleri (admin-nav.ts).
 *
 * Kanıt: `/admin/roles` menü girişi `users.manage` iznine bağlanır,
 * `collectAdminNavPermissionCodes` tüm kodları tekilleştirir ve
 * `canAccessAdminNavItem` fail-closed eşleme yapar.
 */

import { describe, expect, it } from "vitest"
import {
  ADMIN_NAV_PERMISSION_REQUIREMENTS,
  canAccessAdminNavItem,
  collectAdminNavPermissionCodes,
} from "./admin-nav"

describe("ADMIN_NAV_PERMISSION_REQUIREMENTS — /admin/roles", () => {
  it("roles girişi users.manage iznine bağlıdır", () => {
    expect(ADMIN_NAV_PERMISSION_REQUIREMENTS["/admin/roles"]).toEqual({
      mode: "all",
      codes: ["users.manage"],
    })
  })

  it("tüm menü girişlerinin izin seti taşır (boş set fail-closed'dur)", () => {
    for (const [href, requirement] of Object.entries(
      ADMIN_NAV_PERMISSION_REQUIREMENTS,
    )) {
      expect(href).toMatch(/^\/admin\//)
      expect(requirement.codes.length).toBeGreaterThan(0)
      expect(["all", "any"]).toContain(requirement.mode)
    }
  })
})

describe("canAccessAdminNavItem — eşleme semantiği", () => {
  it("all modunda tüm kodlar true ise erişim vardır", () => {
    expect(
      canAccessAdminNavItem("/admin/roles", { "users.manage": true }),
    ).toBe(true)
    expect(
      canAccessAdminNavItem("/admin/users", { "users.manage": true }),
    ).toBe(true)
  })

  it("all modunda tek eksik kod erişimi kapatır", () => {
    expect(
      canAccessAdminNavItem("/admin/roles", { "users.manage": false }),
    ).toBe(false)
    expect(canAccessAdminNavItem("/admin/roles", {})).toBe(false)
  })

  it("bilinmeyen rota ve boş izin seti fail-closed false döner", () => {
    expect(canAccessAdminNavItem("/admin/yok", { "users.manage": true })).toBe(
      false,
    )
  })

  it("any modunda tek eşleşme yeterlidir", () => {
    expect(
      canAccessAdminNavItem("/admin/candidate-batches", {
        "ai.manage": true,
        "questions.approve": false,
      }),
    ).toBe(true)
    expect(
      canAccessAdminNavItem("/admin/candidate-batches", {
        "ai.manage": false,
        "questions.approve": false,
      }),
    ).toBe(false)
  })
})

describe("collectAdminNavPermissionCodes", () => {
  it("users.manage yalnız bir kez listelenir ve spam değildir", () => {
    const codes = collectAdminNavPermissionCodes()
    expect(codes).toContain("users.manage")
    expect(codes.filter((code) => code === "users.manage")).toHaveLength(1)
    expect(new Set(codes).size).toBe(codes.length)
  })

  it("sıralı ve büyük/küçük harf normalize döner", () => {
    const codes = collectAdminNavPermissionCodes()
    expect([...codes].sort()).toEqual(codes)
    expect(codes.every((code) => code === code.toLowerCase())).toBe(true)
  })
})