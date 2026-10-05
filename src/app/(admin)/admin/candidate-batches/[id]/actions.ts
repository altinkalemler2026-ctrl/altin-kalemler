"use server"

/**
 * Faz 35 / UI-P2A — AI aday soru insan kararı sunucu aksiyonu.
 *
 * GÜVENLİK (katmanlı, fail-closed):
 *  1. Oturum yoksa `/login`'e yönlendirilir.
 *  2. Karar yetkisi sunucuda yeniden doğrulanır: `ai.manage` VEYA
 *     `questions.approve` (migration 130:1504 ile aynı yetki çifti).
 *  3. Karar uygunluğu sunucuda **yeniden türetilir**; istemciden gelen
 *     hiçbir "karar uygun" bilgisi güvenilmez. Kaynak veri tekrar okunur.
 *  4. RPC'nin kendi guard'ı da `private` katmanında çalışır (SECURITY
 *     DEFINER, `auth.uid()` + `current_user_has_admin_permission`).
 *
 * YAZMA KAPSAMI:
 *  - Tek ve yalnız yazma noktası `public.review_and_promote_ai_question`
 *    RPC'sidir (migration 039 köprüsü -> migration 130 uygulaması).
 *  - Bu ekran YAYINLAMA YAPMAZ. `activate_question_for_students` veya
 *    benzeri hiçbir yayın fonksiyonu bu dosyada çağrılmaz; `revalidatePath`
 *    yalnız admin rotalarına uygulanır, öğrenci rotaları geçersiz kılınmaz.
 *  - Karar, yalnız açık admin tıklaması + ayrı onay adımı ile yazılır.
 */

import { revalidatePath } from "next/cache"
import { redirect } from "next/navigation"
import { createClient } from "@/lib/supabase/server"
import {
  getCandidateBatchDetail,
  hasCandidateBatchReadPermission,
  type CandidateBatchDetail,
} from "@/lib/admin/candidate-batches"
import { isDecisionAvailable, validateDecisionInput } from "@/lib/admin/candidate-decisions"
import { parseBatchUuid } from "@/lib/admin/candidate-batches-errors"
import {
  CANDIDATE_DECISION_ERROR_MESSAGES,
  decisionOutcomeMessage,
  isCandidateDecisionOutcomeStatus,
  mapCandidateDecisionError,
  mapDecisionInputError,
} from "@/lib/admin/candidate-decisions-errors"

type ReviewAndPromoteRpc = (
  functionName: "review_and_promote_ai_question",
  args: {
    p_staging_question_id: string
    p_decision: string
    p_review_notes?: string
  },
) => Promise<{
  data: Record<string, unknown> | null
  error: { message: string } | null
}>

/**
 * Karar sonrası dönülecek adres.
 *
 * `candidatePosition` 1 tabanlı aday sırasıdır; detay sayfasındaki
 * `?candidate=` sorgu parametresi ile aynı sözleşmeyi paylaşır.
 */
function detailPath(batchId: string, candidatePosition?: number): string {
  const base = `/admin/candidate-batches/${batchId}`
  return candidatePosition === undefined
    ? base
    : `${base}?candidate=${candidatePosition}`
}

function flash(path: string, kind: "ok" | "error", message: string): never {
  const params = new URLSearchParams()
  params.set(kind, message)
  redirect(`${path}${path.includes("?") ? "&" : "?"}${params.toString()}`)
}

function readField(formData: FormData, key: string): string {
  const value = formData.get(key)
  return typeof value === "string" ? value : ""
}

function readCandidatePosition(formData: FormData): number | undefined {
  const raw = readField(formData, "candidatePosition")
  if (!/^\d{1,4}$/.test(raw)) return undefined
  return Number(raw)
}

/**
 * Adayı staging kimliğiyle eşleştirir.
 *
 * `getCandidateBatchDetail` hata/eksik dönerse `null` -> fail-closed.
 */
function findCandidateByStagingId(
  detail: CandidateBatchDetail | null,
  stagingQuestionId: string
) {
  return (
    detail?.candidates.find(
      (candidate) => candidate.stagingQuestionId === stagingQuestionId
    ) ?? null
  )
}

/**
 * Aday kararını sunucuda kaydeder.
 *
 * `batchId` yalnızca dönüş adresi ve yeniden doğrulama kaynağıdır; karar
 * uygunluğu staging kaydının kendi kapsamından türetilir.
 */
export async function submitCandidateDecisionAction(
  formData: FormData
): Promise<void> {
  const batchId = parseBatchUuid(readField(formData, "batchId").trim())
  const candidatePosition = readCandidatePosition(formData)

  // Paket kimliği geçersizse detay sayfası hedeflenemez -> liste sayfası.
  if (!batchId) {
    const params = new URLSearchParams()
    params.set("error", CANDIDATE_DECISION_ERROR_MESSAGES.notFound)
    redirect(`/admin/candidate-batches?${params.toString()}`)
  }

  const path = detailPath(batchId, candidatePosition)

  const validated = validateDecisionInput({
    stagingQuestionId: readField(formData, "stagingQuestionId"),
    decision: readField(formData, "decision"),
    rationale: readField(formData, "rationale"),
  })
  if (!validated.ok) {
    flash(path, "error", mapDecisionInputError(validated.error))
  }

  // 1) Oturum
  const supabase = await createClient()
  const { data: userData } = await supabase.auth.getUser()
  if (!userData.user) {
    redirect("/login")
  }

  // 2) Sunucu yetkisi (migration 130:1504 ile ayni yetki cifti).
  if (!(await hasCandidateBatchReadPermission())) {
    flash(path, "error", CANDIDATE_DECISION_ERROR_MESSAGES.forbidden)
  }

  // 3) Karar uygunlugunu sunucuda yeniden turet. Istemci katmanindaki
  //    disabled durumu yalnizca bilgilendirme amacli; otorite budur.
  const detail = await getCandidateBatchDetail(batchId)
  if (detail.status === "error") {
    flash(path, "error", CANDIDATE_DECISION_ERROR_MESSAGES.generic)
  }

  const candidate = findCandidateByStagingId(
    detail.item,
    validated.stagingQuestionId
  )
  if (!candidate) {
    flash(path, "error", CANDIDATE_DECISION_ERROR_MESSAGES.notFound)
  }

  if (!isDecisionAvailable(candidate, validated.decision)) {
    flash(path, "error", CANDIDATE_DECISION_ERROR_MESSAGES.notEligible)
  }

  // 4) Tek yazma noktasi. Yayin fonksiyonu YOK.
  const rpc = supabase.rpc.bind(supabase) as unknown as ReviewAndPromoteRpc
  const { data, error } = await rpc("review_and_promote_ai_question", {
    p_staging_question_id: validated.stagingQuestionId,
    p_decision: validated.decision,
    p_review_notes:
      validated.rationale.length > 0 ? validated.rationale : undefined,
  })

  if (error) {
    flash(path, "error", mapCandidateDecisionError(error))
  }

  const status = data?.status
  if (!isCandidateDecisionOutcomeStatus(status)) {
    // Beklenmeyen yanit: fail-closed, hicbir basari iddiasi yok.
    flash(path, "error", CANDIDATE_DECISION_ERROR_MESSAGES.generic)
  }

  // Yalniz admin rotalari; ogrenci rotalari kasitli olarak gecersiz kilinmaz.
  revalidatePath(path)
  revalidatePath(`/admin/candidate-batches/${batchId}/islem-durumu`)
  revalidatePath("/admin/candidate-batches")

  flash(path, "ok", decisionOutcomeMessage(status))
}