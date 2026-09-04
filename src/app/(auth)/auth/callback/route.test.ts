/**
 * Auth callback route testleri (Server Component GET handler).
 *
 * - No code → /login?error=auth_callback
 * - exchangeCodeForSession error → /login?error=auth_callback
 * - getUser error → /login?error=auth_user
 * - Invalid metadata → /login?error=profile_data
 * - DB error on profile insert → /login?error=profile_setup
 * - Existing profile → /dashboard (no overwrite)
 * - New profile created → /dashboard
 */

import { describe, expect, it, vi, beforeEach } from "vitest"

const exchangeMock = vi.hoisted(() => vi.fn())
const getUserMock = vi.hoisted(() => vi.fn())
const fromMock = vi.hoisted(() => vi.fn())
const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

function makeRequest(url: string) {
  return new Request(url) as import("next/server").NextRequest
}

function setupClient(
  user: Record<string, unknown> | null,
  opts?: {
    exchangeError?: { message: string }
    userError?: { message: string }
    existingProfile?: { id: string } | null
    profileError?: { message: string }
  }
) {
  const maybeSingleResult = opts?.existingProfile ?? null
  const upsertResult = { error: opts?.profileError ?? null }

  const selectChain = {
    eq: vi.fn().mockReturnValue({
      maybeSingle: vi.fn().mockResolvedValue({ data: maybeSingleResult }),
    }),
  }

  fromMock.mockImplementation(() => ({
    select: vi.fn().mockReturnValue(selectChain),
    upsert: vi.fn().mockResolvedValue(upsertResult),
  }))

  createClientMock.mockResolvedValue({
    auth: {
      exchangeCodeForSession: exchangeMock.mockResolvedValue({
        error: opts?.exchangeError ?? null,
      }),
      getUser: getUserMock.mockResolvedValue({
        data: { user },
        error: opts?.userError ?? null,
      }),
    },
    from: fromMock,
  })
}

import { GET } from "./route"

beforeEach(() => {
  vi.clearAllMocks()
})

describe("Auth callback GET", () => {
  it("code yoksa /login?error=auth_callback", async () => {
    setupClient(null)
    const req = makeRequest("http://localhost:3000/auth/callback")

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/login?error=auth_callback")
  })

  it("exchangeCodeForSession hatasinda /login?error=auth_callback", async () => {
    setupClient(null, { exchangeError: { message: "bad code" } })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/login?error=auth_callback")
  })

  it("getUser hatasinda /login?error=auth_user", async () => {
    setupClient(null, { userError: { message: "no user" } })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/login?error=auth_user")
  })

  it("gecersiz metadata ile /login?error=profile_data", async () => {
    setupClient({
      id: "u1",
      user_metadata: { nickname: "", grade_level: 99 },
    })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/login?error=profile_data")
  })

  it("DB hatasinda /login?error=profile_setup", async () => {
    setupClient(
      {
        id: "u2",
        user_metadata: { nickname: "valid", grade_level: 8 },
      },
      { profileError: { message: "db down" } }
    )
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/login?error=profile_setup")
  })

  it("mevcut profile dokunulmaz, /dashboard'a redirect", async () => {
    setupClient(
      {
        id: "u3",
        user_metadata: { nickname: "existing", grade_level: 10 },
      },
      { existingProfile: { id: "u3" } }
    )
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/dashboard")

    const fromCall = fromMock.mock.results[0]?.value
    expect(fromCall).toBeDefined()
    expect(fromCall.upsert).not.toHaveBeenCalled()
  })

  it("yeni profile olusturulur, /dashboard'a redirect", async () => {
    setupClient(
      {
        id: "u4",
        user_metadata: { nickname: "newuser", grade_level: 6 },
      },
      { existingProfile: null }
    )
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/dashboard")

    const fromResults = fromMock.mock.results
    expect(fromResults.length).toBe(2)

    const fromSecondCall = fromResults[1]?.value
    expect(fromSecondCall).toBeDefined()
    expect(fromSecondCall.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        id: "u4",
        nickname: "newuser",
        grade_level: 6,
      }),
      expect.objectContaining({ onConflict: "id" })
    )
  })

  it("next=/reset-password izinliyse reset-password'a redirect", async () => {
    setupClient({
      id: "u5",
      user_metadata: { nickname: "resetuser", grade_level: 7 },
    })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123&next=/reset-password"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/reset-password")
  })

  it("izinli olmayan next degeri yok sayilir, /dashboard'a redirect", async () => {
    setupClient({
      id: "u6",
      user_metadata: { nickname: "hacker", grade_level: 9 },
    })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123&next=/admin/users"
    )

    const res = await GET(req)

    expect(res.headers.get("location")).toContain("/dashboard")
    expect(res.headers.get("location")).not.toContain("/admin")
  })

  it("open redirect denemesi (//evil.com) yok sayilir", async () => {
    setupClient({
      id: "u7",
      user_metadata: { nickname: "openredirect", grade_level: 5 },
    })
    const req = makeRequest(
      "http://localhost:3000/auth/callback?code=abc123&next=//evil.com"
    )

    const res = await GET(req)

    const location = res.headers.get("location") ?? ""

    expect(location).toContain("/dashboard")
    expect(location).not.toContain("evil.com")
  })
})
