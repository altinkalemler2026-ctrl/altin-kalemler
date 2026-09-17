/**
 * Yazılı + videolu çözüm hattı türleri (EK KAPSAM).
 *
 * Sözleşme:
 * - Her sorunun yazılı çözümü yapılandırılmıştır: yöntem, işlem/adımlar,
 *   sonuç, doğru cevabın gerekçesi, gerektiğinde yanlış seçenek
 *   açıklamaları ve yaygın hata.
 * - Yazılı çözüm, doğru şıkkın yazılmasından ibaret DEĞİLDİR; bağımsız
 *   doğrulamadan geçer (bkz. solution-validator.ts).
 * - Video çözüm hattı aynı yapıya bağlanır: onaylı çözüm → anlatım
 *   metni/storyboard → seslendirme → adımlarla eşleşen görsel/formül →
 *   altyazı → tutarlılık denetimi → insan yayın onayı.
 * - Video, soru + ÇÖZÜM SÜRÜMÜ'ne bağlıdır; çözüm değişirse eski video
 *   güncel sayılmaz (solutionVersion içerik hash'i ile karşılaştırılır).
 * - Video bir kez üretilip saklanır; her izleyişte AI çağrısı yapılmaz.
 */

import type { AiWorkerOptionKey } from "@/ai-worker/types"

// ============================================================
// YAZILI ÇÖZÜM
// ============================================================

/** Tek bir çözüm adımı. */
export interface SolutionStep {
  /** Adımın kısa başlığı (ör. "Verilenleri yazalım"). */
  title: string
  /** Adımın açıklama/işlem metni. */
  content: string
  /** Gerektiğinde formül/ifade (LaTeX metin olarak). */
  formula?: string
}

/** Yanlış seçenek açıklaması. */
export interface WrongOptionExplanation {
  option: Exclude<AiWorkerOptionKey, never>
  explanation: string
}

/**
 * Yapılandırılmış yazılı çözüm. "Yalnız doğru şıkkın yazılması" bu
 * şemanın doldurulmuş hâli ile ASLA örtüşmez; validator bunu reddeder.
 */
export interface WrittenSolution {
  /** Çözümde kullanılan yöntem (ör. "Kesirlerde payda eşitleme"). */
  method: string
  /** Sıralı işlem/adımlar. En az bir adım ZORUNLU. */
  steps: SolutionStep[]
  /** Nihai sonuç ifadesi (ör. "Sonuç 3/4'tür."). */
  result: string
  /** Doğru cevabın gerekçesi; adım adım zinciri şıkka bağlar. */
  correctAnswerJustification: string
  /** Gerektiğinde yanlış seçenek açıklamaları. */
  wrongOptionExplanations?: WrongOptionExplanation[]
  /** Gerektiğinde yaygın hata (öğrenci tuzakları). */
  commonMistakes?: string[]
}

/**
 * Çözüm sürümü: yazılı çözümün canonical JSON serileştirmesinin içerik
 * hash'i. İçerik değişirse hash değişir → çözüme bağlı video otomatik
 * olarak "güncel değil" sayılır.
 */
export type SolutionVersion = string

/** Bağımsız yazılı çözüm doğrulama sonucu. */
export type SolutionValidationStatus = "pass" | "fail" | "needs_review"

export interface SolutionValidation {
  status: SolutionValidationStatus
  /** Deterministik neden kodları (fail/needs_review için). */
  reasons: string[]
}

// ============================================================
// VİDEO ÇÖZÜM HATTI
// ============================================================

/** Video üretim hattı aşamaları (sıralı durum makinesi). */
export const VIDEO_PIPELINE_STAGES = [
  "not_started",
  "narration",
  "storyboard",
  "voiceover",
  "visuals",
  "subtitles",
  "consistency_audit",
  "human_publish",
  "published",
] as const

export type VideoPipelineStage = (typeof VIDEO_PIPELINE_STAGES)[number]

/** Video hattı anahtarı üretiminin durumu (sağlayıcı yapılandırması). */
export type VideoProviderConfigState = "not_configured" | "configured"

export interface VideoNarration {
  /** Adım adım anlatım metni (storyboard kaynağı). */
  narrationText: string
  language: "tr"
}

export interface VideoStoryboard {
  scenes: Array<{
    order: number
    /** Anlatımdaki adıma bağlı başlık. */
    stepTitle: string
    voiceoverText: string
    /** Bu sahnede gösterilecek görsel/formül içeriği (metin olarak). */
    visualContent: string
  }>
}

export interface VideoSubtitles {
  language: "tr"
  /** Altyazı parçaları (timing ms + metin). */
  segments: Array<{ startMs: number; endMs: number; text: string }>
}

/**
 * Tutarlılık denetimi sonucu: ses/görüntü/cevap/tutarlılık. Bu denetim
 * bağımsızdır ve AI değerlendirmesini kesin doğruluk garantisi olarak
 * SUNMAZ.
 */
export interface VideoConsistencyAudit {
  passed: boolean
  issues: string[]
}

/** Üretilmiş video artefaktları (tek seferlik üretilir, saklanır). */
export interface VideoArtefacts {
  videoUrl: string
  storagePath: string
  subtitles: VideoSubtitles
  durationMs: number
  /** Hangi çözüm sürümünden üretildiği (içerik hash'i). */
  solutionVersion: SolutionVersion
}

/**
 * Bir soru için video çözüm hattı iş görünümü. Öğrenciye bozuk/boş
 * oynatıcı gösterilmez: yalnız `published` + `humanApproved` ise ve
 * güncel solutionVersion ile eşleşiyorsa video kullanılabilir.
 */
export interface VideoSolutionPipeline {
  questionId: string
  stage: VideoPipelineStage
  providerConfig: VideoProviderConfigState
  /** Pipeline'ın üretildiği çözüm sürümü (çözüm değişirse stale olur). */
  builtForSolutionVersion: SolutionVersion | null
  /** Mevcut yazılı çözüm sürümü (karşılaştırma eşiği). */
  currentSolutionVersion: SolutionVersion | null
  isStale: boolean
  narration: VideoNarration | null
  storyboard: VideoStoryboard | null
  artefacts: VideoArtefacts | null
  consistencyAudit: VideoConsistencyAudit | null
  humanApproved: boolean
  /** Denetim geçti + insan onayı + sağlayıcı yapılandırıldı + güncel değil. */
  readyForStudents: boolean
}

// ============================================================
// SOLÜSYON VARLIĞI (question_solution_assets uyumlu künye)
// ============================================================

/** question_solution_assets asset_type allowlist (004). */
export const SOLUTION_ASSET_TYPES = [
  "text_solution",
  "video",
  "audio",
  "image",
  "pdf",
  "interactive_player",
  "other",
] as const

export type SolutionAssetType = (typeof SOLUTION_ASSET_TYPES)[number]

/** question_solution_assets validation_status allowlist (004). */
export const SOLUTION_ASSET_VALIDATION_STATUSES = [
  "pending",
  "valid",
  "invalid",
  "duplicate_suspected",
  "needs_review",
] as const

export type SolutionAssetValidationStatus =
  (typeof SOLUTION_ASSET_VALIDATION_STATUSES)[number]

/** Admin panelinde görünen izinli çözüm varlığı DTO'su. */
export interface SolutionAssetView {
  id: string
  assetType: SolutionAssetType
  validationStatus: SolutionAssetValidationStatus
  isActive: boolean
  sourceType: string | null
  /** Yazılı çözüm metni (text_solution). */
  assetText: string | null
  /** Video/medya URL'si (varsa). */
  assetUrl: string | null
  createdAt: string
  /** Çözüm sürümü (içerik hash'i) — migration ile DB'ye taşınır. */
  solutionVersion: SolutionVersion | null
}

/** Admin paneli için bir sorunun çözüm + video özeti. */
export interface SolutionOverview {
  questionId: string
  questionCode: string
  subjectName: string | null
  gradeLevel: number
  writtenSolutions: SolutionAssetView[]
  videoPipeline: VideoSolutionPipeline | null
}