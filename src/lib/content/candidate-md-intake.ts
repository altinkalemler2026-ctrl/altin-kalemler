/**
 * Markdown aday soru paketi v1.1 intake facade'ı (Faz 22).
 *
 * Akış (deterministik, DB'ye girmeden önce her şey sunucuda doğrulanır):
 *
 *   parseCandidateMd(document)
 *     → CandidateMdPackageV11  (uyducu yok; yalnız dökümandaki bilgi)
 *   preflightCandidateMdPackage(package, out_of_package)
 *     → MdPreflightResult       (DB erişimi YOK)
 *   register_candidate_md_batch RPC  → gerçek evren duplicate kontrolü dahil
 *     sunucu zorunlu doğrulama; staging'e yazar; yayın ASLA.
 *
 * Üretici (producer) dökümanda **Üretici:** etiketiyle gelebilir; yoksa
 * çağıran açıkça verir; hiçbirinde yoksa paket reddedilir (uydurma yok).
 *
 * DB duplicate saptaması sunucuda zorunludur (private.register_candidate_md_batch).
 * Facade testleri için opsiyonel `checkUniverseDuplicate` kancası verilir;
 * production'da devre dışı bırakılıp DB'ye güvenilir (closed-loop).
 */

import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/supabase/types"

import type {
  MdIntakeSubmitResult,
  MdPreflightResult,
  CandidateMdPackageV11,
} from "./candidate-md-types"

import { parseCandidateMd } from "./candidate-md-parser"
import { preflightCandidateMdPackage } from "./candidate-md-preflight"

export type MdIntakeClient = SupabaseClient<Database>

export interface MdIntakeOptions {
  /** Dökümandaki **Üretici:** etiketi yokken kullanılır. */
  producer?: { id: string; model?: string }
  /** Paket düzeyi ders adı (dökümanda **Ders:** varsa onunla ezilir). */
  subjectRef?: string
  /** Facade testleri için isteğe bağlı evren kontrollü kanca. */
  checkUniverseDuplicate?: (questionText: string) => Promise<boolean>
}

interface MdIntakeRpcClient {
  rpc(
    fn: "register_candidate_md_batch",
    args: { p_payload: Record<string, unknown> }
  ): Promise<{ data: unknown; error: { message: string } | null }>
}

function toNarrowClient(client: MdIntakeClient): MdIntakeRpcClient {
  return client as unknown as MdIntakeRpcClient
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.filter((v): v is string => typeof v === "string")
}

function asInt(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value)
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value.trim())
    if (Number.isFinite(n)) return Math.trunc(n)
  }
  return fallback
}

/**
 * Dökümanı ayrıştırır ve deterministik preflight yapar.
 * DB'ye DOKUNMAZ; testlerde doğrudan kullanılabilir.
 */
export function prepareCandidateMd(
  document: string,
  options: MdIntakeOptions = {}
): {
  preflight: MdPreflightResult
  parseOk: boolean
  parseNotes: string[]
  package: CandidateMdPackageV11 | null
} {
  const parsed = parseCandidateMd(document)

  const parsedPackage = parsed.package

  // Üretici: döküman etiketi önceliklidir; yoksa seçenek; yoksa null.
  if (parsedPackage && options.producer && !parsedPackage.producer) {
    parsedPackage.producer = { ...options.producer }
  }

  // Paket dersi: seçenek varsa ve paket tarafı belirtilmemişse kullanılır.
  if (parsedPackage && options.subjectRef && !parsedPackage.subject_ref) {
    parsedPackage.subject_ref = options.subjectRef
  }

  const preflight = preflightCandidateMdPackage(
    parsedPackage,
    parsed.out_of_package
  )

  return {
    preflight,
    parseOk: parsed.ok,
    parseNotes: parsed.parse_notes,
    package: parsedPackage,
  }
}

function isEmptyRpcData(data: unknown): boolean {
  if (!data || typeof data !== "object" || Array.isArray(data)) return true
  const obj = data as Record<string, unknown>
  return typeof obj.batch_id !== "string"
}

/**
 * Markdown dökümanını alır; yalnız preflight'ı geçen paketi DB'ye
 * iletir. DB yanıtı MdIntakeSubmitResult'a eşlenir. Ham RPC hatası
 * dışarı sızmaz; allowlist'li özet döner.
 */
export async function submitCandidateMdBatch(
  client: MdIntakeClient,
  document: string,
  options: MdIntakeOptions = {}
): Promise<MdIntakeSubmitResult> {
  const { preflight, parseOk, package: preparedPackage } = prepareCandidateMd(
    document,
    options
  )

  if (!parseOk) {
    return {
      ok: false,
      status: "rejected",
      batch_id: null,
      batch_key: null,
      batch_status: null,
      counts: null,
      staging_ids: [],
      publication_allowed: false,
      review_required: true,
      error: null,
      root_errors: preflight.root_errors,
    }
  }

  // Root hatalı paket DB'ye İLETİLMEZ (üretici yok, şema/origin/yayın/durum
  // ihlali). Aday seviyesi hataları (yalnız invalid adaylar) SQL katmanında
  // kaydedilir; admin denetim izi için iletim yine yapılır.
  if (preflight.root_errors.length > 0) {
    return {
      ok: false,
      status: "forbidden",
      batch_id: null,
      batch_key: null,
      batch_status: null,
      counts: null,
      staging_ids: [],
      publication_allowed: false,
      review_required: true,
      error: null,
      root_errors: preflight.root_errors,
    }
  }

  // Opsiyonel evren kancası (yalnızca testlerde; production DB zorunlu).
  if (options.checkUniverseDuplicate && preflight.candidates.length > 0) {
    const duplicates = new Set<number>()
    if (preparedPackage) {
      for (const candidate of preflight.candidates) {
        if (candidate.status !== "valid") continue
        const text =
          preparedPackage.questions[candidate.index]?.question_text ?? ""
        if (text.trim().length > 0 && (await options.checkUniverseDuplicate(text))) {
          duplicates.add(candidate.index)
        }
      }
    }
    for (const candidate of preflight.candidates) {
      if (candidate.status === "valid" && duplicates.has(candidate.index)) {
        candidate.status = "duplicate"
        candidate.errors.push("existing_universe_duplicate_question_text")
      }
    }
  }

  // Paket-dışı sayaçlar metadata olarak DB'ye geçer (yalnız SAYI).
  const payload = preparedPackage
  if (!payload) {
    return {
      ok: false,
      status: "rejected",
      batch_id: null,
      batch_key: null,
      batch_status: null,
      counts: null,
      staging_ids: [],
      publication_allowed: false,
      review_required: true,
      error: null,
      root_errors: ["no_candidate_blocks_found"],
    }
  }

  const validCount = preflight.candidates.filter((c) => c.status === "valid").length

  const { data, error } = await toNarrowClient(client).rpc(
    "register_candidate_md_batch",
    { p_payload: payload as unknown as Record<string, unknown> }
  )

  if (error) {
    return {
      ok: false,
      status: "error",
      batch_id: null,
      batch_key: null,
      batch_status: null,
      counts: null,
      staging_ids: [],
      publication_allowed: false,
      review_required: true,
      error: error.message,
      root_errors: [],
    }
  }

  if (isEmptyRpcData(data)) {
    return {
      ok: false,
      status: "error",
      batch_id: null,
      batch_key: null,
      batch_status: null,
      counts: null,
      staging_ids: [],
      publication_allowed: false,
      review_required: preflight.review_required,
      error: "batch_id_missing_in_rpc_response",
      root_errors: [],
    }
  }

  const d = data as Record<string, unknown>
  const rpcStatus = typeof d.status === "string" ? d.status : "error"

  return {
    ok: true,
    status:
      rpcStatus === "already_received"
        ? "already_received"
        : rpcStatus === "error"
          ? "error"
          : "submitted",
    batch_id: typeof d.batch_id === "string" ? d.batch_id : null,
    batch_key: typeof d.batch_key === "string" ? d.batch_key : null,
    batch_status: rpcStatus,
    counts: {
      totalItems: asInt(d.total_items),
      validItems: asInt(d.valid_items ?? validCount),
      invalidItems: asInt(d.invalid_items),
      duplicateItems: asInt(d.duplicate_items),
      insertedItems: asInt(d.inserted_items),
    },
    staging_ids: asStringArray(d.staging_ids),
    publication_allowed: false,
    review_required: preflight.review_required,
    error: null,
    root_errors: preflight.root_errors,
  }
}