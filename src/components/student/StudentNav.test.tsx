/**
 * StudentNav testleri (Client Component).
 *
 * - Beş baglantiyi icerir: Ana Sayfa, Antrenman, Yarisma, Lig, Profil
 * - Aktif route aria-current="page" ile vurgulanir
 * - Takma ad gorunur
 * - Logout formu logout action cagirir
 * - Sinif secimi/degistirme navigasyonu yoktur
 */

import { render, screen, fireEvent } from "@testing-library/react"
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
  it("bes ozetme baglantisini icerir", () => {
    usePathnameMock.mockReturnValue("/dashboard")
    render(<StudentNav nickname="altinkalem" logout={vi.fn()} />)

    for (const label of [
      "Ana Sayfa",
      "Antrenman",
      "Yarışma",
      "Lig",
      "Profil",
    ]) {
      expect(screen.getAllByRole("link", { name: label }).length).toBeGreaterThan(0)
    }
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
