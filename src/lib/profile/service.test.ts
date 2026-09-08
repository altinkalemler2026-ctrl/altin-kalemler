/**
 * Profil servis testleri (Faz 10).
 *
 * - Mapper'lar YALNIZ allowlist alanları taşır; bilinmeyen alanlar
 *   (email, uuid, metadata) sessizce düşürülür.
 * - Nickname doğrulaması mevcut DB kuralını yansıtır (boş olamaz);
 *   23505 unique hatası güvenli Türkçe mesaja eşlenir.
 * - Avatar seçimi yalnız niyeti (karakter kodu) RPC'ye taşır.
 */

import { describe, expect, it, vi } from "vitest"

import {
  AVATAR_UNAVAILABLE_MESSAGE,
  NICKNAME_DUPLICATE_MESSAGE,
  NicknameValidationError,
  ProfileServiceError,
  mapAvatarOption,
  mapAvatarSelection,
  mapOwnProfileSummary,
  selectOwnAvatar,
  updateOwnNickname,
} from "./service"

describe("mapOwnProfileSummary", () => {
  it("yalniz nickname + grade + avatar allowlist'ini tasir", () => {
    const summary = mapOwnProfileSummary(
      {
        nickname: "MatematikUstasi",
        grade_level: 7,
        email: "sentinel@evil.test",
        id: "sentinel-uuid",
        some_private_metadata: { secret: "sentinel" },
      },
      {
        character: { character_code: "character_1", name: "Karakter 1" },
        secret_column: "sentinel",
      }
    )

    expect(summary).toEqual({
      nickname: "MatematikUstasi",
      gradeLevel: 7,
      avatar: { code: "character_1", name: "Karakter 1" },
    })

    expect(JSON.stringify(summary)).not.toContain("sentinel")
    expect(JSON.stringify(summary)).not.toContain("evil")
  })

  it("loadout yoksa avatar null doner", () => {
    const summary = mapOwnProfileSummary(
      { nickname: "A", grade_level: 5 },
      null
    )

    expect(summary.avatar).toBeNull()
    expect(summary.gradeLevel).toBe(5)
  })

  it("grade sayi degilse 0'a dusurur (guvenli)", () => {
    const summary = mapOwnProfileSummary(
      { nickname: "A", grade_level: "7" },
      null
    )

    expect(summary.gradeLevel).toBe(0)
  })
})

describe("mapAvatarOption / mapAvatarSelection", () => {
  it("katalog satirindan yalniz kod+ad+aciklama tasir", () => {
    const option = mapAvatarOption({
      character_code: "character_1",
      name: "Karakter 1",
      description: "Başlangıç karakteri.",
      unlock_value: 999,
      secret: "sentinel",
    })

    expect(option).toEqual({
      code: "character_1",
      name: "Karakter 1",
      description: "Başlangıç karakteri.",
    })
    expect(JSON.stringify(option)).not.toContain("sentinel")
  })

  it("character_code yoksa satir dusturulur", () => {
    expect(mapAvatarOption({ name: "x" })).toBeNull()
  })

  it("RPC cevabini guvenli sonuca esler", () => {
    expect(
      mapAvatarSelection({ character_code: "character_1", character_name: "Karakter 1" })
    ).toEqual({ code: "character_1", name: "Karakter 1" })
  })
})

describe("updateOwnNickname", () => {
  function makeClient(updateResult: { data: unknown; error: unknown }) {
    return {
      from: vi.fn().mockImplementation(() => ({
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        select: vi.fn().mockReturnThis(),
        single: vi.fn().mockResolvedValue(updateResult),
        maybeSingle: vi.fn().mockResolvedValue({ data: null, error: null }),
      })),
    } as never as Parameters<typeof updateOwnNickname>[0]
  }

  it("bosluklu nickname validation hatasi verir", async () => {
    const client = makeClient({ data: null, error: null })

    await expect(updateOwnNickname(client, "u1", "   ")).rejects.toThrow(
      NicknameValidationError
    )
  })

  it("nickname dogru kaynagi gunceller ve grade yazmaz", async () => {
    const update = vi.fn().mockReturnThis()
    const eq = vi.fn().mockReturnThis()
    const select = vi.fn().mockReturnThis()
    const single = vi
      .fn()
      .mockResolvedValue({ data: { nickname: "YeniAd", grade_level: 7 }, error: null })
    const maybeSingle = vi
      .fn()
      .mockResolvedValue({ data: null, error: null })

    const client = {
      from: vi.fn().mockImplementation(() => ({ update, eq, select, single, maybeSingle })),
    } as never as Parameters<typeof updateOwnNickname>[0]

    const result = await updateOwnNickname(client, "u1", "  YeniAd  ")

    expect(update).toHaveBeenCalledWith({ nickname: "YeniAd" })
    expect(eq).toHaveBeenCalledWith("id", "u1")
    expect(result.nickname).toBe("YeniAd")
    expect(result.gradeLevel).toBe(7)

    // grade_level hicbir koşulda yazma yükünde olmamalı.
    const updateArg = JSON.stringify(update.mock.calls[0])
    expect(updateArg).not.toContain("grade_level")
    expect(updateArg).not.toContain("id")
  })

  it("23505 unique hatasini guvenli Turkce mesaja esler", async () => {
    const client = makeClient({
      data: null,
      error: { code: "23505", message: "duplicate key value violates unique constraint" },
    })

    await expect(updateOwnNickname(client, "u1", "X")).rejects.toThrow(
      NICKNAME_DUPLICATE_MESSAGE
    )
  })

  it("baska DB hatasini ham mesaj sizdirmadan sarar", async () => {
    const client = makeClient({
      data: null,
      error: { code: "XX000", message: "PG::InternalError sentinel-detay" },
    })

    await expect(updateOwnNickname(client, "u1", "X")).rejects.toThrow(
      ProfileServiceError
    )
    await expect(updateOwnNickname(client, "u1", "X")).rejects.not.toThrow(
      /sentinel-detay/
    )
  })
})

describe("selectOwnAvatar", () => {
  it("yalniz trimlenmis kodu RPC'ye tasir", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { character_code: "character_1", character_name: "Karakter 1" },
      error: null,
    })

    const client = { rpc } as never as Parameters<typeof selectOwnAvatar>[0]

    const result = await selectOwnAvatar(client, " character_1 ")

    expect(rpc).toHaveBeenCalledWith("select_own_avatar", {
      p_character_code: "character_1",
    })
    expect(result).toEqual({ code: "character_1", name: "Karakter 1" })
  })

  it("bos kodda RPC cagirmaz", async () => {
    const rpc = vi.fn()
    const client = { rpc } as never as Parameters<typeof selectOwnAvatar>[0]

    await expect(selectOwnAvatar(client, "")).rejects.toThrow(
      AVATAR_UNAVAILABLE_MESSAGE
    )
    expect(rpc).not.toHaveBeenCalled()
  })

  it("P0001 kural hatasini guvenli mesaja esler", async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: null,
      error: { code: "P0001", message: "Gecersiz avatar." },
    })

    const client = { rpc } as never as Parameters<typeof selectOwnAvatar>[0]

    await expect(selectOwnAvatar(client, "x")).rejects.toThrow(
      AVATAR_UNAVAILABLE_MESSAGE
    )
  })
})

describe("fetchOwnProfileSummary / fetchAvatarCatalog", () => {
  it("katalog bos ise status=empty doner", async () => {
    const { fetchAvatarCatalog } = await import("./service")

    const order = vi.fn().mockReturnThis()
    const client = {
      from: vi.fn().mockImplementation(() => ({
        select: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        order,
      })),
    } as never as Parameters<typeof fetchAvatarCatalog>[0]

    // select zinciri await edilebilir bir soz dondurmeli.
    order.mockReturnValue(Promise.resolve({ data: [], error: null }))

    const catalog = await fetchAvatarCatalog(client)

    expect(catalog.status).toBe("empty")
    expect(catalog.options).toEqual([])
  })
})
