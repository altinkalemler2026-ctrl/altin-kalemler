import { test, expect } from "@playwright/test"

import { installLocalOnlyGuard } from "./helpers/local-only-network"

// Local-only: trace/video/screenshot kapali; sifre/token artifact'a yazilmaz.
// Kimlik bilgileri yalnizca local runner (scripts/run-faz7-e2e.ps1) tarafindan
// child-process env olarak enjekte edilir; kaynak koda yazilmaz.
test.use({ trace: "off", video: "off", screenshot: "off" })

// Ayni E2E kullanici cifti uzerinde sirali calisir (paralel cakisma yok).
test.describe.configure({ mode: "serial" })

interface Cred {
  email: string
  password: string
  nickname: string
}

function actorCreds(): Cred[] {
  const aEmail = process.env.E2E_USER_A_EMAIL
  const aPass = process.env.E2E_USER_A_PASSWORD
  const bEmail = process.env.E2E_USER_B_EMAIL
  const bPass = process.env.E2E_USER_B_PASSWORD
  if (!aEmail || !aPass || !bEmail || !bPass) {
    throw new Error(
      "E2E_USER_A_EMAIL/PASSWORD and E2E_USER_B_EMAIL/PASSWORD must be set by the local-only runner."
    )
  }
  return [
    { email: aEmail, password: aPass, nickname: "E2E_Ogrenci_A" },
    { email: bEmail, password: bPass, nickname: "E2E_Ogrenci_B" },
  ]
}

const QUESTIONS_TOTAL = 5

async function login(
  browser: import("@playwright/test").Browser,
  cred: Cred
) {
  const context = await browser.newContext({
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
  })
  const page = await context.newPage()
  const guard = installLocalOnlyGuard(page)

  await page.goto("/login")
  await expect(page).toHaveURL(/\/login/)

  await page.getByLabel("E-posta").fill(cred.email)
  await page.getByLabel("Şifre").fill(cred.password)
  await page.getByRole("button", { name: "Giriş Yap" }).click()

  await expect(
    page.getByRole("heading", { name: "Öğrenci ana sayfası" })
  ).toBeVisible({ timeout: 20_000 })

  return { context, page, guard }
}

/** Matematik kartindaki kuyruguna katil butonunu dondurur. */
function mathQueueButton(page: import("@playwright/test").Page) {
  const card = page.locator("section div.rounded-2xl", {
    has: page.getByRole("heading", { name: "Matematik" }),
  })
  return card.getByRole("button", { name: /Sıraya katıl/ })
}

test.describe("yarışma — negatif akışlar", () => {
  test("anonim kullanıcı yarışma sayfasına giremez (/login'e yönlendirilir)", async ({
    browser,
  }) => {
    const context = await browser.newContext({
      baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
    })
    const page = await context.newPage()
    const guard = installLocalOnlyGuard(page)

    await page.goto("/competition")
    await expect(page).toHaveURL(/\/login/, { timeout: 15_000 })

    expect(guard.blockedHosts(), "remote requests were blocked").toEqual([])
    await context.close()
  })

  test("katılımcı olmayan öğrenci yarışma oturumuna ve sonucuna erişemez", async ({
    browser,
  }) => {
    const cred = actorCreds()[0]
    const { context, page, guard } = await login(browser, cred)

    const foreignId = "00000000-0000-4000-8000-0000000000ff"

    await page.goto(`/competition/${foreignId}`)
    await expect(page).toHaveURL(/\/competition$/, { timeout: 15_000 })

    await page.goto(`/competition/${foreignId}/result`)
    await expect(page).toHaveURL(/\/competition$/, { timeout: 15_000 })

    expect(guard.blockedHosts(), "remote requests were blocked").toEqual([])
    await context.close()
  })
})

test.describe("yarışma — pozitif akış", () => {
  test("Eşleşme, 5 soruluk yarışma ve sunucu sonucu (A kazanır / B kaybeder)", async ({
    browser,
  }) => {
    test.setTimeout(300_000)
    const [credA, credB] = actorCreds()
    const sessionA = await login(browser, credA)
    const sessionB = await login(browser, credB)

    // 1. A kuyruga girer, bekler.
    await sessionA.page.goto("/competition")
    await mathQueueButton(sessionA.page).click()
    await expect(
      sessionA.page.getByText(/Eşleşme aranıyor/)
    ).toBeVisible({ timeout: 20_000 })

    // 2. B kuyruga girer -> aninda eslesme.
    await sessionB.page.goto("/competition")
    await mathQueueButton(sessionB.page).click()
    await expect(
      sessionB.page.getByText(/Eşleşme bulundu/)
    ).toBeVisible({ timeout: 20_000 })
    await sessionB.page
      .getByRole("button", { name: /Yarışmaya başla/ })
      .click()
    await expect(sessionB.page).toHaveURL(/\/competition\/[0-9a-f-]{36}$/)

    // 3. A polling ile eslesmeyi gorur ve oturuma girer.
    await expect(
      sessionA.page.getByText(/Eşleşme bulundu/)
    ).toBeVisible({ timeout: 30_000 })
    await sessionA.page
      .getByRole("button", { name: /Yarışmaya başla/ })
      .click()
    await expect(sessionA.page).toHaveURL(/\/competition\/[0-9a-f-]{36}$/)

    // 4. Her iki oyuncu hazir olur; ilk soru acilir.
    await expect(
      sessionA.page.getByRole("button", { name: /Hazırım/ })
    ).toBeVisible({ timeout: 30_000 })
    await sessionA.page
      .getByRole("button", { name: /Hazırım/ })
      .click()

    await expect(
      sessionB.page.getByRole("button", { name: /Hazırım/ })
    ).toBeVisible({ timeout: 30_000 })
    await sessionB.page
      .getByRole("button", { name: /Hazırım/ })
      .click()

    // 5. Soru soru cevapla: A dogru ('A'), B yanlis ('B').
    for (let q = 1; q <= QUESTIONS_TOTAL; q += 1) {
      await expect(
        sessionA.page.getByText(new RegExp(`Soru ${q} / ${QUESTIONS_TOTAL}`))
      ).toBeVisible({ timeout: 60_000 })
      await expect(
        sessionB.page.getByText(new RegExp(`Soru ${q} / ${QUESTIONS_TOTAL}`))
      ).toBeVisible({ timeout: 60_000 })

      // Sunucu puanı arayüzde görünür; rakip skoru görünmez.
      await expect(sessionA.page.getByText(/Puanın:/)).toBeVisible()

      // Gerçek kullanıcı etkileşimi: sr-only radio girdisi yerine
      // 44px+ etiket satırına tıklanır (a11y hedef alanı).
      const labelA = sessionA.page
        .locator("label")
        .filter({ has: sessionA.page.getByRole("radio", { name: /Seçenek A/ }) })
      await labelA.click()
      const labelB = sessionB.page
        .locator("label")
        .filter({ has: sessionB.page.getByRole("radio", { name: /Seçenek B/ }) })
      await labelB.click()

      await sessionA.page
        .getByRole("button", { name: "Cevapla" })
        .click()
      await sessionB.page
        .getByRole("button", { name: "Cevapla" })
        .click()

      // Görünür answered paragrafı (sr-only status da aynı metni
      // içerdiğinden strict mode için ayrıştırıcı kullanılır).
      await expect(
        sessionA.page.getByText(/Şu anki puanın:/)
      ).toBeVisible({ timeout: 20_000 })
      await expect(
        sessionB.page.getByText(/Şu anki puanın:/)
      ).toBeVisible({ timeout: 20_000 })
    }

    // 6. Yarisma tamamlanir; iki taraf da sonuc ekranina yonlendirilir.
    await expect(sessionA.page).toHaveURL(
      /\/competition\/[0-9a-f-]{36}\/result$/,
      { timeout: 60_000 }
    )
    await expect(sessionB.page).toHaveURL(
      /\/competition\/[0-9a-f-]{36}\/result$/,
      { timeout: 60_000 }
    )

    // 7. Sonuc ekranlari: sunucu sonucu (V1) kullanilir.
    await expect(
      sessionA.page.getByRole("heading", { name: "Yarışma sonucu" })
    ).toBeVisible()
    await expect(sessionA.page.getByText("Kazandın!")).toBeVisible()
    await expect(sessionB.page.getByText("Kaybettin")).toBeVisible()

    // Hata inceleme: 5 soru satiri kendi cevap durumuyla listelenir.
    for (let q = 1; q <= QUESTIONS_TOTAL; q += 1) {
      await expect(
        sessionB.page.getByText(`Soru ${q}`, { exact: true })
      ).toBeVisible()
    }
    await expect(sessionB.page.getByText("Hata inceleme")).toBeVisible()

    // Sabit 100/+20 XP Emergent kalintisi ARAYUZDE YOKTUR.
    const aText = (await sessionA.page.textContent("body")) ?? ""
    const bText = (await sessionB.page.textContent("body")) ?? ""
    expect(aText).not.toContain("+20")
    expect(bText).not.toContain("+20")
    expect(aText).not.toContain("XP")

    // Tekrar yarış girisi.
    await expect(
      sessionA.page.getByText("Tekrar yarış")
    ).toBeVisible()

    expect(sessionA.guard.blockedHosts(), "remote requests were blocked").toEqual([])
    expect(sessionB.guard.blockedHosts(), "remote requests were blocked").toEqual([])

    await sessionA.context.close()
    await sessionB.context.close()
  })
})
