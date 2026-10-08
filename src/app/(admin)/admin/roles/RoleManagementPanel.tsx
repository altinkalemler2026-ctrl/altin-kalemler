"use client"

/**
 * Faz UI-P4C — süper admin rol atama/kaldırma paneli.
 *
 * İki adımlı yazma modeli (BU FAZIN ANA GÜVENLİK ÖZELLİĞİ):
 *   1. "Onaya Git" — YAZMAZ. Yalnız yerel istemci durumunu değiştirip onay
 *      adımını açar. `type="button"`dır ve hiçbir `<form action=...>`
 *      içinde değildir; basıldığında sunucuda hiçbir aksiyon çalışmaz.
 *   2. "İşlemi Onayla" — TEK yazma noktası (`submitRoleMutationAction`).
 *      Adım 1'de seçim tamamlanmadan bu form hiç render edilmez.
 *
 * Koruma garantileri:
 * - `super_admin` rolü bu panelde HİÇBİR SEÇENEKTE görünmez (savunma
 *   katmanı; sayfa kataloğu da zaten filtreler, DB E6/E7 son otoritedir).
 * - Hedef listesinde oturum sahibi bulunmaz (sayfada `buildRoleManagementView`
 *   `actorUserId`'yi her zaman çıkarır); kendine işlem istemci + sunucu + DB
 *   üç katmanında da reddedilir.
 * - Onay adımı her render'da yeniden geçerlilik denetler: hedef kaybolduysa
 *   veya seçilen rol artık kaldırılabilir/atanabilir değilse adım 1'e düşer.
 * - Çift gönderim koruması: `useFormStatus` + yerel `submitting` bayrağı;
 *   RPC'ler idempotent olduğundan (`already_*`) kayıt kopyası oluşmaz.
 *
 * Erişilebilirlik:
 * - Durum duyuruları `role="status"`, uyarılar `role="alert"` ile verilir.
 * - Etkileşimli hedefler en az 44px yüksekliğindedir (`min-h-11`).
 * - Adım değişiminde odak onay adımı başlığına taşınır (klavye kullanıcısı
 *   adım değişimini kaçırmaz).
 */

import { useEffect, useRef, useState } from "react"
import { useFormStatus } from "react-dom"
import { ADMIN_ROLES_MESSAGES as M } from "@/lib/admin/admin-panel-messages"
import { SUPER_ADMIN_ROLE_CODE } from "@/lib/admin/role-management-shared"
import { ROLE_MUTATION_OPERATION_LABELS } from "@/lib/admin/role-management-errors"
import { submitRoleMutationAction } from "./actions"

export interface PanelTarget {
  userId: string
  label: string
  isRosterAdmin: boolean
  assignedRoleCodes: string[]
}

export interface PanelRole {
  roleCode: string
  name: string
}

export interface RoleManagementPanelProps {
  targets: PanelTarget[]
  roles: PanelRole[]
}

type Operation = "assign" | "revoke"

interface ConfirmedSelection {
  targetUserId: string
  targetLabel: string
  operation: Operation
  roleCode: string
  roleName: string
}

/** Tek yazma düğmesi: `useFormStatus` ile form gönderimi sırasında kilitlenir. */
function SubmitButton({ defaultLabel }: { defaultLabel: string }) {
  const status = useFormStatus()
  return (
    <button
      type="submit"
      disabled={status.pending}
      className={`inline-flex min-h-11 items-center rounded-xl px-5 py-2.5 font-semibold ${
        status.pending
          ? "cursor-wait bg-emerald-100 text-emerald-800"
          : "bg-emerald-700 text-white hover:bg-emerald-800"
      }`}
    >
      {status.pending ? M.pendingLabel : defaultLabel}
    </button>
  )
}

/** Onay adımı: seçilen işlemi salt okunur gösterir ve tek yazma düğmesini sunar. */
function ConfirmStep({
  selection,
  onCancel,
}: {
  selection: ConfirmedSelection
  onCancel: () => void
}) {
  const headingRef = useRef<HTMLHeadingElement>(null)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    headingRef.current?.focus()
  }, [])

  return (
    <section
      aria-labelledby="role-confirm-heading"
      className="mt-6 rounded-xl border border-gray-200 bg-gray-50 p-4"
    >
      <h3
        id="role-confirm-heading"
        ref={headingRef}
        tabIndex={-1}
        className="text-sm font-semibold text-gray-800 outline-none"
      >
        {M.stepConfirmHeading}
      </h3>
      <p className="mt-1 text-sm text-gray-600">{M.stepConfirmHint}</p>

      <dl className="mt-4 grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl bg-white px-4 py-3">
          <dt className="text-xs text-gray-500">{M.confirmTargetLabel}</dt>
          <dd className="mt-1 break-words text-sm font-medium text-gray-900">
            {selection.targetLabel}
          </dd>
          <dd className="mt-0.5 break-all text-xs text-gray-500">
            {selection.targetUserId}
          </dd>
        </div>
        <div className="rounded-xl bg-white px-4 py-3">
          <dt className="text-xs text-gray-500">{M.confirmOperationLabel}</dt>
          <dd className="mt-1 text-sm font-semibold text-gray-900">
            {ROLE_MUTATION_OPERATION_LABELS[selection.operation]}
          </dd>
        </div>
        <div className="rounded-xl bg-white px-4 py-3">
          <dt className="text-xs text-gray-500">{M.confirmRoleLabel}</dt>
          <dd className="mt-1 text-sm font-semibold text-gray-900">
            {selection.roleName}
          </dd>
        </div>
      </dl>

      <p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
        {M.confirmNotice}
      </p>

      {/* TEK YAZMA NOKTASI. */}
      <form
        action={submitRoleMutationAction}
        onSubmit={() => setSubmitting(true)}
        className="mt-4 grid gap-3"
      >
        <input type="hidden" name="operation" value={selection.operation} />
        <input type="hidden" name="targetUserId" value={selection.targetUserId} />
        <input type="hidden" name="roleCode" value={selection.roleCode} />

        <div className="flex flex-wrap gap-3">
          <SubmitButton defaultLabel={M.confirmLabel} />
          <button
            type="button"
            onClick={() => {
              setSubmitting(false)
              onCancel()
            }}
            disabled={submitting}
            className="inline-flex min-h-11 items-center rounded-xl border border-gray-300 bg-white px-5 py-2.5 font-semibold text-gray-700 hover:bg-gray-100 disabled:cursor-not-allowed disabled:text-gray-400"
          >
            {M.cancelLabel}
          </button>
        </div>
      </form>
    </section>
  )
}

export default function RoleManagementPanel({
  targets,
  roles,
}: RoleManagementPanelProps) {
  // `super_admin` savunma katmanı: sayfa filtrelese de panel asla sunmaz.
  const managableRoles = roles.filter(
    (role) => role.roleCode !== SUPER_ADMIN_ROLE_CODE,
  )
  const rolesByCode = new Map(managableRoles.map((r) => [r.roleCode, r]))

  // Adım 1 durumu (yazmasız): radyo seçimleri.
  const [draftTarget, setDraftTarget] = useState<string | null>(null)
  const [operation, setOperation] = useState<Operation | null>(null)
  const [roleCode, setRoleCode] = useState<string | null>(null)
  const [confirmed, setConfirmed] = useState<ConfirmedSelection | null>(null)

  const selectedTarget =
    targets.find((target) => target.userId === draftTarget) ?? null

  const availableRoles =
    !selectedTarget || !operation
      ? []
      : operation === "assign"
        ? managableRoles.filter(
            (role) => !selectedTarget.assignedRoleCodes.includes(role.roleCode),
          )
        : managableRoles.filter((role) =>
            selectedTarget.assignedRoleCodes.includes(role.roleCode),
          )

  const selectionComplete =
    selectedTarget !== null && operation !== null && roleCode !== null

  // Onay adımı her render'da yeniden denetlenir; seçim geçersizse adım 1.
  const confirmSelection =
    confirmed &&
    confirmed.roleCode !== SUPER_ADMIN_ROLE_CODE &&
    selectedTarget?.userId === confirmed.targetUserId &&
    availableRoles.some((role) => role.roleCode === confirmed.roleCode)
      ? confirmed
      : null

  function resetSelection() {
    setDraftTarget(null)
    setOperation(null)
    setRoleCode(null)
    setConfirmed(null)
  }

  function handleTargetChange(userId: string) {
    setDraftTarget(userId)
    setOperation(null)
    setRoleCode(null)
  }

  function proceed() {
    if (!selectedTarget || !operation || !roleCode) return
    const role = rolesByCode.get(roleCode)
    setConfirmed({
      targetUserId: selectedTarget.userId,
      targetLabel: selectedTarget.label,
      operation,
      roleCode,
      roleName: role?.name ?? roleCode,
    })
  }

  return (
    <section
      aria-labelledby="role-panel-heading"
      className="rounded-2xl border border-gray-200 bg-white p-4 shadow-sm sm:p-6"
    >
      <h2 id="role-panel-heading" className="text-lg font-semibold text-gray-900">
        {M.mutationOpenHeading}
      </h2>
      <p className="mt-1 text-sm text-gray-600">{M.mutationOpenIntro}</p>

      {confirmSelection ? (
        <ConfirmStep
          selection={confirmSelection}
          onCancel={resetSelection}
        />
      ) : targets.length === 0 ? (
        <p
          role="status"
          className="mt-4 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-600"
        >
          {M.noTargets}
        </p>
      ) : (
        <section aria-labelledby="role-select-heading" className="mt-4">
          <h3
            id="role-select-heading"
            className="text-sm font-semibold text-gray-800"
          >
            {M.stepSelectHeading}
          </h3>
          <p className="mt-1 text-sm text-gray-600">{M.stepSelectHint}</p>

          <fieldset className="mt-4 grid gap-2">
            <legend className="text-sm font-medium text-gray-700">
              {M.targetLegend}
            </legend>
            {targets.map((target) => (
              <label
                key={target.userId}
                className="flex min-h-11 items-start gap-3 rounded-xl border border-gray-300 bg-white px-4 py-3"
              >
                <input
                  type="radio"
                  name="role-target"
                  value={target.userId}
                  checked={draftTarget === target.userId}
                  onChange={() => handleTargetChange(target.userId)}
                  className="mt-1 h-4 w-4"
                />
                <span className="grid gap-0.5">
                  <span className="text-sm font-semibold text-gray-900">
                    {target.label}
                    {target.isRosterAdmin && (
                      <span className="ml-2 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-normal text-gray-600">
                        {M.rolesLabel}
                      </span>
                    )}
                  </span>
                  <span className="break-all text-xs text-gray-500">
                    {target.userId}
                  </span>
                  {target.assignedRoleCodes.length === 0 ? (
                    <span className="text-xs text-gray-500">
                      {M.noRoles}
                      {!target.isRosterAdmin && ` · ${M.profileMissing}`}
                    </span>
                  ) : (
                    <span className="flex flex-wrap gap-1">
                      {target.assignedRoleCodes.map((code) => (
                        <span
                          key={code}
                          className="rounded-full bg-indigo-50 px-2 py-0.5 text-xs font-medium text-indigo-700"
                        >
                          {rolesByCode.get(code)?.name ?? code}
                        </span>
                      ))}
                    </span>
                  )}
                </span>
              </label>
            ))}
          </fieldset>

          <fieldset className="mt-4 grid gap-2">
            <legend className="text-sm font-medium text-gray-700">
              {M.operationLegend}
            </legend>
            <div className="grid gap-2 sm:grid-cols-2">
              {(["assign", "revoke"] as const).map((op) => (
                <label
                  key={op}
                  className={`flex min-h-11 items-start gap-3 rounded-xl border px-4 py-3 ${
                    selectedTarget
                      ? "border-gray-300 bg-white"
                      : "cursor-not-allowed border-gray-200 bg-gray-50"
                  }`}
                >
                  <input
                    type="radio"
                    name="role-operation"
                    value={op}
                    disabled={!selectedTarget}
                    checked={operation === op}
                    onChange={() => {
                      setOperation(op)
                      setRoleCode(null)
                    }}
                    className="mt-1 h-4 w-4"
                  />
                  <span
                    className={`text-sm font-semibold ${
                      selectedTarget ? "text-gray-900" : "text-gray-400"
                    }`}
                  >
                    {ROLE_MUTATION_OPERATION_LABELS[op]}
                  </span>
                </label>
              ))}
            </div>
          </fieldset>

          <fieldset className="mt-4 grid gap-2">
            <legend className="text-sm font-medium text-gray-700">
              {M.roleLegend}
            </legend>
            {availableRoles.length === 0 ? (
              <p
                role="status"
                className="rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-600"
              >
                {operation === "revoke"
                  ? M.noRevokableRolesHint
                  : operation === "assign"
                    ? M.noAssignableRolesHint
                    : M.targetHint}
              </p>
            ) : (
              <div className="grid gap-2 sm:grid-cols-2">
                {availableRoles.map((role) => (
                  <label
                    key={role.roleCode}
                    className="flex min-h-11 items-start gap-3 rounded-xl border border-gray-300 bg-white px-4 py-3"
                  >
                    <input
                      type="radio"
                      name="role-selection"
                      value={role.roleCode}
                      checked={roleCode === role.roleCode}
                      onChange={() => setRoleCode(role.roleCode)}
                      className="mt-1 h-4 w-4"
                    />
                    <span className="text-sm font-semibold text-gray-900">
                      {role.name}
                      <span className="ml-2 text-xs font-normal text-gray-500">
                        {role.roleCode}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
            )}
          </fieldset>

          <button
            type="button"
            onClick={proceed}
            disabled={!selectionComplete}
            className={`mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-xl px-5 py-2.5 font-semibold sm:w-auto ${
              selectionComplete
                ? "bg-gray-900 text-white hover:bg-gray-700"
                : "cursor-not-allowed bg-gray-100 text-gray-400"
            }`}
          >
            {M.proceedLabel}
          </button>
        </section>
      )}
    </section>
  )
}