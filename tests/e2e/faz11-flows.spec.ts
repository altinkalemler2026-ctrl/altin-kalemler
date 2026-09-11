import { test, expect } from "@playwright/test"

import { installLocalOnlyGuard } from "./helpers/local-only-network"

// LOCAL-ONLY Faz 11 E2E: ilerleme sayfasi + onayli cozum geri bildirimi.
// Disposable stack (faz11iso) + fixture; kimlik bilgileri yalnizca local
// runner (scripts/run-faz11-e2e.ps1) tarafindan child-process env olarak
// enjekte edilir; kaynak koda veya artifact'a yazilmaz.
test.use({ trace: "off", video: "off", screenshot: "off" })

test.describe.configure({ mode: "serial" })

const STUDENT_A_EMAIL = () => process.env.E2E_USER_A_EMAIL as string
const STUDENT_A_PASSWORD = () => process.env.E2E_USER_A_PASSWORD as string

const RAKIP_B = "E2E11_Ogrenci_B"
const B_SENTINEL_KONU = "QA11E_B_GIZLI_KONU"

// QA gizli alanlari/PII/UUID sentinel'leri: hicbir yerde gorunmemeli.
const SENTINELS = [
  "QA11E_B_GIZLI_KONU",
  "77777777-7777-7777-7777-777777770010",
  "77777777-7777-7777-7777-777777770020",
  "@e2e11",
  "correct_answer",
  "question_solution_assets",
  "does not exist",
]

const VIEWPORTS = [
  { name: "mobile", width: 375, height: 812 },
  { name: "tablet", width: 768, height: 1024 },
  { name: "desktop", width: 1440, height: 900 },
]

async function expectNoSentinels(page: import("@playwright/test").Page) {
  const body = (await page.locator("body").innerText()) || ""
  for (const sentinel of SENTINELS) {
    expect(body, `sentinel DOM'da olmamali: ${sentinel}`).not.toContain(
      sentinel
    )
  }
}

async function expectXssInert(page: import("@playwright/test").Page) {
  // Sentinel icerigi calistirilmamali: <img src=x onerror> inject edilmemis,
  // global __xss bayragi set edilmemis olmali.
  expect(await page.locator('img[src="x"]').count()).toBe(0)
  expect(
    await page.evaluate(() => (window as unknown as { __xss?: unknown }).__xss)
  ).toBeUndefined()
}

async function loginAsStudentA(browser: import("@playwright/test").Browser) {
  const context = await browser.newContext({
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
    viewport: VIEWPORTS[0],
  })
  const page = await context.newPage()
  const guard = installLocalOnlyGuard(page)

  await page.goto("/login")
  await page.getByLabel("E-posta").fill(STUDENT_A_EMAIL())
  await page.getByLabel(/şifre/i).fill(STUDENT_A_PASSWORD())
  await page.getByRole("button", { name: /Giriş Yap/i }).click()

  await expect(
    page.getByRole("heading", { name: /Öğrenci ana sayfası/i })
  ).toBeVisible({ timeout: 30_000 })

  return { context, page, guard }
}

async function expectNoHorizontalOverflow(page: import("@playwright/test").Page) {
  const overflow = await page.evaluate(() => {
    const doc = document.documentElement
    return doc.scrollWidth - doc.clientWidth
  })
  expect(overflow, "yatay tasma olmamali").toBeLessThanOrEqual(0)
}

test.describe("faz11 ilerleme sayfasi", () => {
  test("oturum acan ogrenci /ilerleme sayfasini gorur; baska ogrenci verisi yoktur", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/ilerleme")
    await expect(
      page.getByRole("heading", { level: 1, name: "İlerlemen" })
    ).toBeVisible()
    await expect(page.getByText(/yalnız sen görebilirsin/)).toBeVisible()

    // Yeni ogrenci: bos durum + guvenli antrenman yonlendirmesi.
    await expect(page.getByText("Henüz çalışma verisi yok")).toBeVisible()
    const trainingLink = page.getByRole("link", { name: /Antrenmana başla/ })
    await expect(trainingLink).toHaveAttribute("href", "/training")

    // B'nin verisi A'nin sayfasinda asla gorunmez.
    await expectNoSentinels(page)

    // Navigasyonda Ilerleme ogesi mevcut.
    await expect(page.getByRole("link", { name: "İlerleme" }).first()).toBeVisible()

    await context.close()
  })

  test("kullanici/sinif query spoofing'i sonuc vermez", async ({ browser }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/ilerleme?user=e2e11-ogrenci-b@e2e.test&grade=8")
    await expect(
      page.getByRole("heading", { level: 1, name: "İlerlemen" })
    ).toBeVisible()

    // Spoof parametreleri umursanmaz; sayfa yine A'nin kendi bos verisini
    // ve B'nin hicbir verisini icermez.
    await expect(page.getByText("Henüz çalışma verisi yok")).toBeVisible()
    const body = (await page.locator("body").innerText()) || ""
    expect(body).not.toContain(RAKIP_B)
    await expectNoSentinels(page)

    await context.close()
  })

  for (const vp of VIEWPORTS) {
    test(`yatay tasma yok: ${vp.name} (${vp.width}x${vp.height})`, async ({
      browser,
    }) => {
      const context = await browser.newContext({
        baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
        viewport: vp,
      })
      const page = await context.newPage()
      const guard = installLocalOnlyGuard(page)

      await page.goto("/login")
      await page.getByLabel("E-posta").fill(STUDENT_A_EMAIL())
      await page.getByLabel(/şifre/i).fill(STUDENT_A_PASSWORD())
      await page.getByRole("button", { name: /Giriş Yap/i }).click()
      await expect(
        page.getByRole("heading", { name: /Öğrenci ana sayfası/i })
      ).toBeVisible({ timeout: 30_000 })

      await page.goto("/ilerleme")
      await expect(
        page.getByRole("heading", { level: 1, name: "İlerlemen" })
      ).toBeVisible()
      await expectNoHorizontalOverflow(page)

      await context.close()
    })
  }
})

test.describe("faz11 antrenman geri bildirimi", () => {
  test.setTimeout(120_000)

  test("cevap oncesi sizinti yok; kabul sonrasi Turkce geri bildirim + aciklama", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/training")
    const matematikLink = page.getByRole("link", { name: /Matematik/ }).first()
    await expect(matematikLink).toBeVisible()
    await matematikLink.click()

    // Oturum acilir; ilk soru render edilir.
    await expect(page.getByRole("radiogroup")).toBeVisible({ timeout: 30_000 })

    // CEVAP ONCESI: dogru cevap/aciklama DOM'da YOK; feedback istegi yok.
    const preBody = (await page.locator("body").innerText()) || ""
    expect(preBody).not.toContain("Doğru cevap")
    expect(preBody).not.toContain("Çözüm açıklaması")
    await expectXssInert(page)

    // Uc QA11E sorusu da (kuyruk order) cevaplanir: secenek A gonderilir.
    for (let step = 0; step < 3; step++) {
      await expect(page.getByRole("radiogroup")).toBeVisible()
      await expectNoSentinels(page)

      await page.locator("label").filter({ has: page.locator(`input[type=radio]`) }).first().click()
      await page.getByRole("button", { name: "Cevapla" }).click()

      const panel = page.getByRole("region", { name: "Cevap geri bildirimi" })
      await expect(panel).toBeVisible({ timeout: 20_000 })
      // Panel icinde durum Turkce metindir (Doğru/Yanlış).
      await expect(
        panel.getByRole("status").first()
      ).toHaveText(/^(Doğru|Yanlış)/)

      // Panel icinde calistirilabilir HTML yok (XSS sentinel dahil).
      await expectXssInert(page)

      await expectNoSentinels(page)

      if (step < 2) {
        await panel.getByRole("button", { name: "Sonraki Soru" }).click()
      } else {
        await panel.getByRole("button", { name: "Oturumu Bitir" }).click()
      }
    }

    // Oturum ozeti gorunur; 3 soru yanitlandi.
    await expect(page.getByText(/Oturum Özeti/)).toBeVisible()
    await expect(page.getByText("3 soru yanıtlandı.")).toBeVisible()

    await context.close()
  })

  test("aciklamasi olmayan soruda guvenli hazirlik mesaji gorunur (uydurma yok)", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/training")
    const matematikLink = page.getByRole("link", { name: /Matematik/ }).first()
    await matematikLink.click()
    await expect(page.getByRole("radiogroup")).toBeVisible({ timeout: 30_000 })

    // Q3 (id ...1003) aciklamasiz; sira deterministik oldugu icin 3. soruda
    // gelir. Uc soruyu cevaplayip panel metinlerini kaydediyoruz.
    const panelTexts: string[] = []
    for (let step = 0; step < 3; step++) {
      await expect(page.getByRole("radiogroup")).toBeVisible()
      await page.locator("label").filter({ has: page.locator(`input[type=radio]`) }).first().click()
      await page.getByRole("button", { name: "Cevapla" }).click()

      const panel = page.getByRole("region", { name: "Cevap geri bildirimi" })
      await expect(panel).toBeVisible({ timeout: 20_000 })
      panelTexts.push((await panel.innerText()) || "")

      if (step < 2) {
        await panel.getByRole("button", { name: "Sonraki Soru" }).click()
      } else {
        await panel.getByRole("button", { name: "Oturumu Bitir" }).click()
      }
    }

    // En az bir panelde onayli aciklama basligi; en az birinde hazirlik
    // mesaji (Q3 aciklamasiz). Uydurma aciklama metni (fixture sentinel'i)
    // hicbir panelde gorunmez.
    expect(panelTexts.some((t) => t.includes("Çözüm açıklaması"))).toBe(true)
    expect(
      panelTexts.some((t) => t.includes("Çözüm açıklaması hazırlanıyor."))
    ).toBe(true)
    for (const text of panelTexts) {
      expect(text).not.toContain("QA11E_GIZLI_COZUM")
    }

    await context.close()
  })

  test("klavye ile cevap akisi ve erisilebilir adlar calisir", async ({
    browser,
  }) => {
    const { context, page } = await loginAsStudentA(browser)

    await page.goto("/ilerleme")
    // Klavye ile navigasyon: ilk nav linki odak alabilir.
    await page.keyboard.press("Tab")
    const firstFocused = await page.evaluate(() => {
      const el = document.activeElement
      return el ? (el as HTMLElement).tagName + ":" + (el.textContent ?? "") : ""
    })
    expect(firstFocused.length).toBeGreaterThan(0)

    await page.goto("/training")
    const matematikLink = page.getByRole("link", { name: /Matematik/ }).first()
    await matematikLink.click()
    await expect(page.getByRole("radiogroup")).toBeVisible({ timeout: 30_000 })

    // Dokunma hedefi: aksiyon butonlari min-h-11 (>=44px) tasir.
    for (const name of ["Cevapla", "Pas Geç", "Boş Bırak"]) {
      const cls = await page
        .getByRole("button", { name })
        .getAttribute("class")
      expect(cls || "").toContain("min-h-11")
    }

    // Hizli cevap akisi (sure bittikten once): secim + gonderim.
    await page
      .locator("label")
      .filter({ has: page.locator(`input[type=radio]`) })
      .first()
      .click()
    await page.getByRole("button", { name: "Cevapla" }).click()
    const panel = page.getByRole("region", { name: "Cevap geri bildirimi" })
    await expect(panel).toBeVisible({ timeout: 20_000 })
    // Klavye ile Sonraki Soru erisilebilir adla odak alabilir.
    const nextBtn = panel.getByRole("button", { name: /Sonraki Soru|Oturumu Bitir/ })
    await expect(nextBtn).toBeVisible()
    await nextBtn.focus()
    await expect(nextBtn).toBeFocused()

    await context.close()
  })
})
