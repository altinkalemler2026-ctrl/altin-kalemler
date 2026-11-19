# AK-SEC-GRADE-05 — Migration 166 Kontrollü Canlı Güvenlik Uygulaması

**Tarih:** 2026-11-19 · **Mod:** Açık kullanıcı onaylı kontrollü production uygulaması
**Sonuç:** **TAMAMLANDI / PASS** — GAP-SEC-01 canlıda KAPANDI

---

## 1. Production hedef kimliği

| Kanıt | Değer |
|---|---|
| Docker context | `default` |
| Konteyner | `/supabase_db_yarisma-programi` — inspect ile ad birebir, `Running=true`, `Health=healthy` (GRADE-05 G0 sıkılaştırması) |
| Image | `public.ecr.aws/supabase/postgres:17.6.1.155` (PostgreSQL 17.6) |
| DB / kullanıcı | `postgres` / `postgres` (unix socket) |
| Kong | `127.0.0.1:55321` · Next.js `127.0.0.1:3000` |
| Hosted Supabase | Hiçbir bağlantı kurulmadı |

## 2. SQL tam SHA-256 (DEĞİŞTİRİLEMEZ kimlik)

`supabase/migrations/166_student_profile_write_convergence.sql`
**`5d8296ba10634902d1efffb2b2cd2978d40bb42f3b78d4028db2de81ca7fbe26`**
— GRADE-01/02 kanonik QA kimliğiyle **birebir**. Uygulama anında konteyner İÇİNDE
`docker cp` sonrası yeniden ölçüldü: aynı değer (host≠container drift koruması).
Fail-closed guard sayısı: **8** `FINAL_166:` `RAISE EXCEPTION` (görev metnindeki "7"
sayısı belge sürçmesidir; dosya kimliği SHA ile sabittir ve QA'da koşan baytlarla
birebir aynıdır). Tarihî migration dosyaları içerik değişmedi
(`git diff --ignore-cr-at-eol -- supabase/migrations/` boş).

## 3. Preflight PASS/FAIL matrisi

| Kapı | Sonuç |
|---|---|
| A01–A14 şema/ACL/digest (14.12) | PASS — GRADE-02 tabanıyla birebir; hedef digest `9af4251d…`, M-serisi `d3e2eb58…`; 166 kalıntısı yok (A03 h166=0) |
| B01–B14 canlı durum | PASS — auth=9 profil=7 profilsiz=2 loadout=0 yarışma=0 queue=1 kota=0; idle_txn=0 long5m=0 lock_wait=0 |
| Kuyruk değerlendirmesi | 1 günlük, `status=waiting`, `expires_at` geçmiş → hareketsiz artık; etkin işleyici yok; **dokunulmadı** |
| C1–C5 callback uyumu | PASS — `route.ts` `376a7600…`, `route.test.ts` `5777f91f…` (GRADE-04 ile birebir), `ignoreDuplicates: true` yerinde, aynı PID |
| §7 son kapı (15.5x, taze) | PASS — F01 max=165 count=148 · F02 h165=1 h166=0 · F03 dup=0 · F04/F05 kilit/transaction yok · F06/F07 digest'ler değişmez · F08 sayaçlar tabanla aynı |

## 4–5. Backup dizini, SHA-256 ve geri yüklenebilirlik

| Kanıt | Değer |
|---|---|
| Backup dizini (0700) | `~/ak-166-oncesi-20261119/backup-20261119_153252_1988809/` (dosyalar 0600) |
| Dump | `pre166_20261119_153252.dump` · `pg_dump -Fc -Z zstd` · 3.569.638 bayt |
| Dump SHA-256 | `7c90ce1e947aec90055536257e420b3f4ab2ccfa49bacf4a37e5b4dee586dec6` — konteyner içi kaynak = host hedef = bana bildirilen değer; host'ta bağımsız `sha256sum -c` → **OK** |
| Üretim betiği | `backup_pre166_safe.sh` SHA `9f9184e4…971d`, `bash -n` temiz; kullanıcı SSH oturumunda koştu, STOP yok |
| Dinamik taban (dump öncesi) | `auth=9 profiller=7 kasa=3690 loadouts=0 queue=1 hist_max=165` (`production_tabani.txt`) |
| `--list` | `restore_list.txt` 312 KB; kritik nesneler (student_profiles ×18, student_loadouts ×12, question_vaults ×19, schema_migrations ×16) mevcut |
| **İzole geri yükleme provası** | **AYRİ disposable PostgreSQL konteyneri** (`--network none`, volumesuz, portsuz; image canlıyla birebir); roller canlıdan salt-okunur alınıp probe kumesinde yeniden kuruldu; `restore_rc=0`, stderr `error=0 warning=0`, **PROVA = TABAN birebir** |
| Temizlik | G8a: probe silindi (kayıtlı CID + image birebir doğrulamasıyla). G8b: konteyner geçici dump SHA eşleşmesiyle silindi. Ana stack 5 konteyner Up, DB+Kong healthy |
| Manifest | `manifest.txt` (tüm dosyaların SHA envanteri, 0600) |

## 6–8. Transaction, FINAL_166, history önce/sonra

- Tek `psql -v ON_ERROR_STOP=1 -f` koşumu (dosyanın kendi `BEGIN…COMMIT`'i); `APPLY_RC=0`.
- Sunucu çıktısı: `NOTICE: FINAL_166 OK: student_profiles 093 kolon sozlesmesi + student_loadouts 108 RPC-only siniri yeniden yururlukte (GAP-SEC-01 kapandi)` → ardından `COMMIT` (8 fail-closed assert'in hiçbiri tetiklenmedi).
- History **önce**: max=165, count=148, h166=0 → **sonra**: **max=166, count=149, h165=1, h166=1, dup=0** (h166 satırı dosyanın kendi transaction'ında yazıldı).

## 9–11. ACL/RLS önce/sonra + grade_level + loadout RPC-only

| Kontrol | Önce (canlı) | Sonra (canlı) | Beklenen |
|---|---|---|---|
| `student_profiles` relacl authenticated | `arw` (İHLAL) | **`ar`** | ✓ tablo-geneli UPDATE yok (R03=false) |
| `nickname` kolon UPDATE (authenticated) | var | **var** (R04=true) | ✓ meşru hakkın korundu |
| `grade_level` kolon UPDATE (authenticated) | **true (GAP-SEC-01)** | **false** (R05) | ✓ kapandı |
| `grade_level` INSERT | true | true (R06) | ✓ 093 sözleşmesi yalnız UPDATE'i kısıtlar; kayıt-anı INSERT meşru (E1–E10 izole kanıtı) |
| `student_loadouts` relacl authenticated | `arw` | **`r`** (R10: I/U/D=false, S=true) | ✓ |
| `student_loadouts` politikaları | 3 (017 yazma dahil) | **1** (yalnız `student reads own loadout/r`) | ✓ 017 yazma politikaları etkisiz |
| `student_loadouts` satırları | 0 | 0 (R12) | ✓ veri korunmuş |
| service_role yönetim yolu | arwdDxtm | arwdDxtm (R11 ✓) | ✓ (assert #5 geçti) |
| `student_profiles` politikaları | 4 | 4 aynı isimler (R09) | ✓ |
| Tablo yorumu | 093 metni | **"093+166…"** (R13) | ✓ |
| Hedef-tablo digest | `9af4251d…` | `168cad19a49ad7da734a90302b6bdc9cfa8efc0e3af4609378c95e9f989b7a60` | ✓ 166'nın amaçladığı değişim; bileşen matrisi yukarıdaki satırlarla tek tek doğrulandı |

Başka kullanıcı profillerine yazmayı mümkün kılan yeni izin yok: tek kolon grant'i
`nickname` (R08 envanteri), RLS politikaları değişmedi, FORCE RLS bilinçli olarak
eklenmedi (GRADE-01 kararı).

## 12. M1–M7 güvenlik sonuçları

Kanonik `scripts/qa_sec_privilege_drift_audit.sql` canlıda salt-okunur koşuldu:
**M1–M7 = 7/7 PASS · `PRIVILEGE AUDIT TEMIZ`**.
DIGEST = `d3e2eb589788d073b54d0c4c021fd234e040658a118fa1a20650ec4e52613612` —
GRADE-02 P24 canlı anıtıyla **birebir aynı** (166 bu nesnelere dokunmadı).
(İzole temiz-zincir anıtı `3509ab09…` farklıdır; bu fark 166-öNCESİ mevcut canlı
drift-çağı ortamından gelir ve preflight'ta P24 kanıtıyla belgelidir — 166 kaynaklı
değişim değildir, §9 uyarısı gereği drift sayılmadı.)
SECURITY_INVARIANT (salt-okunur iki kontrol): danger=0 league_open=0 →
`SECURITY_INVARIANT_OK` NOTICE. (Probe-tablo bölümü canlıda DDL gerektirdiği için
koşulmadı; CI'da koşmaya devam eder.)

## 13. Migration 164/165 değişmezliği

- **164 RPC md5:** `uretim_planlayici_list_vaults = b1ded12a16d4c40dea8ac3c247ecf940` ·
  `uretim_planlayici_list_vault_stock = 3f3f481e8aa7201a339bd091be74a043` — anıtla birebir.
- **165 kota motoru:** 3 kota tablosu ACL `authenticated=r` (yazma yetkisi=0, RPC-only
  sözleşme duruyor), `weekly_quota%` RPC sayısı=2, kota olay/ledger sayıları değişmedi.
- `handle_new_user` SECDEF sözleşmesi duruyor (kayıt akışı etkilenmedi).

## 14. Veri sayımları (uygulama sonrası)

`auth=9 profil=7 loadout=0 queue=1 kota=0 kasa=3690 uyelik=0` — tabanın tamamıyla
birebir; hiçbir veri kaybı yok. (Soru sayısı 0 — yayın-öncesi ortam gerçeği.)

## 15. Next.js ve Kong sağlık kontrolü (restart YAPILMADI)

- Next.js aynı PID `3901927` (uptime 2 gün+) — hot-process değişmedi.
- `/login` 200 · `/competition` oturumsuz 307 · `/auth/callback` kodsuz 307.
- Kong REST `127.0.0.1:55321` yanıt veriyor (anahtarsız 401 = beklenti), DB+Kong `healthy`.
- Uygulama logu (`/tmp/next-dev-restart-165.log`): `42501`/`permission denied` **0 adet**
  → callback düzeltmesi canlıda doğrulandı (166 sonrası merge-42501 emsali yok).
  `M_ID` unhandledRejection'ları `chrome-extension://` kaynaklı mevcut istemci
  uzantısı gürültüsüdür, sunucu/DB ile ilgisiz (GAP sayılmadı, bkz. §16).

## 16. Yeni GAP'ler

Yeni GAP **yok**. Enformasyonel notlar:
1. `M_ID` tarayıcı-uzantısı gürültüsü — kullanıcı tarafı Chrome eklentisi; sunucu kodu değil.
2. Kuyruktaki 1 günlük süresi-dolmuş `waiting` kaydı duruyor (temizleme talimatı yoktu) —
   ayrı karar kalemi.
3. Drift-digest canlı↔izole farkı (`d3e2eb58` vs `3509ab09`) 166-öncesi ortamsaldır
   (§12); istenirse ayrı envanter işi.
4. Önceden açık kalemler değişmedi: GAP-SEC-G02 kararı, GAP-CI-01, GAP-CI-03, B-1 ürün kalemi.

## 17. Karar

**TAMAMLANDI / PASS.** §15 tamamlanma kriterlerinin tamamı kanıtlandı:
SQL SHA · taze preflight · doğrulanmış yedek + izole prova · tek transaction ·
FINAL_166 OK · h166=1/max=166 · grade_level UPDATE kapalı · nickname korunmuş ·
loadout RPC-only · M1–M7 PASS · 164/165 korunmuş · sayaçlar tutarlı · Next/Kong sağlıklı ·
yetki dışı işlem yapılmadı (Git işlemi, restart, 167, canlı yazma testi, hosted bağlantı: hiçbiri).

## 18. Geri dönüş sınırları

- Doğrulanmış geri dönüş noktası: `backup-20261119_153252_1988809` (SHA `7c90ce1e…`,
  izole provada `restore_rc=0` ile geri yüklenebilirliği kanıtlı).
- Bu kapsamda **geri dönüş gerekmedi**; otomatik ACL geri yükleme/restore yapılmadı.
- Olası geri dönüş yalnız ayrı ve açık kullanıcı onayıyla, öncelikle ileri-düzeltme
  (yeni migration) tercih edilerek yürütülür; canlı DB'ye blind restore yapılmaz.

## 19. Sonraki önerilen adım

1. **Commit paketi (kullanıcı izni bekliyor):** `166_student_profile_write_convergence.sql`
   + GRADE-01…05 raporları + callback iki dosyası + checkpoint-03 QA düzeltmeleri;
   push + CI yeşil kontrolü ayrı izinlerde.
2. CI'da bilinçli-kırmızı 4 suite, 166 commit'lenince kendiliğinden döner (GRADE-01 §11).
3. Eski açık kalemler: GAP-SEC-G02 kararı, GAP-CI-03 types drift, GAP-CI-01 AdminNav, B-1.

---

### Kanıt dizinleri (erişim kısıtlı)

- `~/ak-166-oncesi-20261119/backup-20261119_153252_1988809/` — dump, SHA256SUMS,
  restore_list/rc/stdout/stderr, production_tabani, probe CID kanıtı, manifest (0700/0600)
- `~/ak-166-oncesi-20261119/kanit-141220/` — preflight A/B, final gate, apply çıktıları
  (`ag05_apply_out.txt` — FINAL_166 OK + COMMIT), post-apply matrisi, drift denetimi,
  SECURITY_INVARIANT, app-log kuyruğu
- `~/ak-166-oncesi-20261119/backup_pre166_safe.sh` — SHA `9f9184e4…971d`
- Gizli anahtar/JWT/cookie/PII hiçbir log veya raporda yoktur.
