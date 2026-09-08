/**
 * NicknameForm testleri (Faz 10).
 *
 * - Yalnız nickname gönderilir; grade/user_id alanı YOKTUR.
 * - Kaydetme sırasında buton kilitlenir (çift gönderim engellenir).
 * - Başarı/hata mesajları aria-live bölgesinde görünür.
 * - Başarısız işlem mevcut takma adı bozmaz.
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import NicknameForm from "./NicknameForm"

function setup(overrides: {
  action?: ReturnType<typeof vi.fn>
  currentNickname?: string
} = {}) {
  const action =
    overrides.action ??
    vi.fn().mockResolvedValue({
      ok: true,
      data: { nickname: overrides.currentNickname ?? "MatematikUstasi" },
    })

  render(
    <NicknameForm
      currentNickname={overrides.currentNickname ?? "MatematikUstasi"}
      action={action as never}
    />
  )

  return { action }
}

describe("NicknameForm", () => {
  it("takma ad inputu ve Kaydet butonu gorunur", () => {
    setup()

    expect(screen.getByLabelText("Takma ad")).toHaveValue("MatematikUstasi")
    expect(
      screen.getByRole("button", { name: "Kaydet" })
    ).toBeInTheDocument()
  })

  it("grade/user_id hidden inputu DAHIL hicbir ek alan göndermez", () => {
    setup()

    expect(
      document.body.querySelector('input[name="grade_level"]')
    ).toBeNull()
    expect(document.body.querySelector('input[name="user_id"]')).toBeNull()
    expect(document.body.querySelector('input[name="id"]')).toBeNull()
  })

  it("basarili guncellemede Turkce onay mesaji ve aria-live görünür", async () => {
    const { action } = setup()
    action.mockResolvedValue({
      ok: true,
      data: { nickname: "YeniAd" },
    })

    fireEvent.change(screen.getByLabelText("Takma ad"), {
      target: { value: "YeniAd" },
    })
    fireEvent.click(screen.getByRole("button", { name: "Kaydet" }))

    await waitFor(() => {
      expect(screen.getByText("Takma adın güncellendi.")).toBeInTheDocument()
    })
    expect(action).toHaveBeenCalledWith("YeniAd")
  })

  it("hata durumunda guvenli mesaj gosterilir ve nickname korunur", async () => {
    const { action } = setup()
    action.mockResolvedValue({
      ok: false,
      message:
        "Bu takma ad başka bir öğrenci tarafından kullanılıyor. Lütfen farklı bir takma ad dene.",
    })

    fireEvent.change(screen.getByLabelText("Takma ad"), {
      target: { value: "AlınanAd" },
    })
    fireEvent.click(screen.getByRole("button", { name: "Kaydet" }))

    await waitFor(() => {
      expect(
        screen.getByText(/başka bir öğrenci tarafından kullanılıyor/)
      ).toBeInTheDocument()
    })
    expect(screen.getByLabelText("Takma ad")).toHaveValue("AlınanAd")
  })

  it("gönderim sirasinda buton kilitlenir (çift gönderim engellenir)", async () => {
    let resolveAction: (value: unknown) => void = () => {}
    const action = vi
      .fn()
      .mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveAction = resolve
          })
      )

    setup({ action })

    fireEvent.click(screen.getByRole("button", { name: "Kaydet" }))

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Kaydet" })).toBeDisabled()
    })

    resolveAction({ ok: true, data: { nickname: "MatematikUstasi" } })

    await waitFor(() => {
      expect(screen.getByRole("button", { name: "Kaydet" })).not.toBeDisabled()
    })
    expect(action).toHaveBeenCalledTimes(1)
  })

  it("sinif notu gorunur: sınıf değiştirilemez", () => {
    setup()

    expect(screen.getByText(/Sınıfın değiştirilemez/)).toBeInTheDocument()
  })
})
