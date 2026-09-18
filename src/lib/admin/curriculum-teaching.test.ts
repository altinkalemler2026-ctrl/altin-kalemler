// @vitest-environment node
/**
 * Faz 16 P0.1 — Öğretmen Konu-Açma okuyucu testleri (110/119 RPC'leri).
 *
 * - curriculum.manage izni fail-closed doğrulanır (error/false → yetki YOK).
 * - DTO allowlist: ham RPC satırı keyfi alan taşımaz; her alan tip
 *   kontrolünden geçer, bilinmeyen status null'a düşer.
 * - Liste hata durumu ayrıdır; ham RPC hata metni asla taşınmaz.
 * - Ders/yıl künyesi okuma: subject RLS + aktif müfredat yılları.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

import {
  hasCurriculumTeachingPermission,
  listCurriculumTeachingApprovals,
  listCurriculumTeachingMeta,
  mapCurriculumTeachingItem,
} from "./curriculum-teaching"

/**
 * from(table) çağrılarını tabloya göre yönlendiren istemci mock'u.
 * Her tablo için yeni (sıfırlanmış) bir builder üretir; builder sonucu
 * resultsByTable'dan alınırken CURRENT tabloyu bilmesi gerekir. Basit
 * yaklaşım: from, her tablo için kendi builder'ını kurar ve builder'ın
 * `then`'i o tablonun sonucunu döndürür.
 */
function makeTableClient(resultsByTable: Record<string, unknown>) {
  const orderCalls: Record<string, unknown[][]> = {}
  const eqCalls: Record<string, unknown[][]> = {}
  const fromMock = vi.fn((table: string) => {
    orderCalls[table] = []
    eqCalls[table] = []
    const calls = {
      eq: [] as unknown[][],
      order: [] as unknown[][],
    }
    const builder = {
      eq: vi.fn((...args: unknown[]) => {
        calls.eq.push(args)
        eqCalls[table] = calls.eq
        return builder
      }),
      order: vi.fn((...args: unknown[]) => {
        calls.order.push(args)
        orderCalls[table] = calls.order
        return builder
      }),
      select: vi.fn(() => builder),
      then: (resolve: (v: unknown) => unknown) =>
        Promise.resolve(resultsByTable[table]).then(resolve),
    }
    return builder
  })
  return {
    client: { from: fromMock },
    fromMock,
    orderCalls,
    eqCalls,
  }
}

beforeEach(() => {
  createClientMock.mockReset()
})

describe("hasCurriculumTeachingPermission", () => {
  it("curriculum.manage true ise yetki var", async () => {
    const rpcMock = vi.fn().mockResolvedValue({ data: true, error: null })
    createClientMock.mockImplementation(async () => ({ rpc: rpcMock }))
    expect(await hasCurriculumTeachingPermission()).toBe(true)
    expect(rpcMock.mock.calls[0]?.[0]).toBe(
      "teacher_review_admin_has_permission"
    )
    expect(rpcMock.mock.calls[0]?.[1]).toEqual({
      p_permission_code: "curriculum.manage",
    })
  })

  it("false veya hata durumunda fail-closed", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: false, error: null }),
    }))
    expect(await hasCurriculumTeachingPermission()).toBe(false)

    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "permission denied" },
      }),
    }))
    expect(await hasCurriculumTeachingPermission()).toBe(false)
  })
})

describe("mapCurriculumTeachingItem — allowlist DTO", () => {
  it("bilinen alanları doğru tiplerle eşler", () => {
    const item = mapCurriculumTeachingItem({
      schedule_item_id: "a4090000-0000-4000-8000-000000000001",
      schedule_profile_id: "a2000000-0000-4000-8000-0000000000c1",
      profile_code: "TYMM2026-PROF-2026-2027",
      profile_name: "TYMM 2026 (9-11) Varsayılan Plan",
      grade_level: 9,
      topic_name: "MAT.9.1 SAYILAR",
      outcome_text: "Kazanım metni",
      start_week: 1,
      status: "approved",
      updated_at: "2026-09-03T10:00:00.000Z",
      bazuka: "SIZMAYAN-ALAN",
    })
    expect(item.scheduleItemId).toBe("a4090000-0000-4000-8000-000000000001")
    expect(item.scheduleProfileId).toBe("a2000000-0000-4000-8000-0000000000c1")
    expect(item.profileCode).toContain("TYMM2026")
    expect(item.gradeLevel).toBe(9)
    expect(item.startWeek).toBe(1)
    expect(item.status).toBe("approved")
    expect(JSON.stringify(item)).not.toContain("SIZMAYAN-ALAN")
  })

  it("bilinmeyen status null'e düşer (fail-closed)", () => {
    const item = mapCurriculumTeachingItem({
      schedule_item_id: "x",
      grade_level: 10,
      status: "unknown-state",
    })
    expect(item.status).toBeNull()
  })

  it("eksik alanlar güvenli varsayılan alır", () => {
    const item = mapCurriculumTeachingItem({})
    expect(item.scheduleItemId).toBe("")
    expect(item.gradeLevel).toBe(0)
    expect(item.status).toBeNull()
    expect(item.profileCode).toBeNull()
    expect(item.updatedAt).toBeNull()
  })
})

describe("listCurriculumTeachingApprovals", () => {
  it("RPC items dizisini DTO'ya eşler", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: {
          subject_id: "s",
          academic_year: "2026-2027",
          items: [
            {
              schedule_item_id: "a4090000-0000-4000-8000-000000000001",
              grade_level: 9,
              topic_name: "MAT.9.1",
              status: "approved",
            },
            {
              schedule_item_id: "a4090000-0000-4000-8000-000000000002",
              grade_level: 10,
              topic_name: "MAT.10.1",
              status: null,
            },
          ],
        },
        error: null,
      }),
    }))
    const result = await listCurriculumTeachingApprovals(
      "430903f3-527e-4e12-b7e8-ac0afdb784aa",
      "2026-2027"
    )
    expect(result.status).toBe("ok")
    expect(result.items).toHaveLength(2)
    expect(result.items[0]?.status).toBe("approved")
    expect(result.items[1]?.status).toBeNull()
  })

  it("RPC hatası status:'error' döner; ham hata taşınmaz", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "curriculum.manage yetkisi gerekli." },
      }),
    }))
    const result = await listCurriculumTeachingApprovals("s", "2026-2027")
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
    expect(JSON.stringify(result)).not.toContain("yetkisi")
  })

  it("items eksikse boş liste döner", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: null, error: null }),
    }))
    const result = await listCurriculumTeachingApprovals("s", "2026-2027")
    expect(result.status).toBe("ok")
    expect(result.items).toEqual([])
  })
})

describe("listCurriculumTeachingMeta", () => {
  it("subjects + aktif yılları birlikte döner, yıllar tekil ve en yeni başta", async () => {
    const { client, fromMock } = makeTableClient({
      subjects: { data: [{ id: "s1", name: "Matematik" }], error: null },
      curriculum_versions: {
        data: [
          { academic_year: "2026-2027" },
          { academic_year: "2026-2027" },
          { academic_year: "2025-2026" },
        ],
        error: null,
      },
    })
    createClientMock.mockImplementation(async () => client)

    const result = await listCurriculumTeachingMeta()
    expect(result.status).toBe("ok")
    expect(result.subjects).toEqual([{ id: "s1", name: "Matematik" }])
    expect(result.years.map((y) => y.academicYear)).toEqual([
      "2026-2027",
      "2025-2026",
    ])
    expect(fromMock).toHaveBeenCalledWith("curriculum_versions")
  })

  it("subject okuma hatası status:'error' döner", async () => {
    const { client } = makeTableClient({
      subjects: { data: null, error: { message: "db down" } },
      curriculum_versions: {
        data: [{ academic_year: "2026-2027" }],
        error: null,
      },
    })
    createClientMock.mockImplementation(async () => client)
    const result = await listCurriculumTeachingMeta()
    expect(result.status).toBe("error")
    expect(result.subjects).toEqual([])
    expect(result.years).toEqual([])
    expect(JSON.stringify(result)).not.toContain("db down")
  })
})