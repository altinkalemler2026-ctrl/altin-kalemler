/**
 * StudentNav testleri (Client Component).
 *
 * - Baglantilari icerir: Ana Sayfa, Antrenman, Ilerleme, Tekrar, Yarisma, Lig, Profil
 * - Aktif route aria-current="page" ile vurgulanir
 * - Takma ad gorunur
 * - Logout formu logout action cagirir
 * - Sinif secimi/degistirme navigasyonu yoktur
 */

import { render, screen, fireEvent, within, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const usePathnameMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  usePathname: usePathnameMock,
}))

import StudentNav from "./StudentNav"

beforeEach(() => {
  usePathnameMock.mockReset()
})

describe("StudentNav", () => {
  it("ogrenci baglantilari icerir (Faz 11: Ilerleme dahil)", () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    for (const label of [
      "Ana Sayfa",
      "Antrenman",
      "İlerleme",
      "Tekrar",
      "Yarışma",
      "Lig",
      "Profil",
    ]) {
      expect(screen.getAllByRole("link", { name: label }).length).toBeGreaterThan(0)
    }

    // Ilerleme rotasi /ilerleme'ye gider.
    const progressLinks = screen
      .getAllByRole("link", { name: "İlerleme" })
      .map((link) => link.getAttribute("href"))
    expect(progressLinks).toContain("/ilerleme")
  })

  it("aktif route aria-current ile isaretlenir", () => {
    usePathnameMock.mockReturnValue("/training")

    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const trainingLinks = screen.getAllByRole("link", { name: "Antrenman" })
    const activeTraining = trainingLinks.find(
      (link) => link.getAttribute("aria-current") === "page"
    )

    expect(activeTraining).toBeDefined()

    const dashboardLinks = screen.getAllByRole("link", { name: "Ana Sayfa" })
    const activeDashboard = dashboardLinks.find(
      (link) => link.getAttribute("aria-current") === "page"
    )

    expect(activeDashboard).toBeUndefined()
  })

  it("takma ad gorunur", () => {
    usePathnameMock.mockReturnValue("/dashboard")

    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    expect(screen.getByText("@altinkalem")).toBeInTheDocument()
  })

  it("cikis yap dugmesi logout action cagirir", async () => {
    usePathnameMock.mockReturnValue("/dashboard")
    const logoutMock = vi.fn().mockResolvedValue(undefined)

    render(<StudentNav nickname="altinkalem" logout={logoutMock} />)

    fireEvent.click(screen.getByRole("button", { name: "Çıkış Yap" }))

    await vi.waitFor(() => {
      expect(logoutMock).toHaveBeenCalledTimes(1)
    })
  })

  it("sinif secimi navigasyonu yoktur", () => {
    usePathnameMock.mockReturnValue("/dashboard")

    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    expect(screen.queryByLabelText(/Sınıf/)).not.toBeInTheDocument()
    expect(
      screen.queryByRole("combobox", { name: /Sınıf/ })
    ).not.toBeInTheDocument()
  })

  it("sinif/grade rota baglantisi icermez", () => {
    usePathnameMock.mockReturnValue("/dashboard")

    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const links = screen.getAllByRole("link")
    const hrefs = links.map((link) => link.getAttribute("href"))

    expect(hrefs).not.toContain("/grade")
    expect(hrefs).not.toContain("/class")
  })
})

describe("StudentNav mobil 'Diğer' menüsü (Faz 12)", () => {
  it("acilir, Ilerleme/Tekrar icerir ve odak ilk baglantiya gider", async () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const moreButton = screen.getByRole("button", { name: "Diğer" })
    expect(moreButton.getAttribute("aria-expanded")).toBe("false")

    fireEvent.click(moreButton)

    expect(moreButton.getAttribute("aria-expanded")).toBe("true")

    const menu = document.getElementById("student-more-menu")
    expect(menu).not.toBeNull()
    within(menu as HTMLElement).getByRole("link", { name: "İlerleme" })
    within(menu as HTMLElement).getByRole("link", { name: "Tekrar" })

    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute("href", "/ilerleme")
    })
  })

  it("aktif route icin panel baglantisi aria-current tasir", () => {
    usePathnameMock.mockReturnValue("/ilerleme")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    fireEvent.click(screen.getByRole("button", { name: "Diğer" }))

    const menu = document.getElementById("student-more-menu") as HTMLElement
    expect(
      within(menu).getByRole("link", { name: "İlerleme" })
    ).toHaveAttribute("aria-current", "page")
  })

  it("Escape menuyu kapatir ve odak dugmeye doner", () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const moreButton = screen.getByRole("button", { name: "Diğer" })
    fireEvent.click(moreButton)
    expect(moreButton.getAttribute("aria-expanded")).toBe("true")

    fireEvent.keyDown(document, { key: "Escape" })

    expect(moreButton.getAttribute("aria-expanded")).toBe("false")
    expect(document.activeElement).toBe(moreButton)
  })

  it("dis tiklamada menü kapanir", () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const moreButton = screen.getByRole("button", { name: "Diğer" })
    fireEvent.click(moreButton)
    expect(moreButton.getAttribute("aria-expanded")).toBe("true")

    fireEvent.pointerDown(document.body)

    expect(moreButton.getAttribute("aria-expanded")).toBe("false")
  })

  it("menu icindeki baglantiya tiklaninca menü kapanir", () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    const moreButton = screen.getByRole("button", { name: "Diğer" })
    fireEvent.click(moreButton)
    expect(moreButton.getAttribute("aria-expanded")).toBe("true")

    const menu = document.getElementById("student-more-menu") as HTMLElement
    fireEvent.click(within(menu).getByRole("link", { name: "İlerleme" }))

    expect(moreButton.getAttribute("aria-expanded")).toBe("false")
    expect(
      document.getElementById("student-more-menu")
    ).not.toBeInTheDocument()
  })
})
