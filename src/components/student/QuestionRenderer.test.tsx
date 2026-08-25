/**
 * QuestionRenderer guvenlik testleri.
 *
 * - Malicious HTML payload'lari textContent olarak render edilir.
 * - Script, iframe, img, object, embed, svg node'lari DOM'a eklenmez.
 * - dangerouslySetInnerHTML kullanilmaz.
 * - Dis URL/resource istegi olusturulmaz.
 */

import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"

import QuestionRenderer from "./QuestionRenderer"

describe("QuestionRenderer", () => {
  it("stemHtml duz metin olarak render edilir", () => {
    render(
      <QuestionRenderer
        stemHtml="<p>2 + 2 kac eder?</p>"
        options={{ A: "<p>3</p>", B: "<p>4</p>" }}
      />
    )
    expect(screen.getByText("2 + 2 kac eder?")).toBeDefined()
    expect(screen.getByText("3")).toBeDefined()
    expect(screen.getByText("4")).toBeDefined()
  })

  it("script tag'lari DOM'a eklenmez ve calismaz", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml='<p>Soru</p><script>alert("xss")</script>'
        options={{}}
      />
    )
    const scripts = container.querySelectorAll("script")
    expect(scripts.length).toBe(0)
    expect(container.textContent).toContain("Soru")
  })

  it("iframe tag'lari DOM'a eklenmez", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml='<p>Soru</p><iframe src="evil.com"></iframe>'
        options={{}}
      />
    )
    const iframes = container.querySelectorAll("iframe")
    expect(iframes.length).toBe(0)
  })

  it("img onerror ile XSS calismaz", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml='<img src="x" onerror="alert(1)">'
        options={{}}
      />
    )
    const imgs = container.querySelectorAll("img")
    expect(imgs.length).toBe(0)
  })

  it("svg onload ile XSS calismaz", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml='<svg onload="alert(1)"><text>test</text></svg>'
        options={{}}
      />
    )
    const svgs = container.querySelectorAll("svg")
    expect(svgs.length).toBe(0)
  })

  it("style tag'i DOM'a eklenmez", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml="<style>body{display:none}</style><p>Soru</p>"
        options={{}}
      />
    )
    const styles = container.querySelectorAll("style")
    expect(styles.length).toBe(0)
  })

  it("object ve embed tag'lari DOM'a eklenmez", () => {
    const { container } = render(
      <QuestionRenderer
        stemHtml='<object data="evil.swf"></object><embed src="evil.swf">'
        options={{}}
      />
    )
    expect(container.querySelectorAll("object").length).toBe(0)
    expect(container.querySelectorAll("embed").length).toBe(0)
  })

  it("bos stemHtml icin fallback mesaji gosterilir", () => {
    render(<QuestionRenderer stemHtml="" options={{}} />)
    expect(screen.getByText("Soru metni bulunamadi.")).toBeDefined()
  })

  it("seceneklerden olmayan harf render edilmez", () => {
    render(
      <QuestionRenderer
        stemHtml="Soru"
        options={{ A: "Secenek A" }}
      />
    )
    expect(screen.getByText("Secenek A")).toBeDefined()
    expect(screen.queryByText("Secenek B")).toBeNull()
  })

  it("HTML icerikleri textContent olarak temizlenir", () => {
    render(
      <QuestionRenderer
        stemHtml="<b>Kalin</b> ve <i>italik</i>"
        options={{ A: '<a href="https://evil.com">link</a>' }}
      />
    )
    expect(screen.getByText("Kalin ve italik")).toBeDefined()
    expect(screen.getByText("link")).toBeDefined()
    const links = document.querySelectorAll("a")
    expect(links.length).toBe(0)
  })
})
