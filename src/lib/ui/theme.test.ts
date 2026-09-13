/**
 * Tema sistemi saf mantik testleri (Faz 12).
 *
 * - Varsayilan tema Altin Arena'dir; tercih yalniz localStorage'da.
 * - Gecersiz/erisilemez storage degeri varsayilana doner (yiVAP yok).
 * - THEME_INIT_SCRIPT yalniz onayli iki temayi uygular.
 * - applyTheme yalniz temali yuzeyleri gunceller; DB/token degismez.
 */

import { describe, expect, it } from "vitest"

import {
  DEFAULT_THEME,
  THEME_INIT_SCRIPT,
  THEME_STORAGE_KEY,
  THEMES,
  applyTheme,
  isTheme,
  persistTheme,
  readStoredTheme,
} from "./theme"

function fakeStorage(
  values: Record<string, string> = {}
): Pick<Storage, "getItem" | "setItem"> {
  const store = new Map(Object.entries(values))
  return {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => void store.set(key, value),
  }
}

describe("theme", () => {
  it("varsayilan tema Altin Arena'dir; yalniz iki onayli tema vardir", () => {
    expect(DEFAULT_THEME).toBe("arena")
    expect(THEMES).toEqual(["arena", "atolye"])
    expect(isTheme("arena")).toBe(true)
    expect(isTheme("atolye")).toBe(true)
    expect(isTheme("space")).toBe(false)
    expect(isTheme(null)).toBe(false)
  })

  it("THEME_INIT_SCRIPT yalniz onayli iki tema ve kayit anahtarini kullanir", () => {
    expect(THEME_INIT_SCRIPT).toContain(THEME_STORAGE_KEY)
    expect(THEME_INIT_SCRIPT).toContain('"arena"')
    expect(THEME_INIT_SCRIPT).toContain('"atolye"')
    expect(THEME_INIT_SCRIPT).not.toContain("dark")
  })

  it("storage yoksa varsayilan tema doner", () => {
    expect(readStoredTheme()).toBe("arena")
    expect(readStoredTheme(undefined)).toBe("arena")
  })

  it("gecerli kayitli tema okunur", () => {
    expect(readStoredTheme(fakeStorage({ [THEME_STORAGE_KEY]: "atolye" }))).toBe(
      "atolye"
    )
  })

  it("gecersiz kayit varsayilana doner", () => {
    expect(
      readStoredTheme(fakeStorage({ [THEME_STORAGE_KEY]: "uzay" }))
    ).toBe("arena")
  })

  it("storage hata verdiginde varsayilana duser (cokme yok)", () => {
    const broken: Pick<Storage, "getItem" | "setItem"> = {
      getItem: () => {
        throw new Error("SecurityError")
      },
      setItem: () => {
        throw new Error("SecurityError")
      },
    }
    expect(readStoredTheme(broken)).toBe("arena")
    expect(() => persistTheme("atolye", broken)).not.toThrow()
  })

  it("persistTheme tercihi yazar", () => {
    const storage = fakeStorage()
    persistTheme("atolye", storage)
    expect(storage.getItem(THEME_STORAGE_KEY)).toBe("atolye")
  })

  it("applyTheme yalniz temali yuzeyleri gunceller (FOUC onleyici scriptle uyumlu)", () => {
    const themed = document.createElement("div")
    themed.setAttribute("data-theme-surface", "")
    themed.setAttribute("data-theme", "arena")
    const plain = document.createElement("div")
    document.body.append(themed, plain)

    applyTheme("atolye")

    expect(themed.getAttribute("data-theme")).toBe("atolye")
    expect(plain.hasAttribute("data-theme")).toBe(false)

    themed.remove()
    plain.remove()
  })
})