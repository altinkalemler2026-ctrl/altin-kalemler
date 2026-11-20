/**
 * MatchmakingQueue bileseni testleri (Faz 7).
 *
 * - Sayfa yuklenirken 084 ile kuyruk durumu geri yuklenir.
 * - Beklerken polling join DEGIL get_own_matchmaking_status ile yapilir
 *   (rate-limit tuketmez; join yalnizca acik katilimda bir kez cagrilir).
 * - matched durumunda yarisma bilgisi gosterilir ve oturuma gidilir.
 * - Kuyruk suresi dolunca (not_queued) zaman asimi durumu gosterilir.
 * - Duplicate tiklama ikinci join gondermez.
 * - Error durumunda tekrar denenebilir.
 */

import { cleanup, render, screen, act } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

const pushMock = vi.fn()

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
}))

vi.mock("@/app/(student)/competition/actions", () => ({
  joinMatchmakingQueueAction: vi.fn(),
  leaveMatchmakingQueueAction: vi.fn(),
  getOwnMatchmakingStatusAction: vi.fn(),
}))

import {
  joinMatchmakingQueueAction,
  leaveMatchmakingQueueAction,
  getOwnMatchmakingStatusAction,
} from "@/app/(student)/competition/actions"
import { COMPETITION_ERROR_MESSAGES } from "@/lib/competition/errors"
import type { SubjectWeeklyQuotaStatus } from "@/lib/competition/types"

import MatchmakingQueue from "./MatchmakingQueue"

const mockedJoin = vi.mocked(joinMatchmakingQueueAction)
const mockedLeave = vi.mocked(leaveMatchmakingQueueAction)
const mockedStatus = vi.mocked(getOwnMatchmakingStatusAction)

const SUBJECT_ID = "11111111-1111-1111-1111-111111111111"

function renderQueue() {
  return render(
    <MatchmakingQueue subjectId={SUBJECT_ID} subjectName="Matematik" />
  )
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.useFakeTimers({ shouldAdvanceTime: true })
  mockedStatus.mockResolvedValue({
    ok: true,
    data: { status: "not_queued", competitionId: null, competitionCode: null },
  })
})

afterEach(() => {
  vi.useRealTimers()
  cleanup()
})

describe("MatchmakingQueue — bos durum (084 restore)", () => {
  it("084 not_queued dondugunde siraya katil butonu gorunur", async () => {
    renderQueue()

    expect(
      await screen.findByRole("button", { name: /sıraya katıl/i })
    ).toBeDefined()
    expect(mockedStatus).toHaveBeenCalledWith(SUBJECT_ID)
  })

  it("084 waiting dondugunde kuyruk bekleyisi geri yuklenir", async () => {
    mockedStatus.mockResolvedValue({
      ok: true,
      data: { status: "waiting", competitionId: null, competitionCode: null },
    })
    renderQueue()

    expect(await screen.findByText(/eşleşme aranıyor/i)).toBeDefined()
    expect(
      screen.getByRole("button", { name: /kuyruktan çık/i })
    ).toBeDefined()
    // Restore restore beklerken join cagrilmamalidir.
    expect(mockedJoin).not.toHaveBeenCalled()
  })

  it("084 matched dondugunde eslesme ve yarismaya basla geri yuklenir", async () => {
    mockedStatus.mockResolvedValue({
      ok: true,
      data: {
        status: "matched",
        competitionId: "33333333-3333-3333-3333-333333333333",
        competitionCode: "F5-RESTORED",
      },
    })
    renderQueue()

    expect(await screen.findByText(/eşleşme bulundu/i)).toBeDefined()
    expect(screen.getByText(/F5-RESTORED/)).toBeDefined()
    expect(mockedJoin).not.toHaveBeenCalled()
  })
})

describe("MatchmakingQueue — joining", () => {
  it("pending sirasinda siraya ekleniyor mesaji gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockReturnValue(new Promise(() => {}))
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(screen.getByText(/sıraya ekleniyorsun/i)).toBeDefined()
    expect(screen.queryByRole("button", { name: /sıraya katıl/i })).toBeNull()
  })
})

describe("MatchmakingQueue — queued", () => {
  it("kuyrukta beklerken mesaj gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(await screen.findByText(/eşleşme aranıyor/i)).toBeDefined()
    expect(
      screen.getByRole("button", { name: /kuyruktan çık/i })
    ).toBeDefined()
  })

  it("beklerken polling 084 ile yapilir; join tekrar cagrilmez", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    // Restore: kuyruk bos (idle). Join sonrasi poll waiting bekler.
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    expect(await screen.findByText(/eşleşme aranıyor/i)).toBeDefined()

    // Poll waiting beklesin (not_queued zaman asimi tetikler).
    mockedStatus.mockResolvedValue({
      ok: true,
      data: { status: "waiting", competitionId: null, competitionCode: null },
    })

    const joinCallsAfterJoin = mockedJoin.mock.calls.length
    const statusCallsBeforePoll = mockedStatus.mock.calls.length

    await act(async () => {
      await vi.advanceTimersByTimeAsync(9_000)
    })

    // Poll 3x status cagirmis olmali; join artmamali.
    expect(
      mockedStatus.mock.calls.length - statusCallsBeforePoll
    ).toBeGreaterThanOrEqual(3)
    expect(mockedJoin.mock.calls.length).toBe(joinCallsAfterJoin)
  })

  it("poll matched buldugunda eslesme durumu gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    await screen.findByText(/eşleşme aranıyor/i)

    // Poll artık matched donsun.
    mockedStatus.mockResolvedValue({
      ok: true,
      data: {
        status: "matched",
        competitionId: "33333333-3333-3333-3333-333333333333",
        competitionCode: "F5-POLLED",
      },
    })

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3_000)
    })

    expect(await screen.findByText(/eşleşme bulundu/i)).toBeDefined()
    expect(screen.getByText(/F5-POLLED/)).toBeDefined()
  })

  it("kuyruktan cikma calisir ve idle doner", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    mockedLeave.mockResolvedValue({ ok: true, data: { cancelled: 1 } })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    await user.click(await screen.findByRole("button", { name: /kuyruktan çık/i }))

    expect(
      await screen.findByRole("button", { name: /sıraya katıl/i })
    ).toBeDefined()
    expect(mockedLeave).toHaveBeenCalledTimes(1)
  })
})

describe("MatchmakingQueue — zaman asimi", () => {
  it("poll not_queued dondugunde zaman asimi durumu gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    await screen.findByText(/eşleşme aranıyor/i)

    // Kuyruk suresi doldu -> 084 not_queued doner.
    mockedStatus.mockResolvedValue({
      ok: true,
      data: { status: "not_queued", competitionId: null, competitionCode: null },
    })

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3_000)
    })

    expect(await screen.findByText(/zaman aşımına uğradı/i)).toBeDefined()
    expect(
      await screen.findByRole("button", { name: /sıraya katıl/i })
    ).toBeDefined()
  })
})

describe("MatchmakingQueue — error", () => {
  it("hata durumunda mesaj gosterilir ve tekrar dene butonu cikar", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message: "Seçili ders bulunamadı veya şu anda pasif durumda.",
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(await screen.findByRole("alert")).toBeDefined()
    expect(screen.getByText(/bulunamadı/i)).toBeDefined()
    expect(
      screen.getByRole("button", { name: /tekrar dene/i })
    ).toBeDefined()
  })

  it("tekrar dene ile yeni join denemesi yapilabilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message: "Genel hata.",
    })
    renderQueue()
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    await user.click(await screen.findByRole("button", { name: /tekrar dene/i }))

    expect(mockedJoin.mock.calls.length).toBeGreaterThanOrEqual(2)
  })
})

// ------------------------------------------------------------
// 163: Haftalik kota kilidi (UX kilidi + eszamanli KOTA_163)
// ------------------------------------------------------------

const QUOTA_MESSAGE =
  "Haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte tekrar yarışmalara katılabilirsiniz."

describe("MatchmakingQueue — 163 haftalik kota", () => {
  it("quotaBlocked true: buton pasif + tam urun mesaji; tiklama join gondermez", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <MatchmakingQueue
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        quotaBlocked
      />
    )
    const button = await screen.findByRole("button", { name: /sıraya katıl/i })

    expect(button.hasAttribute("disabled")).toBe(true)
    expect(screen.getByText(QUOTA_MESSAGE)).toBeDefined()

    await user.click(button)
    expect(mockedJoin).not.toHaveBeenCalled()
  })

  it("eszamanli tuketim: join KOTA_163 mesaji donerse buton kilitlenir, tekrar-dene yok", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({ ok: false, message: QUOTA_MESSAGE })
    render(
      <MatchmakingQueue subjectId={SUBJECT_ID} subjectName="Matematik" />
    )
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    // Sunucu kota mesaji aynen gosterilir (errors.ts 42-19 sozlesmesi).
    expect(await screen.findByText(QUOTA_MESSAGE)).toBeDefined()
    expect(screen.queryByRole("button", { name: /tekrar dene/i })).toBeNull()
    const button = screen.getByRole("button", { name: /sıraya katıl/i })
    expect(button.hasAttribute("disabled")).toBe(true)

    // Kilit sonrasi tiklama ikinci join gondermez.
    await user.click(button)
    expect(mockedJoin).toHaveBeenCalledTimes(1)
  })

  it("teknik hata kota mesaji DEGIL: tekrar dene korunur (hata ayrimi)", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message:
        "Beklenmeyen bir hata olustu. Lutfen tekrar deneyin; sorun surerse destek ekibine bildirin.",
    })
    render(
      <MatchmakingQueue subjectId={SUBJECT_ID} subjectName="Matematik" />
    )
    await screen.findByRole("button", { name: /sıraya katıl/i })

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(await screen.findByRole("button", { name: /tekrar dene/i })).toBeDefined()
    expect(
      screen.queryByText(/haftalık yarışma hakkınız tükendi/i)
    ).toBeNull()
  })

  it("quotaBlocked false (varsayilan): mevcut davranis bozulmaz, buton aktif", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: true,
      data: {
        status: "waiting",
        queueId: "22222222-2222-2222-2222-222222222222",
        gradeLevel: 10,
        subjectId: SUBJECT_ID,
      },
    })
    renderQueue()
    const button = await screen.findByRole("button", { name: /sıraya katıl/i })

    expect(button.hasAttribute("disabled")).toBe(false)
    await user.click(button)
    expect(mockedJoin).toHaveBeenCalledWith(SUBJECT_ID)
  })
})

// ------------------------------------------------------------
// 165: Ders bazli kota (AK-QUOTA-SUBJECT-01) — kart basi sayilar,
// ders-ozel kilit ve KOTA_165 eszamanli kilitleme
// ------------------------------------------------------------

const SUBJECT_QUOTA_MESSAGE =
  "Bu ders için haftalık yarışma hakkınız tükendi. Yeni haftanın başlamasıyla birlikte bu derste tekrar yarışabilirsiniz."

function subjectQuota(
  overrides: Partial<SubjectWeeklyQuotaStatus> = {}
): SubjectWeeklyQuotaStatus {
  return {
    subjectId: SUBJECT_ID,
    competitionsUsed: 0,
    competitionsLimit: 40,
    newQuestionsUsed: 0,
    newQuestionsLimit: 200,
    ...overrides,
  }
}

describe("MatchmakingQueue — 165 ders bazli kota", () => {
  it("quota verisi kartta O DERSE ait sayilari gosterir", async () => {
    render(
      <MatchmakingQueue
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        quota={subjectQuota({ competitionsUsed: 7, newQuestionsUsed: 35 })}
      />
    )
    expect(
      await screen.findByText(/Bu derste bu hafta: Yarışma 7\/40/)
    ).toBeDefined()
    expect(screen.getByText(/Yeni soru: 35\/200/)).toBeDefined()
    expect(screen.getByText(/33 yarışma hakkın kaldı/)).toBeDefined()
  })

  it("quota null iken kart HICBIR sayi uydurmaz (163 davransi aynen)", async () => {
    const { container } = render(
      <MatchmakingQueue subjectId={SUBJECT_ID} subjectName="Matematik" />
    )
    await screen.findByRole("button", { name: /sıraya katıl/i })
    expect(container.textContent).not.toMatch(/Bu derste bu hafta/)
  })

  it("ders bazli kilit: YALNIZ bu kart kapanir + ders-ozel mesaj gosterilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <MatchmakingQueue
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        quotaBlocked
        quota={subjectQuota({ competitionsUsed: 40, newQuestionsUsed: 200 })}
      />
    )
    const button = await screen.findByRole("button", { name: /sıraya katıl/i })
    expect(button.hasAttribute("disabled")).toBe(true)
    // Ders-ozel tam urun mesaji (kuresel 163 mesajl karistirilmaz):
    expect(screen.getByText(SUBJECT_QUOTA_MESSAGE)).toBeDefined()
    await user.click(button)
    expect(mockedJoin).not.toHaveBeenCalled()
  })

  it("eszamanli KOTA_165: join ders mesajı donerse kart kilitlenir, tekrar-dene yok", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({ ok: false, message: SUBJECT_QUOTA_MESSAGE })
    render(
      <MatchmakingQueue
        subjectId={SUBJECT_ID}
        subjectName="Matematik"
        quota={subjectQuota()}
      />
    )
    await screen.findByRole("button", { name: /sıraya katıl/i })
    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(await screen.findByText(SUBJECT_QUOTA_MESSAGE)).toBeDefined()
    expect(screen.queryByRole("button", { name: /tekrar dene/i })).toBeNull()
    expect(
      screen.getByRole("button", { name: /sıraya katıl/i }).hasAttribute("disabled")
    ).toBe(true)

    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))
    expect(mockedJoin).toHaveBeenCalledTimes(1)
  })

  it("eszamanli KOTA_165 soru hakki mesaji da karti kilitler", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    mockedJoin.mockResolvedValue({
      ok: false,
      message: COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject,
    })
    render(
      <MatchmakingQueue
        subjectId={SUBJECT_ID}
        subjectName="Fizik"
        quota={subjectQuota({ newQuestionsUsed: 198 })}
      />
    )
    await screen.findByRole("button", { name: /sıraya katıl/i })
    await user.click(screen.getByRole("button", { name: /sıraya katıl/i }))

    expect(
      await screen.findByText(
        COMPETITION_ERROR_MESSAGES.weeklyQuestionQuotaSubject
      )
    ).toBeDefined()
    expect(
      screen.getByRole("button", { name: /sıraya katıl/i }).hasAttribute("disabled")
    ).toBe(true)
  })
})
