# AK-VAULT-42W-02 — Eski Kasa Mimarisi Denetimi ve Kontrollü Geçiş Planı

**Proje:** Altın Kalemler · **Dizin:** `/home/selami/yarisma-programi`
**Mod:** Salt-okunur mimari inceleme + geçiş tasarımı · **Tarih:** 2026-11-09
**Durum:** **GÜVENLİ DUR — yalnız denetim ve geçiş planı.** Canlı DB'ye yazılmadı; migration uygulanmadı; kasa/soru/üyelik/RLS/RPC değiştirilmedi; worker koşmadı; commit/push yapılmadı.

Kanıt düzeyi kuralları: her iddia dosya+migration/fonksiyon veya canlı salt-okunur DB ölçümüyle verilmiştir. Ölçülemeyen hiçbir şey "yapılmış" sayılmamış; önceki raporlardaki varsayımlar (ör. 150/151 "TASLAK" başlığı) canlı kanıtla düzeltilmiştir.

---

## 0. Yürütme özeti

1. Canlı DB'de **36 kasa** vardır ve TAMAMI eski 049 bant seed'idir (`TR-G12-MATH*`, yalnız 12. sınıf Matematik, 35 easy + 1 mixed kök). **13 LEGACY konu yer tutucusu** (`question_vault_topics`, P1–P4 ebeveynlerinde) duruyor. **Aktif üyelik 0** — hiçbir kasanın içinde soru yok.
2. Yeni sözleşme (`SINIF.DERS.SEVIYE.HAFTA`, K1–K42, kolay/orta/zor) ile mevcut yapı arasındaki **asıl uyumsuzluk yapısal**: mevcut kasalar 12 haftalık BAND kasalarıdır; haftalık kasa kimliği (hafta numarası) şemada hiçbir kolonda yoktur. Ayrıca aynı ders/sınıf/hafta/seviye için **tek-kasa benzersizliğini** sağlayacak hiçbir kısıt yoktur.
3. Öğrencinin **"güncel yarışma seviyesi" (kolay/orta/zor) DB/kod gerçeğinde HİÇBİR YERDE tutulmuyor**. Lig ekseni Bronz→Elmas (+24/−12/0) zorluk ekseni değildir; `league_transition_rules` 0 satır ve okuyucusuz; antrenman/yarışma soru seçim RPC'lerinde zorluk filtresi yoktur. Sözleşme md. 6/8 sunucu tarafında BUGÜN uygulanamaz — en büyük açık karar budur.
4. **Sızma güvenliği fiilen geçerlidir** (kasalar ve üyelik tabloları RLS + policy'siz → hiçbir istemci rolü okuyamaz; sorular yalnız SECURITY DEFINER RPC'lerden sanitize edilerek çıkar) — KORU kararı.
5. Takvim: `academic_weeks` 2026–2027 = **K1–K41** (2026-09-14 → 2027-06-28, ölçüldü). K42 için tarih YOK; **K42 kararı kullanıcıda** (resume 5 Kas açık iş #4). Hedef sayım K41=3.567, K42=3.654 kasa (29 sınıf-ders çifti × hafta × 3 seviye).
6. Geçiş, **eklemeli (additive)** yürütülebilir: eski 36 kasa ve 13 LEGACY bağı AYNEN korunur; yeni haftalık kasalar `vault_code = SINIF.DERS.SEVIYE.HAFTA` ile yeni satırlar olarak eklenir (UUID'ler değişmez, md. 10'a uygun); eski ağaç ancak tüm QA yeşil + açık onayla `is_active=false` ile DEVREDEN ÇIKAR. **DROP/DELETE/TRUNCATE bu planda hiçbir yerde yoktur.**

---

## 1. Yeni kasa sözleşmesi (karar zemini)

Kullanıcıya görünen kimlik: `SINIF.DERS.SEVİYE.HAFTA` (örn. `12.Matematik.kolay.01`).
Kurallar: sınıflar 9–12; haftalar 01–42; seviyeler kolay/orta/zor; her uygun ders/sınıf/haftaya üç kasa; aynı ders/sınıf/hafta/seviyeye tek kasa; öğrenci yalnız kendi sınıfı + dersi + aktif haftası + güncel yarışma seviyesinin kasasına erişir; geçmiş/gelecek hafta erken açılmaz; seviye değişimi yarışma kurallarına uyar; içerik API/RPC/RLS üzerinden sızmaz; kasa hazırlığı / haftalık aktiflik / öğrenci erişimi ayrışır. Görünen isim sözleşmesi UUID kimliklerini değiştirmez.

Bu sözleşme, resume.md (17) bloğundaki 29 Ekim kullanıcı kararıyla (her yıl+sınıf+ders+haftaya Kolay/Orta/Zor birer kasa; hafta bitince kasalar yeni yarışmalara kapanır) ve resume.md (21) açık iş #4 ile (42 haftalık kolay–orta–zor kurulum; 41/42 kararı kullanıcıda) aynı hattın devamıdır. Ana sözleşme (`docs/project/altin-kalemler-ana-sozlesme.md`) düzeyinde hafta/kasa yalnız P4 satırında (satır 256–257) geçmektedir; 41/42 kararı henüz ana sözleşmeye işlenmemiştir (bkz. §13 risk R-7).

---

## 2. Eski mimarinin tam envanteri (canlı kanıtla)

### 2.1 Canlı DB ölçümleri (2026-11-09, salt-okunur psql)

| Ölçüm | Sonuç |
|---|---|
| `question_vaults` | **36 satır** — hepsi `vault_type='academic'`, `is_active=true`, yalnız 12. sınıf Matematik; kök=1 (`TR-G12-MATH`); zorluk: 35 easy + 1 mixed (kök). `medium`/`hard` kasa YOK |
| `question_vault_activation_windows` | **30 satır** (12 yaprak A + 9 B + 6 C + 3 D), tümü enabled; bantlar 0-tabanlı `[0,12) [12,24) [24,36) [36,48)` |
| `question_vault_topics` | **13 satır** — TAMAMI `topic_id IS NULL` + `legacy_topic_code LIKE 'LEGACY-%'` (LEGACY-1..13; P1×3, P2×3, P3×4, P4×3); 4 ebeveyn kasaya bağlı |
| `question_vault_memberships` | **0** (aktif 0) — hiçbir kasada soru yok |
| `question_vault_demand_policies / snapshots` | 0 / 0 |
| `question_vault_rules` | 0 |
| `annual_stock_targets` | 0 |
| `question_generation_requests` / `ai_question_generation_dispatches` | 0 / 0 |
| `student_pack_exposures` | 0 |
| `academic_weeks` | tek yıl 2026-2027, **41 hafta**, K1–K41, 2026-09-14 → 2027-06-28 |
| `curriculum_schedule_items` | 26 satır (yalnız Matematik, migration 111; K# 1-tabanlı, start dahil/end hariç) |
| Geçerli sınıf-ders çifti (aktif müfredat sürümünde kazanımı olan) | **29** (8 ders; Tarih yalnız 9–11, Felsefe yalnız 10–11) |
| Migration geçmişi | `supabase_migrations.schema_migrations` max=154; **150 ve 151 KAYITLI ve FİİLEN UYGULANMIŞ** (bkz. §2.6) |

### 2.2 Tablo ve ilişkiler (kasa çekirdeği)

| Yapı | Kaynak | Özet |
|---|---|---|
| `question_vaults` | 048_question_vault_foundation.sql:12–85 | `vault_code` (UNIQUE, 048:15), `vault_type` CHECK {source, academic, practice, competition, one_v_one, exam, quarantine, archive} (048:19–31), `parent_vault_id` self-FK RESTRICT (048:33–35), `grade_level` 1–12, `subject_id` FK, `difficulty_level` CHECK {easy, medium, hard, mixed} nullable (048:47–56), `section_code/section_order`, `is_dynamic`, `is_active`, `allow_practice/competition/one_v_one/exam`, `metadata jsonb`, `created_by/updated_by` |
| `question_vault_topics` | 048:108–140 | kasa↔konu; `topic_id` veya `legacy_topic_code/name` zorunlu (CHECK 048:128–133); LEGACY-1..13 buradadır (049:624–674 seed) |
| `question_vault_activation_windows` | 048:155–210 | `start_week/end_week ≥0`, `end≥start`, `starts_at/ends_at`, `is_enabled`, `priority`; 049:576–614 metadata→pencere üretimi |
| `question_vault_rules` | 048:225–284 | eligibility/exclusion/selection kuralları; canlıda 0 satır |
| `question_vault_memberships` | 051:18–109 | `unique(vault_id, question_id)` (051:74); `membership_status` {active, inactive, blocked, pending_review}; `practice/competition/one_v_one/exam_eligible`; 151 ile **partial UNIQUE `uq_question_active_single_vault` (question_id WHERE active)** — "bir soru tek kasa" kullanıcı kararı DB kısıtı oldu |
| Demand planner | 057:36–450 + 058 | `question_vault_demand_policies` (unique(vault_id)), `question_vault_demand_snapshots`, `question_generation_requests` (partial unique: kasa başına tek AÇIK talep, 057:438–450) |
| `academic_weeks` | 067:29–53 | PK (academic_year, week 0–52); gist exclude ile çakışma yasağı; yalnız service_role; `resolve_current_academic_period()` DEFINER fail-closed (067:83–99) |
| `student_weekly_counters` | 068 | haftalık 500 tüketim tavanı; RLS: öğrenci yalnız kendi satırı (tek client policy'li kasa-çevresi tablo) |
| `annual_stock_targets` | 060:35–117 | `stock_scope` {weekly_competition, rewarded_competition, training}; `weekly_competition` için base ≥300 CHECK (060:93–98); unique(curriculum_version_id, stock_scope, grade_level, subject_id, week) |
| `ai_question_generation_dispatches` | 137:139+ | WP-08 üretim dispatch; `vault_id` FK SET NULL |

**`question_vaults`'a bakan FK'ler (canlı ölçüm, 10 adet):** `ai_question_generation_dispatches` (SET NULL), `question_generation_requests` (CASCADE), `student_pack_exposures` (CASCADE), üyelik/topics/windows/rules/policies/snapshots (CASCADE), self-FK parent (RESTRICT). **Sonuç: kasa satırları silinirse bu zincirler sürüklenir — "DROP yok" kararı teknik olarak da zorunludur; devreden çıkarma yalnız `is_active=false` ile yapılır.**

### 2.3 RLS ve izin gerçeği (canlı)

- `question_vaults`, `_topics`, `_activation_windows`, `_rules`, `_memberships`, demand tabloları, `annual_stock_targets`, `academic_weeks`: **RLS ENABLE, HİÇBİR client policy YOK** (canlı `pg_policy` taraması: kasa tablolarında policy 0; tek policy `student_weekly_counters` kendi-satırı). → anon/authenticated hiçbirini okuyamaz/yazamaz; service_role bypass.
- **Hijyen notu:** canlı `relacl`de `question_vaults` ve `academic_weeks` dahil bu tablolar için `anon`/`authenticated`'a `arwdDxtm` (tam) GRANT duruyor (bkz. 108_faz10 genelleştirmesi); RLS policy yokluğu fiilen fail-closed olduğu için sızıntı YOK, ancak bu geniş grant savunma-i-derinlik ihlalidir → matriste DÜZELT.
- `question_vault_inventory_overview` view'ı `security_invoker=true` (051:387) → istemci RLS'e tabi (pratikte boş).

### 2.4 SECURITY DEFINER RPC envanteri (canlı `pg_proc`, prosrc'te `question_vault`/`academic_week` geçen 23 fonksiyon)

| RPC | Kaynak | Yazma? | İzin yüzeyi | Kasa ilişkisi |
|---|---|---|---|---|
| `select_training_questions` | 068:284 (sonraki revizyonlar 096/097/104; **son tanım 104:215**) | evet (exposure+sayaç) | authenticated | Yaprak kasa üyeliği GATE'i: `membership active + practice_eligible + v.is_active + vault_type NOT IN (competition, one_v_one)` (068:412–422). **Zorluk ve hafta-penceresi filtresi YOK**; hafta yalnız `curriculum_schedule_items.start_week <= v_week` konu kapısı (068:340–360) |
| `prepare_competition_pack` | 068:619 (revizyon 076/077; 082 içinde otomatik çağrı) | evet | **yalnız service_role + DEFINER iç çağrı** (082:222–228) | Kasayı `vault_type IN (competition, one_v_one)` + grade + subject + eligibility ile seçer (068:732–782); **hafta/zorluk filtresi YOK**; A: tam dolu ≤5 kasa, B: ≥ soru sayısınca ortak görülmemiş üye |
| `join_matchmaking_queue` | 079 + 082:31–212 | evet | authenticated | Eşleşmede `competitions` (question_count=5) + `prepare_competition_pack` aynı transaction'da (082:192–196) |
| `calculate_question_vault_demand` / `ensure_..._policy` / `create/approve/reject_question_generation_request` | 057/058 (canlı tanım 058 varyantı; 140 override'ları) | snapshot/request yazar | service_role (057:1566–1632); 140 onay/build/record: iç izin `ai.manage ∨ questions.approve` | Pencere semantiği **start DAHİL / end HARİÇ** (058:222–223); hedef = `metadata.target_question_count` (058:175–203); envanter 0 + hafta aktif → critical (058:361–374) |
| `uretim_planlayici_list_vaults / _list_academic_years / _list_academic_weeks / preview_uretim_planlayici_scope_rows` | 141:871/793/822/65 | hayır | authenticated + iç fail-closed izin (42501) | Kasa+pencere+takvim salt-okuma; hafta bandı hedefle çarpılmaz (141:756 `week_multiplication_guard`) |
| `uretim_planlayici_save_plan` | 141:971 | **evet** | authenticated + iç izin | Kasa+hafta aralığı planını `pending_approval` talep olarak yazar (snapshot + request); **onay/üretim başlatmaz** (141:25–26, 960) |
| `uretim_planlayici_list_vault_stock` | 150 (uygulandı) | hayır | authenticated + iç izin | 123–218; dar stok okuma (hedef/kullanilabilir/ayrı eligibility sayıları) |
| `validate_competition_vault_member_limit` (SECURITY INVOKER trigger fn) | 065:61 | reddeder | trigger | `competition/one_v_one` kasalarında aktif üye ≤5 (FOR UPDATE + recount, 065:110–152); academic→paket tür geçişinde de ≤5 (065:167–184) |
| `resolve_current_academic_period` | 067:83 | hayır | yalnız sunucu içi (PUBLIC/anon/authenticated'dan REVOKE, 067:101–103) | UTC günü tek haftaya çözer; bulunamazsa çağıran fail-closed (068 `_faz2_require_period`) |
| `academic_calendar_upsert_week / _delete_week / _list_weeks / _list_years` | (takvim admin RPC'leri) | upsert/delete evet | calendar.manage | `academic_weeks` yazma yolu MEVCUT — K42 kararı teknik olarak tek admin RPC'lik iştir (karar, kod işi değil) |
| `get_question_base_eligibility`, `get_question_vault_inventory_summary` | 051:136/259 | hayır | service_role | temel uygunluk + kasa envanter özeti |

### 2.5 Kod yüzeyi (TypeScript/Next)

- **Admin — Haftalık Kasa Görünümü:** `src/app/(admin)/admin/haftalik-kasa/page.tsx` + `src/lib/admin/kasa-gorunum.ts` — **%100 salt-okunur** (lib "hiçbir okuma/yazma yapmaz", satır 7); çağrılan RPC'ler: `uretim_planlayici_list_vaults`, `_list_academic_years`, `_list_academic_weeks`, `_list_vault_stock` (150). Bant→hafta çevirisi `gorunenHafta = ham + 1`, start dahil/end hariç (kasa-gorunum.ts:138–156); **48→41 kırpımı + "yıl dışı haftalar" ayrıntı uyarısı**; orta/zor sütunları ve kasasız kapsamlar **"Kasa oluşturulmamış"** der (satır 273–282, 306–317); canlı kabulde eksen Hafta 01..41, "42 YOK" (roadmap §16.12.1).
- **Admin — Üretim Planlayıcı:** `src/app/(admin)/admin/uretim-planlayici/actions.ts` → `preview_uretim_planlayici_scope_rows` (yazmasız) ve `uretim_planlayici_save_plan` (pending_approval); çift yetki `ai.manage ∨ questions.approve`.
- **Öğrenci yüzeyleri:** `src/lib/training/service.ts` → `select_training_questions {p_subject_id, p_limit, p_topic_id, p_outcome_id}` — **zorluk/seviye parametresi GEÇMİYOR** (satır 408–418). `src/lib/competition/service.ts` → `join_matchmaking_queue {p_subject_id}` — seviye yok (satır 179–183). `prepare_competition_pack` istemciden hiç çağrılmaz (yalnız types.ts:12271 sözlüğü; DB içi otomatik). Hiçbir öğrenci sayfası vault tablolarını doğrudan okumaz.
- **Haftalık kasa OLUŞTURMA / seed / scheduler kodu YOK**: `grep pg_cron supabase/migrations/` = 0; `grep "kasa.*seed|vault.*schedul" src/ supabase/migrations/` = 0 (resume/roadmap iddiaları canlı doğrulandı).

### 2.6 Belge–kod–canlı farkları (denetim bulgusu)

| # | Belge iddiası | Canlı gerçek |
|---|---|---|
| 1 | 150 ve 151 dosya başlıkları: "TASLAK — UYGULANMAMIŞTIR" | **İkisi de uygulanmış**: history 150/151 kayıtlı; `uretim_planlayici_list_vault_stock` pg_proc'te; `uq_question_active_single_vault` pg_indexes'te (resume 17. blok: 29 Ekim'de onayla uygulandı). Dosya başlıkları BAYAT — commit öncesi düzeltilmeli |
| 2 | 057 dosya gövdesi pencere `target_question_count` okur | DB'de yürürlükteki tanım 058/140 varyantı (metadata hedefi); drift 141:37–42'de resmî olarak kayıtlı |
| 3 | `current-task.json` "güncel görev" | rev 5'te takılı BAYAT checkpoint (UI-P4B.4); kanonik devam kaydı `~/cloud-recovery-20261017/evidence/resume.md` 21. blok (5 Kas) — kasa göreviyle ilgisi yok |
| 4 | "`student_league_memberships` 2 satır" (faz30b2) | Bugün **0 satır** — doğrulanamadı olarak kaydedildi (ortam sıfırlaması olabilir; tahmin yok) |

### 2.7 Test ve QA envanteri (kasa temaslı)

- `scripts/qa_150_151_vault_setup.sql` (785 satır): P1–P8 senaryoları — authenticated reddi (42501), service_role 36 satır/12 kolon, hedef değerleri (A1=300…D1=800), **P4 BEGIN/ROLLBACK yazmasızlık ispatı**, P5/P6/P7 tek-kasa unique_violation (aynı kasa + `uq_question_active_single_vault` kök kasada da), P8 taşıma yolu (inactive UPDATE + yeni aktif INSERT). Yeni geçiş QA'sı için **doğrudan yeniden kullanılabilir kalıp**.
- `scripts/qa_faz2_local_validation.sql`: prati̇k kasa + VA/VB/VC yarışma paket kasaları membership fixture'ları, hafta-bandı schedule fixture'ları, izin denetimleri.
- Birim/entegrasyon: `kasa-gorunum.test.ts` (bant→hafta, kırpım, tekilleştirme), `uretim-planlayici.test.ts` (pencere parser/kesişim), `haftalik-kasa/page.test.tsx` (yetki kapıları), `src/lib/training/integration.local.test.ts` (gerçek DB fixture: `vault_type='competition'` kasasının antrenmana girememe provası).

---

## 3. Uyum hedefi: yeni sözleşme ↔ mevcut yapı karşılaştırması

| Yeni sözleşme maddesi | Mevcut durum | Uçtan uca boşluk |
|---|---|---|
| 1. Sınıflar 9–12 | `grade_level` CHECK 1–12 (048:37–41); kasa verisi yalnız 12 | Şema uyumlu; veri 1/4 sınıf kapsıyor |
| 2. Haftalar 01–42 | `academic_weeks` 0–52 CHECK; yüklü takvim **K1–K41**; kasada hafta kimliği YOK (yalnız bant penceresi + metadata) | **Yapısal boşluk**: hafta-dozurgülü kasa kimliği yok; K42 kararı yok |
| 3. Seviyeler kolay/orta/zor | `difficulty_level` CHECK {easy, medium, hard, mixed} — kavramsal birebir | Şema uyumlu; canlıda medium/hard kasa 0; **etiket Türkçeleştirmesi (kolay/orta/zor) görünüm işi** |
| 4. Her uygun ders/sınıf/haftaya 3 kasa | 36 kasa, 0 hedef; hedef tablosu 0 satır | Tohumlama (seed) yok; 29 çift × hafta × 3 eksik |
| 5. Aynı ders/sınıf/hafta/seviyeye TEK kasa | Benzersizlik yalnız `vault_code` UNIQUE + 051 `(vault_id, question_id)`; **dörtlü benzersizlik YOK** | Yeni partial UNIQUE index şart (151 deseni) |
| 6. Öğrenci yalnız kendi sınıf/ders/aktif-hafta/seviye kasasına erişir | Seçiciler sınıfa göre çalışıyor; **hafta-kasa hizalaması ve seviye HiÇ yok**; seviye kimliği hiçbir yerde yok | Sunucu tarafı çözümleyici RPC + seviye kaynağı KARARI gerekli |
| 7. Geçmiş/gelecek hafta erken açılmaz | Antrenmanda konu kapısı `start_week <= hafta` (068:340–360) → gelecek konu açılmaz; yarışma paketinde hafta kavramı yok | Antrenman kapısı yeterli; haftalık kasalarda "yalnız AKTİF hafta" kuralı yeni RPC'ye yazılacak |
| 8. Seviye değişimi yarışma kurallarına uygun | Lig geçişi = puan bandı (+24/−12/0 → Bronz..Elmas); kolay/orta/zor geçiş kuralı sayısal olarak hiçbir yerde tanımlı değil (faz30b iki raporu: "KODDA_TANIMLI_DEĞİL"; `league_transition_rules` 0 satır, okuyucusuz) | **KARAR BEKLİYOR** — ürün kararı olmadan md. 6/8 kodlanamaz |
| 9. İçerik sızması yok | RLS policy'siz kasa tabloları + sanitize DEFINER payload (068 `_faz2_sanitize_question_payload`) | KORU; yeni yapıda da aynı disiplin |
| 10. Hazırlık / aktiflik / erişim ayrışması | Üçü de fiilen AYNI yerden okunuyor (üyelik = her şey); aktiflik penceresi yalnız planner'da okunuyor, seçimde kullanılmıyor | Üç katmanlı model yeni RPC'lerle kurulacak |
| Görünen isim `SINIF.DERS.SEVIYE.HAFTA`, UUID sabit | `vault_code` özgür text + UNIQUE — görünen isim kodun kendisi | Yeni kasalar sözleşme koduyla açılır; eski kodlar değişmez; `kasa-gorunum` etiketları zaten kodu taşır |

---

## 4. UYUMSUZLUK MATRİSİ (bileşen bileşen)

| # | Bileşen (kaynak) | Karar | Gerekçe + veri etkisi |
|---|---|---|---|
| 1 | `question_vaults` tablosu (048) | **KORU** | UUID kimlik + allow_* + difficulty契约 yeni sözleşmeyle uyumlu; md. 10 (UUID değişmez) burada zaten doğal |
| 2 | `question_vault_code` biçimi (TR-G12-MATH*) | **DEVREDEN ÇIKAR** (yalnız yeni kasalarda yeni biçim) | Eski kodlar SİLİNMEZ/değişmez (kurallar md. "eski kasa silinmez" + kasa-kurulum-plani §1.2); yeni haftalık kasalar `12.Matematik.kolay.01` biçimiyle YENİ satırdır |
| 3 | Eski hiyerarşi ağacı: kök→EASY→P1..P4→A/B/C/D yaprakları (049; 36 satır, 30 pencere) | **DEVREDEN ÇIKAR** (yeni sistem doğrulanınca `is_active=false`; açık onayla) | Bant kasaları (12 haftalık) "her haftaya tek kasa" md. 4/5 ile yapısal olarak bağdaşmaz; 1:1 eşleme mümkün değil. Veri etkisi: üyelik=0 → kapatma hiçbir öğrenci akışını değiştirmez; FK zinciri (10 adet) korunur, satırlar yerinde kalır |
| 4 | `question_vault_activation_windows` + [start,end) semantiği (048/057/058) | **KORU** | Haftalık kasa = tek haftalık pencere `[N-1, N)` (K=ham+1 kuralı kullanıcı onaylı) ile aynı tablo/semantik çalışır; kodsuz uyum |
| 5 | Hafta kimliğinin kolon olarak yokluğu (`question_vaults`'ta week yok) | **YENİDEN YAZ** (eklemeli) | Ya additive `week_number smallint` kolonu + partial unique, ya metadata + expression unique index. Öneri: açık kolon + partial UNIQUE (151 deseni; md. 5 tek-kasa garantisi DB kısıtı olur). Eski 36 satırda NULL kalır → sıfır etki |
| 6 | Aynı ders/sınıf/hafta/seviye tek kasa kısıtı | **YENİDEN YAZ** (yeni partial UNIQUE INDEX) | Bugün hiçbir kısıt yok; 151 GUARD/FINAL deseniyle eklenir; mevcut veri (36/0 üyelik) ihlal etmez |
| 7 | `vault_type` CHECK kümesi (048:19–31) | **KARAR BEKLİYOR** (alt seçenekli) | "Haftalık yarışma kasası" hangi type'ta yaşayacak? (a) `academic` + allow_competition=true → 065 ≤5 limiti ve 068 paket seçicisi DOKUNMAZ (pack seçici yalnız competition/one_v_one arar); (b) yeni `weekly` enum değeri → 065'ten muafiyet şeffaf ama CHECK ALTER'i gerekir; (c) `competition` → 065 ≤5 limiti haftalık havuzu patlatır (YAPILAMAZ). Öneri: (b) `weekly`; karar kullanıcıda (md. "kasa hazırlığı ayrışır" + 065/068 dokunulmazlığı) |
| 8 | 065 `validate_competition_vault_member_limit` trigger | **KORU** | ≤5 = yarışma PAKETİ boyu sözleşmesi (022); eski pack kasalarına dokunmaz; haftalık havuz (7. madde kararıyla) bu trigger'ın kapsamı dışında yaşar — limit GEVŞETİLMEZ |
| 9 | `prepare_competition_pack` (068:619/076/077) | **YENİDEN YAZ** (yeni haftalık seçici; eski korunduğu sürece çalışır) | Kasayı havuz değil PAKET sayan model (A: tam dolu ≤5; B: ≥5 ortak unseen) yeni sözleşmenin "haftanın kasasından yarışma" modeliyle bağdaşmaz; hafta + seviye filtresi bu akışa girmeli. Eski akış matchmaking'i (082) bozulmadan yeni dal eklenir; geçişte `competition/one_v_one` pack kasaları 0 olduğu için fiilen bozulacak bir şey yok |
| 10 | `select_training_questions` (068/104) | **DÜZELT** (kapsam kararıyla) | Antrenman = "işlenmiş konular" ürün kuralı olarak meşru; ancak md. 6 "güncel seviye kasası" antrenmana da yansıtılacaksa zorluk filtresi eklenmesi gerekir — ÜRÜN kararı; bugünkü 36 akademik easy kasa + membership=0 ile fiilen öğrenciye soru gitmiyor zaten (questions=0) |
| 11 | Öğrenci seviye kimliği (kolay/orta/zor) | **KARAR BEKLİYOR → YENİDEN YAZ** | DB/kod/belgede YOK (denetim bulgusu §3 md. 6/8). Seçenekler: (i) lig bandı→zorluk eşlemesi (Bronz=kolay... — 4 lige 3 seviye, sıkışır), (ii) `student_profiles`/yeni tabloya `competition_level` + geçiş kuralları (faz30b'nin sayısallaştırılması). Hangisi olmadan md. 6/8 uygulanamaz; **geçiş planının ilk kullanıcı kararı** |
| 12 | `student_league_memberships` + `_faz5_apply_competition_points` (016/078/105; +24/−12/0) | **KORU** | Altın Kalem lig sözleşmesi değişmez; seviye ekseni (11) buna BAĞLANIRSA tek doğruluk kaynağı burası olur; transition_rules tablosu ölü kalmaya devam eder |
| 13 | `league_transition_rules` (016:137–216) | **DEVREDEN ÇIKAR** (kayıt olarak; silme yok) | 0 satır + okuyucusuz (078:21 "MVP dışı"); seviye geçiş kuralları kararlaşınca ya buraya bağlanır ya da terk edildiği belgeye yazılır |
| 14 | `question_vault_memberships` (051) + 151 tek-kasa index | **KORU** | Üyelik modeli yeni sözleşmeyle uyumlu; "bir soru tek kasa" kullanıcı kararı (151) md. 5 ile çelişmez — soru haftalar arası KOPYALANAMAZ, ancak TAŞINABİLİR (P8 QA yolu). Havuz-bazlı kasa tasarımında bu bilinçli kısıttır |
| 15 | LEGACY-1..13 (`question_vault_topics`, 049:624–674) | **KORU** | Silinmez; gerçek kazanımmış gibi kullanılmaz (kasa-kurulum-plani §1.3); görünümde dürüst etiket zaten uygulanmış; BAĞ_EKLE ayrı kararı bekliyor (G12 OGM ünite eşlemesi) |
| 16 | `academic_weeks` + `resolve_current_academic_period` (067) | **KORU** | Deterministik + fail-closed; haftalık aktifliğin doğal saati; K42 kararı yalnız DATA kararı (yeni satır), kod değişikliği gerektirmez (`academic_calendar_upsert_week` admin yolu mevcut) |
| 17 | Kasa tablolarında RLS ENABLE + policy'sizlik | **KORU** | md. 9 sızma engelinin omurgası; yeni yapıda da aynı disiplin (istisna yok) |
| 18 | Kasa tablolarında `anon/authenticated` geniş `relacl` grantları | **DÜZELT** | RLS fiilen koruyor ama 108 hijyen ruhuyla çelişiyor; dar REVOKE (SELECT/INSERT/UPDATE/DELETE anon+authenticated'dan) küçük ve güvenli migration — QA'de hiçbir öğrenci/admin yolunun tabloyu DİREKT okumadığı kanıtlı (hepsi RPC) |
| 19 | Demand planner (057/058) + policies/snapshots (0 satır) | **KORU** | Pencere semantiği (start dahil/end hariç) haftalık pencereyle doğal uyumlu; `defined target` metadata'dan okunur → haftalık kasalara metadata hedefi verilebilir; service_role-only yüzey dar |
| 20 | `annual_stock_targets` (060; 0 satır) | **KORU** | Ayrı planlama kaydı; 300/500/≤5 kavram karışıklığı kasa-kurulum-plani §1.4'te zaten yasaklanmış — yeni sözleşme de bu ayrımı bozmaz |
| 21 | WP-08 üretim hattı (137/138/139/140: dispatch, claim vault dalı, approve→job köprüsü, liste RPC) | **KORU** | Talep `vault_id` taşır; haftalık kasalar talepler için yeni hedef olur; zincir şema-düzeyinde haftalık kasayla da çalışır (canlıda request=0) |
| 22 | `uretim_planlayici_*` RPC seti + save_plan (141) + panel | **DÜZELT** | Panel/planlama sözleşmesi doğru (pending_approval, onay ≠ üretim); DÜZELTmeler: (a) kasa listesi LIMIT 200 → haftalık seed sonrası 3.500+ satır (sayaç/limit ve sayfalama), (b) 150 stok RPC LIMIT 200 aynı sorun, (c) görünen etikette `SINIF.DERS.SEVIYE.HAFTA` doğal gösterim (kod zaten etiket) |
| 23 | `kasa-gorunum.ts` + `/admin/haftalik-kasa` | **DÜZELT (küçük)** | Görünüm sözleşmesi hazır (K=ham+1, kırpım, kasa-yok dürüstlüğü); haftalık kasalar eklenince otomatik dolar; 42 kararı gelirse tek sabit (`yilHaftaSayisi`) takvimden zaten gelir — kod değişikliği gerektirmeyebilir |
| 24 | `student_weekly_counters` 500 tavanı (068) | **KORU** | Tüketim tavanı kasa sözleşmesinden bağımsız; karıştırılmayacak (kasa-kurulum-plani §1.4) |
| 25 | `student_pack_exposures` (062) | **KORU** | "Hafta bitince kasalar yeni yarışmalara kapanır" izleme katmanı bu tablo + pencere üzerinden kurulur (resume 17: "hafta kapanışı izleme/uyarı katmanı sonraki dilim") |
| 26 | Haftalık kasa oluşturma/scheduling | **YENİDEN YAZ** | Hiç yok (pg_cron 0; seed 0; scheduling 0). Yeni iş: idempotent seed migration'ları + (cron DEĞİL) `resolve_current_academic_period` ile çalışan-zamanı çözümü — 067 fail-closed deseni yeterlidir |
| 27 | QA: `qa_150_151_vault_setup.sql`, `qa_faz2_local_validation.sql` | **KORU + GENİŞLET** | P1–P8 kalıpları yeni geçiş QA'sının iskeleti olur (§9) |
| 28 | 150/151 dosya başlıklarındaki "TASLAK" etiketi | **DÜZELT (belge)** | Canlıda uygulanmış; bayat etiketler commit hijyeni açısından düzeltilmeli (resume açık iş #6) |

---

## 5. Hedef kasa sayısı ve eksik hesabı

Geçerli sınıf-ders çifti (canlı ölçüm, aktif müfredat sürümü, 29 çift):
Matematik 9–12, Fizik 9–12, Kimya 9–12, Biyoloji 9–12, Coğrafya 9–12, Edebiyat/TDE 9–12 (24), Tarih 9–11, Felsefe 10–11.
Kapsam dışı sınıflar (Tarih 12, Felsefe 9/12, TDE Hazırlık) kasa üretmez ve "eksik" sayılmaz (kasa-kurulum-plani satır 5; hafta-konu-eşleme-analizi).

| Senaryo | Hesap | Hedef kasa | Mevcut (eşlenebilir) | Eksik |
|---|---|---|---|---|
| K1–K41 (takvim gerçeği) | 29 × 41 × 3 | **3.567** | 0* | 3.567 |
| K1–K42 (sözleşme hedefi) | 29 × 42 × 3 | **3.654** | 0* | 3.654 (K41'e göre +87) |

\* Mevcut 36 kasa **hiçbiri haftalık değildir** (12 haftalık bant kasaları); md. 5 "hafta+seviye başına TEK kasa"yı sağlayamazlar; bu yüzden 1:1 eşleme YOKTUR. İsteğe bağlı geçiş köprüsü (karar, §6-A3): 12.Matematik.kolay için 41 haftalık yeni kasaların hedef sayıları, eski A/B/C/D metadata hedeflerinden ("bandın haftaya bölünmesi" kuralıyla) ÖNERİ olarak türetilebilir; eski kasalar pasif kalırken hedef mirası alınabilir. Bu bir veri taşıma değil, hedef etiketleme kararadır; soru taşıması membership=0 olduğu için SIFIR maliyetlidir — **ancak kural uydurulmaz, kullanıcı onayı şart**.

Hafta başına üretim yükü referansı: K42'de her hafta 29 × 3 = 87 kasa; 12. sınıf Matematik haftada 3 kasa (`12.Matematik.kolay.NN` / `orta.NN` / `zor.NN`).

---

## 6. Uçtan uca erişim ve aktiflik modeli (UAT: `12.Matematik.kolay.01`)

### 6.1 Bugünkü gerçek (denetim)

1. **Sınıf** nereden: `student_profiles.grade_level` → `_faz2_student_context` (068:186–242; profil→schedule profile→müfredat sürümü zinciri, çözülemezse fail-closed). ✔ sağlam.
2. **Hafta** nereden/hangi anda: her RPC çağrısında anlık `resolve_current_academic_period()` (067:83–99; UTC takvim günü → tek hafta; boşsa `_faz2_require_period` istisna — 068:249–267). ✔ deterministik.
3. **Seviye** nereden: **HİÇBİR YERDEN.** Zorluk ne `student_profiles`'ta ne lig tablosunda kolay/orta/zor olarak var; `select_training_questions` argümanları arasında yok (training/service.ts:408–413), matchmaking'de yok (079/082). ✖ md. 6 uygulanamaz.
4. **Hafta↔kasa hizalaması**: seçim SQL'i kasa penceresini HİÇ okumuyor (068:412–422 yalnız tip+eligibility). `12.Matematik.kolay.01` adlı bir kasa yarın açılsa bile bugünkü seçici onu 37. haftada da 1. hafta gibi kullanırdı. ✖ md. 7 uygulanamaz (seviyesiz olduğu gibi).
5. **Sızma**: orta/zor/gelecek-hafta/başka-sınıf kasalarının içeriğine erişim bugün de imkânsız — ama "kasa" kavramı zaten toptan kapalı (RLS policy'siz) ve öğrenciye soru yalnız DEFINER RPC'lerden gidiyor. Frontend filtreleme hiçbir yerde kapı DEĞİL (kapı DB'de); doğrulandı: hiçbir öğrenci sayfası vault tablosu okumuyor (§2.5). ✔ md. 9 bugün için geçerli.

### 6.2 Hedef model (geçiş tasarımı — erişim katmanları ayrışmış)

```
[A] HAZIRLIK  : haftalık kasalar seed'le açılır (is_active=true, pencere [N-1,N),
                difficulty easy/medium/hard, allow_* bayrakları, metadata hedefi)
[B] AKTİFLİK  : "aktif hafta" = resolve_current_academic_period() (anlık, cron'suz);
                kasa→hafta bağı pencereden/week_number'dan; geçmiş hafta kasası
                kendiliğinden pasif (pencere dışı), KAPANIR — satır silinmez,
                başlamış yarışmalar + exposure kayıtları korunur (29 Ekim kararı)
[C] ERİŞİM    : YENİ DEFINER çözümleyici (örn. resolve_active_vault(p_subject_id)):
                auth.uid() → grade_level + seviye (md. 6 kaynağı §6-A1 kararıyla)
                + akademik hafta → TEK kasa; bulunamazsa fail-closed (068 deseni);
                paket/antrenman/tekrar RPC'leri soruları yalnız bu kasa kümesinden
                seçer; sanitize payload (068 _faz2_sanitize) aynen korunur
```

UAT senaryosu (hedef modelde): kolay-seviyeli 12. sınıf öğrencisi → `resolve_active_vault(Matematik)` = `12.Matematik.kolay.{aktif_hafta}`; `orta/zor` satırları çözümleme kümesine hiç girmez (sunucu kararı, frontend değil); gelecek hafta kasası pencere dışı → çözümlenemez; 9. sınıf kasası grade eşleşmez. Tüm negatifler §9'daki QA senaryolarıyla kanıtlanır.

---

## 7. K42 takvim kararı (md. 5)

- Ölçülü gerçek: `academic_weeks` 2026-2027 = **K1–K41** (2026-09-14 → 2027-06-28). K42 satırı YOK.
- Tasarım tarihi: 049 bantları 48 hafta varsayar; kullanıcı onaylı kuralla `[36,48)` → K37–41'e kırpıldı, "42–48 yıl dışı, ayrıntıda uyarılı" (vault-setup-onay-paketi §3; roadmap §16.12.1; canlı görünümde "42 YOK").
- `ak-question-pipeline-ux-01` (8 Kas) açıkça istiyor: dağıtımdan ÖNCE "dağıtım takvimi = K1–K41, pencereler ona kırpılır" tek cümleyle kanonikleştirilmeli. Resume açık iş #4: 41/42 kararı kullanıcıda.
- **Rastgele tarih üretmiyoruz.** K42'nin tek meşru yolu kullanıcı/ürün kararıdır; teknik olarak `academic_calendar_upsert_week` (calendar.manage RPC) ile tek satır eklenmesi yeterli — ama 2027-06-28 sonrası bir K42 tarihi resmî MEB takviminde karşılığı olmadan eklenirse tüm "hafta NN" sözleşmesi resmî takvimle çelişir.

**Karar önerisi (onay bekliyor):**
- **Seçenek 1 (önerilen):** Dağıtım takvimi kanonik olarak **K1–K41**; `SINIF.DERS.SEVIYE.HAFTA` haftaları 01–41 üretilir; "K42" hedefi 2027–2028 yılı takvimi açıklandığında o yıla devredilir. Ana sözleşmeye tek cümle eklenir.
- **Seçenek 2:** K42 = 2027-06-28 → 2027-07-05 olarak `academic_weeks`'e eklenir (takvim verisi, kod değişmez; +29×3=87 kasa). Yalnız kullanıcı "K42 resmî olmayan ek haftadır" diyorsa uygulanır; sınır uyarısı: 068 `week between 0 and 52` CHECK uyumlu, gist exclude uyumlu — teknik engel yok.
- Her iki durumda da seed migration'ları haftayı `academic_weeks`'TEN okur (sabit gömmez); K42 kararı sonra değişirse ek seed additive çalışır.

---

## 8. LEGACY-13 ve 36 mevcut kasa koruma planı

1. **Silme yok, DROP yok, TRUNCATE yok, kod değişimi yok** (kasa-kurulum-plani §1.2 sabit kuralı bu görevde de bağlayıcı).
2. 36 kasa + 30 pencere + 13 LEGACY topic: yeni seed'ler `ON CONFLICT (vault_code) DO NOTHING` ile **eski satırlara hiçbir zaman dokunmaz**; eski kod uzayı (`TR-*`) ile yeni kod uzayı (`9.*`–`12.*`) ayrışıktır — çarpışma imkânsız (canlı ölçüm: `TR-` dışı kasa yok, yeni biçimde kasa yok).
3. LEGACY-1..13: gerçek kazanımmış gibi kullanılmaz; görünümde "Konu planı henüz eşlenmedi" dürüst etiketi zaten yayında (kasa-gorunum testleri). BAĞ_EKLE (OGM ünite eşlemesi) ayrı kullanıcı kararı olarak olduğu gibi durur.
4. **Devreden çıkarma** en son ve yalnız: tüm yeni kasalar seed + QA yeşil + öğrenci erişim kanıtı tamamlandıktan sonra, AÇIK kullanıcı onayıyla `UPDATE ... SET is_active=false WHERE vault_code LIKE 'TR-G12-MATH%'` (tek data-only migration; FK zincirleri bozulmaz; rollback = aynı UPDATE true). Bu bile zorunlu değildir — pasif pencere semantiğiyle eski ağaç etkisiz de bırakılabilir; **satır silme hiçbir senaryoda yoktur.**
5. Membership=0 sayesinde hiçbir soru taşıma planı gerekmez; ilk gerçek membership yazımı (yeni RPC+UI, resume açık iş #3) eski kasalara değil yeni haftalık kasalara hedeflenir; 151 tek-kasa kısıtı taşmaları DB çekirdeğiyle reddetmeye devam eder.

---

## 9. Migration uygulama sırası (TASARIM — hiçbiri bu görevde uygulanmadı)

Önkoşul kararlar (kod öncesi): **A1** seviye kaynağı+geçiş kuralı (§6-C), **A2** K41/K42 (§7), **A3** `vault_type` politikası (matris #7). Bunlarsız M3+ yazılmaz.

| Sıra | İş | Tür | Kapsam/etki | Kabul |
|---|---|---|---|---|
| M0 | Yedek + taban çizgisi: pg_dump + SHA256 (kullanıcının korumalı terminali; 2 Kas AK-BACKUP-SAFE-01 deseni), salt-okunur sayaç raporu (36/30/13/0/0/41…) | operasyon | yazmasız | manifest + hash |
| M1 | Şema additive: `week_number smallint` (NULL) + `vault_type` CHECK genişlemesi `'weekly'` (A3=(b) ise) + partial UNIQUE `(subject_id, grade_level, difficulty_level, week_number) WHERE week_number IS NOT NULL AND is_active=true` — 151 deseni: GUARD (mevcut veride ihlal 0 — 36 satırda week NULL → geçer) + history + FINAL fail-closed | migration | 0 satır veri etkisi | index tanımı + GUARD/FINAL yeşil |
| M2 | Takvim satırı (yalnız A2=Seçenek 2 ise): `academic_weeks` K42 INSERT (idempotent) | migration/data | +1 satır | gist exclude çakışmasız |
| M3 | Haftalık kasa seed'i — sınıf-ders başına ayrı, idempotent migration (146–149 deseni; GUARD: `academic_weeks` sayacı + 29 çift yoksa FAIL; FINAL: beklenen sayı = 29×hafta×3 − 0): `vault_code='12.Matematik.kolay.01'`, name Türkçe, `vault_type='weekly'`, `week_number=N`, pencere `[N-1,N)` enabled, `allow_competition=true`, metadata hedef (A3 miras kuralı uygulanmışsa) | migration | +3.567/+3.654 satır, mevcut 36'ya DOKUNMAZ | tekrar koşum 0 yeni satır; sayaç tam |
| M4 | Erişim çözümleyici + seçim RPC'leri (additive): `resolve_active_vault`, haftalık paket hazırlayıcı (eski `prepare_competition_pack` korunur, matchmaking yeni dalı çağırır), seviye okuyucu (A1 kararı), tümü DEFINER + `search_path=''` + iç fail-closed + REVOKE/GRANT 150 deseni; mevcut 068 ailesine davranış bozmadan dal | migration | yeni fonksiyonlar; eski tanımlar ya hiç değişmez ya CREATE OR REPLACE ile geriye-uyumlu | §10 negatif/pozitif QA hepsi yeşil |
| M5 | Yönetici paneli: kasa listesi/stok RPC LIMIT 200 → sayfalama veya toplam-sayım kolonu; `/admin/haftalik-kasa` 3 seviye × N hafta grid'i 42 kararıyla hizalanır (muhtemelen kodsuz dolar); save_plan hedefi haftalık kasaya çevrilir (kasa seçimi zaten serbest) | kod+migration | UI; DB yazma sözleşmesi aynı (pending_approval) | mevcut admin test paketi + yeni fixture testleri |
| M6 | Membership yazım yolu (resume açık iş #3 ile birleşir): tek admin RPC + UI, iç izin, 151 ile uyumlu; eski kasalara yazım KAPALI hedef listeyle | migration+kod | yeni RPC | P5–P8 kalıbı QA |
| M7 | Erişilebilirlik/hijyen: kasa tablolarında anon/authenticated REVOKE (matris #18); haftalık-kasa relacl denetimi FINAL'e eklenir | migration | izin daraltma (gevşetme YOK) | `has_table_privilege` negative probe'lar |
| M8 | Devreden çıkarma (EN SON, ayrı açık onay): eski TR-G12-MATH* ağacı `is_active=false`; 049 dosyasına dokunulmaz (tarihî); bayat "TASLAK" başlıklarının belge düzeltmesi; commit serisi (kullanıcı onayı) | data-only migration | 36 satır status flag | erişim QA'sı değişmedi kanıtı |

**Güvenli durdurma koşulları (her adımda):** GUARD/FINAL istisnası → transaction rollback, dur; sayaç sapması (36→≠36, LEGACY≠13, membership≠0 öncesi) → dur; seed'de beklenmedik kod çarpışması → dur; QA'de tek negatif sızıntı (yetkisiz okuma) → M4+ ilerlemez; kota/erişim uyarısında → son commit'te dur ve raporla. **Hata başına ≤3 kontrollü deneme → BLOCKED.**

**Rollback (adım adım, silmesiz):**
- M1/M2/M4/M7: `DROP INDEX/FUNCTION` + history DELETE (151'in kendi rollback kalıbı); şema geri-alınabilir, veri kaybı yok.
- M3: haftalık kasa satırlarını silmek YOK → `is_active=false` (data-only) veya provada ROLLBACK; gerçek DB'de "görünmez kıl + işaretle".
- M8: `is_active=true` geri UPDATE.
- Genel: M0 dump + SHA256 + (varsa) off-box kopya; geri dönüş betikleri uygulamadan ÖNCE yazılır ve izole DB'de prova edilir (148/149 deseni).

---

## 10. İzole QA senaryoları (disposable DB — benzersiz ad/port, Docker envanter karşılaştırmalı)

Kalıp: `qa_150_151_vault_setup.sql` P1–P8 + 148/149 prova deseni. Tümü sentetik fixture; gerçek kullanıcı verisi kopyalanmaz.

- **Q1 Kimlik/izin:** anon & authenticated → kasa tabloları SELECT 0 satır; 150/141/140 RPC'lerine yetkisiz çağrı → 42501; `resolve_active_vault` oturumsuz → 42501.
- **Q2 Seed bütünlüğü:** M3 iki kez koşar → 0 yeni satır; sayaç = 29×hafta×3; eski 36 satırın `updated_at`/alanları BİREBİR değişmedi; LEGACY-13 = 13; `TR-*` kodları değişmedi.
- **Q3 Tek-kasa dörtlüsü:** aynı (grade, subject, difficulty, week)'e ikinci INSERT → 23505 (M1 indexi); farklı seviye/hafta → başarılı.
- **Q4 Pencere semantiği:** kasa K N'de `[N-1,N)`; `calculate_question_vault_demand(week=N-1)` aktif / `(N)` değil (start dahil/end hariç).
- **Q5 Erişim UAT (md. 6/7):** fixture öğrenciler — 12.sınıf-kolay: `resolve_active_vault` = `12.Matematik.kolay.{aktif}`; orta/zor/gelecek-hafta/9.sınıf sorguları → NULL/reddedilen kapsam. Seviye fixture'ı A1 kararına göre; A1=(i) ise lig-bandı→seviye matrisi tek tek doğrulanır.
- **Q6 Sızma (md. 9):** haftanın kolay kasasına üye fixture soru → orta/zor öğrenci RPC çıktısında soru KİMLİĞİ bile görünmez; `_faz2_sanitize` alan denetimi (correct_answer sızmaz).
- **Q7 Hafta kapanışı:** sahte takvimle ileri tarih simülasyonu (izole DB'de `academic_weeks` fixture yılı) → önceki hafta kasası çözümlenemez; `student_pack_exposures` eski kayıtları durur.
- **Q8 Geriye-dönük uyum:** eski matchmaking akışı (082→068) ve antrenman RPC'si fixture'larda değişmiş davranış göstermez; `vault_type='competition'` pack kasası senaryosu (qa_faz2 fixture'ları) aynen geçer.
- **Q9 065 limiti:** `weekly` kasasına >5 aktif üye KABUL (kapsam dışı); `competition` kasasına 6. üye RED (limit gevşemedi kanıtı).
- **Q10 Hijyen (M7 sonrası):** `has_table_privilege('anon','question_vaults','SELECT')=false` vb.; FINAL bölümlerine gömülür.
- Kapanış: kalıntı sayacı 0 (fixture temizliği), konteyner/ağ envanteri öncesi/sonrası karşılaştırmalı.

---

## 11. Açık riskler

| # | Risk | Etki | Azaltım |
|---|---|---|---|
| R-1 | **Seviye ekseni yokluğu** (md. 6/8 sunucuda uygulanamaz; faz30b sayısız; transition_rules ölü) | Blokör — M4 yazılamaz | §6-A1 kararı; geçiş planı bunu ilk kullanıcı kararı olarak kilitler |
| R-2 | **41/42 belirsizliği** | Seed sayımı ±87; kullanıcıya görünen "42" sözü ile takvim çelişkisi | §7 kararı; seed haftayı takvimden okur (kod geleceğe dayanıklı) |
| R-3 | 065 ≤5 limiti ile haftalık havuz çelişkisi (eğer `competition` type seçilirse) | Seed/QA'da patlar; yanlış iş çözümü üretime sızar | Matris #7 kararı; QA Q9 negatif+pozitif kanıt |
| R-4 | `prepare_competition_pack` eski modeline yeni haftalık kasaların sızması (grade+subject eşleşmesiyle yanlış seçim) | Yanlış haftanın/hiç kasasının paketlenmesi | M4'te ayrı dal; eski seçici kapsamı dar tutulur; Q8 regresyon |
| R-5 | Geniş relacl (anon/auth tam grant) — RLS bugün kapatıyor ama tek policy ihlali anında açığa çıkar | Güvenlik borcu | M7; FINAL'e izin denetimi gömülür |
| R-6 | List RPC'lerinde LIMIT 200 (141/150) 3.500+ kasada sessiz kırpma | Admin panelinde eksik görünüm ("uydurma yok" ilkesi zedelenir) | M5 sayfalama; QA'da sayaç kolonu |
| R-7 | Sözleşme katmanları: hafta/42 kararı ana sözleşmede yok; `current-task.json` bayat; 150/151 başlıkları bayat; HEAD 06fa906'dan beri commit yok (198+ dosya çalışkan ağaçta) | Belge-kod sürüklenmesi; geri dönülemez kayıp riski | Kararların ana sözleşmeye işlenmesi + commit serisi (KULLANICI ONAYI — push ayrı izin) |
| R-8 | Off-box yedek yok (resume 19/20: her şey aynı diskte) | Felaket senaryosunda seed/uygulama sonrası dönüşsüzlük | M0 yedeği + kullanıcı talimatıyla manuel yedek; V2 kurulumu kullanıcı kararıyla durduruldu — hatırlatılır |
| R-9 | Eski 36 kasayı "etkili" sanma yanılgısı (üyelik 0; öğrenciye hiç soru gitmiyor) | Yanlış önceliklendirme ("kasa var, iş bitmiş") | Bu raporun §0/§2 ölçümleri referans alınsın; görünümler zaten "okunamıyor/0" ayrımını yapıyor |

---

## 12. Ayrı kullanıcı onayı gerektiren işlemler (hiçbiri bu görevde yapılmadı)

1. **A1 — Seviye kaynağı ve geçiş kuralı** (md. 6/8): lig-bandı eşlemesi mi, yeni `competition_level` alanı + sayısallaştırılmış geçiş kuralları mı (faz30b). Ürün kararı.
2. **A2 — K41 vs K42** (§7): takvim verisi eklemek (K42 tarihi) veya K1–K41 kanonikleştirmesi + ana sözleşmeye tek cümle.
3. **A3 — `vault_type='weekly'`** (CHECK genişletme) veya eşdeğeri kapsam kararı (matris #7).
4. **M1–M8 migration'larının uygulanması** — her biri kendi onay paketleriyle (GUARD/FINAL + izole prova + yedek); toplu tek onay verilmez.
5. **Eski 36 kasanın `is_active=false` devreden çıkarılması** (M8) — yalnız tüm doğrulamalar sonrası.
6. **Membership yazım RPC'si + paneli** (M6) ve ilk gerçek soru dağıtımı (promotion→aktivasyon→kasa zinciri insan kararları: 039/040 kapıları).
7. **Yedek alma (manuel)** ve izole-prova ortamı hazırlığı (Docker envanter karşılaştırması).
8. **Git commit/push serisi** (bayat başlıklar dahil) — push sonrası CI yeşili olmadan faz bitmiş sayılmaz.
9. `annual_stock_targets` satırlarının doldurulması (300 tabanlı haftalık plan kaydı — kasa hedefinden ayrı; 0 satır "planlama yapılmadı" demektir, kusur değil).

---

## 13. Sonuç

Eski kasa mimarisi **çalışan iskeleti koruyan, yapısal kabuğu değiştirilen** bir geçişle yeni sözleşmeye taşınabilir: 048/051/067 tablo çekirdeği, 057/058 planlama motoru, RLS disiplini, 150/151 ve WP-08 hattı **KORU**; bant-tabanlı 36 kasalık 049 ağacı doğrulanmış yeni sistem devreye alınırken **DEVREDEN ÇIKAR** (flag-only); hafta kimliği, tek-kasa dörtlü kısıtı, seviye ekseni ve haftalık erişim/paket çözümü **YENİDEN YAZ** (tamamı additive); panel ve izin hijyeni **DÜZELT**; seviye geçiş kuralları ile K42 **KARAR BEKLİYOR**. Sıfır DROP/DELETE/TRUNCATE, sıfır eski-kasa değişikliği, kanıtlı yedek ve 151/148/149 kalıbında GUARD/FINAL/izole-prova disipliniyle plan, altı açık kullanıcı kararı (A1–A3 + M-onayları + commit/push) bekler durumdadır.

**GÜVENLİ DUR korunuyor: denetim ve plan dışında hiçbir işlem yapılmamıştır.**
