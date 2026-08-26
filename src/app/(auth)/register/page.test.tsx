/**
 * Register page testleri (Client Component).
 *
 * - signUp session donerse router.replace("/dashboard")
 * - session yoksa dogrulama mesaji
 * - signUp error guvenli mesaj
 * - sifre/token ciktilanmaz
 */

import { render, screen, fireEvent, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const replaceMock = vi.hoisted(() => vi.fn())
const signUpMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  useRouter: () => ({ replace: replaceMock }),
}))

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { signUp: signUpMock },
  }),
}))

import RegisterPage from "./page"

beforeEach(() => {
  replaceMock.mockReset()
  signUpMock.mockReset()
})

function fillAndSubmit(overrides?: {
  email?: string
  password?: string
  passwordAgain?: string
  nickname?: string
  gradeLevel?: string
}) {
  render(<RegisterPage />)

  fireEvent.change(screen.getByLabelText("Kullanıcı adı"), {
    target: { value: overrides?.nickname ?? "testnick" },
  })
  fireEvent.change(screen.getByLabelText("Sınıf"), {
    target: { value: overrides?.gradeLevel ?? "10" },
  })
  fireEvent.change(screen.getByLabelText("E-posta"), {
    target: { value: overrides?.email ?? "test@test.com" },
  })
  fireEvent.change(screen.getByLabelText("Şifre"), {
    target: { value: overrides?.password ?? "securepass1" },
  })
  fireEvent.change(screen.getByLabelText("Şifre tekrar"), {
    target: { value: overrides?.passwordAgain ?? "securepass1" },
  })

  fireEvent.click(screen.getByRole("button", { name: "Kayıt Ol" }))
}

describe("RegisterPage", () => {
  it("session donerse /dashboard'a redirect eder", async () => {
    signUpMock.mockResolvedValue({
      data: {
        user: { id: "u1" },
        session: { access_token: "tok" },
      },
      error: null,
    })

    fillAndSubmit()

    await waitFor(() => {
      expect(replaceMock).toHaveBeenCalledWith("/dashboard")
    })
  })

  it("session yoksa dogrulama mesaji gosterir", async () => {
    signUpMock.mockResolvedValue({
      data: { user: { id: "u2" }, session: null },
      error: null,
    })

    fillAndSubmit()

    await waitFor(() => {
      expect(
        screen.getByText(
          "Kayıt alındı. E-posta adresinize gelen doğrulama bağlantısını kontrol edin."
        )
      ).toBeDefined()
    })
    expect(replaceMock).not.toHaveBeenCalled()
  })

  it("signUp error guvenli mesaj gosterir", async () => {
    signUpMock.mockResolvedValue({
      data: { user: null, session: null },
      error: { message: "internal failure details" },
    })

    fillAndSubmit()

    await waitFor(() => {
      expect(
        screen.getByText(
          "Kayıt oluşturulamadı. Bilgilerinizi kontrol edip tekrar deneyin."
        )
      ).toBeDefined()
    })
    expect(replaceMock).not.toHaveBeenCalled()
  })

  it("sifre veya token ciktilanmadi", async () => {
    signUpMock.mockResolvedValue({
      data: { user: { id: "u3" }, session: null },
      error: null,
    })

    fillAndSubmit({ password: "supersecret99", passwordAgain: "supersecret99" })

    await waitFor(() => {
      expect(signUpMock).toHaveBeenCalled()
    })

    const body = document.body.textContent ?? ""
    expect(body).not.toContain("supersecret99")
    expect(body).not.toContain("access_token")
    expect(body).not.toContain("tok")
  })

  it("bos alanlarla form gonderilemez", async () => {
    render(<RegisterPage />)

    fireEvent.click(screen.getByRole("button", { name: "Kayıt Ol" }))

    await waitFor(() => {
      expect(
        screen.getByText("Lütfen tüm alanları doldurun.")
      ).toBeDefined()
    })
    expect(signUpMock).not.toHaveBeenCalled()
  })

  it("sifre eslesmiyorsa hata gosterir", async () => {
    render(<RegisterPage />)

    fireEvent.change(screen.getByLabelText("Kullanıcı adı"), {
      target: { value: "nick" },
    })
    fireEvent.change(screen.getByLabelText("Sınıf"), {
      target: { value: "5" },
    })
    fireEvent.change(screen.getByLabelText("E-posta"), {
      target: { value: "a@b.com" },
    })
    fireEvent.change(screen.getByLabelText("Şifre"), {
      target: { value: "pass12345" },
    })
    fireEvent.change(screen.getByLabelText("Şifre tekrar"), {
      target: { value: "pass99999" },
    })

    fireEvent.click(screen.getByRole("button", { name: "Kayıt Ol" }))

    await waitFor(() => {
      expect(
        screen.getByText("Şifreler birbiriyle aynı değil.")
      ).toBeDefined()
    })
    expect(signUpMock).not.toHaveBeenCalled()
  })

  it("kullanici olusturulamadi hatasi guvenli mesaj", async () => {
    signUpMock.mockResolvedValue({
      data: { user: null, session: null },
      error: null,
    })

    fillAndSubmit()

    await waitFor(() => {
      expect(
        screen.getByText("Kullanıcı hesabı oluşturulamadı.")
      ).toBeDefined()
    })
    expect(replaceMock).not.toHaveBeenCalled()
  })
})
