# AK-GIT-CHECKPOINT-01 — Güvenli Kayıt Hazırlığı (2026-11-17)

**Sonuç: READY_WITH_GAPS** — commit grupları ve allowlist'ler kanıtlı; İLK PUSH
üç ön koşul GAP'e bağlı (§7). Bu fazda add/commit/push/reset/restore YAPILMADI,
hiçbir dosya değiştirilmedi, GÜVENLİ DUR.

---

## 1. Güncel durum (yeniden doğrulandı)

| Ölçüm | Değer |
|---|---|
| HEAD / dal | `f3ba037` / `main` (03 raporundaki ile aynı; def58d0→f3ba037 atalık doğrulandı) |
| Dirty giriş | **688** (porcelain) = 201 modified + 487 untracked (klasör katlamalı) + 1 deleted; -uall: **1151 untracked dosya** |
| HEAD migration ağacı | 127 dosya, son sürüm **131** (050/113/115/116 tarihî numaraları hiç yok) |
| Working-tree migration dosyaları | **161** dosya (001–165) |
| Canlı history | 148 satır, max 165 |

### 1.1 Kritik bulgu — "62 değişmiş migration" CRLF yanıltmacası
201 modified dosyanın **109'u salt satır-sonu dönüşümü (LF→CRLF)**:
CR silinerek yapılan byte-hash karşılaştırmasında içerikleri HEAD ile birebir.
62 "değiştirilmiş" migration (001–069) dâhil — **tarihî migration içerikleri
değişmemiştir** (`git diff --ignore-cr-at-eol` migrations altında boş). `.gitattributes`
yok, `core.autocrlf` ayarlı değil → dönüşüm diske yazılmış. Bu dosyalar commit
EDİLMEZ; opsiyonel hijyen adımı §6 W0'da.
**Gerçek içerik değişikliği: 92 dosya** (`/tmp/opencode/agc01_real_modified.txt`).

## 2. Sınıflandırma (A–G)

| Grup | Kapsam | Sayı | Kanıt durumu |
|---|---|---|---|
| **A — QA kanıtlı migration** | `supabase/migrations/132–165` (34 dosya, untracked) | 34 | §3: 162/163/164/165 SHA birebir; 001–164 temiz zincir consistency-02'de 160/160 |
| **B — Kota + admin düzeltmeleri** | B1 kota frontend'i: allowlist 11 src + `gizli-dersler.ts/.test.ts` (§4.3 sızıntı kapatması) | 13 | 15-dosya allowlist SHAları bugün **15/15 birebir**; 139/139 + 207/207 test; canlıda servis ediliyor |
| **C — Generated types** | `src/lib/supabase/types.ts` (14524 satır, merged) | 1 | tsc 0 hata; DRIFT GUARD KARARI BEKLİYOR (§5) |
| **D — Test/QA/rapor** | `scripts/qa-clean-install/*` (3), `scripts/qa_*` + dry-run/intake (23), `tests/e2e` ops (6), `docs/reports` untracked (392), `drafts/*` kanıt (186) | ~610 | Faz raporlarına bağlı; D3/drafts derlemesi ayrı onayla |
| **E — Kullanıcı WIP** | Gerçek-modified src dosyalarının B1 dışı kalanları (~50), untracked src'nin B1 dışısı (~46: bulk-gate, gate-review, uretim-planlayıcı, haftalik-kasa, TrainingSessionSingle…), ai-worker (35), `.opencode/agents` (14), AGENTS.md, opencode.json, docs/design+question-production+references (~260) | ~460 | Atıf bu fazda dosya-dozunda yapılamadı → **commit planı dışı**, kirli bırakılır |
| **F — Secret/geçici/commit dışı** | `.env.local` (gitignore ✓), `.env*` kuralı ✓, `legacy-questions.xlsx` ✓ ignore; yedekler repo dışında (`~/ak-165-oncesi-*`, `~/ak-163-oncesi-*`) ✓; `.playwright-mcp/` (146 — **IGNORE DEĞİL**, §6 W0); `ak4223-*.png` ekran görüntüleri; `/tmp/opencode` betikleri | — | Secret taraması temiz (§6.0) |
| **G — Belirsiz/inceleme** | `.env.example` **silinmiş** (referans taraması: README/CI/sözleşmede bağımlılık yok → geri getir VEYA silme commit'i kullanıcı kararı); `package.json`+`package-lock.json` (next 16.3.1→16.3.8 gerçek değişiklik — W-deps); CRLF-only 109 dosya (§6 W0 hijyeni) | — | Karar kullanıcıya sunuldu |

## 3. Migration zinciri (görev §3)

- 132–165 = 34 dosya untracked; aralık kesintisiz; tracked ≤131 ile birlikte
  toplam 161 dosya.
- **SHA doğrulamaları (bugünkü dosya ↔ QA kaydı birebir):**
  - 162 `e2093b55…4a7133` = 42-14/42-15 QA + consistency-01 ✓
  - 163 `300d1e87…4b3658c` = 42-163/42-21 apply SHA ✓
  - 164 `780cc250…eb580f` = ak-vault-vis-03/05 ✓
  - 165 `655b51039…dfad4e36` = 01/02/03/05 kanonik ✓
  - Tarihî dosyalara dokunulmadı (CRLF-only'ler bile byte-içerik aynı).
- **CI temiz kurulum:** chain assert **dinamik** (`ls | wc -l` + son sürüm) →
  sayı güncellemesi gerekmez. ANCAK `supabase db reset` hook'suz çalışır ve
  **156_sec1b** fail-closed guard'ı service_role taban izinlerini, **157_sec2**
  "63 yazma politikası = 63 yetkili tablo" sözleşmesini ister — bunlar zincirde
  GRANT edilmez (modul-era manuel yetkiler). Kanıt: consistency-02 §2 aileleri +
  hook'lu runner'ın hook'suz koşuda aynı sınıfta çökmesi. **CI'da 132–165
  göründüğü an `Reset database` adımı KIRMIZI yanar** → GAP-CI-02 (§5).
- **13 tarihî migration-history farkı (korundu, raporlanıyor):** dosyada olup
  canlı history'de OLMAYAN sürümler: **111 112 114 117 118 119 120 121 122 123
  124 125 126** (13 adet; cloud-recovery/modul-era doğrudan uygulama). Ters
  fark yok. Canlıda geriye dönük history yazma işlemi YAPILMADI (yazma yasağı);
  CI taze kurulumda 161'ini de kaydeder → CI tutarlı, fark yalnız canlıda.
- ENV_REPAIR geçmişi gizlenmedi: taban izin aynaları artık dosyalı hook'larda
  (`hook_after155_*`, `hook_after156_*`) — D grubunda commit edilip CI'a
  taşınmaları öneriliyor (§6 W1).

## 4. Generated types / CI drift riski (görev §4)

### 4.1 Guard kaynağı (ci.yml L251–258, gerçek kod)
`supabase gen types typescript --local --schema public` (CI pini **2.115.0**)
çıktısı committed `src/lib/supabase/types.ts` ile **tam dosya `diff -u`** — tek
hunk bile kırmızı yakar.

### 4.2 Kırmızı olma koşulları (kanıta dayalı, iki bağımsız neden)
1. **Manuel override (KESİN):** merged dosyada `list_question_generation_requests`
   Returns alanları `| null` güvenli; 2.115.0 mekaniği (RETURNS TABLE'da
   nullability katalogda yok) alanları null'sız üretir → 139 CI zincirine
   girdiği an bu hunk her zaman fark üretir. 139 şu an tracked değil; W1 ile
   gireceğinden tetik W1+C dalgasında.
2. **CLI sürüm farkı (OLASILIK):** yerelde 2.115.0 kurulamıyor (01'den beri);
   merge 2.115.1-beta.13 ile üretildi (eski-format ailesi). 2.115.0 çıktısıyla
   byte-kimliği kanıtsız → kanıtsız PASS ilan edilmez.
Not: HEAD'deki committed types.ts HEAD zinciriyle (≤131) uyumlu ve override
içermiyor → guard bugünkü HEAD'de yeşil; risk yalnız yeni dalgalarla gelir.

### 4.3 B1 bağımlılık sızıntısı (YENİ bulgu, GAP-ALLOW-01 kapandı)
Canlıya çıkan `competition/page.tsx` baytı (allowlist #13, SHA birebir)
`@/lib/gizli-dersler` import ediyor; modül HEAD'de YOK ve untracked. 15'li
allowlist tek başına CI checkout'unda **build kırardı**. Kapatma: W2 allowlist'i
`src/lib/gizli-dersler.ts` + `.test.ts` ile genişletildi (testleri bugün 4/4
PASS; tsc/build bu dosyalarla yeşil doğrulandı).

### 4.4 Karar seçenekleri (kullanıcı)
- **K1 (öneri):** types.ts'yi override'sız saf üretimle commit et; önce izole
  sandbox'ta (cp -al kalıbı) tsc + 2 tüketicinin (`uretim-talepleri.ts`,
  `UretimTalepDetayView.tsx`) derlendiğini doğrula; guard yalnız CLI-farkı
  riskiyle koşar.
- **K2:** override korunur → ci.yml'ye hedefli muafiyet huntingsi gerekir
  (ci.yml değişikliği ayrı onay; guard'ı sulandırır).

## 5. CI kırmızı bayrakları (ilk push ön koşulları)

| GAP | Koşul | Kapatma |
|---|---|---|
| **GAP-CI-01** | `test:unit` kapsamındaki `AdminNav.test.tsx` **bugün 1/15 FAIL** (doğrulandı) → her push kırmızı | Frontend onarım görevi (test GEVŞETİLEMEZ); push'tan ÖNCE yeşil |
| **GAP-CI-02** | `supabase db reset` hook'suz → 156'da çöker (§3) | ci.yml "Reset database" adımını hook'lu clean-install semantiğine taşı (onaylı patch) + **001–165 tam zincirin hook'lu izole kanıtı henüz YOK** (consistency-02 001–164/160 dosyaydı; 165 eklentili 161-dosya koşusu gerekir) |
| **GAP-CI-03** | Drift guard §4.2 | K1/K2 kararı (+K1 sandbox tsc kanıtı) |
| GAP-CI-04 | `next build` | **KAPANDI** — working tree'de `npm run build` PASS (Next 16.3.8 Turbopack, 28 rota, TS 22.5s) |
| GAP-CI-05 | `npm ci` bütünlüğü | package.json+lock birlikte commit edilmeli (next 16.3.8 pin'i working tree ile aynı) |

## 6. Güvenli commit planı (`git add .` YOK — her grup allowlist'li)

### W0 — Yerel hijyen (push yok, dosya-değiştirme bu fazda YAPILMADI; karar listesi)
- `.gitignore` + satır: `.playwright-mcp/`, `ak4223-*.png` (kök ekran görüntüleri).
- CRLF-only 109 dosya: ya `dos2unix` ile LF'a çevir (içerik-koruyan; git temizlenir)
  ya da olduğu gibi bırak (kalıcı kirlilik). Opsiyonel: `.gitattributes` `* text=auto eol=lf`.
- `.env.example`: geri getir veya silme kararını kayıt altına al.

### W1 — Migration zinciri + kurulum altyapısı (temel; diğer her şey buna bağlı)
- Allowlist: `supabase/migrations/132_*.sql … 165_*.sql` (34) +
  `scripts/qa-clean-install/` (3 dosya) + **ci.yml reset-adımı patch'i** (onaylı).
- Bağımlılık: yok (SQL + betik + workflow).
- Kanıt: §3 SHAları; consistency-02 001–164 zincir PASS; 05 FINAL_165 canlı kanıtı.
- Secret taraması: temiz (§6.0). Migration uyumu: canlı hist max=165 ile birebir.
- Mesaj: `feat(db): add migrations 132-165 (weekly quota takeover incl. 165) + clean-install hooks`
- CI riski: GAP-CI-02 patch'siz KIRMIZI → patch + 161-dosyalık hook'lu izole
  kanıt koşusu prerequisite. **Önce uygulanacak adım budur.**

### W2 — Kota frontend'i (B1) — W1 sonrası
- Allowlist (15): allowlist #2–13 + `drafts/ak-quota-subject-01/rollback_165*.sql`
  (2) + `src/lib/gizli-dersler.ts` + `src/lib/gizli-dersler.test.ts`.
- Bağımlılık: import kapanışı doğrulandı (tek sızıntı kapatıldı); actions.ts ve
  geri kalan, committed HEAD halleriyle uyumlu (HEAD'de gizli-dersler referansı yok).
- Kanıt: 15/15 SHA; 207/207; build PASS; 05 canlı kabulü.
- Mesaj: `feat(competition): per-subject weekly quota UI (flag-gated, 165)`
- CI riski: AdminNav onarımı (GAP-CI-01) hâlâ genel push engeli.

### W2b — (bağımsız, küçük) Bağımlılık pini
- `package.json` + `package-lock.json` birlikte: `next 16.3.1→16.3.8` + eslint-config pin.
- Kanıt: build PASS 16.3.8; canlı dev 16.3.8. CI: npm ci deterministik.

### W3 — Generated types — W1 ile birlikte veya hemen sonra; K1/K2 kararıyla
- Allowlist: `src/lib/supabase/types.ts`. Mesaj: `chore(db): regenerate types for 132-165 chain`.
- CI riski: §4.2 — K1 seçilirse yalnız CLI-farkı olasılığı; K2 ise muafiyet yaması şart.

### W4 — Rapor/Kanıt belgeleri (CI'sız risk yok)
- `docs/reports/ak-*` + tamamlanan fazların `drafts/ak-*/` kanıtları (derleme
  listesi ayrı: log/masking denetiminden geçmiş dosyalar; .playwright-mcp hariç).
- Önceki oturumda yazılan bu fazın raporu dâhil.

### Commit DIŞI kalanlar
E grubu tamamı (kullanıcı WIP'i), `.env*`, yedekler, `.playwright-mcp/`, PNG'ler,
CRLF-only dosyalar (W0'a kadar), G kararları çözülmemiş öğeler.

### 6.0 Secret taraması (219 aday dosya + drafts/docs)
`sb_publishable`/`sb_secret`/JWT/`password=`/private-key desenleri: commit
adaylarında **sıfır gerçek değer**; tek eşleşenler rol adları (SQL GRANT'ları),
`process.env` referansları, test fixture'ı ("DEĞER_ASLA_SEÇİLMEMELİ" sahte
deseni) ve agent-doc örneği `[MASK]:5432/app`. Değerler hiçbir yere basılmadı.

## 7. KARAR: **READY_WITH_GAPS**

Commit grupları hazırlıksız değil; ancak **ilk push** şunlar olmadan yeşil olamaz:
1. AdminNav test onarımı (GAP-CI-01) — frontend görevi.
2. ci.yml hook'lu reset yaması + **001–165 hook'lu izole kurulum kanıtı** (GAP-CI-02).
3. K1/K2 drift kararı (GAP-CI-03).

**İlk güvenli commit grubu:** W1 (34 migration + 3 qa-clean-install dosyası) —
tek başına commit EDİLEBİLİR; push ise yamalı ci.yml ile birlikte anlamlıdır.
**Sonraki uygulama adımı (öneri sırası):**
1. İzole disposable DB'de `clean_install.sh 161` koşusu (hook'lar + 165 dâhil
   001–165 tam zincir) → yeşil ise GAP-CI-02'nin kanıt yarısı kapanır.
2. AdminNav onarım görevi.
3. ci.yml reset-patch taslağı + onay.
4. K1 sandbox tsc doğrulaması → W3 dosyasının kesin hali.
5. W1 → W2 → W2b → W3 dalgası; her fazda push için ayrıca açık izin.

Kalan riskler: E grubu atıflandırılmamış ~460 dosya (kullanıcı kararına kadar
kirli kalır — veri kaybı riski yok, diskte); 13 tarihî history farkı canlıda
daimî (bilinçli); CRLF dosyaları hijyen adımı yapılmazsa kalıcı dirty.

*GÜVENLİ DUR — bu faz yalnız envanter+plan üretti; Git'i yazan tek komut
çalıştırılmadı.*
