/**
 * ResetPasswordForm testleri (Client Component).
 *
 * - Sifreler eslesmezse hata mesaji ve updateUser cagrilmaz
 * - Kisa sifrede hata mesaji
 * - updateUser basarili: cikis yapilir ve /login'e yonlendirilir
 * - updateUser hatasi: guvenli mesaj, oturum kapatilmaz
 * - Sifre ciktilanmaz
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const pushMock = vi.hoisted(() => vi.fn())
const refreshMock = vi.hoisted(() => vi.fn())
const updateUserMock = vi.hoisted(() => vi.fn())
const signOutMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: refreshMock }),
}))

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { updateUser: updateUserMock, signOut: signOutMock },
  }),
}))

import ResetPasswordForm from "./ResetPasswordForm"

beforeEach(() => {
  pushMock.mockReset()
  refreshMock.mockReset()
  updateUserMock.mockReset()
  signOutMock.mockReset()
})

function fillAndSubmit(password: string, passwordAgain: string) {
  render(<ResetPasswordForm />)

  fireEvent.change(screen.getByLabelText("Yeni şifre"), {
    target: { value: password },
  })
  fireEvent.change(screen.getByLabelText("Yeni şifre tekrar"), {
    target: { value: passwordAgain },
  })

  fireEvent.click(screen.getByRole("button", { name: "Şifreyi Güncelle" }))
}

describe("ResetPasswordForm", () => {
  it("sifreler eslesmezse hata gosterir ve updateUser cagrilmaz", async () => {
    fillAndSubmit("securepass1", "different1")

    await waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Şifreler birbiriyle aynı değil."
      )
    })

    expect(updateUserMock).not.toHaveBeenCalled()
  })

  it("kisa sifrede hata gosterir ve updateUser cagrilmaz", async () => {
    fillAndSubmit("kisa", "kisa")

    await waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Şifre en az 8 karakter olmalıdır."
      )
    })

    expect(updateUserMock).not.toHaveBeenCalled()
  })

  it("basarili guncellemede cikis yapilir ve /login'e yonlendirilir", async () => {
    updateUserMock.mockResolvedValue({ data: { user: {} }, error: null })
    signOutMock.mockResolvedValue({ error: null })

    fillAndSubmit("securepass1", "securepass1")

    await waitFor(() => {
      expect(updateUserMock).toHaveBeenCalledWith({ password: "securepass1" })
    })

    await waitFor(() => {
      expect(signOutMock).toHaveBeenCalledTimes(1)
    })

    await waitFor(
      () => {
        expect(pushMock).toHaveBeenCalledWith("/login")
      },
      { timeout: 3000 }
    )

    expect(refreshMock).toHaveBeenCalled()
    expect(screen.getByRole("status")).toHaveTextContent(
      "Şifren güncellendi."
    )
  })

  it("updateUser hatasinda guvenli mesaj gosterilir ve oturum kapatilmaz", async () => {
    updateUserMock.mockResolvedValue({
      data: { user: null },
      error: { message: "session expired" },
    })

    fillAndSubmit("securepass1", "securepass1")

    await waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(
        "Şifre güncellenemedi."
      )
    })

    expect(signOutMock).not.toHaveBeenCalled()
    expect(pushMock).not.toHaveBeenCalled()
  })

  it("sifre degeri ekrana cikti olarak yazilmaz", () => {
    render(<ResetPasswordForm />)

    fireEvent.change(screen.getByLabelText("Yeni şifre"), {
      target: { value: "securepass1" },
    })

    const input = screen.getByLabelText(
      "Yeni şifre"
    ) as HTMLInputElement

    expect(input.type).toBe("password")
  })
})
