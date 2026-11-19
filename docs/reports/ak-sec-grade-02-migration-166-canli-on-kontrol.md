# AK-SEC-GRADE-02 — Migration 166 Canlı Uygulama Ön Kontrolü

**Görev:** Salt-okunur production preflight + uygulama planı (canlı uygulama yetkisi YOK)
**Canlı migration:** 165 · **Aday:** 166_student_profile_write_convergence.sql
**Durum:** BİTTİ — **NO-GO (koşullu)** — §9'a bakınız
**Yöntem:** Yalnız salt-okunur canlı sorguları; tek taze disposable QA probe'u
(`qa_asg02_probe`, kuruldu-koştu-düşürüldü); AK-SEC-GRADE-01 kanıtları yeniden koşulmadı.

---

## 1. Kapsam ve kaynaklar

- `AGENTS.md` + ana sözleşme; `docs/reports/ak-sec-grade-01-sinif-yetki-acigi-onarimi.md`
- Kanıt dizini notu: görev metnindeki `drafts/ak-sec-grade-01/` **mevcut değil**;
  AK-SEC-GRADE-01 kanıtları `/tmp/opencode/asg01/` (betikler + `out/` logları)
  altındadır. Bu rapor buna işaret eder, dizin uydurulmamıştır.
- `docs/reports/ak-quota-subject-05-migration-165-canli-yayin.md` (yayın yöntemi emsali)
- `docs/reports/ak-git-checkpoint-03-legacy-qa-ci-regresyon.md`
- Migration 093, 108, 156, 157, 165, taslak 166; `src/lib/profile/service.ts`,
  `src/app/(auth)/auth/callback/route.ts`, admin servisleri.

## 2. SQL Kimliği — PASS

- `supabase/migrations/166_student_profile_write_convergence.sql`
- **SHA-256 (tam):** `5d8296ba10634902d1efffb2b2cd2978d40bb42f3b78d4028db2de81ca7fbe26`
- Önceki rapor kimliği `5d8296ba…be26` ile **birebir eşleşiyor**; dosya değişmemiş,
  izole QA'da (001–166 zinciri, dört suite, N-1…N-8, M1–M7, 165 regresyonu, CI replika
  pili FAILS=0) test edilen sürümün aynısı. SQL'e dokunulmadı.

## 3. Canlı Preflight Tablosu (salt-okunur, tek oturum)

| # | Kontrol | Sonuç |
|---|---|---|
| P01–P02 | Sunucu/DB | PG 17.6; `supabase_db_yarisma-programi` Up 2 weeks (healthy); db=postgres — quota-05 raporundakiyle aynı hedef (Contabo VPS = bu makine) |
| P03 | DB envanteri | `postgres, qa_aqs01_a, qa_aqs01_b, storage_vectors, template1` (beklenen taban) |
| P04–P06 | Tarihçe | hist_count=148 (drift-çağı tabanı), **max=165, h165=1, h166=0** |
| P07–P08 | Mevcut ACL | profiles ve loadouts: `authenticated=arw` → **ihlal canlıda duruyor**, 166 kalıntısı yok |
| P09 | Kolon yazma kayıtları | yalnız `nickname/authenticated/UPDATE` (093 beklentisiyle tutarlı) |
| P10–P12 | Politika/RLS | profiles 4, loadouts 3 politika; her iki tabloda RLS on, **force=false** (≤131'den beri; RPC owner-pass sözleşmesi) |
| P13 | Tablo yorumu | 093 dönemi metni, "+166" yok → 166 hiç uygulanmamış |
| P14 | Trigger'lar | 4 tetik (guard_schedule_profile, sync_public_profile_nickname, 2× set_updated_at) — 166 hiçbiriyle çakışmıyor |
| P15 | 157 §C matrisi pre | writable=63 = policy=63 → parity bozuk değil; 166 post'unda 62==62 (izolede kanıtlı) |
| P16–P21 | Canlı veri | profiles=**7**, loadouts=**0**, competitions=**0 (boş)**, queue=1, kota tabloları 3/etkiler 0; auth.users=**9**, **profilsiz kullanıcı=2** |
| P22–P23 | SECDEF sözleşmeleri | loadouts yazan definer'lar: `equip_student_character, equip_student_cosmetic, select_own_avatar, unequip_student_character` (RPC-only model intact); profiles'a yazan tek definer `handle_new_user` (owner, INSERT … DO NOTHING — 166'dan etkilenmez) |
| P24 | M-serisi digest (canlı anlık) | `d3e2eb589788d073b54d0c4c021fd234e040658a118fa1a20650ec4e52613612` — **post-apply anchor** (166 bu nesnelere dokunmaz, değişmemeli) |
| P25 | Hedef tablo digest pre | `9af4251d182878d5e94eb3bb293c298a11fff8e635cdd7fd876a370d4db35665` — 166 sonrası **değişmesi beklenir** (onarımın kendisi); beklenen post ACL'si izolede belgelendi |
| P26–P28 | Sağlık/lock | 3 aktif bağlantı, idle-in-txn=0, 5dk+ transaction YOK, lock_wait=0 |
| P29–P31 | M1/M3/M6 canlı | M1=`{postgres,service_role}` · M3 questions auth=r · M6 league SELECT=0 → M-serisi canlıda sağlam |
| P32 | service_role | profiles UPDATE + loadouts SELECT = true → yönetici/arka uç yolları 166 sonrası da tam |
| P33–P35 | Bağımlılık | Bu iki tabloyu referans alan view YOK; loadouts'a FK YOK; db=33 MB (yedek/dump hızlı) |

**Kalıntı taraması:** 166 nesne/izin kalıntısı yok (P06/P07/P08/P13). Canlı veri
166 ile **şema düzeyinde uyumlu** — 166 hiçbir veri satırına dokunmaz (yalnız
ACL/policy/katalog), izin allowlistassert'leri canlı ön-durumda geçecek şekilde
tasarlanmış ve izole zincirde geçmiştir.

## 4. Kullanıcı Verisi ve Uygulama Etki Analizi

| Soru | Yanıt | Kanıt |
|---|---|---|
| Nickname güncellemesi korunuyor mu? | **Evet** | 166 `UPDATE(nickname)` kolon izni verir; izolede N-3 PASS row_count=1; probe P-D bugünkü zincirde tekrar PASS |
| Sınıf seviyesi artık değişmez mi? | **Evet** | 166 tablo UPDATE/DELETE'yi iptal eder; izolede N-1/N-2 42501, kolon ACL'de grade_level yazma kaydı kalmaz |
| Yönetici/service-role korunuyor mu? | **Evet** | service_role `arwdDxtm` dokunulmaz (P32 + izole N-4/N-8) |
| Uygulama loadouts'a doğrudan yazıyor mu? | **Hayır** | `src` genelinde tek akış: `profile/service.ts` SELECT + `select_own_avatar` RPC; loadouts canlıda 0 satır → RPC-only geçişi hiçbir ekranı bozmaz |
| RPC-only modeline geçiş ekran bozar mı? | **Hayır** | 4 equip/select definer'ı yerinde (P22); profil/avatar ekranları RPC kullanıyor |
| 166 verileri silmeden uygulanır mı? | **Evet** | Dosyada DML yok; izole 001–166 kurulumunda fixture sayımları korundu |
| Öğrenci/eşleşme/kasa verileri korunur mu? | **Evet** | Yalnız katalog nesneleri değişir; canlı sayımlar (7/0/0/1/0) preflight anında sabitlendi, post-apply karşılaştırma anchor'ı |

### 4.1 KRİTİK BULGU — `auth/callback` upsert uyumsuzluğu (GAP-SEC-G03)

`src/app/(auth)/auth/callback/route.ts:70-79` kullanıcı oturumuyla (anon→authenticated
değil, `createClient()` session) şu statement'ı üretir:

```
INSERT INTO student_profiles (id, nickname, grade_level)
VALUES (…) ON CONFLICT (id) DO UPDATE SET nickname=…, grade_level=…
```

PostgREST upsert'i (varsayılan merge) **çakışma olmasa bile** planlama anında SET
edilen tüm kolonların UPDATE yetkisini ister. **Taze disposable probe (001–166
zinciri, `qa_asg02_probe`):**

- `CB-EXISTING-UPSERT: DENIED sqlstate=42501` → **mevcut akış 166 sonrası KIRILIR**
- `CB-FIX-DONOTHING: ALLOWED` → `.upsert(…, { onConflict:"id", ignoreDuplicates:true })`
  (ON CONFLICT DO NOTHING) **uyumlu**; ürün semantiği mevcut guard ile aynı
  (profil arada oluştuysa dokunma)
- `CB-FIX-PLAIN-INSERT`: yalnız duplicate'te 23505 (yetkim sorunu değil)
- `CB-NICKNAME-UPDATE: ALLOWED row_count=1` → meşru profil akışı sağlam

**Etki yüzeyi:** `handle_new_user` (SECDEF) metadata'lı kayıtlarda profili owner
olarak açtığı için ana yol etkilenmez; ancak canlıda **profilsiz 2 kullanıcı**
(kullanıcı adı/sınıf metadata'sız kayıt olmuş) ve gelecekteki metadata'sız
kayıtlar callback upsert'ine düşer → 166 bugün uygulanırsa bu kullanıcılar
`error=profile_setup` ile profilini oluşturamaz.

## 5. Canlı Uygulama Tasarımı (uygulanmadı — ön koşul sağlanınca)

Quota-05 (165) yayın metodolojisiyle birebir:

1. **Taze tutarlı yedek:** `/home/selami/ak-166-oncesi-<tarih>/backup-<ts>/` (0700),
   `pg_dump -Fc` (zstd) `postgres` db, dosya 0600; **SHA-256 kaydı**; doğrulama
   disposable DB'ye `pg_restore -c` (canlıya restore YOK).
2. **SQL kimlik allowlist:** tek dosya `166_student_profile_write_convergence.sql`,
   SHA `5d8296ba…fbe26`; container `/tmp`'ye kopyalandıktan **sonra orada da** aynı
   SHA doğrulanır (host≠container drift koruması, quota-05 emsali).
3. **Tek transaction:** dosyanın kendisi `BEGIN/COMMIT` taşır; `psql -v ON_ERROR_STOP=1`
   ile tek `docker exec -u postgres … psql -d postgres -f`; rc≠0 → commit oluşmaz.
4. **FINAL_166:** `NOTICE: FINAL_166 OK …` çıktı zorunluluğu; yoksa başarısız sayılır.
5. **Migration history:** dosya `supabase_migrations.schema_migrations` satırını
   kendisi yazar → post: h166=1, max=166, dup=0, hist=149 (148 tabanından).
6. **Post-apply ACL/RLS doğrulaması (salt-okunur):**
   - profiles `authenticated=ar`, loadouts `authenticated=r`
   - kolon yazma kaydı yalnız `nickname/authenticated/UPDATE`
   - politika sayıları 4/1; RLS on; force=false (değişmez tasarım gereği)
   - tablo yorumunda "+166"; P25 digest'i beklenen post değerine dönmeli
7. **Yetki reddinin salt-okunur katalog kanıtı (canlıda UPDATE DENEME YOK):**
   - `has_table_privilege('authenticated','student_profiles','UPDATE') = false`
   - `has_column_privilege('authenticated','student_profiles','grade_level','UPDATE') = false`
   - `has_column_privilege('authenticated','student_profiles','nickname','UPDATE') = true`
   - `has_table_privilege('authenticated','student_loadouts','INSERT/UPDATE/DELETE') = false`
   - loadouts 017 yazma politikalarının `pg_policy`'de yokluğu
   - Davranışsal (42501) kanıt **yalnız disposable kopyada** (izolede mevcut).
8. **Meşru işlem kanıtı:** `select_own_avatar` ve `get_internal_correct_answer`
   definer ACL'leri değişmemiş; app nickname UPDATE kataloğu §6.7 ile doğrulanır.
9. **M1–M7 değişmezliği:** P24 digest `d3e2eb58…` post-apply'de **birebir aynı**
   kalmalı (166 bu nesnelere dokunmaz); 164 md5 kontrolleri quota-05 setiyle.
10. **Migration 165 kota güvenliği:** kota nesneleri (P20/P21) 166 kapsamı dışında;
    post-apply'de tablo varlığı + events sayımı değişmemiş olmalı (0→0).
11. **Veri sayımları:** yedek-anı ↔ post-apply karşılaştırması (7/0/0/1/0, auth 9).

## 6. Geri Dönüş (rollback) Koşulları

- **Kontrollü rollback (yalnız ACL/policy geri yükleme):** 166 yalnız katalog
  değiştirdiğinden güvenli geri alma = eski GRANT'ların yeniden uygulanması + 017
  loadout politikalarının yeniden oluşturulmasıdır; veri kaybı riski sıfırdır.
  **Ancak bu GAP-SEC-01 ihlalini yeniden açar** → yalnız 166'da ortaya çıkan,
  önceden görülmeyen bir üretim kırılması olursa ve kullanıcı kararıyla yapılır;
  otomatik rollback tasarlanmaz.
- **Tam restore:** backup'ın ardından yazılan tüm veriyi kaybettirir → 166 için
  rollback aracı olarak **yasak**; yedek yalnız SQL felaketi (transaction içinde
  beklenmedik yıkım — EXISTS/parity assert'leri bunu commit öncesi durdurur)
  sigortasıdır.
- **Fail-closed:** ON_ERROR_STOP + dosya içi assert'ler sayesinde yarım durum
  oluşmaz (tek transaction abort → hiç uygulanmamış). RC/`FINAL_166` yoksa dur,
  raporla, uygulama yapılmış sayma.

## 7. Açık GAP'ler

| GAP | Durum |
|---|---|
| **GAP-SEC-G03** (YENİ) | `auth/callback` upsert'i 166 sonrası 42501 (§4.1, probe kanıtlı). Canlıdaki 2 profilsiz kullanıcı + metadata'sız gelecek kayıtlar etkilenir. Çözüm adayı probe'da doğrulandı: `ignoreDuplicates:true`. **Bu görevde kod değişikliği yasak — düzeltilene kadar canlı 166 NO-GO.** |
| GAP-SEC-01 | Canlıda hâlâ AÇIK (166 uygulanmadığı sürece kapalı sayılmaz); 166 taslağı izolede kapattı. |
| GAP-SEC-G02 | Temiz zincirde visibility tablosunda authenticated SELECT yok → `ON CONFLICT (user_id)` arbiter 42501 (166'ya özgü değil, pre-166 var; app kullanmıyor). 166 içeriği değil; ayrı karar. |
| H09 (qa_sec157) | Canlı-çağı seed beklentisi vs temiz zincir — kozmetik rapor farkı, 166 regresyonu değil. |
| GAP-CI-01 / GAP-CI-03 | AdminNav / types drift — bu kapsamın dışında, açık. |

## 8. Önerilen Sıra

1. **GAP-SEC-G03 app uyumu** (ayrı, küçük kod fazı): `auth/callback` upsert →
   `ignoreDuplicates:true`; PostgREST uçtan uca (REST katmanından) doğrulama; CI yeşil.
2. 166 + rapor + checkpoint-03 QA düzeltmelerinin commit'i (kullanıcı izniyle) → CI GO.
3. Canlı 166 uygulaması §5 planıyla (ayrı açık onay).

## 9. GO / NO-GO Kararı

# **NO-GO** (koşullu)

**Gerekçe:** Görev kuralı — *"Doğrudan tablo yazımı kullanan aktif bir uygulama
akışı tespit edilirse canlı uygulama için NO-GO ver."* `auth/callback` kullanıcı-oturumu
upsert'i tam olarak budur ve 166 sonrası kırılması **taze disposable probe ile
kanıtlanmıştır** (42501); canlıda bu yola düşen 2 gerçek kullanıcı vardır.

**NO-GO kapsamı:** Yalnız **canlı 166 uygulaması**. Migration 166'nın kendisi
teknik olarak hazırdır (izole 001–166 yeşil, M1–M7 sabit, ACL'ler converge, veri
korunur); engel tek satırlık **uygulama tarafı uyumlaştırmanın** (GAP-SEC-G03) henüz
yapılmamış olmasıdır. GAP-SEC-G03 kapatılıp PostgREST düzeyinde doğrulanınca ve
commit+CI yeşil olduğunda bu karar **GO**'ya döner (uygulama izni yine ayrıdır).

**Temizlik:** `qa_asg02_probe` düşürüldü, container `/tmp/asg02_probe.sql` silindi;
DB envanteri tabana döndü (`postgres, qa_aqs01_a, qa_aqs01_b, storage_vectors`);
`qa_aqs01_a/b` ve ana stack korundu. Canlıda tek yazma/deneme yapılmadı.

**Tam SQL SHA-256:** `5d8296ba10634902d1efffb2b2cd2978d40bb42f3b78d4028db2de81ca7fbe26`
