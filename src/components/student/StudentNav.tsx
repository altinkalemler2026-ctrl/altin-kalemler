"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"

const NAV_ITEMS = [
  { href: "/dashboard", label: "Ana Sayfa" },
  { href: "/training", label: "Antrenman" },
  { href: "/competition", label: "Yarışma" },
  { href: "/league", label: "Lig" },
  { href: "/profile", label: "Profil" },
] as const

function isActive(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`)
}

const LINK_CLASS =
  "flex min-h-11 min-w-11 items-center justify-center rounded-xl text-sm font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"

function linkClass(active: boolean): string {
  return active
    ? `${LINK_CLASS} bg-gray-900 text-white`
    : `${LINK_CLASS} text-gray-700 hover:bg-gray-100`
}

export default function StudentNav({
  nickname,
  logout,
}: {
  nickname: string
  logout: () => Promise<void>
}) {
  const pathname = usePathname()

  return (
    <>
      <header className="sticky top-0 z-40 border-b border-gray-200 bg-white">
        <div className="mx-auto flex w-full max-w-5xl items-center justify-between gap-4 px-4 py-3">
          <div className="flex min-w-0 items-center gap-3">
            <span className="text-base font-bold text-gray-900">
              Altın Kalemler
            </span>

            <span
              className="hidden truncate text-sm text-gray-600 sm:inline"
              aria-label={`Giriş yapan: ${nickname}`}
            >
              @{nickname}
            </span>
          </div>

          <nav
            aria-label="Öğrenci menüsü"
            className="hidden items-center gap-1 sm:flex"
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

            <form action={logout}>
              <button
                type="submit"
                className="min-h-11 rounded-xl px-3 text-sm font-medium text-red-700 transition hover:bg-red-50 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900"
              >
                Çıkış Yap
              </button>
            </form>
          </nav>
        </div>
      </header>

      <nav
        aria-label="Öğrenci menüsü"
        className="fixed inset-x-0 bottom-0 z-40 border-t border-gray-200 bg-white pb-[env(safe-area-inset-bottom)] sm:hidden"
      >
        <div className="flex items-stretch justify-around px-1 py-1">
          {NAV_ITEMS.map((item) => {
            const active = isActive(pathname, item.href)

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={`flex flex-1 flex-col items-center gap-0.5 rounded-lg px-1 py-1.5 text-[11px] font-medium transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-gray-900 ${
                  active ? "text-gray-900" : "text-gray-500"
                }`}
              >
                <span
                  aria-hidden="true"
                  className={`h-1.5 w-6 rounded-full ${
                    active ? "bg-gray-900" : "bg-transparent"
                  }`}
                />
                {item.label}
              </Link>
            )
          })}
        </div>
      </nav>
    </>
  )
}
