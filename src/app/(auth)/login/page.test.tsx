import { fireEvent, render, screen, waitFor } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

const pushMock = vi.hoisted(() => vi.fn())
const refreshMock = vi.hoisted(() => vi.fn())
const signInMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, refresh: refreshMock }),
}))

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: { signInWithPassword: signInMock },
    rpc: rpcMock,
  }),
}))

import LoginPage from "./page"

beforeEach(() => {
  pushMock.mockReset()
  refreshMock.mockReset()
  signInMock.mockReset()
  rpcMock.mockReset()
})

function fillAndSubmit() {
  render(<LoginPage />)
  fireEvent.change(screen.getByLabelText("E-posta"), {
    target: { value: "reviewer@example.com" },
  })
  fireEvent.change(screen.getByLabelText("Şifre"), {
    target: { value: "securepass1" },
  })
  fireEvent.click(screen.getByRole("button", { name: "Giriş Yap" }))
}

function mockPermissions(
  permissions: Record<string, boolean>,
  errorCode?: string,
) {
  rpcMock.mockImplementation(
    async (
      _functionName: string,
      args: { p_permission_code: string },
    ) => {
      if (errorCode === args.p_permission_code) {
        return { data: null, error: { message: "permission denied" } }
      }
      return {
        data: permissions[args.p_permission_code] === true,
        error: null,
      }
    },
  )
}

describe("LoginPage", () => {
  it("question reviewer rolünü candidate başlangıcına yönlendirir", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions({ "questions.view": true, "questions.approve": true })

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/admin/candidate-batches")
    })
    expect(refreshMock).toHaveBeenCalledTimes(1)
    expect(rpcMock).toHaveBeenCalledWith(
      "teacher_review_admin_has_permission",
      { p_permission_code: "questions.view" },
    )
    expect(rpcMock).toHaveBeenCalledWith(
      "teacher_review_admin_has_permission",
      { p_permission_code: "ai.manage" },
    )
    expect(rpcMock).toHaveBeenCalledWith(
      "teacher_review_admin_has_permission",
      { p_permission_code: "questions.approve" },
    )
  })

  it("questions.view olmadan aday başlangıcına yönlendirmez", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions({ "questions.approve": true })

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/dashboard")
    })
  })

  it("öğrenciyi öğrenci paneline yönlendirir", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions({})

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/dashboard")
    })
  })

  it("öğrenciyi tek denemeyle öğrenci paneline yönlendirir (yeniden deneme yok)", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions({})

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/dashboard")
    })
    // Doğrulanmış "izin yok" durumunda yeniden deneme tetiklenmez.
    expect(rpcMock).toHaveBeenCalledTimes(3)
    expect(refreshMock).toHaveBeenCalledTimes(1)
  })

  it("geçici izin RPC hatasında tek kontrollü yeniden denemeyle admin hedefine gider", async () => {
    signInMock.mockResolvedValue({ error: null })
    const permissions: Record<string, boolean> = {
      "questions.view": true,
      "questions.approve": true,
    }
    // İlk denemenin üç çağrısı da geçici hata döndürür (RC-1 senaryosu).
    rpcMock
      .mockResolvedValueOnce({ data: null, error: { message: "permission denied" } })
      .mockResolvedValueOnce({ data: null, error: { message: "permission denied" } })
      .mockResolvedValueOnce({ data: null, error: { message: "permission denied" } })
      .mockImplementation(
        async (_functionName: string, args: { p_permission_code: string }) => ({
          data: permissions[args.p_permission_code] === true,
          error: null,
        }),
      )

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/admin/candidate-batches")
    })
    // İlk deneme (3) + tek kontrollü yeniden deneme (3).
    expect(rpcMock).toHaveBeenCalledTimes(6)
    expect(refreshMock).toHaveBeenCalledTimes(1)
    expect(
      screen.queryByText("Giriş sonrası yetki doğrulanamadı. Lütfen tekrar deneyin."),
    ).toBeNull()
  })

  it("kalıcı izin hatasında yönlendirme yok, güvenli Türkçe durum ve ham hata sızıntısı yok", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions(
      { "questions.view": true, "questions.approve": true },
      "questions.view",
    )

    fillAndSubmit()

    await waitFor(() => {
      expect(
        screen.getByText("Giriş sonrası yetki doğrulanamadı. Lütfen tekrar deneyin."),
      ).toBeInTheDocument()
    })
    // Fail-open yasak: ne admin ne öğrenci rotasına yönlendirme.
    expect(pushMock).not.toHaveBeenCalled()
    expect(refreshMock).not.toHaveBeenCalled()
    // İki tam deneme sonrası hâlâ belirsiz.
    expect(rpcMock).toHaveBeenCalledTimes(6)
    // Ham RPC hata metni / durum kodu UI'a sızmaz.
    expect(screen.queryByText(/permission denied/i)).toBeNull()
    expect(screen.queryByText(/unauthorized/i)).toBeNull()
    expect(screen.queryByText(/401/i)).toBeNull()
  })

  it("doğrulanmış izin yoksaylaması (view var, onay izni yok) öğrenci paneline götürür", async () => {
    signInMock.mockResolvedValue({ error: null })
    mockPermissions({ "questions.view": true })

    fillAndSubmit()

    await waitFor(() => {
      expect(pushMock).toHaveBeenCalledWith("/dashboard")
    })
    expect(rpcMock).toHaveBeenCalledTimes(3)
  })

  it("geçersiz girişte izin sorgusu ve yönlendirme yapmaz", async () => {
    signInMock.mockResolvedValue({ error: { message: "invalid credentials" } })
    mockPermissions({ "questions.view": true, "questions.approve": true })

    fillAndSubmit()

    await waitFor(() => {
      expect(
        screen.getByText("E-posta veya şifre hatalı."),
      ).toBeInTheDocument()
    })
    expect(rpcMock).not.toHaveBeenCalled()
    expect(pushMock).not.toHaveBeenCalled()
    expect(refreshMock).not.toHaveBeenCalled()
  })
})
