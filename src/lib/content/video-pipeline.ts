/**
 * Video çözüm üretim hattı (durum makinesi + sahte sağlayıcı).
 *
 * AKIŞ: onaylı çözüm → anlatım/storyboard → seslendirme → adımlarla
 * eşleşen görsel → altyazı → tutarlılık denetimi → insan yayın onayı.
 *
 * SÖZLEŞME:
 * - Sağlayıcı configure edilmemişse (providerConfig='not_configured') hiçbir
 *   aşama ilerlemez ve hiçbir artefakt "başarılı" GÖSTERİLMEZ.
 * - Video bir kez üretilip saklanır; her izleyişte AI çağrısı yapılmaz.
 * - Video, çözüm sürümüne (içerik hash'i) bağlıdır; yazılı çözüm
 *   değişirse isStale=true olur ve eski video güncel sayılmaz.
 * - Tutarlılık denetimi kesin doğruluk garantisi SUNMAZ; yalnız
 *   ses/görüntü/cevap/tutarlılık göstergelerini denetler.
 *
 * Bu kapsamda GERÇEK TTS/video API çağrısı YOKTUR; FakeVideoSolutionProvider
 * deterministik artefakt üretir ve gereksinim fotoğraftaki sağlayıcı
 * ihtiyacını uygulanmadan raporlar.
 */

import { createHash } from "node:crypto"

import type { AiWorkerOptionKey } from "@/ai-worker/types"

import { validateWrittenSolution } from "./solution-validator"
import type { WrittenSolution } from "./solution-types"

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

// ============================================================
// SAĞLAYICI ARABİRİMİ
// ============================================================

export interface VideoGenerationContext {
  questionText: string
  writtenSolution: WrittenSolution
  correctAnswer: string
  solutionVersion: string
}

export interface VoiceoverResult {
  voiceoverUrl: string
  storagePath: string
  durationMs: number
}

export interface VisualsResult {
  /** Sahne → görsel içerik eşlemesi (adımlarla hizalı). */
  scenes: Array<{ order: number; stepTitle: string; visualRef: string }>
}

export interface VideoRenderResult {
  videoUrl: string
  storagePath: string
  durationMs: number
}

/** Video üretim hattı sağlayıcı sözleşmesi. Derste gerçek sağlayıcı yoktur. */
export interface VideoSolutionProvider {
  readonly providerName: string
  /** Ayar eksikse false; false iken hiçbir aşama "başarılı" sayılmaz. */
  readonly configured: boolean

  generateNarration(context: VideoGenerationContext): Promise<{ narrationText: string; storyboardText: string }>
  generateVoiceover(context: VideoGenerationContext): Promise<VoiceoverResult>
  generateVisuals(context: VideoGenerationContext): Promise<VisualsResult>
  generateSubtitles(context: VideoGenerationContext): Promise<Array<{ startMs: number; endMs: number; text: string }>>
  renderVideo(context: VideoGenerationContext): Promise<VideoRenderResult>
}

/** Yapılandırılmamış durumu temsil eden sağlayıcı — görev başarısı asla üretmez. */
export function notConfiguredProviderName(): string {
  return "unconfigured"
}

// ============================================================
// SAHTE SAĞLAYICI (testler + yerel önizleme; gerçek çağrı YOK)
// ============================================================

/**
 * Deterministik sahte sağlayıcı. configured=false ile "yapılandırılmadı"
 * durumu test edilir; configured=true iken bilinen değerler döner.
 */
export class FakeVideoSolutionProvider implements VideoSolutionProvider {
  readonly providerName: string
  readonly configured: boolean

  constructor(configured: boolean) {
    this.providerName = configured ? "fake-video-provider" : notConfiguredProviderName()
    this.configured = configured
  }

  async generateNarration(context: VideoGenerationContext) {
    if (!this.configured) throw new Error("Video sağlayıcı yapılandırılmadı.")
    const stepTitles = context.writtenSolution.steps.map((s) => s.title).join(", ")
    return {
      narrationText: `${context.writtenSolution.method}. Adımlar: ${stepTitles}. Sonuç: ${context.writtenSolution.result}`,
      storyboardText: context.writtenSolution.steps
        .map((step, index) => `${index + 1}. ${step.title}: ${step.content}`)
        .join("\n"),
    }
  }

  async generateVoiceover(context: VideoGenerationContext) {
    if (!this.configured) throw new Error("Video sağlayıcı yapılandırılmadı.")
    return { voiceoverUrl: `/assets/fake-voiceover-${context.solutionVersion.slice(0, 6)}.mp3`, storagePath: `solutions/audio/${context.solutionVersion.slice(0, 6)}.mp3`, durationMs: 45_000 }
  }

  async generateVisuals(context: VideoGenerationContext) {
    if (!this.configured) throw new Error("Video sağlayıcı yapılandırılmadı.")
    return {
      scenes: context.writtenSolution.steps.map((step, index) => ({
        order: index + 1,
        stepTitle: step.title,
        visualRef: `slide-${index + 1}`,
      })),
    }
  }

  async generateSubtitles(context: VideoGenerationContext) {
    if (!this.configured) throw new Error("Video sağlayıcı yapılandırılmadı.")
    return [
      { startMs: 0, endMs: 15_000, text: context.writtenSolution.method },
      ...context.writtenSolution.steps.map((step, index) => ({
        startMs: 15_000 + index * 10_000,
        endMs: 15_000 + (index + 1) * 10_000,
        text: step.title,
      })),
    ]
  }

  async renderVideo(context: VideoGenerationContext) {
    if (!this.configured) throw new Error("Video sağlayıcı yapılandırılmadı.")
    return { videoUrl: `/assets/fake-video-${context.solutionVersion.slice(0, 6)}.mp4`, storagePath: `solutions/video/${context.solutionVersion.slice(0, 6)}.mp4`, durationMs: 45_000 }
  }
}

// ============================================================
// SÖZLEŞME SAF FONKSİYONLARI
// ============================================================

/** Yazılı çözümün deterministik içerik sürümü hash'i. */
export function buildSolutionVersion(solution: WrittenSolution): string {
  return createHash("sha256").update(JSON.stringify(solution)).digest("hex")
}

/** Sahne → adım eşleme ve alt yazı/cevap tutarlılık denetimi (saf, bilgi sızıntısız). */
export function auditVideoConsistency(args: {
  storyboardText: string
  narrationText: string
  correctAnswer: string
  steps: WrittenSolution["steps"]
}): { passed: boolean; issues: string[] } {
  const issues: string[] = []
  const answerLetter = args.correctAnswer.trim().toUpperCase()

  if (!/^[A-E]$/.test(answerLetter)) {
    issues.push("gecersiz_cevap_harfi")
  }

  if (args.storyboardText.trim().length < 10) {
    issues.push("storyboard_bos")
  }

  if (args.narrationText.trim().length < 10) {
    issues.push("anlatim_bos")
  }

  const stepCoverage = args.steps.filter((step) => args.storyboardText.includes(step.title)).length
  if (args.steps.length > 0 && stepCoverage < args.steps.length) {
    issues.push("adim_anlatim_eslesmiyor")
  }

  return { passed: issues.length === 0, issues }
}

function isOptionKey(value: unknown): value is AiWorkerOptionKey {
  return typeof value === "string" && /^[A-E]$/.test(value)
}

/** Yazılı çözümün onay kalitesi için ön kapı: validator pass olmalı. */
export function solutionReadyForVideo(
  solution: WrittenSolution,
  correctAnswer: string
): boolean {
  if (!isOptionKey(correctAnswer)) return false
  const validation = validateWrittenSolution(solution, correctAnswer)
  return validation.status === "pass" && solution.steps.length >= 2
}

// ============================================================
// HATTIN TAMAMLANIŞI (admin yeniden üretim akışı tarafından çağrılır)
// ============================================================

export interface PipelineRunResult {
  stage: VideoPipelineStage
  providerConfigured: boolean
  isStale: boolean
  readyForStudents: boolean
  issues: string[]
  mediaUrls: Array<{ assetType: "video" | "audio"; url: string }>
}

/**
 * Yapılandırılmış sağlayıcıyla hattı sonuna kadar çalıştırır (kayıt
 * yapmaz; dönen medya URL'lerini çağıranın saklaması beklenir).
 * videos kaydedildikten sonra bir kez çağrılır; her izleyişte AI çağrısı
 * yapılmaz — hattı admin yeniden üretim AKTİF tetikler.
 */
export async function runVideoPipeline(
  provider: VideoSolutionProvider,
  context: VideoGenerationContext
): Promise<PipelineRunResult> {
  const issues: string[] = []

  if (!provider.configured) {
    return {
      stage: "not_started",
      providerConfigured: false,
      isStale: false,
      readyForStudents: false,
      issues: ["saglayici_yapilandirilmadi"],
      mediaUrls: [],
    }
  }

  if (!isOptionKey(context.correctAnswer)) {
    return {
      stage: "not_started",
      providerConfigured: true,
      isStale: false,
      readyForStudents: false,
      issues: ["gecersiz_cevap_harfi"],
      mediaUrls: [],
    }
  }

  const validation = validateWrittenSolution(context.writtenSolution, context.correctAnswer)
  if (validation.status !== "pass") {
    return {
      stage: "not_started",
      providerConfigured: true,
      isStale: false,
      readyForStudents: false,
      issues: validation.reasons,
      mediaUrls: [],
    }
  }

  const narration = await provider.generateNarration(context)
  const voiceover = await provider.generateVoiceover(context)
  const visuals = await provider.generateVisuals(context)
  const subtitles = await provider.generateSubtitles(context)
  const video = await provider.renderVideo(context)

  const audit = auditVideoConsistency({
    storyboardText: narration.storyboardText,
    narrationText: narration.narrationText,
    correctAnswer: context.correctAnswer,
    steps: context.writtenSolution.steps,
  })

  if (visuals.scenes.length !== context.writtenSolution.steps.length) {
    issues.push("gorsel_adim_sayisi_uyusmuyor")
  }
  if (subtitles.length < 1) {
    issues.push("altyazi_yok")
  }
  if (!audit.passed) {
    issues.push(...audit.issues)
  }

  const readyForStudents = audit.passed && visuals.scenes.length === context.writtenSolution.steps.length && subtitles.length >= 1

  return {
    stage: readyForStudents ? "human_publish" : "consistency_audit",
    providerConfigured: true,
    isStale: false,
    readyForStudents,
    issues,
    mediaUrls: [
      { assetType: "audio", url: voiceover.voiceoverUrl },
      { assetType: "video", url: video.videoUrl },
    ],
  }
}