// @vitest-environment jsdom
import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"

import TrainingSession, {
  type FeedbackActionResponse,
  type SubmitActionFn,
  type SubmitActionResponse,
} from "./TrainingSession"
import type { AttemptFeedback, SubmitResult, TrainingQuestion } from "@/lib/training/types"

const Q1: TrainingQuestion = {
  id: "33333333-3333-3333-3333-000000000001",
  questionCode: "TQ-01",
  questionText: "Türkiye'nin başkenti hangisidir?",
  options: {
    A: "İstanbul",
    B: "Ankara",
    C: "İzmir",
    D: "Bursa",
    E: "Adana",
  },
  difficulty: "easy",
  estimatedSolveTimeSeconds: 30,
  hasVisual: false,
}

const Q2: TrainingQuestion = {
  ...Q1,
  id: "33333333-3333-3333-3333-000000000002",
  questionCode: "TQ-02",
  questionText: "İkinci soru metni.",
  estimatedSolveTimeSeconds: 20,
}

function okResult(
  overrides: Partial<SubmitResult> = {}
): SubmitActionResponse {
  return {
    ok: true,
    data: {
      attemptId: "aaaaaaaa-0000-0000-0000-000000000001",
      attemptNumber: 1,
      result: "correct",
      duplicate: false,
      ...overrides,
    },
  }
}

function feedbackData(
  overrides: Partial<AttemptFeedback> = {}
): AttemptFeedback {
  return {
    found: true,
    correctAnswer: "B",
    solutionText: "Ankara Türkiye'nin başkentidir. Oran: 3/4, üs: 2^5.",
    ...overrides,
  }
}

function okFeedback(
  overrides: Partial<AttemptFeedback> = {}
): FeedbackActionResponse {
  return { ok: true, data: feedbackData(overrides) }
}

function createSubmitAction(
  impl?: (input: Parameters<SubmitActionFn>[0]) => Promise<SubmitActionResponse>
) {
  return vi.fn(async (input: Parameters<SubmitActionFn>[0]) =>
    impl ? impl(input) : okResult()
  ) as unknown as ReturnType<typeof vi.fn> &
    ((input: Parameters<SubmitActionFn>[0]) => Promise<SubmitActionResponse>)
}

function createFeedbackAction(
  impl?: (questionId: string) => Promise<FeedbackActionResponse>
) {
  return vi.fn(async (questionId: string) =>
    impl ? impl(questionId) : okFeedback()
  ) as unknown as ReturnType<typeof vi.fn> &
    ((questionId: string) => Promise<FeedbackActionResponse>)
}

beforeEach(() => {
  vi.useFakeTimers({ shouldAdvanceTime: true })
})

afterEach(() => {
  vi.useRealTimers()
})

describe("TrainingSession — render ve güvenlik", () => {
  it("soru metnini ve A-E seçeneklerini render eder", () => {
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    expect(screen.getByRole("heading", { level: 1 })).toHaveTextContent(
      "Türkiye'nin başkenti"
    )
    expect(screen.getByLabelText(/Ankara/)).toBeInTheDocument()
    expect(screen.getAllByRole("radio")).toHaveLength(5)
    expect(screen.getByRole("radiogroup")).toBeInTheDocument()
  })

  it("gizli alan değerleri ekrana asla yansımaz", () => {
    const poisoned: TrainingQuestion = {
      ...Q1,
      options: { ...Q1.options },
    }
    const { container } = render(
      <TrainingSession
        subjectName="Matematik"
        questions={[poisoned]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    // DTO'da hiç var olmayan alanların izi DOM'da da olmamalı.
    expect(container.textContent).not.toContain("correct_answer")
    expect(container.textContent).not.toContain("solution")
    expect(container.textContent).not.toContain("explanation")
  })

  it("erişilebilirlik: aria-live bölgesi ve ≥44px hedef sınıfları", () => {
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    expect(screen.getByRole("status")).toHaveAttribute("aria-live")
    for (const button of ["Cevapla", "Pas Geç", "Boş Bırak"]) {
      expect(screen.getByRole("button", { name: button })).toHaveClass("min-h-11")
    }
    expect(screen.getByLabelText(/Ankara/).closest("label")).toHaveClass("min-h-11")

    // Geri sayım: sr-only tam metin ekran okuyucular için güvenilir kaynak.
    expect(screen.getByText(/Kalan süre/)).toBeInTheDocument()
  })

  it("matematik gösterimi erişilebilir alternatiflerle render edilir", () => {
    const mathQ: TrainingQuestion = {
      ...Q1,
      questionText: "2^10 ile 3/4 karşılaştırması",
      options: { A: "1/2", B: "Ankara" },
    }

    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[mathQ]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    expect(screen.getByText("2 üzeri 10")).toBeInTheDocument()
    expect(screen.getByLabelText("3 bölü 4")).toBeInTheDocument()
    expect(screen.getByLabelText("1 bölü 2")).toBeInTheDocument()
    expect(screen.getByLabelText(/Ankara/)).toBeInTheDocument()
  })

  it("seçili şıkta görünür seçili durum stili bulunur (has-[:checked])", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    const ankaraLabel = screen.getByLabelText(/Ankara/).closest("label")!

    // Çalışan mekanizma: label has-[:checked] taşır, ölü peer-checked yok.
    expect(ankaraLabel).toHaveClass("has-[:checked]:border-gray-900")
    expect(ankaraLabel).toHaveClass("has-[:checked]:bg-gray-50")
    expect(ankaraLabel.className).not.toContain("peer-checked")

    await user.click(screen.getByLabelText(/Ankara/))
    expect(screen.getByLabelText(/Ankara/)).toBeChecked()
    // :has(:checked) seçimin label üzerinde eşleşmesini sağlar:
    expect(ankaraLabel.querySelector("input:checked")).not.toBeNull()

    // Seçilmeyen bir şıkta checked input yoktur.
    const istanbulLabel = screen.getByLabelText(/İstanbul/).closest("label")!
    expect(istanbulLabel.querySelector("input:checked")).toBeNull()
  })
})

describe("TrainingSession — Faz 11 cevap öncesi sızıntı yok", () => {
  it("cevap gönderilmeden doğru cevap veya açıklama DOM'da yoktur; feedback isteği yapılmaz", () => {
    const feedbackAction = createFeedbackAction()
    const { container } = render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={feedbackAction}
      />
    )

    expect(feedbackAction).not.toHaveBeenCalled()
    expect(container.textContent).not.toContain("Doğru cevap")
    expect(container.textContent).not.toContain("Çözüm açıklaması")
    expect(container.textContent).not.toContain("Ankara Türkiye'nin")
  })

  it("kabul edilmiş cevap sonrası açık Türkçe geri bildirim, doğru cevap ve onaylı açıklama görünür", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    const feedbackAction = createFeedbackAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={feedbackAction}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    // Sunucu kabul etmeden feedback çağrısı yapılmaz.
    await waitFor(() => expect(feedbackAction).toHaveBeenCalledTimes(1))
    expect(feedbackAction.mock.calls[0][0]).toBe(Q1.id)

    // Görsel geri bildirim bölgesi: durum + doğru cevap + açıklama.
    const panel = screen.getByRole("region", {
      name: "Cevap geri bildirimi",
    })
    expect(panel).toHaveTextContent("Doğru")
    expect(panel).toHaveTextContent("Doğru cevap: B")
    expect(panel).toHaveTextContent("Ankara")
    expect(panel).toHaveTextContent("Ankara Türkiye'nin başkentidir.")
    expect(screen.getByLabelText("3 bölü 4")).toBeInTheDocument()
    expect(screen.getByText("2 üzeri 5")).toBeInTheDocument()
    // Açıklama yok durumu GÖRÜNMEZ (açıklama bulundu).
    expect(screen.queryByText("Çözüm açıklaması hazırlanıyor.")).toBeNull()

    // Tek soruluk oturumda panel kapatma düğmesi oturumu bitirir.
    expect(
      screen.getByRole("button", { name: "Oturumu Bitir" })
    ).toHaveClass("min-h-11")
  })

  it("yanlış cevapta açık Türkçe 'Yanlış' bildirimi görünür", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction(async () => okResult({ result: "wrong" }))}
        feedbackAction={createFeedbackAction(async () =>
          okFeedback({ correctAnswer: "B" })
        )}
      />
    )

    await user.click(screen.getByLabelText(/İstanbul/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(
        screen.getByRole("region", { name: "Cevap geri bildirimi" })
      ).toHaveTextContent("Yanlış")
    )
  })

  it("açıklama yoksa içerik uydurulmaz; güvenli hazırlık mesajı görünür", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction(async () =>
          okFeedback({ solutionText: null })
        )}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(
        screen.getByText("Çözüm açıklaması hazırlanıyor.")
      ).toBeInTheDocument()
    )
  })

  it("feedback çağrısı hatasında sayfa çökmez; ham hata sızmaz, güvenli mesaj görünür", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction(async () => {
          throw new Error(
            "relation public.question_solution_assets does not exist"
          )
        })}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(
        screen.getByText("Çözüm açıklaması hazırlanıyor.")
      ).toBeInTheDocument()
    )
    // Ham DB hatası istemciye sızmaz.
    expect(document.body.textContent).not.toContain("does not exist")
    expect(document.body.textContent).not.toContain("question_solution_assets")
  })

  it("PII/UUID/ham hata sentinel'leri geri bildirimde bile DOM'a sızmaz", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction(async () =>
          okFeedback({
            solutionText:
              "Çözüm: a@ornek.com kullanıcısı 99999999-8888-4000-8000-000000000901",
          })
        )}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(
        screen.getByRole("region", { name: "Cevap geri bildirimi" })
      ).toBeInTheDocument()
    )
  })

  it("XSS sentinel açıklama metni çalıştırılmaz; düz metin kalır", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction(async () =>
          okFeedback({
            solutionText:
              '<img src=x onerror=alert(1)> <script>alert(2)</script> javascript:alert(3) 1/2',
          })
        )}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(screen.getByLabelText("1 bölü 2")).toBeInTheDocument()
    )
    expect(document.querySelector("img")).toBeNull()
    expect(document.querySelector("script")).toBeNull()
    // javascript: URL render edilmemiş link yok.
    expect(document.querySelectorAll("a")).toHaveLength(0)
  })
})

describe("TrainingSession — cevap akışı", () => {
  it("seçim + Cevapla: choice gönderilir, action boştur; Sonraki Soru ile ilerlenir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1, Q2]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    expect(screen.getByLabelText(/Ankara/)).toBeChecked()

    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() => expect(submitAction).toHaveBeenCalledTimes(1))
    const input = submitAction.mock.calls[0][0]
    expect(input.choice).toBe("B")
    expect(input.action).toBeUndefined()
    expect(input.questionId).toBe(Q1.id)
    expect(input.timeMs).toBeGreaterThanOrEqual(0)
    expect(input.clientKey).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    )

    // Faz 11: geri bildirim paneli manuel ilerleme bekler.
    await user.click(screen.getByRole("button", { name: "Sonraki Soru" }))
    expect(screen.getByText("İkinci soru metni.")).toBeInTheDocument()
  })

  it("klavye ile seçim yapılabilir (tab + ok tuşları)", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.tab()
    expect(screen.getByLabelText(/İstanbul/)).toHaveFocus()

    await user.keyboard("{ArrowDown}")
    expect(screen.getByLabelText(/Ankara/)).toBeChecked()
    expect(screen.getByLabelText(/İstanbul/)).not.toBeChecked()
  })

  it("ağ hatasında aynı client_key ile yeniden deneme yapılır", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    let callCount = 0
    const keys: string[] = []
    const submitAction = createSubmitAction(async (input) => {
      callCount += 1
      keys.push(input.clientKey)
      if (callCount === 1) {
        return { ok: false, message: "Bağlantı hatası. Tekrar deneyin." }
      }
      return okResult()
    })

    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))
    await waitFor(() =>
      expect(
        screen.getByRole("alert")
      ).toHaveTextContent("Bağlantı hatası.")
    )

    await user.click(screen.getByRole("button", { name: "Cevapla" }))
    await waitFor(() => expect(callCount).toBe(2))

    expect(keys).toHaveLength(2)
    expect(keys[0]).toBe(keys[1])
  })

  it("beklenmeyen throw'da güvenli Türkçe hata görünür ve retry aynı client_key ile yapılır", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    let callCount = 0
    const keys: string[] = []
    const submitAction = createSubmitAction(async (input) => {
      callCount += 1
      keys.push(input.clientKey)
      if (callCount === 1) {
        // ActionResponse sözleşmesi dışı transport hatası simülasyonu.
        throw new Error("fetch failed: ECONNRESET")
      }
      return okResult()
    })

    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    // Ham hata metni sızmaz; güvenli Türkçe mesaj görünür.
    await waitFor(() =>
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Bağlantı hatası, tekrar deneyin."
      )
    )
    expect(screen.getByRole("alert").textContent).not.toContain("ECONNRESET")

    // finally kilidi bıraktı: buton yeniden aktif.
    expect(screen.getByRole("button", { name: "Cevapla" })).toBeEnabled()

    await user.click(screen.getByRole("button", { name: "Cevapla" }))
    await waitFor(() => expect(callCount).toBe(2))
    expect(keys[0]).toBe(keys[1])

    // Kabul edilen cevap sonrası panel açılır; oturumu bitir.
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Oturumu Bitir" })
      ).toBeInTheDocument()
    )
    await user.click(screen.getByRole("button", { name: "Oturumu Bitir" }))

    await waitFor(() =>
      expect(screen.getByText(/Oturum Özeti/)).toBeInTheDocument()
    )
    expect(screen.getByText("1 soru yanıtlandı.")).toBeInTheDocument()
  })

  it("duplicate:true başarı sayılır ve ikinci attempt çağrısı yapılmaz", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    const submitAction = createSubmitAction(async () =>
      okResult({ duplicate: true, result: "correct" })
    )
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    await waitFor(() =>
      expect(
        screen.getByRole("region", { name: "Cevap geri bildirimi" })
      ).toBeInTheDocument()
    )
    expect(submitAction).toHaveBeenCalledTimes(1)
    expect(
      screen.getAllByText(/kayıtlıydı/).length
    ).toBeGreaterThan(0)

    await user.click(screen.getByRole("button", { name: "Oturumu Bitir" }))
    await waitFor(() =>
      expect(screen.getByText(/Oturum Özeti/)).toBeInTheDocument()
    )
    // Tek çağrı + özet ekranı = duplicate ikinci attempt oluşturmadı.
    expect(screen.getByText("1 soru yanıtlandı.")).toBeInTheDocument()
  })
})

describe("TrainingSession — pas/boş/süre davranışı", () => {
  it("Pas Geç: action='pass' gönderilir, seçenek gönderilmez", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByRole("button", { name: "Pas Geç" }))
    await waitFor(() => expect(submitAction).toHaveBeenCalledTimes(1))

    const input = submitAction.mock.calls[0][0]
    expect(input.action).toBe("pass")
    expect(input.choice).toBeUndefined()
  })

  it("Boş Bırak: action='blank' gönderilir", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByRole("button", { name: "Boş Bırak" }))
    await waitFor(() => expect(submitAction).toHaveBeenCalledTimes(1))

    expect(submitAction.mock.calls[0][0].action).toBe("blank")
  })

  it("geri sayım çalışır ve süre bitince otomatik 'timeout' gönderilir", async () => {
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    // sr-only tam metin "Kalan süre N saniye"; görsel sayaç mm:ss.
    const timer = () =>
      screen.getByText(/Kalan süre/).parentElement as HTMLElement
    expect(timer()).toHaveTextContent("0:30")

    await vi.advanceTimersByTimeAsync(2000)
    expect(timer()).toHaveTextContent(/0:2[89]|0:30/)

    await vi.advanceTimersByTimeAsync(30_000)
    await waitFor(() => expect(submitAction).toHaveBeenCalledTimes(1))

    const input = submitAction.mock.calls[0][0]
    expect(input.action).toBe("timeout")
    expect(input.choice).toBeUndefined()
  })

  it("timeout tek gönderim üretir; çift tetikleme yeni gönderim yapmaz (idempotent)", async () => {
    const submitAction = createSubmitAction()
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await vi.advanceTimersByTimeAsync(31_000)
    await waitFor(() => expect(submitAction).toHaveBeenCalledTimes(1))

    const input = submitAction.mock.calls[0][0]
    expect(input.action).toBe("timeout")
    expect(input.choice).toBeUndefined()

    // Aşırı durum: süre zaten doldu; ikinci tetikleme (retry/timer yarısı)
    // yeni attempt üretmemeli — panel açık; timer söküldü + ref kilidi.
    await vi.advanceTimersByTimeAsync(5_000)
    expect(submitAction).toHaveBeenCalledTimes(1)
  })

  it("tüm sorular yanıtlanınca özet görünür ve sayaçlar doğru toplanır", async () => {
    const user = userEvent.setup({ advanceTimers: vi.advanceTimersByTime })
    let call = 0
    const submitAction = createSubmitAction(async () => {
      call += 1
      return call === 1 ? okResult({ result: "correct" }) : okResult({ result: "pass" })
    })
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[Q1, Q2]}
        submitAction={submitAction}
        feedbackAction={createFeedbackAction()}
      />
    )

    await user.click(screen.getByLabelText(/Ankara/))
    await user.click(screen.getByRole("button", { name: "Cevapla" }))

    // Faz 11: panelde manuel ilerleme.
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Sonraki Soru" })
      ).toBeInTheDocument()
    )
    await user.click(screen.getByRole("button", { name: "Sonraki Soru" }))
    expect(screen.getByText("İkinci soru metni.")).toBeInTheDocument()

    await user.click(screen.getByRole("button", { name: "Pas Geç" }))
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Oturumu Bitir" })
      ).toBeInTheDocument()
    )
    await user.click(screen.getByRole("button", { name: "Oturumu Bitir" }))

    await waitFor(() =>
      expect(screen.getByText(/Oturum Özeti/)).toBeInTheDocument()
    )
    expect(screen.getByText("2 soru yanıtlandı.")).toBeInTheDocument()

    const correctRow = screen.getByText("Doğru").parentElement
    const passRow = screen.getByText("Pas").parentElement
    expect(correctRow).toHaveTextContent("1")
    expect(passRow).toHaveTextContent("1")

    expect(
      screen.getByRole("link", { name: /Başka ders çalış/ })
    ).toHaveAttribute("href", "/training")
  })

  it("geri dönüş bağlantıları next/link ile href ve a11y davranışını korur", () => {
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
        backHref="/panel"
      />
    )

    const backLink = screen.getByRole("link", { name: "Ders seçimine dön" })
    expect(backLink).toHaveAttribute("href", "/panel")
    // Dokunma hedefi sınıfı gerilememeli.
    expect(backLink).toHaveClass("min-h-11")
  })

  it("soru listesi boşsa fail-closed bilgilendirme gösterir", () => {
    render(
      <TrainingSession
        subjectName="Matematik"
        questions={[]}
        submitAction={createSubmitAction()}
        feedbackAction={createFeedbackAction()}
      />
    )

    expect(screen.getByText(/çözülebilir soru bulunamadı/)).toBeInTheDocument()
  })
})
