/**
 * MathText testleri — erişilebilir matematik render.
 *
 * - "3/4" kesir görünümü + ekran okuyucu alternatifi "3 bölü 4"
 * - "2^10" üst simge + "2 üzeri 10"
 * - Düz metin değişmeden kalır
 * - HTML enjekte edilmez (React escaping)
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

import MathText, { MathTextErrorBoundary } from "./MathText"

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

describe("MathText — Faz 11 güvenlik ve dayanıklılık", () => {
  it("script/event-handler/javascript: sentinel'leri çalıştırmaz; düz metin kalır", () => {
    const { container } = render(
      <MathText text='<script>alert(1)</script> javascript:alert(2) <a href="javascript:alert(3)">tıkla</a> 3/4' />
    )

    expect(container.querySelector("script")).toBeNull()
    expect(container.querySelector("a")).toBeNull()
    expect(screen.getByLabelText("3 bölü 4")).toBeInTheDocument()
    // Metin çalıştırılmaz; kaçırılmış HTML parçaları düz metin olarak görünür.
    expect(screen.getByText(/javascript:alert\(2\)/)).toBeInTheDocument()
  })

  it("long formülde kırılma sınıflarını taşır (mobil yatay taşma önlemi)", () => {
    const { container } = render(
      <MathText text="123456789012345678901234567890/999999999999999999999999999999" />
    )

    const wrapper = container.firstElementChild as HTMLElement
    expect(wrapper.className).toContain("break-words")
    expect(wrapper.className).toContain("min-w-0")
  })

  it("renderer hatasında sayfayı çökertmez; birebir düz metin fallback gösterir", () => {
    const consoleError = vi
      .spyOn(console, "error")
      .mockImplementation(() => undefined)

    function Boom(): never {
      throw new Error("render patlaması")
    }

    const { container } = render(
      <MathTextErrorBoundary text="Güvenli düz metin" className="deneme">
        <Boom />
      </MathTextErrorBoundary>
    )

    expect(container.textContent).toBe("Güvenli düz metin")
    expect(container.textContent).not.toContain("render patlaması")
    consoleError.mockRestore()
  })
})
