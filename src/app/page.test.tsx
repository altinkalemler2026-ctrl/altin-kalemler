/**
 * Root page testleri (Server Component).
 *
 * - authenticated → /dashboard
 * - unauthenticated → /login
 * - Next.js boilerplate render edilmez
 */

import { describe, expect, it, vi } from "vitest"

const redirectMock = vi.hoisted(() =>
  vi.fn((_url: string) => {
    throw new Error(`REDIRECT:${_url}`)
  })
)
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}))

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

function mockClient(user: { id: string } | null) {
  createClientMock.mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user } }),
    },
  })
}

import Home from "./page"

describe("Root page", () => {
  it("authenticated ise /dashboard'a redirect eder", async () => {
    mockClient({ id: "99999999-8888-4000-8000-000000000901" })

    await expect(Home()).rejects.toThrow("REDIRECT:/dashboard")
  })

  it("unauthenticated ise /login'e redirect eder", async () => {
    mockClient(null)

    await expect(Home()).rejects.toThrow("REDIRECT:/login")
  })

  it("Next.js boilerplate render edilmez", async () => {
    mockClient(null)

    await expect(Home()).rejects.toThrow("REDIRECT:/login")

    const body = document.body.textContent ?? ""
    expect(body).not.toContain("Get started by editing")
    expect(body).not.toContain("app/page.tsx")
    expect(body).not.toContain("Vercel")
  })
})
