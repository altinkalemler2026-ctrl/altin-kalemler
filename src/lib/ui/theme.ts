/**
 * Tema sistemi (Faz 12) — saf mantik modulu.
 *
 * Iki onayli tema vardir: "arena" (Altin Arena) ve "atolye" (Renkli
 * Atolye). Varsayilan tema Altin Arena'dir; kullanici tercihi yalniz
 * localStorage'da tutulur, DB degisikligi YOKTUR.
 *
 * Ilk acilista (paint oncesi) resim cakismasi yasanmamasi icin
 * `THEME_INIT_SCRIPT` kullanilir: script, bulundugu temali yuzeyin
 * (data-theme-surface) data-theme ozelligini localStorage degerine
 * gore gunceller. Gecersiz/degiskesici degerler yok sayilir.
 *
 * Bu dosyanin hem server hem client surecte calisabilmesi icin
 * `document`/`window`'a dogrudan erisim yoktur; `applyTheme` istemci
 * tarafinda cagrilir.
 */

export const THEME_STORAGE_KEY = "altin-kalemler:tema"

export const DEFAULT_THEME = "arena"

export const THEMES = ["arena", "atolye"] as const

export type Theme = (typeof THEMES)[number]

export function isTheme(value: unknown): value is Theme {
  return value === "arena" || value === "atolye"
}

/**
 * localStorage degerini guvenle okur. Storage yoksa, erisim hata
 * verirse ya da deger gecersizse varsayilan temayi doner.
 */
export function readStoredTheme(
  storage: Pick<Storage, "getItem"> | null | undefined = undefined
): Theme {
  if (!storage) return DEFAULT_THEME

  try {
    const value = storage.getItem(THEME_STORAGE_KEY)
    return isTheme(value) ? value : DEFAULT_THEME
  } catch {
    return DEFAULT_THEME
  }
}

export function persistTheme(
  theme: Theme,
  storage: Pick<Storage, "setItem"> | null | undefined = undefined
): void {
  if (!storage) return

  try {
    storage.setItem(THEME_STORAGE_KEY, theme)
  } catch {
    // Storage erisilemezse (gizli mod vb.) tercih saklanamaz; tema
    // yine de oturum boyunca gecerli kalir.
  }
}

/**
 * Tema degisikligini tum temali yuzeylere (data-theme-surface) uygular.
 * Yalnizca istemci tarafinda cagrilir.
 */
export function applyTheme(theme: Theme): void {
  if (typeof document === "undefined") return

  const surfaces = document.querySelectorAll<HTMLElement>("[data-theme-surface]")
  for (const surface of surfaces) {
    surface.setAttribute("data-theme", theme)
  }
}

/**
 * Paint oncesi calisan satir ici script. Ilk acilista localStorage'daki
 * temayi, icinde bulundugu temali yuzeye uygular (FOUC engeli).
 * `document.currentScript.parentElement` yaklasimiyla yuzeyi bulur;
 * script dogrudan React agacinda render edilmis olabilir.
 */
export const THEME_INIT_SCRIPT = `(function(){try{var k=${JSON.stringify(
  THEME_STORAGE_KEY
)};var v=window.localStorage.getItem(k);if(v!=="arena"&&v!=="atolye")return;var s=document.currentScript;var e=s?s.parentElement:null;if(e)e.setAttribute("data-theme",v)}catch(_){}})();`