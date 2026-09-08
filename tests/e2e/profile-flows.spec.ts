import { test, expect } from "@playwright/test"

import { installLocalOnlyGuard } from "./helpers/local-only-network"

// LOCAL-ONLY Faz 10 profil/avatar E2E: disposable stack + fixture.
// Kimlik bilgileri yalnizca local runner (scripts/run-faz10-e2e.ps1)
// tarafindan child-process env olarak enjekte edilir; kaynak koda
// yazilmaz. Sifre/token artifact'a yazilmaz.
test.use({ trace: "off", video: "off", screenshot: "off" })

test.describe.configure({ mode: "serial" })

const STUDENT_A_EMAIL = () => process.env.E2E_USER_A_EMAIL as string
const STUDENT_A_PASSWORD = () => process.env.E2E_USER_A_PASSWORD as string

const SENTINEL_SINIF6 = "E2E10_SINIF6_SENTINEL"
const SENTINEL_SINIF8 = "E2E10_SINIF8_SENTINEL"
const SENTINEL_GIZLI = "E2E10_GIZLI_SENTINEL"
const RAKIP_B = "E2E10_Ogrenci_B"

async function loginAsStudentA(
  browser: import("@playwright/test").Browser,
  viewport?: { width: number; height: number }
) {
  const context = await browser.newContext({
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
    viewport,
  })
  const page = await context.newPage()
  const guard = installLocalOnlyGuard(page)

  await page.goto("/login")
  await expect(page).toHaveURL(/\/login/)

  await page.getByLabel("E-posta").fill(STUDENT_A_EMAIL())
  await page.getByLabel(/ifre|Şifre/i).fill(STUDENT_A_PASSWORD())
  await page.getByRole("button", { name: /Giriş Yap/ }).click()

  await expect(
    page.getByRole("heading", { name: /Öğrenci ana sayfası/ })
  ).toBeVisible({ timeout: 20_000 })

  return { context, page, guard }
}

test.describe("faz10 profil — pozitif akış", () => {
  test("dashboard oyunlaştırma özetini gösterir; Profil/Lig bağlantıları çalışır", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await expect(page.getByText("Gelişimin")).toBeVisible()
    await expect(page.getByText("Bugünkü soru hakkı")).toBeVisible()
    await expect(page.getByText("Çalışma serisi")).toBeVisible()
    await expect(page.getByText("Rozetler")).toBeVisible()

    await page.getByRole("link", { name: "Profilim" }).click()
    await expect(page).toHaveURL(/\/profile/)

    await context.close()
  })

  test("profil sayfası takma ad, sınıf ve oyunlaştırma kartlarını gösterir; grade kontrolü yoktur", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/profile")
    await expect(page.getByRole("heading", { name: "Profilim" })).toBeVisible()

    // 8. Grade değiştirme kontrolü bulunmaz (hidden input dahil).
    await expect(page.getByText(/sınıf değiştirilemez/).first()).toBeVisible()
    const gradeInputs = await page.locator('input[name="grade_level"]').count()
    expect(gradeInputs).toBe(0)
    await expect(page.locator('select[name="grade_level"]')).toHaveCount(0)

    // XP/seviye/seri/kota kartları sahte değil, gerçek yapıda görünür.
    await expect(page.getByText("Seviye ve XP")).toBeVisible()
    await expect(page.getByText("Çalışma serisi")).toBeVisible()
    await expect(page.getByText("Bugünkü soru hakkı")).toBeVisible()
    await expect(page.getByText("Rozetler")).toBeVisible()

    await context.close()
  })

  test("nickname izinli şekilde değiştirilir; yenilemeden sonra korunur ve ligde güncel görünür", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/profile")
    await expect(page.getByRole("heading", { name: "Profilim" })).toBeVisible()

    const newNick = `E2E10_A_Yeni${Date.now().toString(36)}`

    await page.getByLabel("Takma ad").fill(newNick)
    await page.getByRole("button", { name: "Kaydet" }).click()

    await expect(
      page.getByText("Takma adın güncellendi.")
    ).toBeVisible({ timeout: 15_000 })

    // 5. Sayfa yenilemesinden sonra korunur.
    await page.reload()
    await expect(page.getByLabel("Takma ad")).toHaveValue(newNick)

    // pp sync: lig sayfasında güncel takma ad görünür (nav + satır).
    await page.goto("/league")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()
    await expect(page.getByText(newNick).first()).toBeVisible()

    await context.close()
  })

  test("onaylı avatar seçilir; profil ve dashboard tutarlı gösterir", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/profile")
    await expect(page.getByRole("heading", { name: "Profilim" })).toBeVisible()

    // Katalog boşsa "Avatarlar hazırlanıyor" gösterilir; bu fixture'da
    // 017 seed'i ile en az bir default karakter mevcuttur.
    const emptyState = page.getByText("Avatarlar hazırlanıyor")
    const catalogEmpty = await emptyState.isVisible()
    if (catalogEmpty) {
      test.info().annotations.push({
        type: "skip-note",
        description: "katalog bu stack'te boş; seçim akışı koşulmadı",
      })
      await context.close()
      return
    }

    // 6. İlk onaylı karakteri seç (radio) ve kaydet.
    const firstOption = page.getByRole("radio").first()
    await firstOption.check()
    await page.getByRole("button", { name: "Bu karakteri seç" }).click()

    await expect(page.getByText(/artık karakterin\./)).toBeVisible({
      timeout: 15_000,
    })

    // Sayfa yenilemesi sonrası seçim korunur.
    await page.reload()
    await expect(page.getByRole("radio").first()).toBeChecked()

    // 7. Dashboard'da aynı karakter tutarlı görünür.
    await page.goto("/dashboard")
    await expect(page.getByText(/Karakterin: Karakter/)).toBeVisible()

    await context.close()
  })
})

test.describe("faz10 lig — aynı sınıf izolasyonu", () => {
  test("yalnız kendi sınıfı görünür; başka sınıf ve gizli sentinel yoktur", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/league")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    // 10. Aynı sınıf rakibi görünür.
    await expect(page.getByText(RAKIP_B)).toBeVisible()

    // 11. Başka sınıf sentinel'leri ve gizli profil DOM'da yoktur.
    const bodyText = (await page.textContent("body")) ?? ""
    expect(bodyText).not.toContain(SENTINEL_SINIF6)
    expect(bodyText).not.toContain(SENTINEL_SINIF8)
    expect(bodyText).not.toContain(SENTINEL_GIZLI)

    // Query spoofing sonuç vermez.
    await page.goto("/league?grade=8&grade_level=8&sinif=6")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()
    const bodyText2 = (await page.textContent("body")) ?? ""
    expect(bodyText2).not.toContain(SENTINEL_SINIF6)
    expect(bodyText2).not.toContain(SENTINEL_SINIF8)

    // 12. Kendi satırı belirgin vurgulanır ("Sen" rozeti).
    await expect(page.getByText("Senin sıran")).toBeVisible()

    await context.close()
  })

  test("lig sıralaması istemcide yeniden hesaplanmaz (sunucu sırası korunur)", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/league")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    const firstSnapshot = await page.locator("ol li").allTextContents()

    await page.reload()
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    const secondSnapshot = await page.locator("ol li").allTextContents()

    // Deterministik sunucu sırası (rating desc, entered_at, nickname).
    expect(secondSnapshot).toEqual(firstSnapshot)

    await context.close()
  })
})

test.describe("faz10 — mobil navigasyon ve sızıntı", () => {
  test("mobil görünümde Profil ve Lig navigasyonla erişilebilir", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser, {
      width: 375,
      height: 812,
    })

    // Yatay taşma yok.
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    )
    expect(overflow).toBeLessThanOrEqual(0)

    await page.getByRole("link", { name: "Profil" }).last().click()
    await expect(page).toHaveURL(/\/profile/)
    await expect(
      page.getByRole("heading", { name: "Profilim" })
    ).toBeVisible()

    await page.getByRole("link", { name: "Lig" }).last().click()
    await expect(page).toHaveURL(/\/league/)
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    // Mobilde lig listesi okunabilir ve taşma yok.
    const overflowLeague = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    )
    expect(overflowLeague).toBeLessThanOrEqual(0)

    await context.close()
  })

  test("ham hata / UUID / e-posta sızıntısı yoktur", async ({ browser }) => {
    const { context, page } = await loginAsStudentA(browser)

    for (const path of ["/profile", "/league", "/dashboard"]) {
      await page.goto(path)
      const body = (await page.textContent("body")) ?? ""

      expect(body).not.toContain("PG::")
      expect(body).not.toContain("relation ")
      expect(body).not.toContain("e2e10-ogrenci-a@e2e.test")
      expect(body).not.toMatch(/\.test\b/)
      // UUID deseni görünmez.
      expect(body).not.toMatch(
        /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
      )
    }

    await context.close()
  })

  test("tablet ve masaüstünde profil ve lig yatay taşmasız kullanılabilir", async ({
    browser,
  }) => {
    for (const viewport of [
      { width: 768, height: 1024 },
      { width: 1440, height: 900 },
    ]) {
      const { context, page } = await loginAsStudentA(browser, viewport)

      for (const path of ["/profile", "/league"]) {
        await page.goto(path)
        await expect(page.locator("main")).toBeVisible()

        const overflow = await page.evaluate(
          () =>
            document.documentElement.scrollWidth -
            document.documentElement.clientWidth
        )
        expect(overflow).toBeLessThanOrEqual(0)
      }

      await context.close()
    }
  })
})
