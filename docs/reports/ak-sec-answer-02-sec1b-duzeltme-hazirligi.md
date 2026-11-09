# AK-SEC-ANSWER-02 — SEC-1b Cevap Anahtarı Sızıntısı Kapatma: Düzeltme Hazırlığı ve Birleşik QA

- **Belge:** AK-SEC-ANSWER-02 · 9 Kasım 2026
- **Durum:** GÜVENLİ DUR — izole QA tamam, canlıya HİÇBİR şey uygulanmadı; ONAY bekleniyor
- **Önceki:** `docs/reports/ak-sec-answer-01-duzeltme-hazirligi.md` (SEC-1, KARAR-1 bu belgenin kapanışıdır)
- **Ürün kararı referansı:** KARAR-1 (SEC-1b dilimi) → bu paket en-dar-ilke ile 155'e BitişİK AYRI bir migration (156) olarak hazırlanmıştır; 155 taslağı DEĞİŞTİRİLMEDİ.

---

## 1. Yönetici özeti

SEC-1b, tek bir politika gibi görünüyordu; canlı denetim üç katmanlı bir açığa işaret etti:

1. **RLS:** `questions_student_read` politikası `approved+active` satırların **tüm 30 kolonunu** (correct_answer dahil) her `authenticated` kullanıcıya açıyordu (004 tasarımı; 087 bilinçli korumuştu).
2. **Tablo ACL:** `questions` tablosunda `anon` ve `authenticated` tam DML + TRUNCATE/REFERENCES/TRIGGER/**MAINTAIN** haklarına sahipti — 108 sertleştirmesinden SONRA geri gelmiş zincir-dışı drift.
3. **Kolon ACL:** `anon` ve `authenticated` için 30/30 kolonda kayıtlı SELECT/INSERT/UPDATE/REFERENCES ek yetki kayıtları (tablo REVOKE'undan bağımsız yaşar).

Kod denetimi: öğrencinin doğrudan tablo okuması **yoktur** (tüm öğrenci yolları SECURITY DEFINER RPC zinciri); yönetici paneli doğrudan SELECT yapar ve `correct_answer` okur; yönetici YAZMALarı `admin_question_edit` DEFINER RPC'sindedir. Bu yüzden çözüm **kolon beyaz-listesi değil** (paneli kırardı), **politika düşürme + en-az-ayrıcalık ACL** dilimidir.

**Sonuç (izole canlı kopyasında):** 155+156 birlikte → SEC-1 QA **11 PASS/0 FAIL/1 GAP** + SEC-1b QA **16 PASS/0 FAIL/0 GAP**; drift denetimi kritik matriste (M1–M5, M7) YEŞİL. Tespit edilen ek gerçek: **şema geneli 108 sertleştirmesi geri sarılmış** (161/161 tabloda TRUNCATE/REF/TRIGGER + 159 tabloda anon yazma hakkı) ve **lig RPC-only sözleşmesi bozulmuş** — ayrı karar maddesi (KARAR-3, migration 157 önerisi).

---

## 2. SEC-1b erişim yüzeyi — canlı salt-okunur kanıtlar (9 Kas 2026)

### 2.1 Tablo ACL (`pg_class.relacl`, `public.questions`)

| rol | ÖNCE (canlı) |
|---|---|
| anon | SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN |
| authenticated | SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN |
| postgres | (sahip, 8 hak) |
| service_role | 8 hak (iç akış — dokunulmaz) |

Ölçüm: 161 public tablonun **161'inde** anon/auth TRUNCATE/REF/TRIGGER, **159'unda** anon INSERT/UPDATE/DELETE, **161'inde** auth TRUNCATE duruyor. 108 bu hakları ŞEMANIN TAMAMINDAN almış ve fail-closed assert etmişti (`supabase/migrations/108_faz10_public_table_privilege_hardening.sql`, kayıt `schema_migrations`'ta mevcut). Hakların geri dönmesi zincir-dışıdır; en olası köken 2026-10 cloud-recovery sırasında 108-öncesi bir tabandan geri sarma veya Studio/ad-hoc GRANT (kesin kanıt yok — kökeni silinen geçici DB'lerde değil, etki anlık görüntüsünde).

### 2.2 Kolon düzeyi yetki kayıtları (`information_schema.column_privileges`)

`anon` ve `authenticated`: 30/30 kolonda SELECT+INSERT+UPDATE+REFERENCES kaydı (120+120; "kötü" kritere denk gelen **210** kayıt denetimde ölçüldü). Kritik PostgreSQL gerçeği: **kolon yetkileri ekleyicidir** — tablo SELECT'i dururken yalnız kolon REVOKE'u semptomu çözmezdi; tablo REVOKE'u da kolon kayıtlarını silmez. Üç katman birlikte kapatılmalıdır.

### 2.3 RLS politikaları (`pg_policy`, `public.questions`)

| politika | rol | USING | karar |
|---|---|---|---|
| `question admins read all questions` | authenticated | `current_user_has_admin_permission('questions.view')` | KALIR (yönetici paneli) |
| `questions_student_read` | authenticated | `approved AND is_active` | **DÜŞÜRÜLÜR** (sızıntı kaynağı) |

Yazma politikası (i/u/d) YOK → tablo yazma hakları zaten RLS ile fiilen etkisizdi; hak iptali davranış değiştirmez.

### 2.4 Okuma yolları envanteri

- **Doğrudan tablo SELECT (PostgREST):** yalnız `src/lib/admin/question-bank.ts` (3 yer) + `src/lib/admin/admin-dashboard.ts` (2 yer). `QUESTION_LIST_COLUMNS` `correct_answer` içerir → **kolon beyaz-listesi yönetici panelini kırardı**.
- **Öğrenci yolları (hepsi definer, ownersüz kalmaz):**
  `get_current_competition_question` (public invoker wrapper → `private.get_current_competition_question` **DEFINER/postgres**) → payload `private.get_competition_question_payload` (hassas anahtar **blocklist**'li: correct_answer/answer_key/solution*/explanation* silinir);
  `select_training_questions`, `submit_training_attempt`, `join_matchmaking_queue`, `prepare_competition_pack` DEFINER; `submit_competition_answer`/`sync_competition_state` wrapper→`private.*` DEFINER.
  → 156 hiçbir öğrenci akışını kırmaz (QA B04–B07 ile kanıtlı).
- **Gömme (embed) sorgusu:** `questions(...)` FK-embed kaynak kodunda YOK (grep 0).
- **View'lar:** `correct_answer` içeren view YOK (0). **pg_graphql kurulu değil**; PostgREST aynı kernel ACL/RLS'ini kullanır.
- **Diğer cevap taşıyıcı tablolar:** `correct_answer/correct_option/correct_choice/answer` kolonlu ve `authenticated` okuma politikası olan tablo = yalnız `questions`. `candidate_batch_candidate_results` (112 satır) cevap anahtarı TAŞIMAZ (kolon listesi doğrulandı, RLS var).
- **`admin_question_edit`:** `private.*` DEFINER, izin kapılı (089/122 test kalıpları) → yönetici yazmaları tablo hakkına bağımlı değil.

---

## 3. Tasarım kararları

| # | Karar | Gerekçe |
|---|---|---|
| D1 | Kolon beyaz-listesi YERİNE RLS ile satır-kapılı tablo SELECT | Yönetici paneli `correct_answer` okuyor; definer zinciri zaten sanitized payload üretiyor |
| D2 | `questions_student_read` düşürülür | Kodda meşru okuyucusu kalmadı; 004 tasarım kararı bilinçli geri alınır (ürün: öğrenci soruyu yalnız RPC payload'ından görür) |
| D3 | anon: `REVOKE ALL` + tüm kolon kayıtları silinir | Meşru erişimi yok |
| D4 | authenticated: yalnız SELECT kalır; I/U/D/TRUNCATE/REF/TRIGGER/**MAINTAIN** alınır | Yazma = definer RPC; 108 öncesi drift temizliği bu dar dilimde questions için yapılır |
| D5 | authenticated kolon **SELECT** kayıtlarına dokunulmaz | **PG bulgusu (deneysel):** tüm kolonların SELECT kaydı geri alınınca tablo SELECT'i de düşüyor (eş-yaratım bağımlılığı) → paneli kırardı. Kalan 30 SELECT kaydı tablo SELECT'iyle AYNI etkin haktır; RLS ile yönetici satırlarına kilitlidir. Yazma kolon kayıtları silinir |
| D6 | service_role/postgres'e dokunulmaz; YENİ GRANT yok | Sözleşme; iç akış + QA yolu korunur |
| D7 | Şema-geneli 108 yeniden-sertleştirmesi BU dilime dahil EDİLMEDİ | En-dar-ilke; kapsam kaçırmamak için ayrı karar maddesi (KARAR-3 / 157 önerisi) |

Ek PG bulgusu (D5'i doğuran): `REVOKE ALL (kolon)` kalıbı kolon **SELECT** kaydını kaldırmıyor; haklar tek tek adlandırılmalı (`REVOKE SELECT, INSERT, UPDATE, REFERENCES (kolon)`). Her iki bulgu izole kopyada deneysel kanıtlandı ve 156 içine yorum olarak gömüldü.

## 4. Migration paketi ve uygulama sırası

| sıra | dosya | açıklık penceresi |
|---|---|---|
| 1 | `drafts/ak-sec-answer-01/155_sec1_answer_key_acl.sql` (DEĞİŞMEDİ) | SEC-1 fonksiyon ACL |
| 2 | `drafts/ak-sec-answer-02/156_sec1b_questions_answer_key_hardening.sql` (YENİ) | SEC-1b tablo+kolon+politika |

- İkisi BAĞIMSIZ açıkları kapatır; arka arkaya tek oturumda koşulursa (tek `psql` komut zinciri, her biri `-1`) pencere saniyeler mertebesindedir ve hiçbir ara durumda mevcut açık BÜYÜMEZ.
- Her biri: idempotent + fail-closed assert + tek transaction (`-1`). Sonlarındaki beklenen `NOTICE`: `SEC1 OK` / `SEC1B OK`.
- Zincir ucu 154; 155→156 sıralı numara ile `supabase/migrations/`'e taşınır (ONAY-2).

## 5. Önce/sonra ACL + RLS matrisi (canlı ölçüm → QA kanıtı)

| yüzey | ÖNCE (canlı) | SONRA (155+156, QA'da kanıtlı) |
|---|---|---|
| `questions` relacl anon | 8 hak (tam DML+TRUNCATE/TRIGGER/REF/MAINTAIN) | **(kayıt yok)** |
| `questions` relacl authenticated | 8 hak | **yalnız SELECT** |
| `questions` relacl service_role | 8 hak | 8 hak (değişmedi) |
| `questions` kolon kayıtları (anon/auth/public) | 240 kayıt | yalnız `authenticated` SELECT×30 (D5; tablo SELECT'iyle aynı etkin hak) — yazma/anon kaydı 0 |
| `questions` okuma politikaları | 2 (`admins` + `student_read`) | **1** (`question admins read all questions`) |
| `get_internal_correct_answer` EXECUTE (155) | {postgres, anon, authenticated, service_role} | {postgres, service_role} |
| Lig tabloları SELECT (anon/auth) | AÇIK (108-öncesi drift) | **Bu paket dokunmaz** → KARAR-3/157 |

## 6. Birleşik izole QA raporu

**Ortam:** günlük DB'den `pg_dump` → benzersiz ad `sec1_qa_20261109c` → `psql -f` restore (220 hata yalnız `supabase_db_yarisma-programi` sahiplik/event-trigger/uzantı kapsamlı — DB-düzeyi QA'yı etkilemez; envanter teyidi: 176 public tablo, 385 public fonksiyon, auth şeması, 41 hafta, 4 skor seti, 36 kasa, 112 aday, hedef ders, 2 soru politikası kopyada). Önceki deneme turları `sec1b_qa_20261109a`/`sec1_qa_20261109b` de kullanıldı; **üçü de DROP edildi**, konteyner geçici dosyaları silindi. Docker envanteri baştan/sondan aynı (5 konteyner, hiçbiri yeniden başlatılmadı).

**Uygulama:** 155 → 156 → 156 (idempotency tekrarı) — hepsi `SEC1 OK`/`SEC1B OK`×2, hatasız.

**Sonuçlar (son taze turda):**

- `qa_sec1_answer_key_local.sql`: **11 PASS / 0 FAIL / 1 GAP** — GAP=G01 eski sürümün SEC-1b KAYIT satırıdır (bu paket onu B02 ile kapattı; eski betikteki etiket kasıtlıdır).
- `qa_sec1b_answer_key_local.sql`: **16 PASS / 0 FAIL / 0 GAP.**

| görev senaryosu | test | sonuç + kanıt detayı |
|---|---|---|
| S1 anon RPC cevap alamaz | B01c (+qa_sec1 T02) | 42501 permission denied for function |
| S2 auth RPC cevap alamaz | B01d (+qa_sec1 T03) | 42501 |
| S3 anon tablo dökemez | B01a/b | `correct_answer` VE `id` dökümü 42501 (tam yetki iptali) |
| S4 öğrenci tablo dökemez | B02 | SELECT hakkı var, **0 satır** (RLS), cevap görünmez |
| S5 alternatif yol yok | B03 | yazma/anon kolon kaydı 0, view 0, pg_graphql yok, auth yazma/tehlike hakları 0, service_role SELECT durur |
| S6 izinli metin+şıklar | B04 | kasa paketi RPC payload'ında `question_text`+`option_a..e` VAR, `correct_answer/correct_option/answer_key` YOK |
| S7 tam 5 soru paketi | B05 | `join_matchmaking_queue`×2 → eşleşme + kasadan **tam 5** `competition_questions` (A-önceliği: uygun üyelik sayısı = 5) |
| S8 yarışma cevap kontrolü | B06 | iki oyuncu `correct`, v3 puanı ≥100 |
| S9 antrenman + XP | B07 | `submit_training_attempt` correct + XP=2 (definer yolu bozulmadı) |
| S10 puanlama + rakip bonusu | B08 | base=130 (bant), rakip wrong → **gölge bonus +20** (`opponent_bonus_points=20`, global olay=1), total=150, rakip total=−20, completed — 128 sözleşmesiyle birebir |
| S11 yönetici denetimi | B09 | `super_admin`: `correct_answer='A'` + 7/7 satır okunur |
| S12 yabancı paket erişilemez | B10a/b | `sync_competition_state(yabancı)` → P0001 "You are not a participant"; yabancı `get_current` → `no_active_competition` |
| S13 idempotency | dış tur ×2 + B11 | 155/156 ikinci uygulamada matris değişmedi; yerinde revoke tekrarı temiz |
| S14 veri koruması | B00 | 36 kasa + 41 hafta + 112 aday + 3 parti + 0 soru/yarisma sabitleri korundu |

**QA sırasında bulunan ve düzeltilen üç gerçek (test yanlışı kök nedenleri — sistem hatası değil):**
1. `REVOKE ALL (kolon)` kolon SELECT'ini düşürmüyor → haklar adlandırıldı (156'ya gömüldü).
2. Tüm kolon SELECT kayıtlarını revoke etmek tablo SELECT'ini de düşürüyor → D5 kararı.
3. Gölge rakip bonusu `time_band` NULL ise hesaplanmıyor (`128` satır ~990 `CONTINUE`) ve `waiting→active` başlatıcısı uygulamada yok (bilinen boşluk; 094/qa_sec1 fixture kalıbıyla yaşam adımı simüle edildi). **Bunlar 155/156 kaynaklı değildir; açığın var olmayan yollarını da belgeleyen ek keşiflerdir.**

**Gerçekten çalıştırılamayan/GAP:** qa_sec1 G01 (kayıt etiketi, yukarıda açıklandı). Bunların dışında GAP yoktur; hiçbir FAIL PASS gösterilmemiştir.

## 7. Drift önleme (§5) — `scripts/qa_sec_privilege_drift_audit.sql`

Salt-okunur, canlıda koşabilir; CRITICAL satırlarda DRIFT varsa non-zero exit (CI/cron yakalar).

**Kritik matris (sözleşme):** M1 fonksiyon ACL (155) · M2 anon questions=0 hak · M3 authenticated yalnız SELECT (+MAINTAIN) · M4 kolon kaydı kritere aykırı 0 · M5 yalnız yönetici okuma politikası · M6 lig tabloları RPC-only (108) · M7 service_role SELECT durur. **INFO:** 108-geneli TRUNCATE/REF/TRIGGER ve anon-yazma tablo sayımları + kritik izin+politika **sha256 DIGEST**.

**Canlı taban (9 Kas, migration ÖNCESİ): 8 kritik DRIFT** (M1–M5 = bu paket kapatır; M6×3 = KARAR-3), M7 PASS; INFO: 161 tablo TRUNCATE kırık, 159 tablo anon-yazma. DIGEST ön durum: `724ba6a0faa1d5586a9a9d9d129815e22a1e1d05e9331dae7e35bc769967cf64`.

**155+156 sonrası beklenti (QA'da ölçüldü): M1–M5, M7 PASS; yalnız M6×3 DRIFT kalır** (157 gelene kadar exit non-zero olmaya DEVAM eder — CI entegrasyonu bunu bilmeli). DIGEST beklenen (155+156 sonrası kanonik): `d3e2eb589788d073b54d0c4c021fd234e040658a118fa1a20650ec4e52613612`; 157 ile ayrıca değişecektir (M6 + INFO=0 sonrası yeni taban olarak güncellenir).

**Kullanım:** `docker exec supabase_db_yarisma-programi psql -U postgres -d postgres -f scripts/qa_sec_privilege_drift_audit.sql`. Öneri: haftalık cron/CI adımı + DIGEST değişiminde inceleme. Geçmiş migration'lar YENİDEN YAZILMADI.

## 8. Uygulama riskleri ve canlı ön kontrolleri

Riskler:
- **R-A (düşük):** `questions_student_read`'e gizli bağımlılık → kod taraması 0 buldu; yalnız yönetici modülleri okur. Uygulama sonrası `question-bank` ekran turu + öğrenci yarışma/antrenman turu ile teyit edilmeli (bkz. §9 doğrulama).
- **R-B (düşük):** authenticated yazma/MAINTAIN iptali → yazıcı yok (definer RPC); `has_table_privilege` assert'leri fail-closed.
- **R-C (çok düşük):** hosted kernel MAINTAIN keyword desteği → canlı relacl'de MAINTAIN zaten görünür (destekleniyor); hosted aynı kontrol uygulanmadan önce doğrulanmalı.
- **R-D (bilgi):** `supabase_ai_rest`/`pg_meta`/Studio bağlantıları `postgres` rolünü kullanır — owner hakkı korunur, etkilenmez.
- **R-E (bilgi):** 156 sonrası dahi `authenticated` kolon SELECT kayıtları durur (D5); satır erişimi RLS tek katmanına emanettir — ileride questions'a Geniş okuma politikası EKLENMEMELİ (audit M5 bunu bekler).

Canlı ön kontrol listesi (ONAY gelirse, sırasıyla):
1. Manuel yedek + `git status` (zincir ucu 154, temiz).
2. Bu paketin dosyaları zincire taşındıysa (`supabase/migrations/155_...`, `156_...`) CLI ile; değilse: `docker cp` + `psql -v ON_ERROR_STOP=1 -1 -f` (beklenen `NOTICE: SEC1 OK`, `NOTICE: SEC1B OK`).
3. `supabase_migrations.schema_migrations` kayıtlarının proje konvansiyonuna göre güncellenmesi (CLI komutu kullanılır).
4. Doğrulama (salt-okunur): drift denetimi → M1–M5 PASS beklenir; M6×3 DRIFT bilinçli açık maddedir.
5. Uygulama turu: yönetici soru bankası listesi/açılışı + öğrenci yarışma payload + antrenman cevabı (kalıcı test hesapları A/B ile).
6. Başarısızlık adımlarında → §9 güvenli durdurma.

## 9. Güvenli durdurma ve rollback

- Migration `-1` tek transaction'dır: assert düşerse HİÇBİR iz kalmaz, DB olduğu gibi kalır, işlem durur ve raporlanır (QA'da iki kez fiilen yaşandı ve doğrulandı).
- 156 canlıya uygulandıktan sonra geri alma (yalnız yönetici kararı; yazma hakları GERİ VERİLMEZ — meşru tüketicisi yoktur):
  ```sql
  GRANT SELECT ON public.questions TO authenticated;
  CREATE POLICY questions_student_read ON public.questions
    FOR SELECT TO authenticated
    USING (approval_status = 'approved' AND is_active = true);
  ```
  (Kolon yazma kayıtları bilinçli geri eklenmez.)
- 155 rollback'i 01 raporundaki T09'da kanıtlıdır (tek GRANT + yeniden REVOKE).
- Uygulama sonrası öğrenci akışlarında beklenmedik hata → yukarıdaki SQL ile anında politika-geri-alımı yapılabilir; yarışma/antrenman/puanlama çekirdeği 155/156'dan bağımsız çalışır (definer zinciri) — B04–B08 kanıtı.

## 10. Ayrı kullanıcı onayı gereken işlemler

| madde | içerik |
|---|---|
| ONAY-1 (genişledi) | 155 **ve 156**'nın canlıya uygulanması (tek oturumda art arda, §8 sırası) |
| ONAY-2 | `drafts/` → `supabase/migrations/` taşıması + yerel commit (push ayrıca) |
| KARAR-3 (YENİ) | 157 önerisi: 108 sertleştirmesinin şema geneli yeniden uygulanması (TRUNCATE/REF/TRIGGER + anon/auth DML hijyeni + lig tabloları RPC-only + ALTER DEFAULT PRIVILEGES). M6×3 ancak bununla kapanır; ayrıca Studio/ad-hoc GRANT'ları üreten kanalın belirlenmesi (KARAR-2 ile birlikte) |

## 11. Sınırlar — dokunulmayanlar

Canlı DB'de yalnız salt-okunur sorgu + `pg_dump` okuması yapıldı (canlı içeriği değişmedi; son sayımlar 161 tablo / 36 kasa / 0 soru ile başlangıçla aynı; QA kalıntı DB sayısı 0). Soru/puan/yarışma verisi değişmedi; worker/model çalıştırılmadı; migration uygulanmadı; commit/push/reset/clean yapılmadı; konteynerler yeniden başlatılmadı (5/5 `Up 8 days`, envanter diff'siz); üç izole QA DB'si imha edildi; konteyner `/tmp` geçici dosyaları silindi. Yeni üretim dosyaları: bu rapor, `drafts/ak-sec-answer-02/156_sec1b_questions_answer_key_hardening.sql`, `scripts/qa_sec1b_answer_key_local.sql`, `scripts/qa_sec_privilege_drift_audit.sql` (155 taslağı ve eski QA betiği değiştirilmedi).
