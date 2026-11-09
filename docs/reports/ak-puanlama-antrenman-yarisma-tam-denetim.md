# AK-SYSTEM-AUDIT-01 — Puanlama, Antrenman ve Yarışma Sisteminin Tam Denetimi

**Proje:** Altın Kalemler · **Tarih:** 9 Kasım 2026 · **Mod:** Salt-okunur denetim
**Kanıt kaynakları:** Canlı Supabase DB (`supabase_db_yarisma-programi`, `pg_get_functiondef` ile çekilen **fiilî** fonksiyon gövdeleri), `supabase/migrations/` zinciri, `src/` TypeScript yüzeyi.
**Yöntem kuralı:** Her iddia ya canlı DB ölçümü/fonksiyon gövdesi ya da dosya+migration referansıyla desteklenir. Dokümandaki "tamamlandı" ibareleri tek başına kanıt sayılmamıştır. Canlı DB'de bu oturumda hiçbir yazma yapılmamıştır; puan örnekleri salt-okunur `SELECT resolve_competition_points(...)` çağrılarıyla doğrulanmıştır.

---

## 1. Yönetici özeti

1. **Puanlama motoru canlıda ve tamamen sunucu tarafındadır.** Aktif kural seti `competition_scoring_v3_fixed` (Faz 30D): sabit matris + süre bandı + rakip/bant bonusu. Puan formülü icat edilmemiş, canlı matris satırlarından (`scoring_point_rules`, 252 aktif satır) okunmuştur.
2. **İkili yarışma ucu bucağıyla kodlanmıştır ve entegredir:** `join_matchmaking_queue` (eşleştirme + 5 soruluk paket + atomik auto-prepare) → `advance_competition_progress` (soru sırası + deadline) → `submit_competition_answer` (sunucu değerlendirmesi + bant + puan) → `finalize_competition_if_ready` (sonuç + `+24/0/−12` lig rating'i + XP + lig geçişi). TS istemci katmanı (`src/lib/competition/service.ts`) bu RPC'lerin tamamını çağırır.
3. **Antrenman sahası puansız, bireyseldir:** `select_training_questions` → `submit_training_attempt` → `ingest_student_attempt`; yalnız XP (2/3/5), seri ve rozet üretir. Yarışma puanına, lig rating'ine ve bir "zorluk seviyesine" etkisi **yoktur** (kanıtla §4, §6).
4. **Üç kavram fiilen ayrıdır ve doğru ayrışmıştır:** lig (Bronz→Elmas, rating tabanlı) CANLI; soru-zorluğu (easy/medium/hard) soru/varya düzeyinde CANLI; performans sınıfı (perfect/good/average/poor/…) v3 bant motorunda CANLI. Buna karşılık **"kolay→orta→zor öğrenci seviye geçişi" diye bir mekanizma DB'de de kodda da YOKTUR** — `student_training_levels` ve `training_levels` tabloları 0 satırlı, hiçbir fonksiyonun okumadığı ölü yapılardır (§6).
5. **Beklenen kritik boşluk — veri katmanı:** 36 aktif kasa kabuğu var (`vault_type='academic'`) ancak `question_vault_memberships=0` ve `questions=0`. Bu durumda `prepare_competition_pack` fail-closed davranır: **bugün canlı yığında tek bir yarışma dahi başlatılamaz**; antrenman da boş havuz döndürür. Yarışma antrenman akışları "CANLIDA ÇALIŞIYOR" için uçtan uca veri kanıtı içermez (kanit yetersiz → §8, §12).
6. **Güvenlik bulgusu (Kritik):** `get_internal_correct_answer` public şemada, `authenticated` ve `anon` rollerine EXECUTE'lu ve gövdesinde hiçbir kimlik/yetki kontrolü yok. Correct answer'ı soru UUID'sini bilen **herkese** döndürür (§10 SEC-1).
7. Düzeltme notu: önceki denetim raporundaki "prepare_competition_pack kasa kullanmıyor, istemciden çağrılmıyor" değerlendirmesi **fiilî sürüm için yanlıştır**; canlı sürüm (077+082 sonrası) kasa tabanlıdır ve eşleşme anında katılımcının kendi transaction'ında çağrılır (§8.2).

---

## 2. Gerçek puanlama formülleri ve örnek hesaplar

### 2.1 Aktif kural seti

`scoring_rule_sets` (canlı satırlar):

| rule_set_code | version | is_active |
|---|---|---|
| `faz5_default` (v1, migration `094_competition_scoring_v1_seed.sql`) | 1 | **false** |
| `competition_scoring_v2_negative_wrong_timeout` (`127_…`) | 2 | **false** |
| `competition_scoring_v3_fixed` (`128_faz30d_v3_sabit_puan_rakip_bonus_ustalik_golge.sql`) | 3 | **true** |

`join_matchmaking_queue` yaratılan her yarışmaya aktif seti yazar (canlı gövde: `where srs.is_active = true … limit 1` → bugün v3).

### 2.2 Sabit puan matrisi (canlı `scoring_point_rules`, v3 = 252 aktif satır, 1–12 sınıf × 3 zorluk)

Canlı `SELECT public.resolve_competition_points('602eed11-…',12,…)` çağrılarıyla **birebir doğrulanmıştır**:

| Sonuç \ Zorluk | easy | medium | hard |
|---|---|---|---|
| correct · band `perfect` | **130** | **195** | **260** |
| correct · band `good` | 120 | 180 | 240 |
| correct · band `average` | 110 | 165 | 220 |
| correct · bantsız/`poor` (fallback temel) | 100 | 150 | 200 |
| wrong | **−20** | **−30** | **−40** |
| timeout | **−20** | **−30** | **−40** |
| pass | 0 | 0 | 0 |

- `resolve_competition_points` (public, SECURITY DEFINER): önce `band_code`-satırına özel kural, bulunamazsa `band_code IS NULL` genel satıra düşer (canlı gövde). `poor`/`poor_grace` için matris satırı yoktur → canlı test: `easy/correct/poor → 100` (V2-uyumlu temel puan).
- "Puan asla 0 olmaz" sözleşmesi yalnız `pass` için 0'dır; wrong/timeout negatiftir (v2'den devralınan davranış, 127).

### 2.3 Cevap süresinin etkisi — v3 süre bantları

`private.faz30d_v3_resolve_band(p_time_ms, T)`, `T = questions.expert_solution_time_seconds`:

| Bant | Aralık | Türkçe karşılık | Puan etkisi |
|---|---|---|---|
| `perfect` | süre ≤ 1,00·T | Mükemmel | tam bant puanı |
| `good` | ≤ 1,20·T | İyi | tam bant puanı |
| `average` | ≤ 1,40·T | Orta | tam bant puanı |
| `poor` | ≤ 1,60·T | Kötü | fallback temel puan |
| `poor_grace` | ≤ 1,75·T | Kötü (tolerans) | fallback temel puan |
| `proposed_timeout` | > 1,75·T | Çözememe adayı | (fiilî timeout cevabı `timeout` sonucuna − puan yazılır) |
| T yok/≤0 | — | — | bant NULL → fail-closed `v3_missing_expert_time`, temel puan |

`time_ms` sunucuda hesaplanır: `CHECK (time_ms = GREATEST(0, floor(extract(epoch from (LEAST(answer_received_at, deadline_at) - sent_at)) * 1000)))` (canlı `competition_answers` constraint'i) — istemci süresi güvenilmez, deadline'a kırpılır.

### 2.4 Rakip performansının etkisi — rakip/bant bonusu

`private.faz30d_v3_apply_opponent_bonus()` — `competitions` üzerinde `status → 'completed'` geçişinde tetiklenen trigger; yalnız v3 setinde çalışır; yarışma bazlı `pg_advisory_xact_lock`. Kurallar (`faz30d_v3_opponent_bonus_rules`, canlı satırlar):

| rule_key | değer | koşul |
|---|---|---|
| `opponent_wrong_or_timeout` | **+20** | benim doğru cevabım + rakip aynı soruda wrong/timeout |
| `band_gap_1 / _2 / _3` | **+5 / +10 / +15** | iki doğru, bant rank farkı 1/2/3 (rank: perfect=3, good=2, average=1, poor=0) |
| `same_or_worse_band` | 0 | eşit/alt bant |

Yalnız **kendi doğru cevapları** bonus üretir; rakip cevap yoksa veya bantlardan biri NULL ise bonus üretilmez (canlı gövde `CONTINUE WHEN …`). Uygulama: `UPDATE competition_players SET total_points = SUM(points_awarded) + v_bonus` + gölge (shadow) `faz30d_global_points_events` kaydı (idempotent `event_key` + mutlak toplam yeniden hesabı).

### 2.5 Kazanma/kaybetme/beraberlik ve yarışma sonu puanı

- `finalize_competition_if_ready(p_competition_id)`: tüm soruların tüm oyuncularca cevaplanması → oyuncuları `finished`; sonra en yüksek iki skora göre `win/draw/loss` ve kazanan belirlenir; `competition_results` + JSONB snapshot'lar (`question_results`, `player_results`, `final_scoreboard`, `scoring_snapshot`) yazılır. **Satır 519 (canlı gövde): `PERFORM public._faz5_apply_competition_points(p_competition_id);`**
- `_faz5_apply_competition_points` (Faz 5 motoru, migration `078`, Faz 9 revizyonlu canlı gövde): lig konfigürasyonu `league_rule_sets('faz5_competition_rating').configuration` = **`{"win": 24, "draw": 0, "loss": 12, "forfeit_win": 24, "forfeit_loss": 12}`** → galibete +24, beraberliğe 0, mağlubiyete −12 rating. Yazımlar: `competition_point_changes (change_type='rating')` `ON CONFLICT (competition_id,user_id,change_type) DO NOTHING` + ön kontrol (`if exists … change_type='rating' then return`). Lig geçişi: yeni rating'i `leagues.min_points/max_points` aralığına oturtur; lig değiştiyse `student_league_memberships` güncellenir + `student_league_history` satırı. Ayrıca `_faz9_grant_competition_xp` + günlük aktivite + rozet değerlendirmesi.

### 2.6 transaction ve yetkilendirme güvenliği; çift ödüllendirme engelleri

- Tüm yazım yolları `SECURITY DEFINER` + `search_path` sabit; istemcinin `competition_answers`, `competition_point_changes`, `student_league_memberships` üzerinde hiçbir policy/yetkisi yok (§10).
- **Çift cevap engeli:** `UNIQUE (competition_question_id, user_id)` (`competition_answers`) + submit gövdesinde erken `Answer already submitted` kontrolü (canlı gövde satır ~210).
- **Çift rating engeli:** iki katman (§2.5).
- **Gölge katman idempotency:** `faz30d_global_points_events` `event_key` UNIQUE + toplamların olaylardan mutlak yeniden hesabı.
- Timeout'lar yalnız deadline geçtikten sonra üretilir (`create_missing_competition_timeouts`, 102 cutoff guard: `IF deadline henüz geçmediyse → RETURN 0` canlı gövde).

### 2.7 Örnek hesaplar (mevcut canlı formülle; bonus kuralları §2.4'ten uygulanmıştır)

Soru 12. sınıf yarışması, v3 aktif. "Bonus" sütunu rakibin aynı sorudaki cevabına bağlıdır.

**Örnek A — Öğrenci A mükemmel, Öğrenci B orta (average) çözüyor:**

| Soru zorluğu | A (perfect) | A bonus (gap=2 → +10) | A toplam | B (average) | B bonus (rank farkı negatif → 0) | B toplam |
|---|---|---|---|---|---|---|
| easy | 130 | +10 | **140** | 110 | 0 | **110** |
| medium | 195 | +10 | **205** | 165 | 0 | **165** |
| hard | 260 | +10 | **270** | 220 | 0 | **220** |

**Örnek B — A yanlış, B doğru (perfect) çözüyor (easy):** A = **−20** (yanlış cevap bonusu üretemez); B = 130 **+20** (rakip wrong fault bonusu) = **150**.

**Örnek C — İkisi de çözemiyor:**
- ikisi de wrong → zorluğa göre **−20 / −30 / −40** (her ikisi); bonus yok.
- ikisi de timeout → aynı negatif değerler.
- ikisi de pass → **0 / 0** (tek sıfır-puan durumu).

**Örnek D — Tam yarışma ucu uca (easy havuz, T=60s):** A: 5× perfect (5×130) + rakip 2 soruda wrong (+2×20) + 3 soruda gap-1 (+3×5) = 650+40+15 = **705**. B: 3× average (330) + 1 wrong (−20) + 1 pass (0) = **310**. Sonuç: A kazanır → rating A **+24**, B **−12**; XP `_faz9_grant_competition_xp` (Faz 9 tablosu), lig konumu 705→Bronz aralığında kalır (eşik 1000).

---

## 3. İkili yarışmanın uçtan uca akışı (13 adım, canlı kanıt)

| # | Adım | Karşılık | Durum |
|---|---|---|---|
| 1 | Yarışmaya katılma | `MatchmakingQueue.tsx` → `join_matchmaking_queue(p_subject_id)` (rate-limit 10/300sn, `076`); kimlik `auth.uid()`, sınıf `student_profiles.grade_level` | CANLI |
| 2 | Rakip eşleştirme | Aynı RPC içinde: `pg_advisory_xact_lock('faz5mm:'||grade||':'||subject)` kovası, en eski taze `waiting` partner (15 dk `expires_at`); partner yoksa `{status:'waiting'}` | CANLI |
| 3 | Ders/sınıf seçimi | Ders = RPC parametresi; sınıf = öğrenci profilinden zorunlu (istemci sınıf seçemez) | CANLI |
| 4 | Zorluk seviyesi | **Yarışma geneli zorluk yok.** `competitions` yaratılırken `difficulty` yazılmaz; zorluk soru bazlıdır (§4 adım 6) | HATALI/UYUMSUZ* |
| 5 | Kasa seçimi | `prepare_competition_pack`: `vault_type='one_v_one'` (yarışma tipi `one_vs_one`), aktif, grade+subject eşleşen kasa; A-öncelik: eligible üyelik sayısı **tam** `question_count`=5 ve hiçalık kasa görmedi (`student_pack_exposures` yok); B-yedek: görülmemiş üyelik ≥5 | CANLI (kod) — bugün fail-closed (§8) |
| 6 | Tam 5 soru | `insert … competition_questions (…, question_order, difficulty)` tam `question_count` satır; sayı uyumsuzluğu ve `difficulty` NULL/geçersiz → **exception + tam rollback**; üst sınırı 022 trigger'ı `validate_competition_question_limit` + UNIQUE'ler korur | CANLI |
| 7 | Sunum | `set_competition_player_ready` → `advance_competition_progress` soruları **sıra ile** açar (`sent_at` + `deadline_at` = `resolve_competition_question_time_limit`); `get_current_competition_question` yalnız aktif soruyu sanitize payload ile verir | CANLI |
| 8 | Cevap alma/değerlendirme | `submit_competition_answer` (public wrapper → `private.` gövde): katılımcı + **yalnız current soru** + deadline geçildiyse önce `create_missing_competition_timeouts`; A–E normalizasyon; değerlendirmeye sunucu karar verir | CANLI |
| 9 | Performans sınıflandırma | `time_ms` (constraint'li) → `faz30d_v3_resolve_band` → `time_band_code/name` BEFORE-trigger `faz30d_v3_score_answer` + `trigger_snapshot_competition_answer_band_name` | CANLI |
| 10 | Karşılıklı puan | Satır içi: `points_awarded = resolve_competition_points` (trigger + submit gövdesi satır ~302); `after_competition_answer_progress` trigger'ı her cevaptan sonra `recalculate_competition_player_score` (=`SUM(points_awarded)`) + `advance` çağırır | CANLI |
| 11 | Tamamlanma | Her cevaptan sonra `finalize_competition_if_ready` (submit gövdesi satır ~409); timeout'lar deadline sonrası üretilir | CANLI |
| 12 | Sonuç kaydı | `competition_results` + scoreboard/snapshot JSONB; `competitions.status='completed'` → rakip-bonus trigger'ı (§2.4) | CANLI |
| 13 | Puan/seviye güncellemesi | finalize satır 519 → `_faz5_apply_competition_points`: rating ±, `student_league_history`, lig geçişi, XP, rozet | CANLI (kod) — canlıda 0 çalıştırma kanıtı |

\* Adım 4 "HATALI/UYUMSUZ" notu: yeni haftalık mimarinin `kolay/orta/zor` ekseni bu akışta hiç yok; mevcut akış kendi içinde tutarlıdır (bkz. §13).

**Beş soru kuralının sunucuda zorunluluğu (§7):** eşleştirme yolu **her zaman** `question_count=5` yazar (`079_faz5_matchmaking_entry.sql:202` "MVP #8"; canlı gövde `values (…, 5)`). Tablo CHECK'i `question_count BETWEEN 1 AND 5`tır; yani CHECK tek başına 5'i dayatmaz, ancak (a) matchmaking sabiti, (b) paket materyalizasyonunun tam sayı kontrolü (eksik/fazla → rollback), (c) 022 limit trigger'ı, (d) `current_question_order <= 5` CHECK'i ve (e) finalize'ın "tüm sorular cevaplanmadan bitmez" kuralı birleşince eşleştirme akışında 5 fiilen zorunludur. Yönetici/diğer yaratım yolları 1–5 arası üretebilir — haftalık mimaride sözleşme netleştirilmelidir.

---

## 4. Antrenman sahasının uçtan uca akışı

Giriş ve akış: `src/lib/training/service.ts` → `start_training_session` (110, oturum sarmalayıcı) → `select_training_questions` → öğrenci soruyu çözer → `submit_training_attempt` → `get_attempt_feedback` (109); oturum ilerlemesi `advance_training_session`; kota ekranı `get_my_weekly_usage`; konu/kazanım listeleri `list_training_topics`/`list_training_outcomes`.

Soru bazlı denetim yanıtları (hepsi canlı fonksiyon gövdesinden):

1. **Nasıl giriliyor?** Öğrenci antrenman sayfası → `start_training_session` + `select_training_questions(p_subject_id, p_limit 1..50, p_topic_id|p_outcome_id)`.
2. **Bireysel mi, ikili mi?** Tamamen **bireysel**. Eşleşme/rakip kavramı antrenman RPC'lerinde, tablolarında ve TS servislerinde yoktur.
3. **Antrenman rakip eşleştirmesi var mı?** Yok. `matchmaking_queue` yalnız yarışmaya aittir.
4. **Hangi kasalardan?** `question_vault_memberships.membership_status='active'` **ve** `practice_eligible=true` **ve** kasa `is_active` **ve** `vault_type NOT IN ('competition','one_v_one')`. Bugün 36 kasa `academic` tipinde uygundur, **ancala üyelik=0 ve soru=0** → havuz boş (§8.4).
5. **Kaç soru?** İstemci `p_limit` ister (1–50); fiilen `least(p_limit, haftalık_kalan, günlük_kalan)` kadar verilir.
6. **Kolay/orta/zor ayrımı?** **YOK.** Canlı `select_training_questions` imzasında zorluk parametresi yoktur; sorguda `difficulty` filtresi yoktur (canlı gövde satır 1–393'te hiç geçmez). `student_training_levels` hiçbir fonksiyon tarafından okunmaz (canlı arama: 0 fonksiyon) ve 0 satırdır.
7. **Cevap kontrolü:** `submit_training_attempt` DB'deki `questions.correct_answer` ile karşılar (`graded_by: 'db_correct_answer'` metadata); sonuç ∈ `correct/wrong/pass/timeout/blank`; **yalnız daha önce `attempt_context='training'` olarak gösterilmiş soru** gönderilebilir (exposure kontrolü).
8. **Sonuçlar nerede?** `student_question_attempts` (+ zorunlu `p_client_key` idempotency'si) ve `student_dimension_metrics` (subject/difficulty/cognitive_type/question_type/topic/subtopic/outcome eksilerinde doğru-yanlış-tekrar sayaçları, `ingest_student_attempt` canlı gövdesi).
9. **Yarışma puanlarını etkiliyor mu?** **Hayır.** `ingest_student_attempt` içinde XP/rozet/seri yalnız `p_attempt_context='training'` dalında; rating yazan tek motor `_faz5_apply_competition_points`tır ve yalnız `competitions.status='completed'` zincirinden çağrılır. Antrenmanın lig rating'ine giden hiçbir yazma yolu yok.
10. **Seviye yükselmeyi etkiliyor mu?** Hayır — yükseltilecek kalıcı seviye zaten yok (§6). Etkisi yalnız XP: correct başına easy +2 / medium +3 / hard +5 (`_faz9_grant_training_xp`, `UNIQUE(source_type,source_id,user_id)` ile idempotent), doğru/yanlış cevap günlük seri aktivitesi, rozet değerlendirmesi.
11. **Aynı soru yeniden sunulabiliyor mu?** Evet, kontrollü: önce hiç görülmemişler (`student_question_exposures`'ta olmayanlar), yetmezse görülmüşler tekrar olarak dolar; tekrarlar `repeat_*` metriklerinde izlenir.
12. **Haftalık yarışma sorularından ayrılmış mı?** **Kısmen:** ayrım üyelik bayraklarındadır (`practice_eligible` vs `competition_eligible`/`one_v_one_eligible`) + yarışma paketi kasa-bazlı `student_pack_exposures` görmezden gelir. **Hafta ekseni yoktur**: "bu haftanın yarışma soruları antrenmanda görünmez" garantisi hiçbir yerde yok. Kota kapıları: haftalık yeni-soru 500/ders (`student_weekly_counters`), günlük 500 (FAZ9), `training_select` 90/saat, `training_submit` 240/saat.

Müfredat kapısı (canlı gövde): aday sorular öğrencinin **kendi** müfredat profilinde `start_week <= bu hafta` olan işlenmiş konu/kazanımlara `approved` eşlemeli olmalıdır; dışarıdan gelen topic/outcome filtresi fail-closed reddedilir (`gecersiz_kapsam`). `end_week` bilinçli kullanılmaz (işlenen konu kalıcı erişilir).

Ölü sistem notu: `training_maps`/`training_levels`/`training_star_rules`/`training_unlock_rules` (018) harita-yıldız sistemi tasarımıdır; `training_levels=0 satır`, öğrenci akışından çağıran yok → **YALNIZCA TASARIM**.

---

## 5. Lig, zorluk ve performans arasındaki ayrım

| Kavram | Teknik karşılık | Kalıcılık | Durum |
|---|---|---|---|
| **A. Lig seviyesi** | `leagues` 4 satır: **Bronz 0–999 · Gümüş 1000–2499 · Altın 2500–4999 · Elmas 5000+** (`min_points/max_points`); öğrencinin `student_league_memberships.rating_points` değeri yarışma başına **+24 / 0 / −12** (forfeit 24/−12) değişir | Kalıcı (sezon motoru `101_faz8_league_season_engine`: `close_league_season` + `leaderboard_*`; pg_cron yok → sezon kapatma manuel/yönetimsel) | CANLI (kod+konfig) — 0 öğrenci kaydı, 0 çalıştırma kanıtı |
| **B. Yarışma zorluğu (kolay/orta/zor)** | Soru/üyelik boyutlu `difficulty ∈ {easy,medium,hard}`; yarışmaya değil **soruya** yazılır (`competition_questions.difficulty`, paket anlık görüntüsünden) | Soru özniteliği | CANLI (soru düzeyinde) — **öğrenci düzeyinde "zorluk seviyesi" kavramı yok** |
| **C. Çözme performansı** | v3 bantları: `perfect/good/average/poor/poor_grace/proposed_timeout` + `answer_result ∈ correct/wrong/timeout/pass` | Cevap başına anlık; `time_band_code`, `points_awarded`, gölge tablo `faz30d_answer_shadow` | CANLI |

Bu üçü kodda birbirinden temiz ayrılmıştır; karıştıran tek şey doküman dilidir ("seviye" kelimesi üçü için de kullanılıyor). Belgedeki "Mükemmel/İyi/Orta/Kötü/Çözememe" eşlemesi C satırındadır (§2.3).

Ayrıca **ustalık gölge skoru** dördüncü, ayrı bir değerdir: `faz30d_answer_shadow._v3_delta` (perfect +150, doğru 0, hatalı −20/−30/−40 — `faz30d_v3_mastery_rules`) ve `faz30d_global_points_totals` (eşikler 0 / 15.000 / 37.500 → L1/L2/L3, `faz30d_v3_level_thresholds`). Bu **yalnız gölge** katmandır: UI'a/lig'e bağlanmamıştır (canlı tablo satır sayısı 0).

---

## 6. Seviye yükselme koşulları

**Lig geçişi (var ve canlı koda bağlı):**
- Puan eşikleri `leagues.min_points/max_points`'ten gelir (§5.A); "puan" = `rating_points` (yarışma sonuçlarından gelen +24/0/−12 toplamı).
- Geçiş her yarışma sonunda `_faz5_apply_competition_points` içinde uygulanır: yeni rating'i kapsayan lige taşı, `student_league_history`'ye `(old→new, yön)` yaz (canlı gövde satır ~209–242).
- Ders bazlı mı? **Genel.** `scope='general'`; ders bazlı lig yok.
- Düşme var mı? Evet — rating eşiğin altına inince aynı mekanizma aşağı taşır. Sezon sıfırlaması `league_rule_sets('standard_points').configuration.season_reset_enabled=true` + `close_league_season` (manuel, cron yok).
- Geçişin soruya etkisi: **yok** — paket seçimi lig rating'e bakmaz (canlı `prepare_competition_pack` gövdesinde rating/geçmişi sorgulayan hiçbir ifade yok).

**Zorluk (kolay→orta→zor) geçişi (YOK):**
- Koşul, eşik, tetikleyici, zamanlama: hiçbiri mevcut değil. Kanıt: (1) canlı veritabanında geçiş üreten fonksiyon araması boş; (2) `student_training_levels` 0 satır + 0 okuyucu; (3) `league_transition_rules` 0 satır + okuyucusu yok (016 mirası); (4) TS yüzeyinde zorluk geçiği yok. Konu yalnız roadmap/önceki denetimde **A1 ürün kararı** olarak kayıtlıdır.
- Yeni eşik/algoritma icat edilmedi; rapor mevcut boşluğu belgeler.

**Performans sınıfı yükseltmesi:** tanım gereği kalıcı değildir; bant cevap başına hesaplanır.

---

## 7. Beş soru kuralının uygulanması

- **Sözleşme:** `079_faz5_matchmaking_entry.sql:22` — "#8 Soru sayısı: kurulan her yarışma question_count = 5"; canlı `join_matchmaking_queue` gövdesi `insert … values (…, 5)` (satır 148–153).
- **Zorlamalar:** (1) paket tam `question_count` soru materyalize eder, eksik/fazla → exception+rollback (`prepare_competition_pack` canlı satır 329–334, 362–367); (2) `competitions_question_count_between_1_and_5` CHECK + `current_question_order` 1–5 CHECK; (3) `competition_questions` INSERT üst sınırı 022 trigger'ı; (4) `advance_competition_progress` bir sonraki soruyu **her iki oyuncu da şu anki soruyu cevaplamadan** açmaz; (5) `finalize` tüm cevaplar gelmeden yarışmayı bitirmez.
- **Zayıf nokta:** CHECK aralığı `1..5` olduğu için 5 sabiti eşleştirme koduna gömülüdür, şema kuralına değil. Yöneticiyle üretilen yarışmalar 1–5 olabilir; haftalık mimari için ikisinden biri bilinçli seçilmelidir.

---

## 8. Kasa ve soru seçim mekanizması

### 8.1 Antrenman seçimi (`select_training_questions`, canlı)
Kasa üyelik filtresi (§4.4) + müfredat kapısı + görülmüşlük rotasyonu + haftalık/günlük kota. **Zorluk ve hafta filtresi yok.** `LIMIT` tabanlı sessiz kırpma yok (kota kadar verip `reason` döndürür).

### 8.2 Yarışma paketi (`prepare_competition_pack`, canlı = 068 + 077 materyalizasyon + 082 auto-prepare)
- `vault_type`: yarışma tipi `one_vs_one` → `'one_v_one'` kasa; diğerleri → `'competition'` kasa.
- **A önceliği:** aktif kasa, grade+subject eşleş, `one_v_one_eligible` (veya `competition_eligible`) **aktif üyelik sayısı tam 5**, ve iki oyuncunun da `student_pack_exposures` kaydı yok.
- **B yedeği:** en az 5 "iki oyuncunun da görmediği" (student_question_exposures dışı) eligible üyelik.
- Hiçbiri → `raise 'Uygulanabilir ortak görülmemis paket kasa yok.'` (**fail-closed**).
- Snapshot: tam 5 satır `competition_questions` + soru zorlukları kopyalanır; `difficulty NULL/geçersiz` → tam rollback; metadata `configuration.faz2_pack` (vault_id, question_ids, öncelik A/B); tekrar hazırlık reddedilir (snapshot değişmezliği); `student_pack_exposures` + `student_question_exposures` yazılır; haftalık kota clamp ile tüketilir.
- Çağrı: `join_matchmaking_queue` aynı transaction içinde `perform` eder (082 auto-prepare; atomik). Katılımcı auth'u ile çalıştığı için istemci RPC'si gerektirmez; ama public + EXECUTE'ludur.
- **Düzeltme:** önceki AK-VAULT-42W raporundaki "kasa kullanmıyor / istemciden çağrılmıyor" ifadesi 068 taslak gövdesine aitti; canlı sürüm vault-tabanlıdır.

### 8.3 Yeni haftalık adlarla uyum (`12.Matematik.kolay.01` vb.)
Mekanik gerçekler (canlı): paket seçimi **yalnız** `vault_type IN ('competition','one_v_one')` + grade+subject + 5-üyelik kuralına bakar; isimlendirme, `hafta`, `zorluk` veya `K1–K42` ekseni seçim sorgusunda **hiç** yoktur. Sonuçlar:
- `vault_type='weekly'`/`'academic'` kasalar pakete **giremez** (bugünkü 36 `academic` kasa gibi).
- 30 günlük A kuralı (tam=5) haftalık büyük havuzlarla çelişir (065 ≤5 limiti de aynı gerilim noktasıdır).
- Zorluk (kolay/orta/zor) eşleşme anahtarı değildir; üç zorluk için ya üç ayrı `one_v_one` kasası ya da üyelik bayrağı genişletmesi gerekir — ürün kararı (§16).
- Eşleşme için gereken çift (grade+subject) bugünkü 29 geçerli ders-sınıf çifti başına ayrı kasalar demektir; K1–K42 × zorluk × ders × sınıf kümesiyle kasa sayısı binleri bulur — önceki geçiş planı (AK-VAULT-42W) hedef hesaplarını korur.

### 8.4 Bugünkü canlı envanter (9 Kasım 2026 ölçümü)
`questions=0` · `question_vault_memberships=0` · `question_vaults=36 (hepsi academic, TR-G12-MATH*)` · `competitions=0` ve tüm runtime tabloları 0 · `academic_weeks=41` · migration geçmişi max **154** (137–141 ve 150–154 kayıtlı). Sonuç: **yarışma ve antrenman uçtan uca bugün veri yokluğunda çalışamaz** (fail-closed). Bu, motorun bozuk olduğu anlamına gelmez; kanıt yetersizliği veri katmanındadır.

---

## 9. Veritabanı tabloları ve RPC haritası

**Puanlama çekirdeği:** `scoring_rule_sets` (3 set, v3 aktif) · `scoring_point_rules` (540 satır; v3=252) · `scoring_time_bands` + `question_scoring_time_bands` (v3'te kod-içi T-oranları esas; tablo bant adları `band_name` snapshot'ı) · `question_solve_time_profiles` · `validate_solve_time_profile_for_scoring`.

**Yarışma:** `competitions` · `competition_players` · `competition_questions` (anlık görüntü; `difficulty` kopyalı) · `competition_answers` (`time_band_code/name`, `points_awarded`, UNIQUE cevap-kullanıcı) · `competition_results` (+081 gizlilik) · `competition_point_changes` · `competition_disconnects` · `matchmaking_queue`.

**Lig:** `leagues` (4) · `league_rule_sets` (2) · `league_transition_rules` (0 satır, miras) · `league_rewards` · `student_league_memberships` · `student_league_history` · `leaderboard_definitions/entries/seasons/snapshots` · `league_season_close_results`.

**Antrenman/metrik:** `student_question_attempts` (context ∈ training/competition/targeted_review) · `student_dimension_metrics` · `student_question_exposures` · `student_pack_exposures` · `student_weekly_counters` · `training_attempts/training_levels/training_maps/…` (ölü, 018) · `student_xp_ledger/totals` · badge/seri tabloları (103).

**v3 gölge:** `faz30d_answer_shadow` · `faz30d_mastery_rules` · `faz30d_level_thresholds` · `faz30d_opponent_bonus_rules` · `faz30d_global_points_events/totals`.

**Kasa:** `question_vaults` (36) · `question_vault_memberships` (0) · `question_vault_requests/dispatches`, `vault_stock` RPC'leri (150/151) — detay: AK-VAULT-42W raporu.

**Ana RPC'ler (şema/erişim):**

| RPC | Şema | Çağıran (kanıt) |
|---|---|---|
| `join_matchmaking_queue` | public | `competition/service.ts:181` |
| `prepare_competition_pack` | public | `join_matchmaking_queue` içi `perform` (082) |
| `set_competition_player_ready`, `sync_competition_state`, `get_current_competition_question`, `get_own_matchmaking_status` | public(+private çiftleri) | service.ts satır 386/406/445/512 |
| `submit_competition_answer` | public wrapper → private | service.ts satır 426 |
| `finalize_competition_if_ready`, `advance_competition_progress`, `recalculate_competition_player_score`, `_faz5_apply_competition_points` | public | trigger/akış içi çağrılar |
| `select_training_questions`, `submit_training_attempt`, `get_attempt_feedback`, `start_training_session`, `advance_training_session`, `get_my_weekly_usage`, `list_training_topics/outcomes` | public | `training/service.ts` |
| `ingest_student_attempt`, `_faz9_grant_training_xp`, `_faz9_grant_competition_xp`, `_faz9_evaluate_badges`, `_faz9_record_daily_activity` | public | ingest + finalize zinciri |
| `close_league_season`, `get_my_league_ranking`, `_faz8_upsert_membership_entry` (trigger) | public | 101; lig üyelik trigger'ı |

Trigger zinciri (canlı `pg_trigger`): `competition_answers` → `faz30d_v3_score_answer` (BEFORE, bant+puan doldurma) · `faz30d_v3_record_answer_events` (gölge olay) · `snapshot_competition_answer_band_name` · `after_competition_answer_progress` (recalc + advance); `competitions` → `faz30d_v3_apply_opponent_bonus` (completed anında); `student_league_memberships` → `_faz8_attach_membership_season` + `_faz8_upsert_membership_entry` (leaderboard senkron).

---

## 10. Güvenlik değerlendirmesi

| # | Bulgu | Derece | Kanıt |
|---|---|---|---|
| SEC-1 | **`get_internal_correct_answer` herkese açık:** public şema; `has_function_privilege('authenticated'/'anon', EXECUTE)=true`; gövdede `auth.uid()`/katılımcı kontrolü YOK; doğru cevabı normalize edip döndürür. PostgREST public şemayı expose ettiğinden soru UUID'sini bilen her istemci (anon dahil) cevabı alır. `SECURITY DEFINER` RLS'i baypas eder. | **KRİTİK** | canlı `pg_get_functiondef` + privilege sorgusu (bu oturum) |
| SEC-2 | Cevap sızıntısı (öğrenciler arası): `competition_answers` öğrenci policy yalnız `user_id = auth.uid()` okuma; rakibin cevabı/puanı RPC payload'larında akış anında döndürülmez (skorlar sync_state'te toplam olarak döner) | GÜVENLİ | canlı policy listesi |
| SEC-3 | Yarışma bitmeden doğru cevap görme: soru payload'ı `_faz2_sanitize_question_payload`'tan geçer; `points_awarded/band` istemciye soru anlık görüntüsünde verilmez. SEC-1 varsa bu koruma by-pass edilebilir (aynı açık) | SEC-1'e bağlı | servis kodu + §10.1 |
| SEC-4 | Puan manipülasyonu: puan/bant yalnız sunucu (trigger + definer); `time_ms` CHECK ile sunucu saatinden türetilir; istemcinin hiçbir puan tablosuna INSERT/UPDATE policy'si yok | GÜVENLİ | constraint + policy listesi |
| SEC-5 | Çift puanlama: UNIQUE(competition_question_id,user_id) + erken "already submitted" + rating çift-katman idempotency + antrenman client_key | GÜVENLİ | §2.6 |
| SEC-6 | Tekrar tamamlama: finalize `status<>'completed'` guard'ları + rating `ON CONFLICT` | GÜVENLİ | canlı gövdeler |
| SEC-7 | Yetkisiz seviye/rating değiştirme: `student_league_memberships`'te öğrenci yalnız kendi satırını okur (r); yazma yalnız definer motorlar; client'a açık RPC yok | GÜVENLİ | policy listesi |
| SEC-8 | Antrenman/yarışma veri karışması: `attempt_context` + context-bazlı exposure kontrolü + XP yalnız training dalında; yarışma attempt'leri `source_answer_id` ile bağlanır | GÜVENLİ | `ingest_student_attempt` |
| SEC-9 | Hijyen: kasa tablolarında relacl'de anon/authenticated tam grant (R-5, önceki rapor) + v1/v2 matris satırlarının durması kozmetiktir; `select_training_questions` `training` dışı context'te exposure aramaz (kasa `practice` filtresi yeter) | DÜŞÜK/ORTA | AK-VAULT-42W §10 |

Not: `submit_competition_answer`, `prepare_competition_pack` vb.'nin anon EXECUTE'u vardır ama gövdeler `auth.uid()` ile fail-close eder — sızıntı değil, yüzey genişliği notudur.

---

## 11. Geçmiş fazlar ve uygulama kanıtları

| Faz | Migration(lar) | Ne getirildi | Canlı doğrulama |
|---|---|---|---|
| Faz 2 | 068–070, 096–097 | antrenman seçim/cevap, haftalık sayaçlar | CANLIDA (kod) |
| Faz 4 | 076 | RPC rate-limit kablosu | CANLIDA (gövdelerde `_faz4_consume_rate_limit`) |
| Faz 5 | 077–080, 082, 084–085 | snapshot materyalizasyon, lig rating motoru, matchmaking, auto-prepare, own-status | CANLIDA (kod) |
| Faz 8 | 101–102 | sezon motoru, cutoff guard | KOD VAR; sezon kapatma cron'suz manuel |
| Faz 9 | 103–106 | gamification (XP/rozet/seri), result guard, ledger guard, günlük kota | CANLIDA (kod) |
| Faz 11/15 | 109, 110 | attempt feedback, training gating/oturum | CANLIDA (kod) |
| Faz 30C/D | 127, 128 | v2 negatif puan, v3 sabit matris + rakip bonusu + gölge | **v3 aktif doğrulandı** (§2.1) |
| WP08/planlayıcı | 137–141, 150–154 | üretim hattı, stock RPC, kiralama guard'ları | kurulu (150/151 fiilen uygulanmış) |

**Uyumsuzluk tablosu (doküman/konfig vs canlı):**

| Konu | Doküman/konfig iddiası | Canlı gerçek |
|---|---|---|
| v1/v2 matrisleri | yerini aldı | `scoring_point_rules`'ta 144+144 satır DURUYOR (is_active kural seti v3; kafa karışıklığı riski) |
| `league_transition_rules` (016) | geçiş kuralları | 0 satır, 0 okuyucu — geçişler `leagues` eşikleriyle `_faz5_apply` içinde |
| `student_training_levels` + 018 harita sistemi | seviyeler/haritalar | 0 satır, 0 fonksiyon okuyucusu — ölü tasarım |
| Önceki AK-VAULT-42W notu "pack kasa kullanmıyor / istemci çağırmıyor" | — | Canlı pack **kasa tabanlı**, join transaction'ında çalışır |
| "5 soru şema zorunluluğu" | sabit 5 | CHECK `1..5`; 5 sabiti kodda |
| 128 başlıklı "shadow" | gölge mod | Gölge + **fiilî bonus/trigger** zinciri kurulu — "gölge" yalnız mastery/global skorlar için |
| Sezon/leaderboard otomasyonu | periyodik | pg_cron yok (0 job) — manuel/yönetimsel |
| Uçtan uca çalıştırma kanıtı | E2E testleri (QA yığınları) | Ana canlı yığında **hiç tamamlanmış yarışma yok** (`competitions=0`) — E2E'ler disposable QA ortamlarında |

---

## 12. Çalışan / eksik / hatalı bileşen matrisi

| Bileşen | Durum |
|---|---|
| v3 puan matrisi + `resolve_competition_points` | **CANLIDA ÇALIŞIYOR** (konfig + canlı fonksiyon çağrı örneği §2.2) |
| v3 süre bandı motoru (trigger) | KOD VAR, BAĞLANTI KURULU; veri olmadan işlenmedi → çalışıyor kanıtı KANIT YETERSİZ |
| Rakip/bant bonusu trigger'ı | KOD VAR, BAĞLANTI KURULU (completed geçişine bağlı) — veri kanıtı yok |
| İkili yarışma akış RPC'leri + TS entegrasyonu | **KOD VAR, BAĞLANTI EKSİK** yalnız şununla: uçtan uca örnek yarışma ana yığında hiç koşmadı (veri yok) |
| Matchmaking eşleştirme | CANLIDA ÇALIŞIYOR (koddan; 15 dk TTL, advisory-lock) — veri kanıtı yok |
| 5 soru kuralı | CANLIDA ÇALIŞIYOR (kod+constraint'ler) |
| Lig rating motoru (+24/0/−12) + geçiş + history | KOD VAR, BAĞLANTI KURULU; 0 çalıştırma |
| Sezon/leaderboard otomasyonu | KOD VAR, ZAMANLAMA EKSİK (cron yok; trigger'lı leaderboard upsert çalışır) |
| Antrenman seçim/cevap/motor | CANLIDA ÇALIŞIYOR (kod+kota+exposure) — havuz boş olduğu için fiili teslim KANIT YETERSİZ |
| Antrenman zorluk seviyeleri (kolay/orta/zor) + geçiş | **YALNIZCA TASARIM** (ölü tablolar; mekanizma yok) |
| `training_maps` harita-yıldız sistemi | YALNIZCA TASARIM (018, ölü) |
| `league_transition_rules` | YALNIZCA TASARIM (miras, sahipsiz) |
| v3 mastery/global seviye (L1–L3) | YALNIZCA TASARIM (gölge tablolar boş, UI bağı yok) |
| Kasa ↔ seçim bağlantısı (haftalık K1–K42, isimlendirme) | **HATALI/UYUMSUZ** bugünkü `academic` tip + boş üyeliklerle: paket fail-closed; hafta/zorluk ekseni seçimde yok |
| `get_internal_correct_answer` erişimi | **HATALI** (SEC-1) |
| Soru bankası + membership verisi | **KANIT YETERSİZ / EKSİK** (0 soru — geçiş planının M-dilimleri bekliyor) |

---

## 13. Haftalık kasa mimarisine entegrasyon ihtiyaçları

1. **`vault_type` kararı (A3):** paket seçimi yalnız `competition`/`one_v_one` arar. `weekly` tipi eklenecekse `prepare_competition_pack` filtresi genişletilmeli (ADDITIVE migration); aksi hâlde haftalık kasalar tip olarak `one_v_one` işaretlenir ama `academic` kasalarla karışır.
2. **Zorluk ekseni:** `12.Matematik.kolay.01` yapısı seçim anahtarına girmeli. İki seçenek: (a) haftanın 3 kasası = 3 `one_v_one` kasa + eşleşmeye zorluk parametresi; (b) tek kasa + üyelikte zorluk bayrağı + pack'te zorluk ağırlığı. (a) mevcut motoru değiştirmez; eşleşme UI'ı zorluk seçimi ekler.
3. **"Tam 5" A-önceliği haftalık havuzla çelişir:** 065 ≤5 limiti ve A kuralı revizyonu; B-yedeğin haftalık davranışı (bu haftanın havuzundan 5 çek + `pack_exposures` ile hafta içi tekrarı kes) bilinçli yazılmalı.
4. **Hafta filtresi yok:** `academic_weeks`'ten çözülen hafta paket seçim süzgecine eklenmeli (seed migration'lar haftayı takvimden okur — AK-VAULT-42W kararıyla uyumlu).
5. **Membership yazım yolu** (resume.md açık iş #3): `practice/competition/one_v_one_eligible` bayraklarının üretim hattıyla doldurulması; bugünkü 0 sayısı her iki akışı da kilitler.
6. **Antrenmanda zorluk:** A1 çözülürse `select_training_questions`'a additive `p_difficulty` + seviye kaynağı.
7. **K41/K42 (A2):** takvim 41 hafta; `prepare/advance` haftayı `_faz2_require_period`'den çözer — K42 sentetik üretilmez.
8. **Öğrenci lig → eşleşme:** eşleşme yalnız grade+subject bakar; "aynı ligden rakip" MVP dışıysa dokümante edilip kapatılmalı.

## 14. Korunması gereken mevcut özellikler

v3 matris + bant motoru + rakip bonusu (konfig-drive'n, tablo destekli); advisory-lock eşleşme/paket atomisitesi; snapshot değişmezliği ve fail-closed zorluk kontrolü; idempotency katmanları (UNIQUE'ler, client_key, rating ON CONFLICT, gölge event_key); RLS "kendi satırını oku" deseni; sanitizer payload; haftalık/günlük kota motoru; müfredat kapısı; XP/rozet/seri ayrılığı (ALTIN KALEM: harcanabilir yalnız yıldız); 081 sonuç gizliliği.

## 15. Önceliklendirilmiş eksik işler

1. **S-1 (hemen):** `REVOKE EXECUTE ON FUNCTION public.get_internal_correct_answer FROM anon, authenticated` (+ gerekiyorsa private şemaya taşıma) — ayrı onaylı güvenlik dilimi.
2. **S-2:** membership/eligibility yazım yolu + soru bankası aktarımı (AK-VAULT-42W M-dilimleri; M0 taban çizgisi).
3. **S-3:** A1/A2/A3 ürün kararları → haftalık kasa seçim entegrasyonu tasarımı (§13.1–13.4).
4. **S-4:** Ana yığında kontrollü iki öğrencili E2E yarışma koşusu (açık izinla; `+24/−12` zincirinin uçtan uca canlı kanıtı bugün yok).
5. **S-5:** Sezon/leaderboard zamanlama kararı (cron mı, yönetimsel mi).
6. **S-6:** v1/v2 matris satırlarının `is_active=false` işaretlenmiş hâlde mi kalacağına karar; "5 soru"nun CHECK'e mi kod sözleşmesine mi kalacağı.
7. **S-7:** ölü yapıların (018 harita sistemi, `league_transition_rules`) resmî "devre dışı" kaydı (silme değil — önceki planın ADDITIVE ilkesi).

## 16. Gereken kullanıcı kararları

| # | Karar | Seçenekler |
|---|---|---|
| A1 | Öğrenci zorluk seviyesi kaynağı ve kolay→orta→zor geçiş kuralı (yok; tanımlanacak mı, neye göre?) | eşik-tabanlı antrenman doğruluğu / manuel / MVP'de yok |
| A2 | K41 mi K42 mi | resmî takvim 41; K42 sentetik değil |
| A3 | Haftalık kasa `vault_type` politikası | `weekly` tipi + pack filtresi / `one_v_one` işaretleme |
| A4 | Haftalık zorluk eşlemesi | 3 kasa/hafta + eşleşmede zorluk seçimi / tek kasa + bayrak |
| A5 | "Tam 5" kuralının haftalık havuzda hali (A-önceliği revizyonu) | tam-5 sözleşmesi / havuzdan 5 + hafta içi tekrar yasağı |
| A6 | SEC-1 düzeltme onayı (revocation migration) | — |
| A7 | Ana yığında canlı E2E yarışma koşusu izni (test hesapları, temizlik sözleşmesi) | — |
| A8 | Sezon/leaderboard otomasyon yöntemi | pg_cron / yönetimsel komut |

---

### Kanıt ekleri (bu oturumda üretilen salt-okunur çıktılar)
- v3 matris canlı fonksiyon örnek hesapları (§2.2 tablosu, 15 satırlık `SELECT` çıktısı).
- `league_rule_sets('faz5_competition_rating').configuration` = `{win:24, draw:0, loss:12, forfeit_win:24, forfeit_loss:12}`.
- `finalize_competition_if_ready` gövdesi satır 519: `PERFORM public._faz5_apply_competition_points(...)`.
- Canlı `pg_trigger` dökümü (competition_answers/competitions/student_league_memberships).
- Privilege sorgusu: `get_internal_correct_answer` auth/anon EXECUTE=true.
- Envanter: migrations max 154 (137–141, 150–154 kayıtlı); questions=0; memberships=0; vaults=36 (`academic`); competitions=0; leagues 4 satır; bonus/mastery/threshold konfig satırları.
