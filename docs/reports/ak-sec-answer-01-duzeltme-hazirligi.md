# AK-SEC-ANSWER-01 — Kritik Cevap Anahtarı Açığı: Düzeltme Hazırlığı

**Proje:** Altın Kalemler · **Tarih:** 9 Kasım 2026 · **Mod:** Salt-okunur inceleme + izole QA (canlıya UYGULANMADI)
**Hedef:** `public.get_internal_correct_answer(uuid)` — AK-SYSTEM-AUDIT-01 SEC-1 bulgusu.
**Durum:** Düzeltme migration'ı + izole QA hazır ve GEÇTİ. **Canlı uygulama için ayrı onay bekleniyor.**

---

## 1. Bulgunun gerçek kanıtı

### 1.1 Canlı fonksiyon durumu (9 Kasım 2026 ölçümü)

| Özellik | Değer | Kaynak |
|---|---|---|
| İmza | `get_internal_correct_answer(p_question_id uuid) RETURNS text` | canlı `pg_proc` (oid 17654) |
| Owner | `postgres` | `pg_get_userbyid(proowner)` |
| Dil/özellik | plpgsql, STABLE, **SECURITY DEFINER** | `prosecdef=t` |
| `search_path` | `""` (080 sertleştirmesi) | `proconfig` |
| **ACL** | `postgres=X, anon=X, authenticated=X, service_role=X` | `proacl` — AÇIĞIN ÖZÜ |
| Gövde kimlik kontrolü | **YOK** — `auth.uid()`/katılımcı/rol kontrolü içermiyor; soru UUID'si verilince cevabı normalize edip döndürür | canlı `pg_get_functiondef` |

PostgREST `public` şemasını yayımladığı ve `authenticated`/`anon` EXECUTE'lu olduğu için: **her istemci (giriş yapmamış dahil) soru UUID'siyle doğru cevabı alabilir.** `SECURITY DEFINER` RLS'i baypas eder.

### 1.2 İzole kopyada fiilî sızma kanıtı (ONARIMDAN ÖNCE)

QA kopya DB'de fixture soru (`correct_answer='C'`) ile:

| Test | Bağlam | Sonuç |
|---|---|---|
| ONCE-A-RPC | `set role anon` → RPC çağrısı | **`C` döndü — SIZINTI** |
| ONCE-B-RPC | `set role authenticated` → RPC çağrısı | **`C` döndü — SIZINTI** |
| ONCE-C-TABLO | `authenticated` → `select correct_answer from questions` | **`C` döndü (SEC-1b, bkz. §3)** |

### 1.3 Yetki drift'inin adli kaydı (kim verdi?)

- `021_secure_competition_scoring.sql`: `CREATE ... ; REVOKE ALL ... FROM PUBLIC` (öğrenciye kapalı tasarlanmış).
- `025_security_hardening.sql`: `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` (satır ~51).
- `080_faz5_competition_hardening.sql`: yalnız `search_path=''` sertleştirmesi; GRANT yok.
- Zincir taraması: `supabase_migrations.schema_migrations.statements` içinde bu fonksiyona **GRANT veren tek bir kayıt bile YOK** (`unnest(statements) ilike '%grant%'` sorgusu boş).
- Sonuç: `anon=X, authenticated=X` kaydı **zincir dışı drifttir** (muhtemel kaynaklar: Studio fonksiyon editörü varsayılanı veya ad-hoc SQL; kanıtlanamadı → “doğrulanmadı” olarak kayıtlı). Kalıcı önlem notu §7.4.
- Çelişki kanıtı: mevcut QA sözleşmesi `scripts/qa_scoring_v1_094_local.sql` **D-43** testi “öğrenci: get_internal_correct_answer EXECUTE reddedilir (42501)” bekler — canlı DB bugün bu sözleşmeyi İHLAL ediyor.

## 2. Bağımlılık haritası (etkilenen hiçbir şey yok mu?)

| Bağımlılık | Tür | 155 sonrası |
|---|---|---|
| `private.submit_competition_answer` | **tek gerçek çağıran** (canlı `prosrc` taraması): definer, owner=postgres → fonksiyonu owner hakkıyla çağırır | ETKİLENMEZ — QA T05'te fiilen kanıtlandı |
| Antrenman değerlendirmesi (`submit_training_attempt`→`ingest_student_attempt`) | `correct_answer`'ı **tablodan** (definer owner) okur; bu fonksiyonu hiç kullanmaz | ETKİLENMEZ — QA T07 fiilen kanıtladı |
| TS istemci yüzeyi | yalnız `src/lib/supabase/types.ts` (otomatik üretimi tip listesi); hiçbir `.rpc(...)` çağrısı yok | ETKİLENMEZ |
| Trigger'lar | bu fonksiyonu kullanan trigger yok | ETKİLENMEZ |
| `service_role` | mevcut `X` hakkı KORUNDU (yeni GRANT yok); QA T04 doğrudan çağrıyı doğrular | ETKİLENMEZ |
| Worker/script'ler | `scripts/` yalnız QA dosyalarında geçer (biri 42501 bekler — lehe) | ETKİLENMEZ |

## 3. Doğru cevabın başka sızma yolları (görev §1.6 taraması)

| # | Yüzey | Bulgular |
|---|---|---|
| SEC-1b (**yeni bulgu, ORTA-KRİTİK**) | `questions` tablosu: `questions_student_read` RLS politikası `approved+active` satırları `authenticated`'a okutur ve `correct_answer` kolonunda `anon/authenticated` **SELECT hakkı** var (`information_schema.column_privileges`). İzole kopyada ONCE-C-TABLO fiilen `C` döndürdü. Banka dolu olduğu an toplu sızdırılabilir (UUID bile gerekmez). **Bu migration kapsamı dışıdır** — en dar düzeltme ilkesi gereği ayrı karar maddesi (§7.3, G01 GAP kaydı) |
| `get_attempt_feedback` | Cevap SONRASI `correct_answer` döndürür — antrenman pedagojisi olarak tasarlanmış (cevap verilmiş sorunun anahtarı öğrenciye açıktır); önceden sızıntı yok |
| Soru payload'ları | `_faz2_sanitize_question_payload` whitelist'i `correct_answer`/`expert_solution_time` İÇERMEZ — yarışma/antrenman teslimatı temiz (canlı gövde) |
| Diğer `authenticated`-callable fonksiyonlar | `correct_answer` geçen 9 fonksiyonun tamamı ya admin-korumalı (`admin_question_edit`, kalite/üretim RPC'leri), ya cevap-sonrası (`get_attempt_feedback`), ya da hedef fonksiyonun kendisi (155 ile kapanır) |
| `question_candidates` / ham üretim tabloları | Kasa denetiminde bilinen relacl hijyen riski (R-5) ayrı izleniyor; öğrenci RPC yüzeyinde cevap anahtarı yaymıyor |

## 4. En küçük güvenli düzeltme

**Dosya:** `drafts/ak-sec-answer-01/155_sec1_answer_key_acl.sql` (yeni, commit edilmedi)

Özü:
```sql
REVOKE ALL ON FUNCTION public.get_internal_correct_answer(uuid)
  FROM PUBLIC, anon, authenticated;
```
artı fail-closed DO bloğu (fonksiyon yoksa patlar; REVOKE sonrası anon/auth izni görünüyorsa patlar; service_role hakkı düşerse patlar) + ölçüm/no-op idempotency.

Kapsal MEDİKLER: tek migration, tek REVOKE. **Yeni GRANT yok; fonksiyon silinmiyor; gövde/imza/owner/SECURITY DEFINER/search_path değişmiyor; puan/cevap algoritmasına dokunulmuyor; service_role mevcut haliyle korunuyor** (iç akışlar + QA araçları). Migration başlığında drift adli kaydı ve gerekçe.

## 5. Önce/sonra izin matrisi

| Rol | CANLI (bugün, müdahalesiz) | QA DB (155 ×2 uygulanmış) |
|---|---|---|
| postgres (owner) | EXECUTE | EXECUTE |
| anon | **EXECUTE (AÇIK)** | — |
| authenticated | **EXECUTE (AÇIK)** | — |
| PUBLIC | yok (021'den kalma REVOKE) | — |
| service_role | EXECUTE | EXECUTE (korundu) |

Canlı satır, rapor yazılırken yeniden ölçüldü: değişmemiş (canlıya hiçbir şey uygulanmadı).

## 6. İzole QA sonuçları

**Ortam:** `sec1_qa_20261109a` (benzersiz ad) — günlük DB'den `pg_dump` → aynı konteynerde taze DB'ye restore (template-copy, servis meşgullüğü nedeniyle engellenince dump kanalıyla). Restore hataları yalnız PostgREST event trigger'ları + `supabase_admin`/`pgbouncer` sahiplikleriyle sınırlı (DB-düzeyi QA için etkisiz; teyit: 176 public tablo, 457 fonksiyon, auth şeması, 41 hafta, 4 skor seti, hedef ders, 2 questions politikası kopyada mevcut). Docker envanteri baştan/sondan aynı (5 konteyner; hiçbiri yeniden başlatılmadı). QA sonrası DB DROP edildi; konteyner geçici dosyaları silindi.

**Betik:** `scripts/qa_sec1_answer_key_local.sql` (tek transaction + ROLLBACK; `sec1_qa_%` dışı DB'de fail-closed).

### Özet: 11 PASS / 0 FAIL / 1 GAP — “QA SEC1 GECTİ”

| Test | Beklenti | Sonuç |
|---|---|---|
| T01 | ACL matrisi = {postgres, service_role} | PASS |
| T02 | **anon doğru cevaba erişemez** (42501) | PASS |
| T03 | **authenticated öğrenci erişemez** (42501) | PASS |
| T04 | service_role doğrudan çağrı çalışır | PASS |
| T05a/b | **Yarışma cevap kontrolü bozulmaz**: definer zinciri; v1 sabitli fixture'da correct=200 / wrong=0 | PASS |
| T06 | **Puan/ödül zinciri değişmez**: completed + galip +24 / mağlup −12 (100→88) | PASS |
| T07 | **Antrenman cevap kontrolü bozulmaz**: correct + easy XP=2 | PASS |
| T08 | Migration tekrar uygulanınca güvenlik gevşemez (idempotent; ayrıca dosya 2. kez gerçekten uygulandı → “SEC1 OK”) | PASS |
| T09a/b | **Rollback prosedürü doğrulanır**: GRANT → anon tekrar çağırabiliyor; REVOKE → tekrar kapanıyor | PASS |
| G01 | SEC-1b tablo okuması (kapsam dışı, bu migration gevşetmez) | GAP (kayıt) |

### Yan gözlemler (bu düzeltmeyle ilgisiz, dürüstlük notu)
1. **094 QA suiti zincir 154'te bayattır:** 155'ten BAĞIMSIZ olarak 1096. satırda (`Uygulanabilir ortak görülmemiş paket kasa yok` fixture drifti) patlıyor; 155 öncesi ve sonrası koşumlar BİREBİR aynı hatayı veriyor → regresyon değil mevcut drift.
2. **Rating alt sıfır kenar davranışı:** `student_league_memberships.current_points=0` mağluba −12 uygulanmıyor (0→0 clamp; `change_type='rating'` satırı 0 ile yazılıyor). T06 bu yüzden önce FAIL verdi; fixture'a 100 puan tohumlayınca −12 kanıtlandı. Mevcut motorun tasarımı; değiştirilmedi.

## 7. Canlı uygulama ön kontrolü (ONAY BEKLEYEN ADIM)

1. **Ön okuma (salt-okunur):** `proacl` 4 roller içeriyor mu (bugünkü gibi mi)? Değiştiyse drift yeniden incelenir, sonra uygulanır.
2. **Uygulama:** `docker cp drafts/ak-sec-answer-01/155_sec1_answer_key_acl.sql supabase_db_yarisma-programi:/tmp/` → `psql -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -f /tmp/155_sec1_answer_key_acl.sql`. Beklenen: `NOTICE: SEC1 OK ...`. Tek transaction; hata olursa tamamı geri alınır.
3. **Etki anı:** ACL değişikliği anlık; PostgREST şema önbelleğini ilgilendirmiyor (fonksiyon imzası değişmiyor) — servis yeniden başlatma GEREKMEZ.
4. **Sonra doğrulama (salt-okunur):** matris = {postgres, service_role}; anon/authenticated `has_function_privilege=false`; yarışma/antrenman RPC uçtan uca davranışı değişmez (banka boş olduğundan fiilî akış testi ancak soru bankası yüklenince mümkün — QA'da fixture ile kanıtlandı). Zincire alım: kullanıcı kararıyla `supabase/migrations/155_...` olarak taşınıp kayıt altına alınır (şu an `drafts/`).
5. **Drift-önleme kalıcı kuralı (öneri, ayrı onay):** Studio'dan fonksiyon düzenleme yasağı veya periyodik ACL denetim QA'sı (`qa_sec1` matris kontrolü kalıcılaştırılabilir). `pg_default_acl` (postgres→public fonksiyonları anon/auth X) gereği YENİ fonksiyonlarda da benzer drift riski vardır; proje kalıbı REVOKE/GRANT'ı migration içinde vermektir.

## 8. Rollback planı

```sql
GRANT EXECUTE ON FUNCTION public.get_internal_correct_answer(uuid) TO anon, authenticated;
```
Tek dosyalık, anlık, çevrimsiz; QA T09'da fiilen doğrulandı. Yalnız yeni bir kırılmayı onarmak için kullanılır (beklenmiyor: iç zincir definer owner üzerinden çalışıyor). Tercih edilen geri alma: 155'in tersi ayrı migration olarak kayda geçer.

## 9. Onay talep listesi

| # | Madde | Durum |
|---|---|---|
| **ONAY-1** | `155_sec1_answer_key_acl.sql`'ın **canlı DB'ye uygulanması** (§7.2 komutları) | **KULLANICI ONAYI BEKLİYOR** |
| ONAY-2 | 155'in `drafts/` → `supabase/migrations/` zincirine alınması + tek yerel commit (push ayrı izin) | ONAY-1 ile birlikte kararlaştırılır |
| KARAR-1 | **SEC-1b** (questions_student_read + correct_answer kolon SELECT hakkı): kolon beyaz-listesi / cevap anahtarının ayrı tabloya ayrılması seçenekleriyle ayrı dilim | Kullanıcı kararı |
| KARAR-2 | Studio/ad-hoc drift önleme politikası (§7.5) | Kullanıcı kararı |

## 10. Yasaklar boyunca uyum
Canlı DB'de yalnız salt-okunur sorgu + `pg_dump` (DB içeriği değişmedi; son matris ölçümü 4 rolleri açıkça gösteriyor). Migration canlıya uygulanmadı; soru/yarışma/puan verisi değişmedi; worker çalıştırılmadı; commit/push/reset yapılmadı; servis konteynerleri restart edilmedi (envanter diff'siz); tek izole DB kuruldu ve imha edildi.

**GÜVENLİ DUR — İZOLE QA GEÇTİ; CANLI UYGULAMA ONAYI BEKLENİYOR.**
