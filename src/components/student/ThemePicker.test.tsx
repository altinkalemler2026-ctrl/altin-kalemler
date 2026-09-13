/**
 * ThemePicker testleri (Faz 12).
 *
 * - Iki onayli tema radyo dugmeleriyle listelenir (klavye erisilebilir).
 * - Secili durum metinle de anlatilir ("(Seçili)").
 * - Secim localStorage'e yazilir ve temali yuzeyler aninda guncellenir.
 * - Harcanabilir yildiz/sekme gibi sahte UI yoktur.
 */

import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import ThemePicker from "./ThemePicker"
import { THEME_STORAGE_KEY } from "@/lib/ui/theme"
import { ThemeProvider, ThemeSurface } from "@/lib/ui/theme-context"

describe("ThemePicker", () => {
  it("iki onayli tema radyo dugmeleriyle listelenir; varsayilan Altin Arena", () => {
    render(<ThemePicker />)

    expect(
      screen.getByRole("radio", { name: /Altın Arena/ })
    ).toBeChecked()
    expect(
      screen.getByRole("radio", { name: /Renkli Atölye/ })
    ).toBeInTheDocument()
    expect(screen.getAllByText("(Seçili)")).toHaveLength(1)
  })

  it("secim localStorage'e yazilir ve temali yuzeyleri gunceller", () => {
    window.localStorage.removeItem(THEME_STORAGE_KEY)

    render(
      <ThemeProvider>
        <ThemeSurface>
          <ThemePicker />
        </ThemeSurface>
      </ThemeProvider>
    )

    const surface = document.querySelector<HTMLElement>("[data-theme-surface]")
    expect(surface).not.toBeNull()
    expect(surface?.getAttribute("data-theme")).toBe("arena")

    fireEvent.click(
      screen.getByRole("radio", { name: /Renkli Atölye/ })
    )

    expect(surface?.getAttribute("data-theme")).toBe("atolye")
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe("atolye")
    expect(
      screen.getByRole("radio", { name: /Renkli Atölye/ })
    ).toBeChecked()
    expect(screen.getAllByText("(Seçili)")).toHaveLength(1)
  })

  it("harcanabilir sayac gostermez; yildiz/mağaza benzeri sahte UI yoktur", () => {
    render(<ThemePicker />)

    expect(screen.queryByText(/yıldız/i)).not.toBeInTheDocument()
    expect(screen.queryByText(/mağaza/i)).not.toBeInTheDocument()
  })
})