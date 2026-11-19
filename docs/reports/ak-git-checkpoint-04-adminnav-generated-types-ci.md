# AK-GIT-CHECKPOINT-04 — AdminNav ve Generated Types CI Engellerinin Kapatılması

**Tarih:** 2026-11-19 · **Önceki faz:** AK-SEC-GRADE-05 (PASS, canlı migration=166)
**Sonuç:** **TAMAMLANDI / PASS** — GAP-CI-01 ve GAP-CI-03 çalışma ağacında kapandı

---

## 1. Önce/sonra Git durumları

| | Önce | Sonra |
|---|---|---|
| HEAD/branch | `f3ba037` / `main` (değişmedi) | aynı — **hiçbir Git işlemi yapılmadı** |
| `src/lib/supabase/types.ts` | HEAD+26 satır override, 12.786 satır, SHA `80435cb2…2d097` | **kanonik 14.524 satır**, SHA `9543de6e2f7bdea80a82d57d268a37fd3d5e185ac6c2b5582d43a336dc0474ed` (CI ile aynı CLI sürümünün çıktısıyla **bayt bayt**) |
| `AdminNav.test.tsx` | HEAD hâli (temiz), SHA `5a8ffd1e…` | sözleşme-güncel, SHA `6aae2dc2…` (+12/−5) |
| `AdminNav.tsx` (kullanıcı WIP) | modified (Stitch masaüstü redesign) | **dokunulmadı** |
| Diğer WIP (~700 girdi) | modified/untracked | **dokunulmadı** |
| reset/clean/restore/stash | — | **kullanılmadı** |

Önceki faz kanıtları (GRADE-01…05) yeniden kullanıldı; canlı DB yalnız salt-okunur
introspeksiyona dokundu (gen types bağlantısı) — hiçbir yazma yok.

## 2. AdminNav hatası ve düzeltmesi (GAP-CI-01)

**Kök neden (kanıtlı):** Kullanıcının WIP masaüstü redesign'ı (`AdminNav.tsx` diff'i:
dikey sidebar + üst şerit) `userLabel`'i DOM'da **3 metin düğümüne** çıkarıyor
(mobil üst bar satır 264, sidebar altı satır 362, masaüstü şerit satır 379) ve
`Giriş yapan:` aria-label'ını **2 öğeye** (satır 261 + 376). Eski test tekil
`getByText`/`getByLabelText` kullandığından `multiple elements` hatası veriyordu.
Uygulama kodu kasıtlı kullanıcı geliştirmesidir → **geri alınmadı**; mock/fixture
sorunu yok.

**Düzeltme (yalnız test, dar kapsamlı):** `getAllByText`→`toHaveLength(3)` ve
`getAllByLabelText`→`toHaveLength(2)` — tam sayıassertion'ları (gevşetme değil;
"suite'teki diğer yeniden-kullanım testlerinin `getAllByRole` deseniyle tutarlı).
Etiket görünürlüğü ve ekran-okuyucu duyurusu sözleşmesi korunur, ayrıca sıkılaştı
(eski test varlık kontrolüydü; yeni test tam DOM sayısını da bağlıyor).

**Sonuç: 15/15 PASS.** Navigasyon davranışı değişmedi (bileşen dosyasına dokunulmadı).

## 3. Generated types uyuşmazlığının açıklaması

Çelişki çözüldü: **DB-CONSISTENCY-03'teki "14.524 satır" asla diske yazılmamış üretilmiş
çıktı sayısıydı; GIT-CHECKPOINT-02'nin ölçtüğü disk gerçeği (HEAD+26 override) doğruydu.**
Bu fazda canlı-166 şemasından CI ile aynı CLI ile yeniden üretildi: tam 14.524 satır —
DB-CONSISTENCY-03 ölçümüyle birebir uyumlu. Committed dosya 141+ döneminden eskiydi;
163/164/165/166 nesneleri (kota tabloları, vault plan RPC'leri, `approve_…` overload
union'ı dâhil) eksikti.

**CLI sürüm durumu:** CI `supabase/setup-cli@v1` ile **2.115.0** pin'li (`ci.yml:71`).
`npx supabase@2.115.0` bu makinede binary veremedi; resmi npm paketi `/tmp/opencode/sbcli`
prefix'ine aynı sürümle kuruldu ve üretim **2.115.0** ile yapıldı — CI üretimiyle aynı
üretici garantisi.

## 4. K1/K2 seçimi ve gerekçesi

**Seçim: K1 — kanonik generated dosya + manuel nullability override'ın kaldırılması.**

Kanıt zinciri:
1. Override yalnız `list_question_generation_requests` nullability'sini düzeltiyordu.
2. **Override ölü koddur:** `src/lib/admin/uretim-talepleri.ts` RPC sonucunu `Database`
   tipinden **okumuyor** — kendi yerel `RpcSatir`/`UretimTalepSatiri` tipleri (doğru
   `| null` sözleşmesiyle) + `as` cast kullanıyor. Depo genelinde
   `Database["public"]["Functions"]` index-okuması **hiç yok** (grep: 0 eşleşme).
3. Runtime nullability sözleşmesi yerel tiplerde zaten doğru ve **değişmedi**.
4. Canlı şemada `approve_question_generation_request` iki overload'lı; üretici doğru
   union üretiyor — eski tekil tip şemaya aykırıydı.
5. K2 (guard muafiyeti) gereksiz karmaşıklık eklerdi; guard ham-diff kaldığı için
   CI tekrarlanabilirliği maksimum ve kalıcı bakım maliyeti sıfır.

§5 tercihi "K1 güvenli değilse override silme" → K1 **güvenli olduğu kanıtlandı**
(2+3: silinen tipin tüketıcisi yok; tam tsc yeşil).

## 5. Değişen dosyalar (yalnız ikisi)

| Dosya | Değişiklik |
|---|---|
| `src/lib/supabase/types.ts` | Tam kanonik yeniden üretim (14.524 satır; CLI 2.115.0, canlı-166 şeması, `--schema public`); ölü override çıktı. Eski hâl yedeği: `/tmp/opencode/agc04/types.ts.once` (`80435cb2…`) |
| `src/components/admin/AdminNav.test.tsx` | Tekil→tam-sayı `getAllBy*` sözleşme güncellemesi (§2) |

## 6. Test matrisi

| Kontrol | Sonuç |
|---|---|
| AdminNav testi | **15/15 PASS** |
| TypeScript `tsc --noEmit` | **0 hata** (kanonik tiplerle tüm depo) |
| ESLint (değişen 2 dosya) | **0 sorun** |
| Tam vitest birim paketi | **105 dosya / 1752 test PASS** |
| Drift guard yerel simülasyonu | pinned CLI ile yeniden üretim → `diff` **birebir — PASS** (`ci.yml:320-329` mantığı aynen) |
| Migration 166 sözleşmesi | SQL SHA `5d8296ba…fbe26` değişmedi; kod tarafı 166 ACL'sine bağımlı davranış değişikliği yok (GRADE-05 kanıtları geçerli) |
| Migration 165 kota | Bu faz SQL/kot kodu değiştirmedi (GRADE-05 §13 korunum kanıtı geçerli) |
| CI 001–166 zinciri | `ci.yml` zincir sayısını/sürümünü dinamik okuyor (`ci.yml:192-193`) → 166 dosyası commit'lenince kendiliğinden desteklenir (GRADE-01 §11) |
| Integration (3 `.local.test.ts`) | **Yerelde koşmadı — bilinçli:** `E2E_DB_CONTAINER` modu fixture'ları ana stack'e yazardı (canlı DB yazma yasağı). CI'da disposable DB'de koşulacak; bu fazın değişikliği compile-time-only (tsc kapsıyor) |
| `next build` | Yerelde koşmadı: üretilen artefaktlar süren `next dev` sürecinin `.next` dizinine dokunurdu (restart yasağı); CI temiz ortamda koşar; tsc+lint+vitest kapsıyor |

**Remote CI PASS ilan edilmemiştir** — gerçek GitHub koşumu commit+push sonrası ölçülecek.

## 7. CI drift guard sonucu

Yerel simülasyon (CI'nin kendisi): `gen types typescript --local --schema public`
→ `diff -u src/lib/supabase/types.ts /tmp/…` → **fark yok, PASS**. Guard'da hiçbir
istisna/gevşetme **yok** (K1 sayesinde guard'a dokunulmadı; `ci.yml` WIP'i bu fazda
değişmedi).

## 8. Kalan GAP'ler

- GAP-CI-01 → **KAPANDI** (bu faz). GAP-CI-03 → **KAPANDI** (bu faz).
- Değişmeyen açık kalemler: GAP-SEC-G02 kararı, B-1 (anonymize/soft-delete ürün kalemi),
  GAP-F1 görsel kabul.
- Yeni GAP yok. Notlar: (a) `approve_…` çift overload'ı UI'da union tipi gerektiriyor —
  tüketici yok, sorun değil; (b) CLI 3.x çıktısı 2.x ile farklı olabilir — CI 2.115.0
  pin'i korundukça tutarlı.

## 9. W1 commit hazırlığı — **GO**

- CI'nin bilinçli-kırmızı 4 suite'i: 166 SQL'i commit setine girerse döner (dinamik zincir).
- Commit seti önerisi: `166 SQL` + `types.ts` + `AdminNav.test.tsx` + GRADE-01…05 ve
  CHECKPOINT-04 raporları + checkpoint-03 QA suite düzeltmeleri (`scripts/qa-clean-install/`)
  + callback iki dosyası + `ci.yml` WIP'i (sahibinin kararıyla).
- Push ve CI yeşil gözlemi **ayrı açık izinler**; bu fazda Git işlemi yapılmadı.

---
Kanıt dizini: `/tmp/opencode/agc04/` (önceki types.ts yedeği, üretim çıktıları
`ag04_types_gen.ts` / `ag04_drift_sim.ts`, CLI 2.115.0 kurulumu `sbcli/`).
