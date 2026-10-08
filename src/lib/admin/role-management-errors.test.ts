/**
 * Faz UI-P4C — rol yönetimi hata/mesaj sözleşmesi testleri.
 *
 * Kanıt: migration 131 ham RPC hataları (E1–E7) her biri doğru güvenli
 * sınıfa eşlenir ve Türkçe kullanıcı metnine çevrilir; eşleşmeyen hata
 * `generic` (fail-closed) olur. `already_*` durumlarının denetim/kayıt
 * sözleşmesi ve işlem-uyuşma denetimi doğrulanır.
 */

import { describe, expect, it } from "vitest"
import {
  isRoleMutationOutcomeStatus,
  mapRoleMutationError,
  mapRoleMutationInputError,
  outcomeHasAudit,
  roleMutationErrorKind,
  roleOutcomeMessage,
  statusMatchesOperation,
} from "./role-management-errors"
import type { RoleMutationInputError } from "./role-management"

describe("girdi hata eşleme", () => {
  it("üç girdi hatasını Türkçe mesaja çevirir", () => {
    expect(mapRoleMutationInputError("invalidOperation")).toMatch(
      /işlem seçildi/,
    )
    expect(mapRoleMutationInputError("invalidTarget")).toMatch(/Hedef/)
    expect(mapRoleMutationInputError("invalidRole")).toMatch(/rol geçersiz/)
  })

  it("bilinmeyen girdi hatasında fail-closed varsayılan döner", () => {
    expect(mapRoleMutationInputError("bozuk" as RoleMutationInputError)).toMatch(
      /Geçersiz bir işlem/,
    )
  })
})

describe("RPC hata sınıfları (migration 131 metinleri)", () => {
  it.each([
    ["Human authentication required.", "authRequired"],
    ["Admin role management requires super admin.", "notSuperAdmin"],
    ["Target user not found.", "targetNotFound"],
    ["Admins cannot change their own admin roles.", "selfTarget"],
    ["Invalid admin role code.", "invalidRole"],
    ["Cannot remove the last super admin.", "lastSuperAdmin"],
    [
      "The super admin role cannot be assigned or revoked through the admin role management interface.",
      "superAdminRole",
    ],
  ])("%s => %s", (message, kind) => {
    expect(roleMutationErrorKind(new Error(message))).toBe(kind)
  })

  it("lastSuperAdmin, superAdminRole'dan önce eşleşir (ayrışımdır)", () => {
    expect(
      roleMutationErrorKind(
        new Error("Cannot remove the last super admin."),
      ),
    ).toBe("lastSuperAdmin")
  })

  it("eşleşmeyen hata generic olur; ham metin taşınmaz", () => {
    expect(roleMutationErrorKind(new Error("some unknown db message"))).toBe(
      "generic",
    )
    expect(roleMutationErrorKind("")).toBe("generic")
    expect(roleMutationErrorKind(null)).toBe("generic")
    expect(roleMutationErrorKind({ code: 500 })).toBe("generic")
  })

  it("mapRoleMutationError her sınıfı Türkçe metne çevirir", () => {
    expect(mapRoleMutationError(new Error("Admins cannot change their own admin roles."))).toMatch(/Kendi admin rollerinizi/i)
    expect(mapRoleMutationError(new Error("Cannot remove the last super admin."))).toMatch(/Son süper yönetici/)
    expect(mapRoleMutationError(new Error("Admin role management requires super admin."))).toMatch(/yalnız süper yönetici/)
    expect(mapRoleMutationError(new Error("Human authentication required."))).toMatch(/giriş yapmalısınız/)
    expect(mapRoleMutationError(new Error("The super admin role cannot be assigned or revoked through the admin role management interface."))).toMatch(/Süper yönetici rolü bu ekrandan/)
    expect(mapRoleMutationError(new Error("Invalid admin role code."))).toMatch(/aktif değil/)
    expect(mapRoleMutationError(new Error("Target user not found."))).toMatch(/Hedef kullanıcı bulunamadı/)
    expect(mapRoleMutationError(new Error("bilinmeyen"))).toMatch(/Rol işlemi tamamlanamadı/)
  })
})

describe("sonuç durumları", () => {
  it("yalnız dört allowlist'li durumu kabul eder", () => {
    expect(isRoleMutationOutcomeStatus("assigned")).toBe(true)
    expect(isRoleMutationOutcomeStatus("already_assigned")).toBe(true)
    expect(isRoleMutationOutcomeStatus("revoked")).toBe(true)
    expect(isRoleMutationOutcomeStatus("already_revoked")).toBe(true)
    expect(isRoleMutationOutcomeStatus("promoted")).toBe(false)
    expect(isRoleMutationOutcomeStatus(null)).toBe(false)
    expect(isRoleMutationOutcomeStatus(undefined)).toBe(false)
  })

  it("outcomeHasAudit yalnız gerçek yazmada true", () => {
    expect(outcomeHasAudit("assigned")).toBe(true)
    expect(outcomeHasAudit("revoked")).toBe(true)
    expect(outcomeHasAudit("already_assigned")).toBe(false)
    expect(outcomeHasAudit("already_revoked")).toBe(false)
  })

  it("statusMatchesOperation işlem ile durumu doğru eşleştirir", () => {
    expect(statusMatchesOperation("assign", "assigned")).toBe(true)
    expect(statusMatchesOperation("assign", "already_assigned")).toBe(true)
    expect(statusMatchesOperation("assign", "revoked")).toBe(false)
    expect(statusMatchesOperation("revoke", "revoked")).toBe(true)
    expect(statusMatchesOperation("revoke", "already_revoked")).toBe(true)
    expect(statusMatchesOperation("revoke", "assigned")).toBe(false)
  })

  it("roleOutcomeMessage delta ve denetim bilgisini bildirir", () => {
    expect(roleOutcomeMessage("assigned")).toMatch(/Rol atandı/)
    expect(roleOutcomeMessage("assigned")).toMatch(/denetim kaydına eklendi/)
    expect(roleOutcomeMessage("revoked")).toMatch(/Rol kaldırıldı/)
    expect(roleOutcomeMessage("already_assigned")).toMatch(/zaten atanmış/)
    expect(roleOutcomeMessage("already_assigned")).toMatch(/denetim kaydı yazılmadı/)
    expect(roleOutcomeMessage("already_revoked")).toMatch(/zaten bu kullanıcıdan kaldırılmış/)
    expect(roleOutcomeMessage("already_revoked")).toMatch(/denetim kaydı yazılmadı/)
  })
})