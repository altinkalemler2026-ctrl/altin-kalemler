"use client"

import Link from "next/link"
import { useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"

export type AdminNavItem = {
  href: string
  title: string
}

// Tailwind `lg:` (1024px) ile aynı kırılım; mobil drawer yalnız buradan kapanır.
const DESKTOP_MEDIA_QUERY = "(min-width: 1024px)"

// Kırılım geçişinden sonra onarılacak odak hedefi.
type PendingFocus = "toggle" | "desktop-first-link"

// Odak, kırılıma bağlı hangi bölgede? Tarayıcı bir alanı gizlediğinde
// (display:none) odak gövdeye düşer ve focusin olayı çıkmaz; bu yüzden
// bölge yalnız gerçek focusin ile menü kapanışıyla değişir.
type FocusRegion = "drawer" | "trigger" | "desktop-nav" | "other"

// Kırılım onarımında odak halkası görünürlüğü: pencere boyutu değişimi
// fareyle yapılsa bile odak yeni görünürlüğe taşındığında kullanıcı
// nereye gittiğini görebilsin. `focusVisible` desteklemeyen tarayıcılar
// bu seçeneği yok sayar.
function focusWithRing(element: HTMLElement | null | undefined): void {
  if (!element) return
  element.focus({ focusVisible: true } as FocusOptions)
}

function isActive(pathname: string, href: string): boolean {
  // Yönetim ana sayfası yalnız birebir eşleşmede aktif; alt rotalar
  // (ör. /admin/questions) ana sayfayı aktif göstermez.
  if (href === "/admin") {
    return pathname === href
  }
  return pathname === href || pathname.startsWith(`${href}/`)
}

const DESKTOP_LINK_BASE =
  "flex min-h-11 shrink-0 items-center whitespace-nowrap rounded-xl px-3 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"

function desktopLinkClass(active: boolean): string {
  return active
    ? `${DESKTOP_LINK_BASE} bg-teal-700 text-white`
    : `${DESKTOP_LINK_BASE} text-gray-700 hover:bg-gray-100 hover:text-gray-900`
}

const MOBILE_LINK_BASE =
  "flex min-h-11 items-center rounded-xl px-3 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"

function mobileLinkClass(active: boolean): string {
  return active
    ? `${MOBILE_LINK_BASE} bg-teal-700 text-white`
    : `${MOBILE_LINK_BASE} text-gray-700 hover:bg-gray-100 hover:text-gray-900`
}

export default function AdminNav({
  items,
  userLabel,
}: {
  items: AdminNavItem[]
  userLabel: string
}) {
  const pathname = usePathname()
  const [menuOpen, setMenuOpen] = useState(false)
  const [viewportEpoch, setViewportEpoch] = useState(0)
  const toggleRef = useRef<HTMLButtonElement>(null)
  const panelRef = useRef<HTMLElement>(null)
  const desktopNavRef = useRef<HTMLElement>(null)
  const menuOpenRef = useRef(false)
  const pendingFocusRef = useRef<PendingFocus | null>(null)
  const focusTimerRef = useRef<number | null>(null)
  const focusRegionRef = useRef<FocusRegion>("other")

  useEffect(() => {
    menuOpenRef.current = menuOpen
  }, [menuOpen])

  // Odak bölgesi izleyicisi: panel/tetikleyici/masaüstü bağlantısı gerçekten
  // odaklandığında bölge yazılır. Odak, gizlenen alandan gövdeye
  // düştüğünde focusin olayı çıkmadığı için bölge bozulmaz.
  useEffect(() => {
    function onFocusIn(event: FocusEvent) {
      const target = event.target as HTMLElement | null
      if (!target) return

      if (toggleRef.current === target) {
        focusRegionRef.current = "trigger"
      } else if (panelRef.current?.contains(target)) {
        focusRegionRef.current = "drawer"
      } else if (desktopNavRef.current?.contains(target)) {
        focusRegionRef.current = "desktop-nav"
      } else {
        focusRegionRef.current = "other"
      }
    }

    document.addEventListener("focusin", onFocusIn, true)
    return () => {
      document.removeEventListener("focusin", onFocusIn, true)
    }
  }, [])

  // Bileşen unmount olursa askıdaki odak zamanlayıcısı iptal edilir.
  useEffect(() => {
    return () => {
      if (focusTimerRef.current !== null) {
        window.clearTimeout(focusTimerRef.current)
      }
    }
  }, [])

  // Açıkken: Esc kapar (odak anında düğmeye döner), dış tıklama kapar
  // (odak tıklama varsayılanı tarafından ezilmesin diye tıklama bittikten
  // sonra düğmeye döner). Panel içindeki bağlantıya tıklanınca menü yalnız
  // kapanır; odak gezinme akışında kalır.
  useEffect(() => {
    if (!menuOpen) return

    function closeMenu(mode: "now" | "after-click") {
      focusRegionRef.current = "other"
      setMenuOpen(false)

      if (mode === "now") {
        toggleRef.current?.focus()
        return
      }

      if (focusTimerRef.current !== null) {
        window.clearTimeout(focusTimerRef.current)
      }
      focusTimerRef.current = window.setTimeout(() => {
        focusTimerRef.current = null
        toggleRef.current?.focus()
      }, 0)
    }

    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault()
        closeMenu("now")
      }
    }

    function onPointerDown(event: PointerEvent) {
      const target = event.target as Node
      if (panelRef.current?.contains(target)) return
      if (toggleRef.current?.contains(target)) return
      closeMenu("after-click")
    }

    document.addEventListener("keydown", onKeyDown)
    document.addEventListener("pointerdown", onPointerDown)
    return () => {
      document.removeEventListener("keydown", onKeyDown)
      document.removeEventListener("pointerdown", onPointerDown)
    }
  }, [menuOpen])

  // Açılışta odak paneldeki ilk bağlantıya taşınır.
  useEffect(() => {
    if (menuOpen) {
      panelRef.current
        ?.querySelector<HTMLAnchorElement>("a")
        ?.focus()
    }
  }, [menuOpen])

  // Kırılım çaprazlaması (F1): masaüstüne geçişte mobil panel güvenli
  // biçimde kapanır (drawer/overlay semantiği masaüstünde kalmaz), mobil
  // dönüşte masaüstü menüdeki odak tetikleyiciye taşınır. Yalnız odak,
  // kaybolacağı alandaysa (panel/tetikleyici/masaüstü bağlantı) onarılır.
  useEffect(() => {
    if (
      typeof window === "undefined" ||
      typeof window.matchMedia !== "function"
    ) {
      return
    }

    const mediaQuery = window.matchMedia(DESKTOP_MEDIA_QUERY)
    let lastKnownDesktop = mediaQuery.matches

    function onChange(event: MediaQueryListEvent) {
      const nowDesktop = event.matches
      if (nowDesktop === lastKnownDesktop) return
      lastKnownDesktop = nowDesktop

      const region = focusRegionRef.current
      // Bölge izlemesi, gizleme kaynaklı odak düşüşünü (odak gövdeye
      // iner, focusin çıkmaz) görmeye devam eder; DOM içerimi kontrolü
      // edemez çünkü panel o an çoktan kaldırılmış olabilir.
      const focusWillBeLost = nowDesktop
        ? region === "drawer" || region === "trigger"
        : region === "desktop-nav"

      if (nowDesktop && menuOpenRef.current) {
        setMenuOpen(false)
      }

      if (focusWillBeLost) {
        pendingFocusRef.current = nowDesktop
          ? "desktop-first-link"
          : "toggle"
        setViewportEpoch((epoch) => epoch + 1)
      }
    }

    mediaQuery.addEventListener("change", onChange)
    return () => {
      mediaQuery.removeEventListener("change", onChange)
    }
  }, [])

  // Kırılım geçişi render'ı tamamladıktan sonra odak onarımı. Odak
  // hedefi, çaprazlama anında odak kaybolacak alandaysa (panel/tetikleyici/
  // masaüstü bağlantı) seçilmiştir; burada yalnızca yeni görünürlükteki
  // hedefe gidilir.
  useEffect(() => {
    if (viewportEpoch === 0) return

    const pending = pendingFocusRef.current
    pendingFocusRef.current = null
    if (!pending) return

    if (pending === "desktop-first-link") {
      focusWithRing(
        desktopNavRef.current?.querySelector<HTMLAnchorElement>("a"),
      )
    } else {
      focusWithRing(toggleRef.current)
    }
  }, [viewportEpoch])

  return (
    <header className="sticky top-0 z-40 border-b border-gray-200 bg-white">
      <div className="mx-auto flex w-full max-w-7xl items-center justify-between gap-4 px-4 py-3">
        <Link
          href="/admin"
          aria-current={
            isActive(pathname, "/admin") ? "page" : undefined
          }
          className="flex min-h-11 shrink-0 items-center rounded-xl text-base font-bold text-gray-900 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
        >
          Altın Kalemler
          <span className="ml-2 rounded-lg bg-navy-100 px-2 py-0.5 text-xs font-semibold text-navy-900">
            Yönetim
          </span>
        </Link>

        <div className="flex min-w-0 items-center gap-3">
          <span
            aria-label={`Giriş yapan: ${userLabel}`}
            className="hidden truncate text-sm text-gray-600 sm:inline"
          >
            {userLabel}
          </span>

          <button
            ref={toggleRef}
            type="button"
            aria-haspopup="true"
            aria-expanded={menuOpen}
            aria-controls="admin-nav-panel"
            onClick={() => setMenuOpen((open) => !open)}
            className="flex min-h-11 min-w-11 items-center justify-center rounded-xl border border-gray-300 px-3 text-sm font-medium text-gray-700 transition hover:bg-gray-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700 lg:hidden"
          >
            {menuOpen ? "Kapat" : "Menü"}
          </button>
        </div>
      </div>

      <nav
        ref={desktopNavRef}
        aria-label="Yönetici menüsü"
        className="hidden border-t border-gray-100 lg:block"
      >
        <ul className="mx-auto flex w-full max-w-7xl items-center gap-1 overflow-x-auto px-4 py-2">
          {items.map((item) => {
            const active = isActive(pathname, item.href)

            return (
              <li key={item.href} className="shrink-0">
                <Link
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  className={desktopLinkClass(active)}
                >
                  {item.title}
                </Link>
              </li>
            )
          })}
        </ul>
      </nav>

      {menuOpen && (
        <nav
          id="admin-nav-panel"
          ref={panelRef}
          aria-label="Yönetici menüsü"
          className="border-t border-gray-100 bg-white lg:hidden"
        >
          <div className="px-4 pt-3 sm:hidden">
            <p className="truncate text-sm text-gray-600">{userLabel}</p>
          </div>
          <ul className="flex flex-col gap-1 px-4 py-3">
            {items.map((item) => {
              const active = isActive(pathname, item.href)

              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    onClick={() => {
                      focusRegionRef.current = "other"
                      setMenuOpen(false)
                    }}
                    className={mobileLinkClass(active)}
                  >
                    {item.title}
                  </Link>
                </li>
              )
            })}
          </ul>
        </nav>
      )}
    </header>
  )
}