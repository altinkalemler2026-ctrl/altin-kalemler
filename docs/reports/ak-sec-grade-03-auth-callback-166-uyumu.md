# AK-SEC-GRADE-03 — Auth Callback / Migration 166 Uyumluluk Düzeltmesi

**Görev:** GAP-SEC-G03 dar kapsamlı uygulama düzeltmesi + izole doğrulama
**Canlı migration:** 165 · **Hazır/uygulanmamış:** 166 · **Canlı DB:** salt-okunur kaldı
**Sonuç:** **PASS — patch teslim, GO (sıra planıyla)** · Canlı callback dosyasına DOKUNULMADI (aktarım ayrı onay bekliyor)

---

## 1. Kaynak Kod Kök Nedeni (koddan doğrulandı)

`src/app/(auth)/auth/callback/route.ts` (93 satır, tamamı okundu):

| Soru | Yanıt |
|---|---|
| İstemci / rol | `createServerClient` (cookie-based, `src/lib/supabase/server.ts`) → PostgREST'e kullanıcı oturumu JWT'siyle `authenticated` rolü |
| Gönderilen alanlar | `{ id, nickname, grade_level }` (metadata doğrulaması 1–12 + boş olmayan nickname) |
| Profil varsa | SELECT `maybeSingle` → upsert ATLANIR → `safeNextPath` redirect |
| Profil yoksa | `.upsert(..., { onConflict: "id" })` — `ignoreDuplicates` verilmemiş → postgrest-js `Prefer: resolution=merge-duplicates` (kaynak: `node_modules/@supabase/postgrest-js/src/PostgrestQueryBuilder.ts:1393`) |
| PostgREST üretimi | `INSERT … ON CONFLICT (id) DO UPDATE SET nickname=…, grade_level=…` → **planlama anında** `UPDATE(grade_level)` kolon yetkisi ister; 166 sonrası bu yetki yok → **42501 (çakışma olmasa bile)** |
| Hata yönetimi | upsert hatası → `/login?error=profile_setup`; exchange/getUser/metadata hataları kendi redirect'leri (korunacak) |

Kanıt zinciri: AK-SEC-GRADE-02 §4.1 probe'u (`CB-EXISTING-UPSERT: DENIED 42501`).

## 2. Hazırlanan Minimal Patch (UYGULANMADI — teslim edildi)

`drafts/ak-sec-grade-03/callback-ignore-duplicates.patch` (35 satır, iki dosya):

1. **route.ts** — upsert options'a tek bayrak: `ignoreDuplicates: true`
   (+ 4 satır açıklayan yorum). Beklenen SQL: `INSERT … ON CONFLICT (id) DO NOTHING`.
2. **route.test.ts** — sözleşme kilidi: upsert çağrısı artık
   `{ onConflict:"id", ignoreDuplicates:true }` beklemeli (bayrak kaldırılırsa test kırılır).

- Canlı ağaçta `git apply --check` → **rc=0 (temiz uygulanır)**; dosyalara dokunulmadı.
- İzole kopya: `/tmp/opencode/asg03/repo` (yalnız bu iki dosya değişmiş, node_modules symlink).
- Sıcak derleme notu (§6): `next dev` (PID 3901927) canlı çalışma ağacında çalışıyor;
  dosya değiştirilirse route otomatik yeniden derlenir — bu yüzden aktarım ayrı onaya bırakıldı.

## 3. Önce / Sonra SQL Davranışı

| | Eski (`merge-duplicates`) | Yeni (`ignore-duplicates`) |
|---|---|---|
| Üretilen SQL | `INSERT … ON CONFLICT (id) DO UPDATE SET nickname, grade_level` | `INSERT … ON CONFLICT (id) DO NOTHING` |
| 166 öncesi (canlı `arw`) | Çalışır (BC-3 referansı: 200) | **Çalışır (BC-1: 201)** |
| 166 sonrası | **42501 — KIRIK (GAP-SEC-G03)** | **Çalışır (E1: 201)** |
| Gerekli yetkiler (166 sonrası) | INSERT + `UPDATE(grade_level)` ✗ | INSERT (tablo) + SELECT (arbiter) ✓ — 166 bunları korur |
| Çakışmada semantik | SET satırı yazardı (guard zaten `!existingProfile` filtresiyle önlerdi) | Dokunmaz — guard'ın amaçladığı semantiğin tam karşılığı, idempotent |

## 4. Gerçek PostgREST E2E (disposable `qa_asg03` = 001–166 zinciri)

Altyapı: gerçek `postgrest:v16.1` konteyneri (ayrı JWT secret — dejenere QA anahtarı,
gerçek kimlik kullanılmadı), `authenticator` rolü, HS256 kendi imzalı JWT'leri,
Kong'un `/rest/v1` prefix-soyma davranışını taklit eden minik proxy. Supabase-js
**2.112.3** (projenin gerçek sürümü) ile doğrudan istemci testi dahil.

| # | Senaryo | Beklenen | Sonuç |
|---|---|---|---|
| E1 | Profilsiz kullanıcı, yamalı POST | 201 + satır (6/ASG03-U1) | **PASS** |
| E2 | Profilli kullanıcı, tekrar POST | 201 `[]`, kayıt değişmez (7/ORIJINAL) | **PASS** |
| E3 | Farklı grade_level ile tekrar callback | grade korunur | **PASS** |
| E4 | Eşzamanlı iki POST (aynı kullanıcı) | tek satır | **PASS** (satır=1; ikinci `[]`) |
| E5 | Bozuk JWT + anon JWT | yazma yok | **PASS** (401/401, satır=0) |
| E6 | Başka kullanıcı id'siyle INSERT | RLS reddi | **PASS** (403, 42501 `insert_own` WITH CHECK) |
| E7 | Doğrudan `grade_level` PATCH | yetki reddi | **PASS** (403, 42501; grade=6 kaldı) |
| E8 | **Eski merge akışı, 166 sonrası** | 403 42501 | **PASS** — düzeltmenin gerekliliği REST katmanında kanıtlı |
| E9 | NOT NULL nickname hatası | hata görünür kalmalı | **PASS** (400, 23502 client'a ulaşır → route `profile_setup`'a yönlendirir; hata yutulmuyor) |
| E10 | Gerçek supabase-js 2.112.3, yamalı çağrı | başarılı | **PASS** (`error=YOK`; aynı istemciyle eski merge → 42501) |

**Geriye dönük uyum (canlı şeması `qa_asg03_pre166` = 001–165, ACL `arw`):**
BC-1 yamalı POST → **201 satır oluştu** · BC-2 tekrar → **201 `[]` değişmedi** ·
BC-3 eski merge → 200 (bugünkü canlı davranış referansı). **Yama her iki şemada da
çalışır → yayın sırası güvenle "önce uygulama yaması, sonra 166" olabilir.**

QA şeffaflık notu: BC turunun ilk koşusu, benim minik proxy'mdeki sabit-kodlu
hedef-port hatası yüzünden yanlış DB'ye (qa_asg03) gitmiş ve 23503/403 üretmişti;
kök neden bulunup proxy düzeltilince BC yukarıdaki gibi temiz geçti. Bu hata ürün
kodundan bağımsız bir QA-altyapı kusuruydu; loglar `/tmp/opencode/asg03/out/`.

## 5. Regresyonlar (hepsi yeşil)

| Kontrol | Sonuç |
|---|---|
| `route.test.ts` (izole kopya, yamalı) | **10/10 PASS** (sözleşme kilidi dahil) |
| TypeScript `tsc --noEmit` (baseline + yamalı) | rc=0 / rc=0 (yeni hata yok) |
| ESLint (iki dosya) | rc=0 |
| grade093 / boundary095 / faz10 / scoring094 (qa_asg03, 166'lı) | rc=0, fail_satiri=0 (dördü de) |
| 166 güvenlik negatifleri N-1…N-8 | **12/12 PASS** |
| Migration 165 temel kota (qa165 fixture+suite) | **50/50 PASS** |
| CI replika pili, M1–M7, 001–166 kurulumu | AK-SEC-GRADE-01 kanıtlarıyla yeniden koşulmadı (bu görev tek bayrak + test beklentisi değiştirdi; geniş tekrar yapılmadı — görev maddesi 6) |

## 6. Canlı Uyumluluk Kapısı (salt-okunur)

- Canlı sayımlar değişmedi: `auth.users=9`, `student_profiles=7`, **profilsiz=2**, hist max=165, h166=0.
- Kayıt akışı: `register/page.tsx` signUp metadata'sı (nickname+grade) → `handle_new_user`
  (SECDEF/owner) profili açar → callback upsert'ine düşmez. Callback upsert'i yalnız
  **metadata'sız kayıt / OAuth / profilsiz 2 canlı kullanıcı** yolunda çalışır —
  yamanın hedef kitlesi tam olarak budur.
- Callback fiilen kullanımda: `register` → `emailRedirectTo=/auth/callback`,
  `forgot-password` → `redirectTo=/auth/callback?next=/reset-password`.
- **Yeni kodun etkinleşme biçimi:** yama canlı çalışma ağacına landığında `next dev`
  hot-reload route modülünü yeniden derler; istek bazında devreye girer, servis
  restart gerekmez. Üretim dağıtımında standart build/release yeterli.
- **Yayın sırası (kanıtlı güvenli):** ① yamanın çalışma ağacına aktarımı (ayrı kullanıcı
  onayı) + commit + CI yeşili → ② canlı davranışın pre-166'da bozulmadığı BC ile sabit →
  ③ Migration 166 canlı uygulaması AK-SEC-GRADE-02 §5 planıyla (ayrı açık onay).

## 7. Migration 166 ile Uyum Kararı

`ignoreDuplicates: true` sözleşmesi 166'nın verdiği yetkilerle (tablo INSERT +
SELECT arbiter + `nickname` kolon UPDATE) birebir örtüşür; hiçbir güvenlik yetkisi
gevşetilmemiştir (166 dosyasına ve ACL'lere dokunulmadı). **166 ile UYUMLUDUR.**

**PASS / FAIL / GAP:** Tüm kontroller PASS. Yeni GAP açılmadı.
- GAP-SEC-G03 → **ÇÖZÜLDÜ-AKTARIM-BEKLİYOR** (patch hazır+doğrulanmış; çalışma ağacına aktarım ayrı onay).
- GAP-SEC-G01 → kapalı sayılmaz (canlıda 166 bekliyor); GAP-SEC-G02 → değişmedi (ayrı karar).

**GO / NO-GO:** Bu görev için **GO** — GAP-SEC-G03'ün teknik engeli izole olarak
kalktı; AK-SEC-GRADE-02'nin koşullu NO-GO'sunun ön koşulu karşılandı. Canlı 166
uygulaması için GO, yamanın aktarımı + commit/CI yeşili SONRASINDA ve GRADE-02
raporundaki §12/§5 ön koşullarıyla geçerlidir (uygulama izni ayrıca alınır).

## 8. Temizlik ve Değişmezlik

- Silinenler (yalnız bu görevin disposable kaynakları): `qa_asg03`, `qa_asg03_pre166`
  DB'leri; `pgrst_qa_asg03`, `pgrst_qa_asg03pre` konteynerleri; iki minik proxy
  süreci; container `/tmp/asg03*` dosyaları. DB envanteri ve `docker ps` baseline'da
  (5 supabase konteyneri healthy); `qa_aqs01_a/b` ve ana stack korundu.
- Canlı DB'de tek yazma yapılmadı; callback/route kodu, migration dosyaları ve
  `types.ts` değişmedi. Kanıt: `git apply --check` temiz geçiyor.
- Korunanlar: izole kopya `/tmp/opencode/asg03/repo` (yamalı), betik+loglar
  `/tmp/opencode/asg03/out/`, patch `drafts/ak-sec-grade-03/`.
