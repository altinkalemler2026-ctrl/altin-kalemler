"use client"

import {
  createContext,
  useCallback,
  useContext,
  useSyncExternalStore,
} from "react"

import {
  DEFAULT_THEME,
  THEME_INIT_SCRIPT,
  applyTheme,
  persistTheme,
  readStoredTheme,
} from "@/lib/ui/theme"
import type { Theme } from "@/lib/ui/theme"

interface ThemeContextValue {
  theme: Theme
  setTheme: (theme: Theme) => void
}

const ThemeContext = createContext<ThemeContextValue>({
  theme: DEFAULT_THEME,
  setTheme: () => {},
})

const THEME_CHANGE_EVENT = "altin-kalemler:tema-change"

function subscribe(onStoreChange: () => void): () => void {
  const handle = () => onStoreChange()
  window.addEventListener("storage", handle)
  window.addEventListener(THEME_CHANGE_EVENT, handle)
  return () => {
    window.removeEventListener("storage", handle)
    window.removeEventListener(THEME_CHANGE_EVENT, handle)
  }
}

function getThemeSnapshot(): Theme {
  return readStoredTheme(window.localStorage)
}

/** Server/ilk render'da daima varsayilan tema kullanilir (hydration uyumu). */
function getServerThemeSnapshot(): Theme {
  return DEFAULT_THEME
}

export const publishThemeChange = (): void => {
  window.dispatchEvent(new Event(THEME_CHANGE_EVENT))
}

/**
 * Ogrenci alani tema baglami (Faz 12). Tema degisikligi server'a
 * gitmez; localStorage'a yazilir ve tum temali yuzeylerin data-theme
 * ozelligi aninda guncellenir.
 *
 * Gercek tema localStorage'dan dis kaynak olarak okunur
 * (useSyncExternalStore); bu, hydration sirasinda SSR uyumlu ilk
 * render kullanir, ardindan fark varsa gunceller. Paint oncesi flash
 * icin satir ici script (THEME_INIT_SCRIPT) temali yuzeyleri dogrudan
 * gunceller; yuzeyler suppressHydrationWarning tasir.
 */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const theme = useSyncExternalStore(
    subscribe,
    getThemeSnapshot,
    getServerThemeSnapshot
  )

  const setTheme = useCallback((next: Theme) => {
    applyTheme(next)
    persistTheme(next, window.localStorage)
    publishThemeChange()
  }, [])

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}

export function useTheme(): ThemeContextValue {
  return useContext(ThemeContext)
}

/** no-op subscribe: hidrasyon guard'i icin degisiklik beklenmez. */
function subscribeNever(onStoreChange: () => void): () => void {
  void onStoreChange
  return () => {}
}

/**
 * Paint oncesi tema script'inin yalniz sunucu/hidrasyon render'inda
 * uretilmesini saglar. React, istemci tarafinda (yumusak gezinti)
 * olusturdugu <script> ogelerini calistirmaz ve bu durumda dev modda
 * uyarir; script bu yuzden yalniz SSR HTML'in icinde yer alir, istemci
 * monte edislerinde uretilmez.
 */
function useIsServerOrHydrating(): boolean {
  return useSyncExternalStore(
    subscribeNever,
    () => false,
    () => true
  )
}

/**
 * Temali yuzey sarmalayici. `data-theme-surface` ozelligi, tema
 * degisince applyTheme ile hemen guncellenir. Paint oncesi tema icin
 * satir ici script yalniz ilk (SSR/hidrasyon) render'da eklenir.
 */
export function ThemeSurface({
  className,
  children,
}: {
  className?: string
  children: React.ReactNode
}) {
  const { theme } = useTheme()
  const isServerOrHydrating = useIsServerOrHydrating()

  return (
    <div
      data-theme-surface
      data-theme={theme}
      suppressHydrationWarning
      className={className}
    >
      {isServerOrHydrating && (
        <script dangerouslySetInnerHTML={{ __html: THEME_INIT_SCRIPT }} />
      )}
      {children}
    </div>
  )
}