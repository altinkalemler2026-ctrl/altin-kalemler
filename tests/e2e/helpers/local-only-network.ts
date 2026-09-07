import type { Page } from "@playwright/test"

const SCHEME_INSPECT = new Set(["http", "https", "ws", "wss"])

/**
 * LOCAL-ONLY network guard.
 *
 * Installs a request interceptor on `page` that only allows traffic to
 * `127.0.0.1` / `localhost` (any scheme in http/https/ws/wss) plus non-HTTP
 * schemes (data:, blob:, file:, ...). Any other hostname is ABORTED and
 * recorded so the test can fail. Only the blocked hostname is ever surfaced —
 * never the query string, headers, body, or any token.
 */
export function guardLocalOnly(page: Page, onBlocked: (host: string) => void): void {
  page.route("**/*", async (route) => {
    const raw = route.request().url()
    let url: URL
    try {
      url = new URL(raw)
    } catch {
      return route.continue()
    }

    const scheme = url.protocol.replace(/:$/, "")
    if (!SCHEME_INSPECT.has(scheme)) {
      return route.continue()
    }

    if (url.hostname === "127.0.0.1" || url.hostname === "localhost") {
      return route.continue()
    }

    onBlocked(url.hostname)
    return route.abort("blockedbyclient")
  })
}

/** Collect blocked remote hostnames on a page and return the accessor + the guard installer. */
export function installLocalOnlyGuard(page: Page): { blockedHosts: () => string[] } {
  const blocked = new Set<string>()
  guardLocalOnly(page, (host) => blocked.add(host))
  return { blockedHosts: () => Array.from(blocked) }
}
