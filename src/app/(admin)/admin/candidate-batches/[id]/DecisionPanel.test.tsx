/**
 * Faz 35 / UI-P2A — karar paneli istemci testleri.
 *
 * En kritik kanıt: karar kaydı için İKİ ayrı bilinçli tıklama gerekir.
 *   - Radyoya tıklamak YAZMAZ; yalnız "Kararı Seç ve Onaya Git" düğmesini
 *     etkinleştirir, onay adımını AÇMAZ.
 *   - "Kararı Seç ve Onaya Git" YAZMAZ; onay adımını açar.
 *   - Yalnız "Kararı Onayla" düğmesi sunucu aksiyonunu çağırır.
 *
 * Sunucu aksiyonu bu dosyada mock'lanır; hiçbir test gerçek yazma yapmaz.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"
import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"

const submitMock = vi.hoisted(() => vi.fn())

vi.mock("./actions", () => ({
  submitCandidateDecisionAction: submitMock,
}))

import CandidateDecisionPanel from "./DecisionPanel"
import { RATIONALE_MAX_LENGTH } from "@/lib/admin/candidate-decisions"
import type { CandidateRecord } from "@/lib/admin/candidate-batches"

const BATCH_ID = "7ea1ff55-2d0d-4e65-b4d0-cade3724f1e3"
const STAGING_ID = "11111111-2222-4333-8444-555555555555"

function makeCandidate(
  stagingStatus: string | null,
  readinessFields?: Array<{ key: string; value: string | number | string[] | null }>
): CandidateRecord {
  return {
    candidateIndex: 0,
    clientQuestionId: "c-1",
    validationStatus: "passed",
    validationErrors: [],
    validationWarnings: [],
    stagingQuestionId: STAGING_ID,
    preview: stagingStatus
      ? ({ stagingStatus } as unknown as Record<string, unknown>)
      : null,
    validationResults: [],
    reviewQueue: [],
    gates: {
      answerVerification: null,
      curriculumFit: null,
      solveTimeVerification: null,
      originalityVerification: null,
      questionQuality: null,
      readiness: readinessFields ? { fields: readinessFields } : null,
      finalReview: null,
    },
  } as unknown as CandidateRecord
}

const READY_FIELDS = [
  { key: "readiness_status", value: "ready_for_human_review" },
  { key: "readiness_score", value: 1 },
  { key: "blocking_reasons", value: [] },
]

const VALIDATING_FIELDS = [
  { key: "readiness_status", value: "human_review_required" },
  { key: "readiness_score", value: 0 },
  { key: "blocking_reasons", value: ["quality_gate_pending"] },
]

function renderPanel(candidate: CandidateRecord) {
  return render(
    <CandidateDecisionPanel
      batchId={BATCH_ID}
      candidate={candidate}
      candidatePosition={1}
    />
  )
}

const APPROVE = "İncelemeyi Onayla"
const REQUEST_CHANGES = "Düzeltme İste"
const REJECT = "Reddet"
const PROCEED = "Kararı Seç ve Onaya Git"
const CONFIRM = "Kararı Onayla"
const CANCEL = "Vazgeç"

beforeEach(() => {
  submitMock.mockReset()
})

describe("kilit kapı: karar yazmadan önce onay adımı yoktur", () => {
  it("ilk render'da onay düğmesi ve hiçbir form yoktur", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
    // Seçim adımı düğmesi var ama henüz seçim olmadığı için devre dışıdır.
    expect(screen.getByRole("button", { name: PROCEED })).toBeDisabled()
    expect(submitMock).not.toHaveBeenCalled()
  })

  it("radyo seçimi tek başına onay adımını AÇMAZ ve yazma yapmaz", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))

    // Seçim yapıldı ama onay adımı henüz yok.
    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
    // Hiçbir yazma olmadı.
    expect(submitMock).not.toHaveBeenCalled()
    // "Onaya git" düğmesi artık etkin.
    expect(screen.getByRole("button", { name: PROCEED })).toBeEnabled()
  })

  it("onaya git düğmesi onay adımını açar ama YAZMAZ", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    // Onay adımı açıldı.
    expect(screen.getByRole("button", { name: CONFIRM })).toBeInTheDocument()
    expect(screen.getByRole("heading", { name: "2. Kararı Onayla" })).toBeInTheDocument()
    // HENÜZ yazma yok.
    expect(submitMock).not.toHaveBeenCalled()
  })

  it("tam akış: seç -> gerekçe -> onaya git -> onayla = tek sunucu çağrısı", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.type(screen.getByLabelText("Gerekçe"), "cozum hatali")
    await user.click(screen.getByRole("button", { name: PROCEED }))
    await user.click(screen.getByRole("button", { name: CONFIRM }))

    expect(submitMock).toHaveBeenCalledTimes(1)
  })

  it("vazgeç onay adımını kapatır ve tekrar seçim adımına döner, yazmaz", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.click(screen.getByRole("button", { name: PROCEED }))
    expect(screen.getByRole("button", { name: CONFIRM })).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: CANCEL }))

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.getByRole("button", { name: PROCEED })).toBeDisabled()
    expect(submitMock).not.toHaveBeenCalled()
  })
})

describe("gerekçe zorunluluğu", () => {
  it("request_changes seçilince gerekçe zorunlu görünür", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REQUEST_CHANGES) }))

    expect(screen.getByText("Zorunlu (en fazla 2000 karakter).")).toBeInTheDocument()
  })

  it("approve seçilince gerekçe isteğe bağlı görünür", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(APPROVE) }))

    expect(
      screen.getByText("İsteğe bağlı (en fazla 2000 karakter).")
    ).toBeInTheDocument()
  })

  it.each([REQUEST_CHANGES, REJECT])(
    "%s için gerekçesiz onay düğmesi devre dışıdır",
    async (label) => {
      const user = userEvent.setup()
      renderPanel(makeCandidate("needs_review", READY_FIELDS))

      await user.click(screen.getByRole("radio", { name: new RegExp(label) }))
      await user.click(screen.getByRole("button", { name: PROCEED }))

      const confirmButton = screen.getByRole("button", { name: CONFIRM })
      expect(confirmButton).toBeDisabled()
      // Gerekçe olmadan yazma başlatılamaz.
      expect(screen.getByRole("alert")).toHaveTextContent(/Zorunlu/)
      expect(submitMock).not.toHaveBeenCalled()
    }
  )

  it("gerekçe yazılınca onay düğmesi etkinleşir", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.type(screen.getByLabelText("Gerekçe"), "hatali")
    await user.click(screen.getByRole("button", { name: PROCEED }))

    expect(screen.getByRole("button", { name: CONFIRM })).toBeEnabled()
  })

  it("approve gerekçesiz de onaylanabilir", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(APPROVE) }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    expect(screen.getByRole("button", { name: CONFIRM })).toBeEnabled()
  })

  it("gerekçe alanı 2000 karakter sınırını tarayıcı düzeyinde ilan eder", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    // Not: `maxlength` tarayıcı tarafından uygulanır ve `fireEvent.change`
    // ile taklit edilemez. Kesme garantisinin otoritesi alan katmanındaki
    // `normalizeRationale` (bkz. candidate-decisions.test.ts) ve sunucu
    // aksiyonundaki `validateDecisionInput` doğrulamasıdır.
    expect(screen.getByLabelText("Gerekçe")).toHaveAttribute(
      "maxlength",
      String(RATIONALE_MAX_LENGTH)
    )
    expect(RATIONALE_MAX_LENGTH).toBe(2000)
  })
})

describe("fail-closed: validating adayda hiçbir karar açılmaz", () => {
  it("üç karar da devre dışıdır ve nedenler görünür metinle açıklanır", () => {
    renderPanel(makeCandidate("validating", VALIDATING_FIELDS))

    expect(screen.getByRole("radio", { name: new RegExp(APPROVE) })).toBeDisabled()
    expect(screen.getByRole("radio", { name: new RegExp(REQUEST_CHANGES) })).toBeDisabled()
    expect(screen.getByRole("radio", { name: new RegExp(REJECT) })).toBeDisabled()
    expect(screen.getByRole("button", { name: PROCEED })).toBeDisabled()
    expect(screen.queryByRole("form")).toBeNull()
    expect(submitMock).not.toHaveBeenCalled()
  })

  it("devre dışı nedeni yalnız renkle değil metin olarak gösterilir", () => {
    renderPanel(makeCandidate("validating", VALIDATING_FIELDS))

    expect(
      screen.getAllByText(
        /Doğrulama ve hazırlık değerlendirmesi tamamlanmadan insan kararı verilemez/
      ).length
    ).toBeGreaterThan(0)
  })

  it("kapılar kapalıyken yazma yolu hiçbir şekilde açılmaz", () => {
    renderPanel(makeCandidate("validating", VALIDATING_FIELDS))

    expect(screen.queryByRole("button", { name: CONFIRM })).toBeNull()
    expect(screen.queryByRole("form")).toBeNull()
  })
})

describe("approve kapısı readiness durumuna göre", () => {
  it("hazır değilse approve kapalı, diğerleri açık", () => {
    renderPanel(makeCandidate("needs_review", VALIDATING_FIELDS))

    expect(screen.getByRole("radio", { name: new RegExp(APPROVE) })).toBeDisabled()
    expect(screen.getByRole("radio", { name: new RegExp(REQUEST_CHANGES) })).toBeEnabled()
    expect(screen.getByRole("radio", { name: new RegExp(REJECT) })).toBeEnabled()
  })

  it("hazırsa üç karar da açıktır", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    expect(screen.getByRole("radio", { name: new RegExp(APPROVE) })).toBeEnabled()
    expect(screen.getByRole("radio", { name: new RegExp(REQUEST_CHANGES) })).toBeEnabled()
    expect(screen.getByRole("radio", { name: new RegExp(REJECT) })).toBeEnabled()
  })

  it("skor tam değilse approve kapalıdır", () => {
    renderPanel(
      makeCandidate("needs_review", [
        { key: "readiness_status", value: "ready_for_human_review" },
        { key: "readiness_score", value: 0.9 },
        { key: "blocking_reasons", value: [] },
      ])
    )

    expect(screen.getByRole("radio", { name: new RegExp(APPROVE) })).toBeDisabled()
  })

  it("terminal durumda hiçbir karar açılmaz", () => {
    renderPanel(makeCandidate("promoted", READY_FIELDS))

    expect(screen.getByRole("radio", { name: new RegExp(APPROVE) })).toBeDisabled()
    expect(screen.getByRole("radio", { name: new RegExp(REQUEST_CHANGES) })).toBeDisabled()
    expect(screen.getByRole("radio", { name: new RegExp(REJECT) })).toBeDisabled()
  })
})

describe("hazırlık özeti ve yayın sınırı", () => {
  it("readiness durum, puan ve engeller gösterilir", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    expect(screen.getByText("ready_for_human_review")).toBeInTheDocument()
    expect(screen.getByText("1.0000")).toBeInTheDocument()
  })

  it("hazırlık değerlendirmesi yoksa bilgilendirme gösterilir", () => {
    renderPanel(makeCandidate("needs_review"))

    expect(
      screen.getByText("Hazırlık değerlendirmesi henüz bulunmuyor.")
    ).toBeInTheDocument()
  })

  it("yayın sınırı uyarısı her zaman görünürdür", () => {
    renderPanel(makeCandidate("validating", VALIDATING_FIELDS))

    expect(
      screen.getByText(/hiçbir karar öğrenciye doğrudan yayın veya canlıya alma sağlamaz/)
    ).toBeInTheDocument()
  })

  it("engel listesi okunabilir biçimde gösterilir", () => {
    renderPanel(makeCandidate("needs_review", VALIDATING_FIELDS))

    expect(screen.getByText("quality_gate_pending")).toBeInTheDocument()
  })
})

describe("a11y", () => {
  it("durum duyuruları role=status ile verilir", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    const status = screen.getByText(/Uygun kararlar:/)
    expect(status).toHaveAttribute("role", "status")
  })

  it("panel bölümü başlıkla etiketlenir", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    const panel = screen.getByRole("region", { name: "İnceleme Kararı" })
    expect(panel).toBeInTheDocument()
  })

  it("etkileşimli hedefler en az 44px yüksekliğindedir", () => {
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    const proceed = screen.getByRole("button", { name: PROCEED })
    expect(proceed.className).toContain("min-h-11")
  })

  it("onay adımı açıldığında odak başlığa taşınır", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.click(screen.getByRole("button", { name: PROCEED }))

    const heading = screen.getByRole("heading", { name: "2. Kararı Onayla" })
    expect(heading).toHaveAttribute("tabindex", "-1")
    expect(heading).toHaveFocus()
  })

  it("onay adımı seçilen kararı ve gerekçeyi özet olarak gösterir", async () => {
    const user = userEvent.setup()
    renderPanel(makeCandidate("needs_review", READY_FIELDS))

    await user.click(screen.getByRole("radio", { name: new RegExp(REJECT) }))
    await user.type(screen.getByLabelText("Gerekçe"), "siklar yanlis")
    await user.click(screen.getByRole("button", { name: PROCEED }))

    const confirmSection = screen.getByRole("region", { name: "2. Kararı Onayla" })
    expect(within(confirmSection).getByText(REJECT)).toBeInTheDocument()
    expect(within(confirmSection).getByText("siklar yanlis")).toBeInTheDocument()
  })
})