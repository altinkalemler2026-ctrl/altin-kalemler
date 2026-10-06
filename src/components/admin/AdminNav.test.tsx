/**
 * AdminNav testleri (Client Component).
 *
 * - Tüm menü bağlantıları gerçek admin rotalarına gider
 * - Aktif rota aria-current="page" ile işaretlenir (ana sayfa yalnız birebir)
 * - Kullanıcı etiketi render edilir
 * - Mobil menü: açılır, odak ilk bağlantıya gider, Escape/dış tıklama/bağlantı
 *   tıklaması güvenli kapanır ve odak düğmeye döner
 * - Menü yalnız navigasyondur: form ve karar/yayın yazma eylemi yok
 * - 44px dokunma hedefi (min-h-11)
 * - F1: kırılım geçişinde mobil panel kapanır, drawer semantiği masaüstünde
 *   kalmaz ve odak gövdeye düşmeden onarılır (mobil→masaüstü→mobil turu)
 * - F2: dış tıklama kapanışında odak tıklamadan sonra açma düğmesine döner
 */

import { render, screen, fireEvent, waitFor, within, act } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const usePathnameMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  usePathname: usePathnameMock,
}))

import AdminNav, { type AdminNavItem } from "./AdminNav"

const ITEMS: AdminNavItem[] = [
  { href: "/admin", title: "Yönetim Ana Sayfası" },
  { href: "/admin/questions", title: "Soru Bankası" },
  { href: "/admin/candidate-batches", title: "Aday Soru Paketleri" },
  { href: "/admin/academic-calendar", title: "Akademik Takvim" },
  { href: "/admin/users", title: "Kullanıcılar" },
  { href: "/admin/teacher-reviews", title: "Öğretmen İncelemeleri" },
  { href: "/admin/curriculum-teaching", title: "Öğretmen Konu Onayı" },
  { href: "/admin/audit", title: "Denetim Kaydı" },
]

function renderNav(pathname = "/admin") {
  usePathnameMock.mockReturnValue(pathname)
  render(<AdminNav items={ITEMS} userLabel="admin@altinkalem.test" />)
}

beforeEach(() => {
  usePathnameMock.mockReset()
})

describe("AdminNav — menü bağlantıları", () => {
  it("tüm bağlantılar gerçek admin rotalarına gider", () => {
    renderNav("/admin/questions")

    const links = screen.getAllByRole("link")
    const hrefs = new Set(links.map((link) => link.getAttribute("href")))

    for (const item of ITEMS) {
      expect(hrefs).toContain(item.href)
      expect(
        screen.getAllByRole("link", { name: item.title }).length,
      ).toBeGreaterThan(0)
    }

    // Hayalî/var olmayan rota bağlantısı yok.
    expect(hrefs).not.toContain("/admin/ogretmenler")
    expect(hrefs).not.toContain("/admin/okullar")
  })

  it("aktif rota aria-current='page' ile işaretlenir", () => {
    renderNav("/admin/questions")

    const questionsLinks = screen.getAllByRole("link", { name: "Soru Bankası" })
    expect(
      questionsLinks.some((link) => link.getAttribute("aria-current") === "page"),
    ).toBe(true)

    const auditLinks = screen.getAllByRole("link", { name: "Denetim Kaydı" })
    expect(
      auditLinks.some((link) => link.getAttribute("aria-current") === "page"),
    ).toBe(false)
  })

  it("alt rota ana sayfayı aktif göstermez; birebir eşleşme aktif gösterir", () => {
    renderNav("/admin/questions")

    const homeOnSubpage = screen.getAllByRole("link", { name: "Yönetim Ana Sayfası" })
    expect(
      homeOnSubpage.some((link) => link.getAttribute("aria-current") === "page"),
    ).toBe(false)

    usePathnameMock.mockReturnValue("/admin")
    const { unmount } = render(
      <AdminNav items={ITEMS} userLabel="admin@altinkalem.test" />,
    )

    const homeOnExact = screen.getAllByRole("link", { name: "Yönetim Ana Sayfası" })
    expect(
      homeOnExact.some((link) => link.getAttribute("aria-current") === "page"),
    ).toBe(true)
    unmount()
  })
})

describe("AdminNav — kullanıcı ve erişilebilirlik", () => {
  it("giriş yapan kullanıcı etiketi gösterilir", () => {
    renderNav("/admin")

    expect(screen.getByText("admin@altinkalem.test")).toBeInTheDocument()
    expect(
      screen.getByLabelText("Giriş yapan: admin@altinkalem.test"),
    ).toBeInTheDocument()
  })

  it("menü bağlantıları 44px dokunma hedefini sağlar", () => {
    renderNav("/admin/audit")

    const auditLinks = screen.getAllByRole("link", { name: "Denetim Kaydı" })
    for (const link of auditLinks) {
      expect(link.className).toContain("min-h-11")
    }

    const toggle = screen.getByRole("button", { name: "Menü" })
    expect(toggle.className).toContain("min-h-11")
  })

  it("menü yalnız navigasyon içerir — form ve karar/yayın eylemi yok", () => {
    renderNav("/admin/candidate-batches")

    expect(screen.queryByRole("form")).not.toBeInTheDocument()

    const buttons = screen.getAllByRole("button")
    expect(buttons.map((b) => b.textContent)).not.toContain("Onayla")
    expect(buttons.map((b) => b.textContent)).not.toContain("Karar")
    expect(buttons.map((b) => b.textContent)).not.toContain("Yayınla")
  })
})

describe("AdminNav — mobil menü", () => {
  it("açılır, öğeleri içerir ve odak ilk bağlantıya gider", async () => {
    renderNav("/admin")

    const toggle = screen.getByRole("button", { name: "Menü" })
    expect(toggle.getAttribute("aria-expanded")).toBe("false")

    fireEvent.click(toggle)

    expect(toggle.getAttribute("aria-expanded")).toBe("true")

    const panel = document.getElementById("admin-nav-panel")
    expect(panel).not.toBeNull()

    for (const item of ITEMS) {
      within(panel as HTMLElement).getByRole("link", { name: item.title })
    }

    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute("href", "/admin")
    })
  })

  it("Escape menüyü kapatır ve odağı düğmeye döndürür", () => {
    renderNav("/admin")

    const toggle = screen.getByRole("button", { name: "Menü" })
    fireEvent.click(toggle)
    expect(toggle.getAttribute("aria-expanded")).toBe("true")

    fireEvent.keyDown(document, { key: "Escape" })

    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(document.activeElement).toBe(toggle)
    expect(document.getElementById("admin-nav-panel")).not.toBeInTheDocument()
  })

  it("dış tıklamada menü kapanır", () => {
    renderNav("/admin")

    const toggle = screen.getByRole("button", { name: "Menü" })
    fireEvent.click(toggle)
    expect(toggle.getAttribute("aria-expanded")).toBe("true")

    fireEvent.pointerDown(document.body)

    expect(toggle.getAttribute("aria-expanded")).toBe("false")
  })

  it("panel içindeki bağlantıya tıklanınca menü kapanır", () => {
    renderNav("/admin")

    fireEvent.click(screen.getByRole("button", { name: "Menü" }))

    const panel = document.getElementById("admin-nav-panel") as HTMLElement
    fireEvent.click(within(panel).getByRole("link", { name: "Denetim Kaydı" }))

    expect(
      screen.getByRole("button", { name: "Menü" }).getAttribute("aria-expanded"),
    ).toBe("false")
    expect(document.getElementById("admin-nav-panel")).not.toBeInTheDocument()
  })
})

/**
 * jsdom `matchMedia` uygulamadığı için kırılım testleri sahte bir
 * MediaQueryList kurar: `setViewport` olayı sanki pencere boyutu
 * değişmiş gibi yayınlar.
 */
type MatchMediaController = {
  setViewport: (desktop: boolean) => void
  restore: () => void
}

function installMatchMedia(initialDesktop: boolean): MatchMediaController {
  const listeners = new Set<(event: MediaQueryListEvent) => void>()
  const original = window.matchMedia
  const mediaQueryList = {
    matches: initialDesktop,
    media: "(min-width: 1024px)",
    onchange: null,
    addEventListener: (
      _type: string,
      listener: (event: MediaQueryListEvent) => void,
    ) => {
      listeners.add(listener)
    },
    removeEventListener: (
      _type: string,
      listener: (event: MediaQueryListEvent) => void,
    ) => {
      listeners.delete(listener)
    },
    addListener: () => undefined,
    removeListener: () => undefined,
    dispatchEvent: () => true,
  }

  window.matchMedia = (() =>
    mediaQueryList) as unknown as typeof window.matchMedia

  return {
    setViewport(desktop: boolean) {
      mediaQueryList.matches = desktop
      act(() => {
        for (const listener of listeners) {
          listener({ matches: desktop } as MediaQueryListEvent)
        }
      })
    },
    restore() {
      window.matchMedia = original
    },
  }
}

describe("AdminNav — kırılım geçişi (F1)", () => {
  it("açık menüyle masaüstüne geçince panel kapanır, drawer semantiği kalmaz, odak ilk masaüstü bağlantısına döner", async () => {
    const media = installMatchMedia(false)

    try {
      renderNav("/admin")

      const toggle = screen.getByRole("button", { name: "Menü" })
      fireEvent.click(toggle)
      expect(toggle.getAttribute("aria-expanded")).toBe("true")
      await waitFor(() => {
        expect(document.activeElement).toHaveAttribute("href", "/admin")
      })

      media.setViewport(true)

      expect(toggle.getAttribute("aria-expanded")).toBe("false")
      expect(document.getElementById("admin-nav-panel")).not.toBeInTheDocument()

      await waitFor(() => {
        expect(document.activeElement).toHaveAttribute("href", "/admin")
      })

      const navs = screen.getAllByRole("navigation", {
        name: "Yönetici menüsü",
      })
      expect(navs).toHaveLength(1)
      expect(navs[0].contains(document.activeElement)).toBe(true)
    } finally {
      media.restore()
    }
  })

  it("mobil→masaüstü→mobil turunda menü kapalı kalır ve odak güvenli biçimde tetikleyiciye döner", async () => {
    const media = installMatchMedia(false)

    try {
      renderNav("/admin")

      const toggle = screen.getByRole("button", { name: "Menü" })
      fireEvent.click(toggle)
      await waitFor(() => {
        expect(document.activeElement).toHaveAttribute("href", "/admin")
      })

      media.setViewport(true)
      await waitFor(() => {
        expect(document.activeElement).toHaveAttribute("href", "/admin")
      })

      media.setViewport(false)
      await waitFor(() => {
        expect(document.activeElement).toBe(toggle)
      })

      expect(toggle.getAttribute("aria-expanded")).toBe("false")
      expect(document.getElementById("admin-nav-panel")).not.toBeInTheDocument()
    } finally {
      media.restore()
    }
  })

  it("kapanık menüyle masaüstüne geçişte odak bozulmaz ve panel hiç açılmaz", async () => {
    const media = installMatchMedia(false)

    try {
      renderNav("/admin")

      media.setViewport(true)
      media.setViewport(false)

      expect(document.getElementById("admin-nav-panel")).not.toBeInTheDocument()
      expect(
        screen.getByRole("button", { name: "Menü" }).getAttribute("aria-expanded"),
      ).toBe("false")
      expect(document.activeElement).toBe(document.body)
    } finally {
      media.restore()
    }
  })
})

describe("AdminNav — dış tıklama odak dönüşü (F2)", () => {
  it("dış tıklama menüyü kapatır ve odak açma düğmesine geri döner", async () => {
    renderNav("/admin")

    const toggle = screen.getByRole("button", { name: "Menü" })
    fireEvent.click(toggle)
    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute("href", "/admin")
    })

    fireEvent.pointerDown(document.body)

    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    await waitFor(() => {
      expect(document.activeElement).toBe(toggle)
    })
  })

  it("Escape davranışı korunur: menü kapanır, odak anında düğmeye döner", async () => {
    renderNav("/admin")

    const toggle = screen.getByRole("button", { name: "Menü" })
    fireEvent.click(toggle)
    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute("href", "/admin")
    })

    fireEvent.keyDown(document, { key: "Escape" })

    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(document.activeElement).toBe(toggle)
  })
})