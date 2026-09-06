# FAZ 6 TASARIM — Hedefli Tekrar ve Kazanım Analitiği

Tarih: 6 Eylül 2026 · Durum: UYGULANMADAN ÖNCE TASARIM (kanıt zinciri başlangıcı)

## 1. Kapsam ve ürün kararları

- Hedefli tekrar, genel konu listesine yönlendirme DEĞİLDİR: öğrencinin KENDİ
  yanlışlarından ve düşük başarı gösteren kazanımlarından sunucu tarafında
  deterministik bir tekrar oturumu üretilir.
- Kazanım bazında güçlü / geliştirilmeli alanlar öğrenciye gösterilir.
- Minimum veri yoksa yüzde GÖSTERİLMEZ; açıklayıcı durum metni vardır.
- Tekrar sonrası ilerleme etkisi ölçülebilir ve öğrenciye gösterilir.
- Bu dosyadaki eşikler SABİT ürün kararıdır; testler bu değerlere bağlıdır.

## 2. Yeni DB yüzeyi (098_faz6_targeted_review.sql)

### 2.1 get_outcome_review_plan(p_subject_id uuid) → jsonb

Öğrencinin KENDİ dönem-kapılı kazanımları için kazanım analitiği + tekrar
etkisi özeti. Kimlik yalnız auth.uid(); kullanıcı parametresi YOKTUR.

Satır alanları (allowlist): outcome_id, outcome_text, band, total_attempts,
success_rate (NULL olabilir), repeat_total, repeat_success_rate,
pending_errors, redeemed, redeem_rate (NULL olabilir), last_attempted_at.

- Kazanım listesi: 096 ile AYNI dönem kapısı — curriculum_schedule_items
  (schedule_profile + grade + subject + is_active + start_week <= hafta)
  üzerinden işlenmiş outcome'lar. Liste dışına veri SIZMAZ.
- Metrik kaynağı: student_dimension_metrics (064) scope_type='outcome'
  satırları (tüm bağlamlar, 069 ile birikmiş; 085 konvansiyonu).
- band eşikleri (TS'teki LOW_SUCCESS_THRESHOLD=40 / STRONG_SUCCESS_THRESHOLD=70
  / MIN_BAND_ATTEMPTS=5 ile BİREBİR; tek canonical kaynak TypeScript'tir,
  SQL yalnız görüntüleme verisini üretir):
  - total_attempts < 5  → band='insufficient_data', success_rate=NULL
  - rate < 40           → band='weak'
  - 40 <= rate < 70     → band='developing'
  - rate >= 70          → band='strong'
- Tekrar etkisi (sorubaşına kazanım düzeyinde, training bağlamı fact):
  - pending_errors: outcome'daki sorulardan EN SON training denemesi
    sonucu 'correct' OLMAYAN (wrong/blank/pass/timeout) soru sayısı.
  - redeemed: EN SON training denemesi 'correct' olan VE bu sonda önce
    en az bir yanlış/boş/pas/timeout denemesi bulunan soru sayısı.
  - redeem_rate = redeemed / (redeemed + pending_errors), yuvarlama 1 hane.
    Payda < 5 İSE NULL (yanıltıcı yüzde engellenir; UI açıklayıcı metin).
  - last_reviewed_at: outcome'daki soruların training fact'lerindeki
    en güncel answered_at (NULL olabilir).
- Yetersiz veri: band='insufficient_data' satırlarında success_rate NULL'dür;
  repeat/redeem alanları görüntülenir ama yüzde alanları NULL kalabilir.

### 2.2 select_targeted_review_questions(p_subject_id, p_outcome_id, p_limit default 5) → jsonb

Deterministik, öğrenciye özgü tekrar oturumu seçimi. SECURITY DEFINER +
search_path='' + auth.uid(); ACL: tam revoke → authenticated grant.

1. Rate limit: _faz4_consume_rate_limit('targeted_review_select', 30, 3600)
   — auth kontrolünden HEMEN sonra, her işten ÖNCE (076/097 konumu).
2. p_limit 1..10 (tekrar oturumları kısa: ürün kararı), p_outcome_id zorunlu.
3. Kapsam kapısı: outcome, öğrencinin dönem-kapılı işlenmiş kazanımı değilse
   FAIL-CLOSED: reason='gecersiz_kapsam', boş liste (096 deseni).
4. HATA HAVUZU (öğrenciye özgü): outcome'daki sorulardan en son training
   denemesi 'correct' olmayan sorular. KOŞULLAR:
   - REDEEM_COOLDOWN: sorunun EN SON training denemesi BUGÜN (UTC takvim
     günü) içinde yapılmışsa havuz DIŞI → aynı yanlışın gereksiz tekrarı
     sınırlandırılır (dünü ve öncesini hedefler; dökümante sabit kural).
   - Havuz boşsa reason='tekrar_gerekmiyor', boş liste (pozitif kapanış).
5. SEÇİM (deterministik; random YOK):
   a. Havuz soruları question_id ASC sırayla p_limit'e kadar alınır
      (zaten exposure sahiptir; sayaç/exposure yazımı YAPILMAZ).
   b. Kalan slotlar 096 eligible-gates ile YENİ görülmemiş sorulardan
      doldurulur (aktif + approved + practice membership + müfredat
      mapping approved); exposure INSERT + _faz2_consume_weekly_capacity
      (yalnız yeni sorular için; 096 atomik deseni).
6. Payload: 096 ile aynı _faz2_sanitize_question_payload + session_kind=
   'targeted_review', outcome_id, wrong_review_count, new_count, weekly.

### 2.3 Sınırlar (en küçük güvenli değişiklik)

- Yeni tablo YOK, mevcut tabloda kolon değişikliği YOK, CREATE OR REPLACE
  ile mevcut fonksiyon gövdesine DOKUNULMAZ (SYSTEMIC_MIGRATION_REPLACEMENT
 _RISK dersleri: yalnız YENİ fonksiyonlar).
- RLS değişikliği YOK: attempts/exposures mevcut "kendi satırını okur"
  politikalarıyla korunur; başkasının analitiği ASLA okunamaz (RPC'ler
  auth.uid() kök veriyi kullanır, p_user parametresi YOKTUR).

## 3. Servis ve UI

- src/lib/review/{types,service,errors}.ts — sıkı allowlist mapper; PII /
  correct_answer bu katmandan ASLA geçmez (training deseni).
- /tekrar (hub): ders seçimi + seçilen dersin kazanım kartları
  (güçlü / geliştirilmeli / öncelikli / yetersiz veri grupları;
  yetersiz veride yüzde YOK, açıklayıcı metin VAR).
- /tekrar/[subjectId]?outcome=... : deterministik tekrar oturumu —
  mevcut TrainingSession bileşeni yeniden kullanılır; oturum sonunda
  pending/redeemed + redeem_rate özeti gösterilir (etki ölçümü).
- a11y: min 44px hedef, aria-live, görünür focus; doğal Türkçe; lang="tr".

## 4. Test sözleşmesi

- Vitest: mapper allowlist (PII düşürme), band eşikleri (5/40/70 sınır
  değerleri), redeem_rate NULL koşulu (payda<5), cooldown davranışı
  (bugünkü yanlış seçilmez), service DI sahte istemci.
- SQL QA (disposable, benzersiz ad/port/dizin): kapsam fail-closed
  (başka sınıf outcome'u → gecersiz_kapsam), rate limit (eşikte P0001,
  bağlam hatası DEĞİL), RLS boundary (başka öğrenci planı okunamaz),
  haftalık kapasite (yalnız YENİ sorular sayılır), kimlik doğrulama
  (anon → 42501), determinizm (aynı fixture'da aynı soru sırası x2).

## 5. Eşik özeti (SABİT)

| Sabit | Değer | Kaynak |
|---|---|---|
| MIN_BAND_ATTEMPTS | 5 | types.ts (mevcut) |
| LOW_SUCCESS_THRESHOLD | 40 | types.ts (mevcut) |
| STRONG_SUCCESS_THRESHOLD | 70 | types.ts (mevcut) |
| MIN_REDEEM_EVIDENCE (payda) | 5 | Bu faz, dokümante |
| REDEEM_COOLDOWN | 1 UTC takvim günü | Bu faz, dokümante |
| review p_limit aralığı | 1..10 (default 5) | Bu faz, dokümante |
| targeted_review_select rate | 30 / 3600sn | Bu faz, dokümante |
