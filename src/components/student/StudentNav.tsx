"use client"

import Link from "next/link"
import { useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"

import { ThemeSurface } from "@/lib/ui/theme-context"

const NAV_ITEMS = [
  { href: "/dashboard", label: "Ana Sayfa" },
  { href: "/training", label: "Antrenman" },
  { href: "/ilerleme", label: "İlerleme" },
  { href: "/tekrar", label: "Tekrar" },
  { href: "/competition", label: "Yarışma" },
  { href: "/league", label: "Lig" },
  { href: "/profile", label: "Profil" },
] as const

/** Mobil alt menüde doğrudan görünen birincil öğeler. */
const MOBILE_PRIMARY_ITEMS = NAV_ITEMS.filter(
  (item) => item.href !== "/ilerleme" && item.href !== "/tekrar"
)

/** Mobil alt menüde "Diğer" başlığı altında toplanan öğeler. */
const MORE_ITEMS = [
  { href: "/ilerleme", label: "İlerleme" },
  { href: "/tekrar", label: "Tekrar" },
] as const

function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`)
}

const LINK_CLASS =
  "flex min-h-11 min-w-11 shrink-0 items-center justify-center whitespace-nowrap rounded-xl px-2 text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"

function linkClass(active: boolean): string {
  return active
    ? `${LINK_CLASS} bg-navy-800 text-white`
    : `${LINK_CLASS} text-ink hover:bg-surface-muted`
}

const MOBILE_LINK_BASE =
  "flex min-h-11 flex-col items-center justify-center gap-0.5 rounded-lg px-0.5 py-1 text-xs font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"

function mobileLinkClass(active: boolean): string {
  return `${MOBILE_LINK_BASE} min-w-0 flex-1 ${
    active ? "text-ink" : "text-ink-muted"
  }`
}

function IndicatorBar({ active }: { active: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={`h-1 w-5 rounded-full ${
        active ? "bg-ink" : "bg-transparent"
      }`}
    />
  )
}

export default function StudentNav({
  nickname,
  logout,
}: {
  nickname: string
  logout: () => Promise<void>
}) {
  const pathname = usePathname()
  const [moreOpen, setMoreOpen] = useState(false)
  const moreButtonRef = useRef<HTMLButtonElement>(null)
  const morePanelRef = useRef<HTMLDivElement>(null)

  // Açıkken: Esc kapar (odak düğmeye döner), dış tıklama kapar.
  // Panel içindeki bir bağlantıya tıklanınca da onClick ile kapanır.
  useEffect(() => {
    if (!moreOpen) return

    function closeMenu() {
      setMoreOpen(false)
      moreButtonRef.current?.focus()
    }

    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault()
        closeMenu()
      }
    }

    function onPointerDown(event: PointerEvent) {
      const target = event.target as Node
      if (morePanelRef.current?.contains(target)) return
      if (moreButtonRef.current?.contains(target)) return
      closeMenu()
    }

    document.addEventListener("keydown", onKeyDown)
    document.addEventListener("pointerdown", onPointerDown)
    return () => {
      document.removeEventListener("keydown", onKeyDown)
      document.removeEventListener("pointerdown", onPointerDown)
    }
  }, [moreOpen])

  // Açılışta odak paneldeki ilk bağlantıya taşınır.
  useEffect(() => {
    if (moreOpen) {
      morePanelRef.current
        ?.querySelector<HTMLAnchorElement>("a")
        ?.focus()
    }
  }, [moreOpen])

  const isMoreActive = MORE_ITEMS.some((item) =>
    isActive(pathname, item.href)
  )

  return (
    <ThemeSurface>
      <header className="sticky top-0 z-40 border-b border-border bg-surface">
        <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-3">
          <div className="flex min-w-0 items-center gap-3">
            <span className="text-base font-bold text-ink">
              Altın Kalemler
            </span>

            <span
              className="hidden truncate text-sm text-ink-muted md:inline"
              aria-label={`Giriş yapan: ${nickname}`}
            >
              @{nickname}
            </span>
          </div>

          <nav
            aria-label="Öğrenci menüsü"
            className="hidden items-center gap-2 overflow-x-auto sm:flex"
          >
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                aria-current={isActive(pathname, item.href) ? "page" : undefined}
                className={linkClass(isActive(pathname, item.href))}
              >
                {item.label}
              </Link>
            ))}

            <form action={logout} className="shrink-0">
              <button
                type="submit"
                className="min-h-11 rounded-xl px-3 text-sm font-medium text-danger-700 transition hover:bg-danger-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
              >
                Çıkış Yap
              </button>
            </form>
          </nav>
        </div>
      </header>

      <nav
        aria-label="Öğrenci menüsü"
        className="fixed inset-x-0 bottom-0 z-40 border-t border-border bg-surface pb-[env(safe-area-inset-bottom)] sm:hidden"
      >
        <div className="flex items-stretch justify-around px-0.5 py-1">
          {MOBILE_PRIMARY_ITEMS.map((item) => {
            const active = isActive(pathname, item.href)

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={mobileLinkClass(active)}
              >
                <IndicatorBar active={active} />
                <span className="flex min-h-8 items-center">{item.label}</span>
              </Link>
            )
          })}

          <div className="relative flex min-w-0 flex-1">
            <button
              ref={moreButtonRef}
              type="button"
              aria-haspopup="true"
              aria-expanded={moreOpen}
              aria-controls="student-more-menu"
              onClick={() => setMoreOpen((open) => !open)}
              className={`${MOBILE_LINK_BASE} w-full ${
                isMoreActive ? "text-ink" : "text-ink-muted"
              }`}
            >
              <IndicatorBar active={isMoreActive} />
              <span className="flex min-h-8 items-center">Diğer</span>
            </button>

            {moreOpen && (
              <div
                id="student-more-menu"
                ref={morePanelRef}
                className="absolute bottom-full right-0 z-50 mb-2 w-48 overflow-hidden rounded-2xl border border-border bg-surface p-1 shadow-modal"
              >
                {MORE_ITEMS.map((item) => {
                  const active = isActive(pathname, item.href)

                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      aria-current={active ? "page" : undefined}
                      onClick={() => setMoreOpen(false)}
                      className="flex min-h-11 items-center rounded-xl px-3 text-sm font-medium text-ink transition hover:bg-surface-muted focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-700"
                    >
                      {item.label}
                    </Link>
                  )
                })}
              </div>
            )}
          </div>
        </div>
      </nav>
    </ThemeSurface>
  )
}