/**
 * AvatarPicker testleri (Faz 10).
 *
 * - Yalnız sunucudan gelen katalog seçenekleri listelenir.
 * - Seçim radyo düğmeleriyle klavye erişilebilir; seçili durum metinle
 *   de anlatılır ("(Seçili)").
 * - Başarı/hata güvenli Türkçe mesaj aria-live bölgesinde.
 * - Seçim yoksa Kaydet pasif.
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import AvatarPicker from "./AvatarPicker"
import type { AvatarOption } from "@/lib/profile/types"

const OPTIONS: AvatarOption[] = [
  {
    code: "character_1",
    name: "Karakter 1",
    description: "Başlangıç karakteri.",
  },
  {
    code: "character_2",
    name: "Karakter 2",
    description: null,
  },
]

describe("AvatarPicker", () => {
  it("katalog seceneklerini radyo düğmeleriyle listeler", () => {
    render(
      <AvatarPicker
        options={OPTIONS}
        currentCode={null}
        action={vi.fn()}
      />
    )

    expect(screen.getByRole("radio", { name: /Karakter 1/ })).toBeInTheDocument()
    expect(screen.getByRole("radio", { name: /Karakter 2/ })).toBeInTheDocument()
  })

  it("secim yokken buton pasif; secim yapilinca aktiflesir", () => {
    render(
      <AvatarPicker
        options={OPTIONS}
        currentCode={null}
        action={vi.fn()}
      />
    )

    const submit = screen.getByRole("button", { name: "Bu karakteri seç" })
    expect(submit).toBeDisabled()

    fireEvent.click(screen.getByRole("radio", { name: /Karakter 1/ }))
    expect(submit).not.toBeDisabled()
  })

  it("mevcut secim isaretli gelir ve '(Seçili)' metniyle anlatılır", () => {
    render(
      <AvatarPicker
        options={OPTIONS}
        currentCode="character_1"
        action={vi.fn()}
      />
    )

    expect(
      screen.getByRole("radio", { name: /Karakter 1/ })
    ).toBeChecked()
    expect(screen.getByText("(Seçili)")).toBeInTheDocument()
  })

  it("basarili secimde Turkce onay mesaji ve karakternin adi görünür", async () => {
    const action = vi.fn().mockResolvedValue({
      ok: true,
      data: { code: "character_2", name: "Karakter 2" },
    })

    render(
      <AvatarPicker options={OPTIONS} currentCode={null} action={action} />
    )

    fireEvent.click(screen.getByRole("radio", { name: /Karakter 2/ }))
    fireEvent.click(screen.getByRole("button", { name: "Bu karakteri seç" }))

    await waitFor(() => {
      expect(
        screen.getByText("Karakter 2 artık karakterin.")
      ).toBeInTheDocument()
    })
    expect(action).toHaveBeenCalledWith("character_2")
  })

  it("sunucu hatasinda ham mesaj yerine guvenli mesaj görünür", async () => {
    const action = vi.fn().mockResolvedValue({
      ok: false,
      message: "Bu avatar şu anda seçilemiyor. Lütfen listeden bir avatar seç.",
    })

    render(
      <AvatarPicker options={OPTIONS} currentCode={null} action={action} />
    )

    fireEvent.click(screen.getByRole("radio", { name: /Karakter 1/ }))
    fireEvent.click(screen.getByRole("button", { name: "Bu karakteri seç" }))

    await waitFor(() => {
      expect(
        screen.getByText(/Bu avatar şu anda seçilemiyor/)
      ).toBeInTheDocument()
    })
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

    render(
      <AvatarPicker options={OPTIONS} currentCode={null} action={action} />
    )

    fireEvent.click(screen.getByRole("radio", { name: /Karakter 1/ }))
    fireEvent.click(screen.getByRole("button", { name: "Bu karakteri seç" }))

    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: "Bu karakteri seç" })
      ).toBeDisabled()
    })

    resolveAction({ ok: true, data: { code: "character_1", name: "Karakter 1" } })

    await waitFor(() => {
      expect(
        screen.getByRole("button", { name: "Bu karakteri seç" })
      ).not.toBeDisabled()
    })
    expect(action).toHaveBeenCalledTimes(1)
  })
})
