# Faz 12 Tema Script Uyarısı — Kapanış Raporu

**Tarih:** 2026-09-13
**Kapsam:** React dev uyarısı `Encountered a script tag while rendering React component...` giderimi + doğrulama

---

## 1. Kök Neden

`ThemeSurface` (`src/lib/ui/theme-context.tsx`) her render'da satır içi `<script>` üretiyordu. Script, FOUC (yanlış tema parlaması) önlemek için **yalnız SSR HTML'inde** gerekli; tarayıcı HTML parse sırasında çalıştırıyor ve `data-theme`'yi ilk boyamadan önce set ediyor.

Sorun: yumuşak (istemci) gezintide `ThemeSurface` istemcide yeniden monte olunca React, aynı render yolunu çalıştırıp `<script>` öğesini boş bir `innerHTML="<script></script>"` ile oluşturuyor ve bu oluşum dev modda uyarı veriyor (script zaten istemcide çalışmaz). Hidrasyonda `prepareToHydrateHostInstance` kullanıldığı için soğuk yüklemede uyarı çıkmıyordu; uyarı yalnız soft-nav yeni mount'larında görünüyordu.

## 2. Yapılan Düzeltme (en küçük, dar kapsamlı)

`src/lib/ui/theme-context.tsx` — script'i `useSyncExternalStore` hidrasyon guard'ı ile koşullandırdım:

- Sunucu render + hidrasyon render'ı: `getServerSnapshot → true` → script SSR HTML'de üretilir ve hidrasyonla eşleşir.
- Hidrasyon sonrası ve yumuşak gezinti mount'ları: `getSnapshot → false` → script DOM'da üretilmez; uyarı kaybolur, sıfır maliyet.
- `subscribeNever`: no-op sabit abonelik.
- `next/script` kullanılmadı — verilen yönergeye uygun; davranış regex/inline script akışında olduğu gibi korunuyor.

Korumalar doğrulandı:
- Varsayılan Altın Arena (ilk yükleme) ✓
- Kayıtlı tema ilk boyamadan önce uygulanıyor (SSR HTML içinde script mevcut) ✓
- Yenilemede tercih korunuyor (localStorage) ✓
- Tema kapsamı öğrenci alanıyla sınırlı ✓

## 3. Değişen Dosya

| Dosya | Değişiklik |
|---|---|
| `src/lib/ui/theme-context.tsx` | `ThemeSurface`'te inline script hidrasyon guard'ı eklendi (`subscribeNever`, `useIsServerOrHydrating`) |

## 4. Doğrulama Sonuçları

- **Birim testleri:** 40/40 PASS — `theme.test.ts` (8), `ThemePicker.test.tsx` (3), `league/page.test.tsx` (12), `profile/page.test.tsx` (17)
- **lint (değişen dosyalar):** ✅ 0 hata / 0 uyarı
- **`tsc --noEmit`:** ✅ 0 hata
- **Soğuk yükleme — arena varsayılanı (localStorage boş):** profil `data-theme="arena"` ✓ (SSR HTML'de 2 init script mevcut)
- **Soğuk yükleme — kayıtlı atolye:** lig `data-theme="atolye"`, `localStorage=atolye`, konsol 0 hata ✓ (SSR HTML `arena` üretir, init script atolye'ye çevirir — FOUC önlenir)
- **Soft-nav profil ↔ lig (her iki yön):** `Encountered a script tag` uyarısı **yok**; konsol 0 hata ✓
- **Runtime tema değişimi:** radyo seçimi → `data-theme="atolye"` BGBG uygulanır + `localStorage=atolye`; yenilemede korunur ✓
- **Görüntü üretimi:** görünüm değişmedi; **yeniden üretilmedi** ✓

## 5. Kalan Eksikler

- `StudentNav` 768×1024'te yatay scroll: "Çıkış Yap" öğesi viewport sınırını 18px aşabiliyor; nav `overflow-x-auto` içinde olduğundan erişilebilir ve sayfa taşması yok. Mevcut durum korundu, tasarım değişmedi.
- 768 px açıklaması netleştirildi: **ThemePicker** 375×812'de tek sütun, 768×1024 ve 1440×900'de iki sütun (`sm:grid-cols-2`). Daha önce raporlanan "768'de tek sütun" ifadesi yanlış selector kaynaklıydı; gerçek Grid iki sütun.
- Commit/push yapılmadı.

## 6. Mevcut 8 Görüntü (tam yollar)

```
docs/reports/faz12th-profile-arena-1440.png
docs/reports/faz12th-profile-arena-375.png
docs/reports/faz12th-profile-atolye-1440.png
docs/reports/faz12th-profile-atolye-375.png
docs/reports/faz12th-league-arena-1440.png
docs/reports/faz12th-league-arena-375.png
docs/reports/faz12th-league-atolye-1440.png
docs/reports/faz12th-league-atolye-375.png
```

---

**Durum:** kapanış raporu tamamlandı. Commit/push onayı bekleniyor.