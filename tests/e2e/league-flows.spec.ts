import { test, expect } from "@playwright/test"

import { installLocalOnlyGuard } from "./helpers/local-only-network"

// LOCAL-ONLY Faz 8 lig E2E: disposable stack + disposable fixture.
// Kimlik bilgileri yalnizca local runner (scripts/run-faz8-e2e.ps1)
// tarafindan child-process env olarak enjekte edilir; kaynak koda
// yazilmaz. Sifre/token artifact'a yazilmaz.
test.use({ trace: "off", video: "off", screenshot: "off" })

test.describe.configure({ mode: "serial" })

const STUDENT_A_EMAIL = () => process.env.E2E_LEAGUE_A_EMAIL as string
const STUDENT_A_PASSWORD = () => process.env.E2E_LEAGUE_A_PASSWORD as string

const SENTINEL_SINIF6 = "E2E8_SINIF6_SENTINEL"
const SENTINEL_SINIF8 = "E2E8_SINIF8_SENTINEL"
const SENTINEL_GIZLI = "E2E8_GIZLI_SENTINEL"

async function loginAsStudentA(
  browser: import("@playwright/test").Browser
) {
  const context = await browser.newContext({
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
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

test.describe("faz8 lig — pozitif akış", () => {
  test("grade 7 öğrenci /league sayfasını görür (başlık, lig, sıra)", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.getByRole("link", { name: "Lig" }).click()
    await expect(page).toHaveURL(/\/league/)

    // 3. Baslik gercek grade'e gore: 7. Sinif Ligi.
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    // 4. Kendi lig ve rating bilgisi.
    await expect(page.getByText("Lig rating:")).toBeVisible()
    await expect(page.getByText("64").first()).toBeVisible()
    await expect(page.getByText(/Bronz/).first()).toBeVisible()

    // 5. Kendi sira karti (rank=2: B 88'de birinci).
    await expect(page.getByText("Senin sıran")).toBeVisible()

    // 6. Ayni sinif gorunur ogrenci listede.
    await expect(page.getByText("E2E8_Ogrenci_B")).toBeVisible()

    // 15. Ham DB hata metni yok.
    const bodyText = await page.textContent("body")
    expect(bodyText).not.toContain("PG::")
    expect(bodyText).not.toContain("relation")

    await context.close()
  })

  test("sayfa yenilenince siralama deterministik kalir", async ({
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

    expect(secondSnapshot).toEqual(firstSnapshot)
    expect(secondSnapshot[0]).toContain("E2E8_Ogrenci_B")
    expect(secondSnapshot[1]).toContain("E2E8_Ogrenci_A")

    await context.close()
  })
})

test.describe("faz8 lig — negatif akış", () => {
  test("başka sınıf sentinelleri ve gizli profil DOM'da görünmez", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/league")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    // 8. Grade 6 sentinel DOM'da yok.
    await expect(page.getByText(SENTINEL_SINIF6)).toHaveCount(0)
    // 9. Grade 8 sentinel DOM'da yok.
    await expect(page.getByText(SENTINEL_SINIF8)).toHaveCount(0)
    // 10. Grade 7 gizli profil DOM'da yok.
    await expect(page.getByText(SENTINEL_GIZLI)).toHaveCount(0)

    const bodyText = await page.textContent("body")
    expect(bodyText).not.toContain(SENTINEL_SINIF6)
    expect(bodyText).not.toContain(SENTINEL_SINIF8)
    expect(bodyText).not.toContain(SENTINEL_GIZLI)

    await context.close()
  })

  test("sınıf/okul seçici yoktur; okul sıralaması yoktur", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/league")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    // 11. Sinif secici yok.
    await expect(page.getByRole("combobox")).toHaveCount(0)
    const bodyText = await page.textContent("body")
    expect(bodyText).not.toMatch(/sınıf seç/i)
    // 12. Okul siralamasi yok.
    expect(bodyText).not.toMatch(/okul sıralaması/i)

    await context.close()
  })

  test("URL/query değiştirerek başka sınıf alınamaz", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    // 13. Grade parametresi UI'da anlamsizdir: icerik degismez.
    await page.goto("/league?grade=8")
    await expect(
      page.getByRole("heading", { name: "7. Sınıf Ligi" })
    ).toBeVisible()

    const bodyText = await page.textContent("body")
    expect(bodyText).not.toContain(SENTINEL_SINIF8)
    expect(bodyText).not.toContain(SENTINEL_SINIF6)

    await context.close()
  })

  test("kimliksiz kullanıcı /league sayfasına giremez", async ({
    browser,
  }) => {
    const context = await browser.newContext({
      baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
    })
    const page = await context.newPage()
    installLocalOnlyGuard(page)

    // 14. Anonim korumali route'a giremez.
    await page.goto("/league")
    await expect(page).toHaveURL(/\/login/, { timeout: 15_000 })

    await context.close()
  })
})
