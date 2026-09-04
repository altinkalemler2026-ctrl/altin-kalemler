/**
 * Reset-password sayfa guard testleri (Server Component).
 *
 * - Oturum yoksa /forgot-password'e yonlendirilir
 * - Oturum varsa ResetPasswordForm render edilir
 */

import { render, screen } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() => vi.fn())
const getUserMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())
const ResetPasswordFormMock = vi.hoisted(() =>
  vi.fn(() => <div>reset-form-yer-tutucu</div>)
)

vi.mock("next/navigation", () => ({
  redirect: redirectMock,
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

vi.mock("@/components/auth/ResetPasswordForm", () => ({
  default: ResetPasswordFormMock,
}))

import ResetPasswordPage from "./page"

beforeEach(() => {
  redirectMock.mockReset()
  getUserMock.mockReset()
  createClientMock.mockReset()
  ResetPasswordFormMock.mockClear()

  redirectMock.mockImplementation((url: string) => {
    throw new Error(`REDIRECT:${url}`)
  })
})

describe("ResetPasswordPage", () => {
  it("oturum yoksa /forgot-password'e yonlendirir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: null },
      error: null,
    })
    createClientMock.mockResolvedValue({ auth: { getUser: getUserMock } })

    await expect(ResetPasswordPage()).rejects.toThrow(
      "REDIRECT:/forgot-password"
    )
  })

  it("getUser hatasinda /forgot-password'e yonlendirir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: null },
      error: { message: "no session" },
    })
    createClientMock.mockResolvedValue({ auth: { getUser: getUserMock } })

    await expect(ResetPasswordPage()).rejects.toThrow(
      "REDIRECT:/forgot-password"
    )
  })

  it("oturum varsa ResetPasswordForm render edilir", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "u1" } },
      error: null,
    })
    createClientMock.mockResolvedValue({ auth: { getUser: getUserMock } })

    const page = await ResetPasswordPage()
    render(page)

    expect(screen.getByText("reset-form-yer-tutucu")).toBeInTheDocument()
  })
})
