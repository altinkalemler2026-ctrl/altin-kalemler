/**
 * Button testleri — varyantlar, boyutlar, loading durumu.
 */

import { render, screen, fireEvent } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import { Button } from "./Button"

describe("Button", () => {
  it("varsayilan primary varyant ile render edilir", () => {
    render(<Button>Kaydet</Button>)

    const button = screen.getByRole("button", { name: "Kaydet" })

    expect(button).toHaveClass("bg-navy-800")
    expect(button).toHaveClass("text-white")
  })

  it("tüm varyantlar doğru sınıflarla render edilir", () => {
    const cases: Array<[string, string]> = [
      ["secondary", "bg-teal-700"],
      ["outline", "border-border-strong"],
      ["ghost", "text-ink"],
      ["danger", "bg-danger-700"],
    ]

    for (const [variant, cls] of cases) {
      const { unmount } = render(<Button variant={variant as never}>x</Button>)

      expect(screen.getByRole("button")).toHaveClass(cls)

      unmount()
    }
  })

  it("44px dokunma hedefi sağlanır", () => {
    render(<Button>Tıkla</Button>)

    expect(screen.getByRole("button")).toHaveClass("min-h-11")
  })

  it("loading durumunda aria-busy set edilir ve buton kilitlenir", () => {
    const onClick = vi.fn()

    render(
      <Button loading onClick={onClick}>
        Gönder
      </Button>
    )

    const button = screen.getByRole("button", { name: "Gönder" })

    expect(button).toHaveAttribute("aria-busy", "true")
    expect(button).toBeDisabled()

    fireEvent.click(button)

    expect(onClick).not.toHaveBeenCalled()
  })

  it("tıklama handler çalışır", () => {
    const onClick = vi.fn()

    render(<Button onClick={onClick}>Tıkla</Button>)

    fireEvent.click(screen.getByRole("button"))

    expect(onClick).toHaveBeenCalledTimes(1)
  })
})
