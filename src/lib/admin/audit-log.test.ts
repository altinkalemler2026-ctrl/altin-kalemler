// @vitest-environment node
/**
 * Denetim kaydı okuyucu testleri (migration 089 admin_audit_log).
 *
 * - audit.view izni fail-closed doğrulanır (error/false → yetki YOK).
 * - DTO allowlist: before_data / after_data payload'ları SEÇİLMEZ ve
 *   DTO'ya taşınmaz (veri minimizasyonu).
 * - action_code filtresi allowlist'lidir; keyfi değer DB'ye gitmez.
 * - Sayfalama güvenli; hata durumu ayrıdır.
 */

import { beforeEach, describe, expect, it, vi } from "vitest"

const createClientMock = vi.hoisted(() => vi.fn())

vi.mock("@/lib/supabase/server", () => ({
  createClient: createClientMock,
}))

import {
  AUDIT_PAGE_SIZE,
  hasAuditViewPermission,
  listAuditLog,
  mapAuditLogEntry,
  parseAuditActionCode,
  parseAuditEntityId,
} from "./audit-log"

/**
 * Supabase postgrest zincirini taklit eden thenable builder:
 * select(..., { head: true }) → count sonucu; aksi halde veri sonucu.
 */
function makeBuilder(
  countResult: { count: number | null; error: unknown },
  dataResult: { data: unknown; error: unknown }
) {
  const state = { head: false }
  const builder = {
    eq: vi.fn((..._args: unknown[]) => builder),
    order: vi.fn((..._args: unknown[]) => builder),
    range: vi.fn((..._args: unknown[]) => builder),
    select: vi.fn((...args: unknown[]) => {
      const opts = args[1] as { head?: boolean } | undefined
      state.head = Boolean(opts?.head)
      return builder
    }),
    then: (
      resolve: (v: unknown) => unknown,
      reject?: (e: unknown) => unknown
    ) => Promise.resolve(state.head ? countResult : dataResult).then(resolve, reject),
  }
  return builder
}

function makeClient(
  rpcResult: { data: unknown; error: unknown },
  countResult: { count: number | null; error: unknown },
  dataResult: { data: unknown; error: unknown }
) {
  const builder = makeBuilder(countResult, dataResult)
  createClientMock.mockImplementation(async () => ({
    rpc: vi.fn().mockResolvedValue(rpcResult),
    from: vi.fn(() => builder),
  }))
  return builder
}

beforeEach(() => {
  createClientMock.mockReset()
})

describe("hasAuditViewPermission", () => {
  it("audit.view true ise yetki var", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: true, error: null }),
    }))
    expect(await hasAuditViewPermission()).toBe(true)
  })

  it("false veya hata durumunda fail-closed", async () => {
    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({ data: false, error: null }),
    }))
    expect(await hasAuditViewPermission()).toBe(false)

    createClientMock.mockImplementation(async () => ({
      rpc: vi.fn().mockResolvedValue({
        data: null,
        error: { message: "permission denied" },
      }),
    }))
    expect(await hasAuditViewPermission()).toBe(false)
  })
})

describe("parseAuditActionCode / parseAuditEntityId", () => {
  it("allowlist dışı action_code reddedilir", () => {
    expect(parseAuditActionCode("question.edit")).toBe("question.edit")
    expect(parseAuditActionCode("DROP TABLE")).toBeUndefined()
    expect(parseAuditActionCode(undefined)).toBeUndefined()
  })

  it("geçersiz entity kimliği reddedilir", () => {
    expect(parseAuditEntityId("not-a-uuid")).toBeUndefined()
    expect(
      parseAuditEntityId("aaaaaaaa-1111-4000-8000-000000000001")
    ).toBe("aaaaaaaa-1111-4000-8000-000000000001")
  })
})

describe("listAuditLog", () => {
  it("yalnız allowlist künye kolonlarını seçer; payload kolonları seçilmez", async () => {
    const builder = makeClient(
      { data: true, error: null },
      { count: 1, error: null },
      {
        data: [
          {
            id: "dddddddd-0000-4000-8000-00000000000d",
            action_code: "question.edit",
            entity_type: "question",
            entity_id: "aaaaaaaa-1111-4000-8000-000000000001",
            actor_user_id: "99999999-8888-4000-8000-000000000901",
            performed_at: "2026-09-03T10:00:00.000Z",
          },
        ],
        error: null,
      }
    )

    const result = await listAuditLog({}, 1)
    expect(result.status).toBe("ok")
    expect(result.items).toHaveLength(1)
    expect(result.items[0]?.actionCode).toBe("question.edit")

    const columnCalls = builder.select.mock.calls.map((c) => String(c[0]))
    for (const columns of columnCalls) {
      expect(columns).not.toContain("before_data")
      expect(columns).not.toContain("after_data")
    }
    expect(columnCalls.some((c) => c.includes("action_code"))).toBe(true)
  })

  it("satır DTO'ya allowlist ile eşlenir; payload alanları taşınmaz", () => {
    const entry = mapAuditLogEntry({
      id: "dddddddd-0000-4000-8000-00000000000d",
      action_code: "question.edit",
      entity_type: "question",
      entity_id: "aaaaaaaa-1111-4000-8000-000000000001",
      actor_user_id: "99999999-8888-4000-8000-000000000901",
      performed_at: "2026-09-03T10:00:00.000Z",
      before_data: { secret: "GIZLI-BEFORE" },
      after_data: { secret: "GIZLI-AFTER" },
    })
    expect(entry.actionCode).toBe("question.edit")
    expect(entry.entityType).toBe("question")
    expect(JSON.stringify(entry)).not.toContain("GIZLI-BEFORE")
    expect(JSON.stringify(entry)).not.toContain("GIZLI-AFTER")
    expect(JSON.stringify(entry)).not.toContain("before_data")
    expect(JSON.stringify(entry)).not.toContain("after_data")
  })

  it("action_code ve entity filtreleri eq ile iletilir", async () => {
    const builder = makeClient(
      { data: true, error: null },
      { count: 0, error: null },
      { data: [], error: null }
    )

    await listAuditLog(
      {
        actionCode: "question.edit",
        entityId: "aaaaaaaa-1111-4000-8000-000000000001",
      },
      1
    )

    const eqArgs = builder.eq.mock.calls.map((c) => [c[0], c[1]])
    expect(eqArgs).toContainEqual(["action_code", "question.edit"])
    expect(eqArgs).toContainEqual([
      "entity_id",
      "aaaaaaaa-1111-4000-8000-000000000001",
    ])
  })

  it("sayım hatası status:'error' döner; ham hata taşınmaz", async () => {
    makeClient(
      { data: true, error: null },
      { count: null, error: { message: "db down" } },
      { data: null, error: null }
    )

    const result = await listAuditLog({}, 1)
    expect(result.status).toBe("error")
    expect(result.items).toEqual([])
    expect(JSON.stringify(result)).not.toContain("db down")
  })

  it("sayfalama: toplam ve aralıklar doğru hesaplanır", async () => {
    const builder = makeClient(
      { data: true, error: null },
      { count: AUDIT_PAGE_SIZE + 5, error: null },
      { data: [], error: null }
    )

    const result = await listAuditLog({}, 2)
    expect(result.total).toBe(AUDIT_PAGE_SIZE + 5)
    expect(result.totalPages).toBe(2)
    expect(builder.range).toHaveBeenCalledWith(
      AUDIT_PAGE_SIZE,
      AUDIT_PAGE_SIZE * 2 - 1
    )
  })

  it("sayfa üst sınırı aşılırsa boş ok sonucu döner", async () => {
    makeClient(
      { data: true, error: null },
      { count: 3, error: null },
      { data: null, error: null }
    )
    const result = await listAuditLog({}, 999_999_999)
    expect(result).toMatchObject({ status: "ok", items: [], totalPages: 1 })
  })
})
