/**
 * Card / Input / Alert / Badge / Progress / EmptyState / Skeleton testleri —
 * her bileşenin örnek durumları.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import { Alert } from "./Alert"
import { Badge } from "./Badge"
import { Card } from "./Card"
import { EmptyState } from "./EmptyState"
import { Input } from "./Input"
import { Progress } from "./Progress"
import { Skeleton } from "./Skeleton"

describe("Card", () => {
  it("varsayilan padding ile render edilir", () => {
    render(<Card data-testid="card">İçerik</Card>)

    const card = screen.getByTestId("card")

    expect(card).toHaveClass("p-6")
    expect(card).toHaveClass("bg-surface")
    expect(card).toHaveClass("shadow-card")
  })

  it("padding=none stilleri kaldırır", () => {
    render(<Card padding="none" data-testid="card" />)

    expect(screen.getByTestId("card")).not.toHaveClass("p-6")
  })
})

describe("Input", () => {
  it("label input ile ilişkilidir", () => {
    render(<Input label="E-posta" />)

    const input = screen.getByLabelText("E-posta")

    expect(input).toBeInTheDocument()
  })

  it("hata durumunda aria-invalid ve role=alert mesajı gösterir", () => {
    render(<Input label="E-posta" error="Geçerli bir e-posta girin." />)

    const input = screen.getByLabelText("E-posta")

    expect(input).toHaveAttribute("aria-invalid", "true")
    expect(input).toHaveAttribute("aria-describedby")

    expect(screen.getByRole("alert")).toHaveTextContent(
      "Geçerli bir e-posta girin."
    )
  })

  it("hint metni aria-describedby ile bağlanır", () => {
    render(<Input label="Şifre" hint="En az 8 karakter" />)

    const input = screen.getByLabelText("Şifre")
    const describedBy = input.getAttribute("aria-describedby")

    expect(describedBy).not.toBeNull()
    expect(document.getElementById(describedBy as string)).toHaveTextContent(
      "En az 8 karakter"
    )
  })
})

describe("Alert", () => {
  it("tüm varyantlar role=alert ile render edilir", () => {
    const cases: Array<[string, string]> = [
      ["info", "text-navy-900"],
      ["success", "bg-success-100"],
      ["warning", "text-warning-900"],
      ["danger", "text-danger-700"],
    ]

    for (const [variant, cls] of cases) {
      const { unmount } = render(
        <Alert variant={variant as never} role="alert">
          mesaj
        </Alert>
      )

      expect(screen.getByRole("alert")).toHaveClass(cls)

      unmount()
    }
  })

  it("varsayilan baslik varyanta gore belirlenir", () => {
    render(<Alert variant="success">Tamam</Alert>)

    expect(screen.getByText("Başarılı")).toBeInTheDocument()
  })
})

describe("Badge", () => {
  it("varyantlar doğru sınıflarla render edilir", () => {
    const cases: Array<[string, string]> = [
      ["neutral", "text-ink-muted"],
      ["navy", "text-navy-900"],
      ["gold", "bg-gold-100"],
      ["teal", "text-teal-700"],
    ]

    for (const [variant, cls] of cases) {
      const { unmount } = render(<Badge variant={variant as never}>x</Badge>)

      expect(screen.getByText("x")).toHaveClass(cls)

      unmount()
    }
  })
})

describe("Progress", () => {
  it("progressbar rolleri ve değerleri doğru set edilir", () => {
    render(<Progress label="İlerleme" value={40} max={80} />)

    const bar = screen.getByRole("progressbar")

    expect(bar).toHaveAttribute("aria-valuemin", "0")
    expect(bar).toHaveAttribute("aria-valuemax", "80")
    expect(bar).toHaveAttribute("aria-valuenow", "40")
    expect(bar).toHaveAttribute("aria-label", "İlerleme")
  })

  it("değer sınır dışına çıkmaz", () => {
    render(<Progress label="İlerleme" value={999} />)

    expect(screen.getByRole("progressbar")).toHaveAttribute(
      "aria-valuenow",
      "100"
    )
  })
})

describe("EmptyState", () => {
  it("baslik, aciklama ve aksiyon render edilir", () => {
    render(
      <EmptyState
        icon={<span aria-hidden="true">—</span>}
        title="Sonuç bulunamadı"
        description="Filtreleri değiştirip tekrar deneyin."
        action={<button type="button">Sıfırla</button>}
      />
    )

    expect(screen.getByText("Sonuç bulunamadı")).toBeInTheDocument()
    expect(screen.getByText(/Filtreleri değiştir/)).toBeInTheDocument()
    expect(
      screen.getByRole("button", { name: "Sıfırla" })
    ).toBeInTheDocument()
  })

  it("icon ve aksiyon olmadan da çalışır", () => {
    render(<EmptyState title="Boş" />)

    expect(screen.getByText("Boş")).toBeInTheDocument()
  })
})

describe("Skeleton", () => {
  it("satir sayisi kadar iskelet render edilir ve aria-hidden olur", () => {
    const { container } = render(<Skeleton lines={3} />)

    expect(container.firstElementChild).toHaveAttribute("aria-hidden", "true")
    expect(container.firstElementChild?.children.length).toBe(3)
  })
})
