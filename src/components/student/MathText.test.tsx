/**
 * MathText testleri — erişilebilir matematik render.
 *
 * - "3/4" kesir görünümü + ekran okuyucu alternatifi "3 bölü 4"
 * - "2^10" üst simge + "2 üzeri 10"
 * - Düz metin değişmeden kalır
 * - HTML enjekte edilmez (React escaping)
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import MathText from "./MathText"

describe("MathText", () => {
  it("düz metni değiştirmeden render eder", () => {
    render(<MathText text="Bir sayı doğrusunda 5 nerede?" />)

    expect(
      screen.getByText("Bir sayı doğrusunda 5 nerede?")
    ).toBeInTheDocument()
  })

  it("kesri görsel ve erişilebilir alternatifle render eder", () => {
    render(<MathText text="Şekilde 3/4 kaçtır?" />)

    const fraction = screen.getByLabelText("3 bölü 4")

    expect(fraction).toBeInTheDocument()
    expect(fraction).toHaveTextContent("3")
    expect(fraction).toHaveTextContent("4")
  })

  it("üsü üst simge ve erişilebilir alternatifle render eder", () => {
    render(<MathText text="2^10 kaçtır?" />)

    expect(screen.getByText("2 üzeri 10")).toBeInTheDocument()
    expect(screen.getByText("10", { selector: "sup" })).toBeInTheDocument()
  })

  it("kesir ve üs aynı metinde birlikte çözülür", () => {
    render(<MathText text="2^3 ve 1/2 karşılaştırması" />)

    expect(screen.getByText("2 üzeri 3")).toBeInTheDocument()
    expect(screen.getByLabelText("1 bölü 2")).toBeInTheDocument()
  })

  it("HTML içerik enjekte etmez", () => {
    const { container } = render(
      <MathText text='<img src=x onerror=alert(1)> 1/2' />
    )

    expect(container.querySelector("img")).toBeNull()
    expect(screen.getByLabelText("1 bölü 2")).toBeInTheDocument()
  })
})
