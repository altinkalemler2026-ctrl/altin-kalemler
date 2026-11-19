-- ============================================================
-- 136_admin_uretim_onizleme.sql
-- Altın Kalemler — WP-08: Üretim planlayıcı SALT-OKUNUR önizleme
--
-- Kapsam (dar):
--   1) `public.preview_question_generation_demand` — 057 demand
--      planner formülünün YAZMASIZ (STABLE) varyantı. Hesap mantığı
--      SQL'de kalır; frontend kopyalamaz. FORMÜL AYNASI: 057
--      satır 665-874 ile birebir; 057 değişirse bu fonksiyon
--      senkronize edilmelidir (bakım notu).
--   2) Önizleme HİÇBİR kayıt oluşturmaz: policy/snapshot/request/
--      dispatch/job/staging yazmaz; yalnız mevcut tabloları okur.
--   3) Kapsam filtreleri: sınıf + ders (zorunlu); konu/alt-konu/
--      kazanım (opsiyonel; GERÇEK eşlemelerle sayılır:
--      question_curriculum_mappings / question_outcome_mappings,
--      review_status='approved', DISTINCT question_id — 097 antrenman
--      seçicisiyle aynı sözleşme; eşlemesiz soru filtreli kapsamda
--      sayılmaz); müfredat sürümü; zorluk; akademik hafta bandı;
--      stock_scope + inventory_scope.
--   4) Orijinal soru sayısı ≠ kasa üyelik sayısı:
--      - existing_approved_active_questions = kapsam içindeki onaylı+aktif
--        sorular (orijinal, DISTINCT).
--      - existing_questions_with_membership_in_scope = aynı sorulardan
--        aktif+kapsam-uygun üyeliği olanlar.
--      - existing_questions_missing_membership = fark (üyelik yazımı
--        bekleyenler).
--      - actual_eligible_inventory = kasa TOPLAM aktif+uygun üyelik
--        (057 aynası; alt kapsam filtresi olsa da kasa toplamıdır).
--   5) Alt kapsam hedefi: kasa→alt kapsam dağılım kuralı şemada YOK;
--      hedef çarpılmaz/bölünmez. Alt kapsamda hedef yalnız kullanıcı
--      AÇIKÇA target_override verirse tanımlı olur (300/floor kırpması
--      alt kapsama uygulanmaz); hedef yoksa gap gösterilir.
--   6) Kural gerçekleri:
--      - 500 = tüketim tavanı (öğrenci/ders/hafta; 068) — hesaba
--        KATILMAZ, tavan olarak kullanılmaz.
--      - 300 tabanı YALNIZ stock_scope='weekly_competition'
--        planlamasında geçerlidir (060:93-98).
--      - Zorluk dağılımı tanımsızsa EŞİT DAĞITILMAZ; 'tanimsiz'
--        gösterilir (uydurma yok).
--      - Policy kaydı yoksa 057 tablo DEFAULT'leri "önerilen
--        varsayılan" etiketiyle kullanılır (kayıt AÇILMAZ).
--      - Kasa (vault) yoksa üyelik 0'dır; "üyelik eksikliği" ayrı
--        satırla gösterilir ve üretim önerisi "kesin miktar"
--        olarak sunulmaz.
--      - Hafta bandı hedefi ÇARPMAZ: pencere hedefi bant içindeki
--        en yüksek pencere hedefi olur (057:754-763 tek hafta
--        okumasının bant varyantı; çarpan yok).
--
-- Not: Yalnız fonksiyon tanımı; tablo şeması/RLS/kayıtlar korunur.
-- db reset YOK.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.preview_question_generation_demand(
  p_grade_level smallint,
  p_subject_id uuid,
  p_curriculum_version_id uuid DEFAULT NULL,
  p_stock_scope text DEFAULT 'weekly_competition',
  p_inventory_scope text DEFAULT 'practice',
  p_week_from integer DEFAULT 1,
  p_week_to integer DEFAULT 1,
  p_difficulty text DEFAULT NULL,
  p_topic_id uuid DEFAULT NULL,
  p_subtopic_id uuid DEFAULT NULL,
  p_outcome_id uuid DEFAULT NULL,
  p_target_override integer DEFAULT NULL,
  p_active_student_count integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_policy record;
  v_policy_source text;
  v_vault_id uuid;
  v_weekly_questions integer;
  v_repeat_weeks integer;
  v_safety numeric;
  v_diversity_weight numeric;
  v_floor integer;
  v_batch integer;
  v_current_ratio numeric;
  v_review_ratio numeric;

  v_diversity numeric;
  v_base numeric;
  v_dynamic integer;
  v_defined_vault_target integer := 0;
  v_is_active_in_week boolean := false;
  v_activation_target integer := 0;
  v_final integer;
  v_override_applied integer := 0;
  v_actual integer := 0;
  v_shortage integer;
  v_excess integer;
  v_current_target integer;
  v_review_target integer;
  v_generation integer;
  v_gen_current integer;
  v_gen_review integer;
  v_week_span integer;
  v_mevcut integer := 0;
  v_mevcut_uyelikli integer := 0;
  v_uyelik_eksik integer := 0;
  v_aday_total integer := 0;
  v_aday_validating integer := 0;
  v_aday_review integer := 0;
  v_jobs_pending integer := 0;
  v_scope_filtered boolean := false;
  v_scope_actual integer := 0;
  v_scope_target integer := 0;
  v_scope_target_source text;
  v_scope_shortage integer := 0;
  v_scope_generation integer := 0;
BEGIN
  -- ------------------------------------------------------------
  -- Yetki (fail-closed): service_role VEYA admin izni.
  -- ------------------------------------------------------------
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Admin permission required.';
  END IF;

  IF p_grade_level IS NULL OR p_grade_level < 1 OR p_grade_level > 12 THEN
    RAISE EXCEPTION 'Geçerli bir sınıf (1-12) gerekli.';
  END IF;
  IF p_subject_id IS NULL THEN
    RAISE EXCEPTION 'Ders gerekli.';
  END IF;
  IF p_stock_scope NOT IN ('weekly_competition','rewarded_competition','training') THEN
    RAISE EXCEPTION 'Geçersiz stok kapsamı.';
  END IF;
  IF p_inventory_scope NOT IN ('practice','competition','one_v_one','exam') THEN
    RAISE EXCEPTION 'Geçersiz kasa/kullanım kapsamı.';
  END IF;
  IF p_difficulty IS NOT NULL
     AND p_difficulty NOT IN ('easy','medium','hard','mixed') THEN
    RAISE EXCEPTION 'Geçersiz zorluk.';
  END IF;

  v_week_span := GREATEST(COALESCE(p_week_to, p_week_from) - COALESCE(p_week_from, 1), 0) + 1;
  IF v_week_span < 1 THEN
    RAISE EXCEPTION 'Geçersiz hafta aralığı.';
  END IF;

  -- ------------------------------------------------------------
  -- Kasa + policy kaynak bulma.
  -- Gerçek veri bağı: kasalar `vault_type='academic'` + allow_* eleriği
  -- (allow_practice/allow_competition/allow_one_v_one/allow_exam) ile
  -- kullanım kapsamını taşır; inventory_scope 'practice' ↔ allow_practice
  -- şemada gerçek bağdır (048:61-64 + 057:788-808 üyelik eleriği) —
  -- isim benzerliği değildir.
  -- ------------------------------------------------------------
  SELECT v.id
  INTO v_vault_id
  FROM public.question_vaults v
  WHERE v.is_active = true
    AND v.grade_level = p_grade_level
    AND v.subject_id = p_subject_id
    AND (
      (p_inventory_scope = 'practice' AND v.allow_practice = true)
      OR (p_inventory_scope = 'competition' AND v.allow_competition = true)
      OR (p_inventory_scope = 'one_v_one' AND v.allow_one_v_one = true)
      OR (p_inventory_scope = 'exam' AND v.allow_exam = true)
    )
  ORDER BY v.id
  LIMIT 1;

  IF v_vault_id IS NOT NULL THEN
    SELECT *
    INTO v_policy
    FROM public.question_vault_demand_policies p
    WHERE p.vault_id = v_vault_id AND p.is_active = true
    ORDER BY p.created_at DESC
    LIMIT 1;
    IF FOUND THEN
      v_policy_source := 'saved_policy';
      v_weekly_questions := v_policy.weekly_questions_per_student;
      v_repeat_weeks := v_policy.target_repeat_weeks;
      v_safety := v_policy.safety_factor;
      v_diversity_weight := v_policy.user_diversity_weight;
      v_floor := v_policy.minimum_inventory_floor;
      v_batch := v_policy.generation_batch_size;
      v_current_ratio := v_policy.current_content_ratio;
      v_review_ratio := v_policy.review_content_ratio;
    END IF;
  END IF;

  IF v_policy_source IS NULL THEN
    v_policy_source := 'recommended_default';
    v_weekly_questions := 20;
    v_repeat_weeks := 8;
    v_safety := 1.250;
    v_diversity_weight := 0.250;
    v_floor := 100;
    v_batch := 20;
    v_current_ratio := 0.700;
    v_review_ratio := 0.300;
  END IF;

  -- ------------------------------------------------------------
  -- 057 FORMÜLÜ — DB'DE UYGULANMIŞ GERÇEK TANIM (calculate_question_
  -- vault_demand prosrc aynası; repo dosyası 057:754-763 DRİFTLİ:
  -- orada w.target_question_count okunur ama kolon yok; DB sürümü
  -- vault.metadata okur). Bakım: 057 değişirse senkronize edin.
  -- ------------------------------------------------------------
  v_diversity := round(
    1 + log(10::numeric, GREATEST(COALESCE(p_active_student_count,0) + 1, 1)::numeric)
        * v_diversity_weight,
    4
  );

  v_base := v_weekly_questions::numeric * v_repeat_weeks::numeric;

  v_dynamic := ceil(v_base * v_diversity * v_safety)::integer;
  v_dynamic := GREATEST(v_dynamic, v_floor);

  -- DEFINED VAULT TARGET: vault.metadata.target_question_count
  -- (insan tanımlı; örnek A1: 300) — 057 DB sürümü aynası.
  SELECT CASE
    WHEN v.metadata ? 'target_question_count'
         AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
    THEN (v.metadata ->> 'target_question_count')::integer
    ELSE 0
  END
  INTO v_defined_vault_target
  FROM public.question_vaults v
  WHERE v.id = v_vault_id;

  -- ACTIVE WINDOW (bant varyantı): bant içinde HERHANGİ bir hafta
  -- pencere içindeyse (start inclusive / end exclusive) activation
  -- hedefi defined_vault_target olur; aksi 0. ÇARPAN YOK: bant
  -- uzunluğu ile hedef çarpılmaz; final'de MAX edilir.
  IF v_vault_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.question_vault_activation_windows w
      WHERE w.vault_id = v_vault_id
        AND w.is_enabled = true
        AND EXISTS (
          SELECT 1
          FROM generate_series(
            COALESCE(p_week_from, 1),
            COALESCE(p_week_to, p_week_from)
          ) AS g(wk)
          WHERE w.start_week <= g.wk
            AND g.wk < w.end_week
        )
    )
    INTO v_is_active_in_week;
  END IF;

  v_activation_target := CASE WHEN v_is_active_in_week THEN v_defined_vault_target ELSE 0 END;

  v_scope_filtered := (p_topic_id IS NOT NULL OR p_subtopic_id IS NOT NULL
                       OR p_outcome_id IS NOT NULL);

  v_final := GREATEST(v_dynamic, v_defined_vault_target, v_floor);

  -- Kullanıcı hedefi (kural sınırları içinde): floor altına düşmez;
  -- weekly_competition planında 300 tabanından küçük olamaz (060:93-98).
  -- Alt kapsam (konu/alt konu/kazanım) filtresi seçiliyken override
  -- KASA TOPLAMINI sessizce büyütmez: override o durumda alt kapsam
  -- hedefidir ve yalnız sub_scope bloğunda uygulanır (sessiz çarpan yok).
  IF p_target_override IS NOT NULL AND p_target_override > 0 THEN
    IF v_scope_filtered THEN
      v_override_applied := 0; -- kasa toplamına uygulanmaz; sub_scope hedefi
    ELSE
      v_override_applied := p_target_override;
      IF p_stock_scope = 'weekly_competition' AND v_override_applied < 300 THEN
        v_override_applied := 300;
      END IF;
      IF v_override_applied < v_floor THEN
        v_override_applied := v_floor;
      END IF;
      v_final := GREATEST(v_final, v_override_applied);
    END IF;
  END IF;

  -- ------------------------------------------------------------
  -- Gerçek uygun üyelik (kasa yoksa 0) — 057:782-808 aynası.
  -- ------------------------------------------------------------
  IF v_vault_id IS NOT NULL THEN
    SELECT count(*)::integer
    INTO v_actual
    FROM public.question_vault_memberships m
    WHERE m.vault_id = v_vault_id
      AND m.membership_status = 'active'
      AND (
        (p_inventory_scope = 'practice' AND m.practice_eligible = true)
        OR (p_inventory_scope = 'competition' AND m.competition_eligible = true)
        OR (p_inventory_scope = 'one_v_one' AND m.one_v_one_eligible = true)
        OR (p_inventory_scope = 'exam' AND m.exam_eligible = true)
      );
  END IF;

  v_shortage := GREATEST(v_final - v_actual, 0);
  v_excess := GREATEST(v_actual - v_final, 0);

  v_current_target := ceil(v_final * v_current_ratio)::integer;
  v_review_target := GREATEST(v_final - v_current_target, 0);

  IF v_shortage > 0 THEN
    v_generation := ceil(v_shortage::numeric / v_batch::numeric)::integer * v_batch;
  ELSE
    v_generation := 0;
  END IF;

  v_gen_current := ceil(v_generation * v_current_ratio)::integer;
  v_gen_review := GREATEST(v_generation - v_gen_current, 0);

  -- ------------------------------------------------------------
  -- Kapsamdaki gerçeklik sayımları (döküm; STOK SAYILMAZ)
  -- ------------------------------------------------------------

  -- 1) Kapsamdaki onaylı+aktif sorular — GERÇEK eşlemelerle. Sözleşme,
  --    097 antrenman seçicisiyle aynıdır (review_status='approved'
  --    eşlemeler; 039 promotion 'approved' yazar):
  --      kazanım seçili  → question_outcome_mappings (sürüm filtresi
  --                        curriculum_outcomes.curriculum_version_id ile)
  --      alt konu seçili → question_curriculum_mappings.subtopic_id
  --      konu seçili     → question_curriculum_mappings.topic_id
  --      filtre yok      → sınıf+ders(+zorluk) genel sayımı
  --    DISTINCT question_id (LEFT JOIN) — çoklu eşleme şişirmez.
  --    Eşlemesiz soru filtreli kapsamda SAYILMAZ (uydurma yok).
  --    v_mevcut_uyelikli = aynı sorularda aktif+kapsam-uygun üyelik.
  SELECT
    count(DISTINCT q.id)::integer,
    count(DISTINCT q.id) FILTER (WHERE m.id IS NOT NULL)::integer
  INTO v_mevcut, v_mevcut_uyelikli
  FROM public.questions q
  LEFT JOIN public.question_vault_memberships m
    ON m.question_id = q.id
   AND m.vault_id = v_vault_id
   AND m.membership_status = 'active'
   AND (
     (p_inventory_scope = 'practice' AND m.practice_eligible = true)
     OR (p_inventory_scope = 'competition' AND m.competition_eligible = true)
     OR (p_inventory_scope = 'one_v_one' AND m.one_v_one_eligible = true)
     OR (p_inventory_scope = 'exam' AND m.exam_eligible = true)
   )
  WHERE q.is_active = true
    AND q.approval_status = 'approved'
    AND q.grade_level = p_grade_level
    AND q.subject_id = p_subject_id
    AND (p_difficulty IS NULL OR q.difficulty = p_difficulty)
    AND (
      (p_topic_id IS NULL AND p_subtopic_id IS NULL AND p_outcome_id IS NULL)
      OR (p_outcome_id IS NOT NULL AND EXISTS (
            SELECT 1
            FROM public.question_outcome_mappings qom
            JOIN public.curriculum_outcomes co ON co.id = qom.outcome_id
            WHERE qom.question_id = q.id
              AND qom.outcome_id = p_outcome_id
              AND qom.review_status = 'approved'
              AND (p_curriculum_version_id IS NULL
                   OR co.curriculum_version_id = p_curriculum_version_id)
          ))
      OR (p_outcome_id IS NULL AND p_subtopic_id IS NOT NULL AND EXISTS (
            SELECT 1
            FROM public.question_curriculum_mappings qcm
            WHERE qcm.question_id = q.id
              AND qcm.subtopic_id = p_subtopic_id
              AND qcm.review_status = 'approved'
              AND (p_curriculum_version_id IS NULL
                   OR qcm.curriculum_version_id = p_curriculum_version_id)
          ))
      OR (p_outcome_id IS NULL AND p_subtopic_id IS NULL
          AND p_topic_id IS NOT NULL AND EXISTS (
            SELECT 1
            FROM public.question_curriculum_mappings qcm
            WHERE qcm.question_id = q.id
              AND qcm.topic_id = p_topic_id
              AND qcm.review_status = 'approved'
              AND (p_curriculum_version_id IS NULL
                   OR qcm.curriculum_version_id = p_curriculum_version_id)
          ))
    );

  -- Kasa üyeliği yazımı bekleyen uygun sorular (döküm; STOK DEĞİL):
  v_uyelik_eksik := GREATEST(v_mevcut - v_mevcut_uyelikli, 0);

  -- Alt kapsam (konu/alt konu/kazanım) seçiliyse gerçek kullanılabilir
  -- stok, O kapsamda eşleşen üyeliklerdir (v_mevcut_uyelikli); kasa
  -- TOPLAM üyeliği değil. Kasa toplam hedefi alt kapsama BÖLÜNMEZ:
  -- şemada kasa→alt kapsam dağılım kuralı YOKTUR (057/060/068'de yok);
  -- çarpma/bölme dağıtımı uydurulmaz. Alt kapsam hedefi yalnız kullanıcı
  -- AÇIKÇA target_override verirse tanımlı olur; 300/floor kırpması
  -- alt kapsama UYGULANMAZ (onlar kasa toplamı kurallarıdır).
  IF v_scope_filtered THEN
    v_scope_actual := v_mevcut_uyelikli;
    IF p_target_override IS NOT NULL AND p_target_override > 0 THEN
      v_scope_target := p_target_override;
      v_scope_target_source := 'kullanıcı aşikâr hedefi (target_override; alt kapsama 300/floor kırpması uygulanmaz)';
      v_scope_shortage := GREATEST(v_scope_target - v_scope_actual, 0);
    ELSE
      v_scope_target := 0;
      v_scope_target_source := 'tanımsız — kasa→alt kapsam dağılım kuralı veride YOK; hedef için target_override gerekli';
      v_scope_shortage := 0;
    END IF;
  ELSE
    v_scope_target := v_final;
    v_scope_target_source := CASE
      WHEN v_vault_id IS NULL THEN 'kasa yok — hedef kaynağı yok'
      ELSE 'kasa toplam hedefi (final_target_inventory; alt kapsam filtresi yok)'
    END;
    v_scope_actual := v_actual;
    v_scope_shortage := v_shortage;
  END IF;

  -- Alt kapsam üretim önerisi: yalnız kullanıcı açık alt kapsam hedefi
  -- verdiğinde hesaplanır (dağılım kuralı yoksa uydurulmaz).
  IF v_scope_filtered AND p_target_override IS NOT NULL
     AND p_target_override > 0 AND v_scope_shortage > 0 THEN
    v_scope_generation := ceil(v_scope_shortage::numeric / v_batch::numeric)::integer * v_batch;
  ELSE
    v_scope_generation := 0;
  END IF;

  -- 2) İnceleme bekleyen staging adayları (STOK SAYILMAZ)
  SELECT count(*) FILTER (
    WHERE s.staging_status NOT IN ('rejected','promoted','already_promoted')
  ), count(*) FILTER (
    WHERE s.staging_status = 'validating'
  ), count(*) FILTER (
    WHERE s.staging_status = 'needs_review'
  )
  INTO v_aday_total, v_aday_validating, v_aday_review
  FROM public.ai_question_staging s
  WHERE s.grade_level = p_grade_level
    AND s.subject_id = p_subject_id
    AND (p_topic_id IS NULL OR s.proposed_topic_id = p_topic_id)
    AND (p_subtopic_id IS NULL OR s.proposed_subtopic_id = p_subtopic_id)
    AND (p_outcome_id IS NULL
         OR s.metadata ->> 'required_outcome_id' = p_outcome_id::text)
    AND (p_difficulty IS NULL OR s.proposed_difficulty = p_difficulty);

  -- 3) Devam eden üretim işleri (kapsam bağlantısı şemada YOK; global)
  SELECT count(*)::integer
  INTO v_jobs_pending
  FROM public.ai_jobs j
  WHERE j.status IN ('pending','queued','processing');

  RETURN jsonb_build_object(
    'scope', jsonb_build_object(
      'curriculum_version_id', p_curriculum_version_id,
      'grade_level', p_grade_level,
      'subject_id', p_subject_id,
      'stock_scope', p_stock_scope,
      'inventory_scope', p_inventory_scope,
      'week_from', p_week_from,
      'week_to', p_week_to,
      'week_span', v_week_span,
      'difficulty', p_difficulty,
      'topic_id', p_topic_id,
      'subtopic_id', p_subtopic_id,
      'outcome_id', p_outcome_id,
      'vault_id', v_vault_id,
      'active_student_count', p_active_student_count,
      'week_to_topic_mapping', 'yok — hafta→konu dağılımı mevcut veride tanımlı DEĞİL; kapsam seçimi MANUEL planlama girdisidir'
    ),
    'policy', jsonb_build_object(
      'source', v_policy_source,
      'weekly_questions_per_student', v_weekly_questions,
      'target_repeat_weeks', v_repeat_weeks,
      'safety_factor', v_safety,
      'user_diversity_weight', v_diversity_weight,
      'minimum_inventory_floor', v_floor,
      'generation_batch_size', v_batch,
      'current_content_ratio', v_current_ratio,
      'review_content_ratio', v_review_ratio
    ),
    'target', jsonb_build_object(
      'base_student_inventory', v_base,
      'diversity_multiplier', v_diversity,
      'dynamic_target', v_dynamic,
      'defined_vault_target', v_defined_vault_target,
      'defined_vault_target_source', CASE
        WHEN v_vault_id IS NULL THEN 'kasa yok — hedef kaynağı yok'
        ELSE 'vault.metadata.target_question_count (insan tanımlı)'
      END,
      'is_active_in_week_band', v_is_active_in_week,
      'activation_target_count', v_activation_target,
      'minimum_inventory_floor', v_floor,
      'target_override_input', p_target_override,
      'target_override_applied', v_override_applied,
      'target_override_scope_note', CASE
        WHEN v_scope_filtered AND p_target_override IS NOT NULL AND p_target_override > 0
        THEN 'Alt kapsam filtresi seçili: girdiğiniz hedef KASA TOPLAMINI büyütmedi; alt kapsam hedefi olarak sub_scope bloğunda uygulandı (sessiz kasa çarpanı yok).'
        ELSE NULL
      END,
      'final_target_inventory', v_final,
      'stock_floor_note', CASE
        WHEN p_stock_scope = 'weekly_competition'
        THEN '300 alt sınırı bu kapsamda geçerlidir (060:93-98; planlama tablosu kaydı yoksa kural olarak uygulanır).'
        ELSE 'Bu stok kapsamında taban zorunluluğu yoktur (060:20-21).'
      END,
      'consumption_cap_note', '500 tüketim tavanı (öğrenci/ders/hafta; 068:522 antrenman, :906 yarışma gösteriminde tüketilir) BU HESABA katılmaz ve kasa kapasitesi/planner üst sınırı olarak kullanılamaz.',
      'week_multiplication_guard', 'Hafta bandı hedefle ÇARPILMAZ; pencere durumu yalnız activation_target''ı (defined_vault_target) açıp kapatır; final MAX ile birleştirilir.'
    ),
    'stock', jsonb_build_object(
      'actual_eligible_inventory', v_actual,
      'actual_inventory_scope_note', CASE
        WHEN v_vault_id IS NULL
        THEN 'Bu kapsamda kasa (vault) yok: üyelik SAYILAMAZ; üretim önerisi kasa+üyelik oluşturulmadan kesin miktar DEĞİLDİR.'
        ELSE 'Sayım yalnız aktif ve kapsam-uygun (eligible) üyelikleri düşer — 057:782-808 aynası. Alt kapsam filtresi seçiliyken kapsam-gerçek stok sub_scope.actual_scoped_member_stock''tur; bu alan kasa TOPLAM üyeliğidir.'
      END,
      'membership_shortage', v_shortage,
      'excess_count', v_excess,
      'current_content_target', v_current_target,
      'review_content_target', v_review_target
    ),
    'sub_scope', jsonb_build_object(
      'is_filtered', v_scope_filtered,
      'actual_scoped_member_stock', CASE WHEN v_scope_filtered THEN v_scope_actual ELSE NULL END,
      'scoped_eligible_missing_membership', CASE WHEN v_scope_filtered THEN v_uyelik_eksik ELSE NULL END,
      'scoped_target', CASE WHEN v_scope_filtered THEN v_scope_target ELSE NULL END,
      'scoped_target_source', CASE WHEN v_scope_filtered THEN v_scope_target_source ELSE NULL END,
      'scoped_shortage', CASE WHEN v_scope_filtered THEN v_scope_shortage ELSE NULL END,
      'recommended_scoped_generation', CASE WHEN v_scope_filtered THEN v_scope_generation ELSE NULL END,
      'distribution_rule_note', 'Kasa→alt kapsam (konu/alt konu/kazanım) dağılım kuralı şemada TANIMLI DEĞİLDİR (057/060/068''de kasa toplamı hedef vardır, alt kapsama bölme kuralı yok). Bu yüzden alt kapsam hedefi otomatik üretilemez; kullanıcı target_override ile AÇIK hedef verirse o hedef ile kapsam-gerçek stok karşılaştırılır. Hedef yoksa gap gösterilir, miktar uydurulmaz.',
      'target_multiplication_guard', 'Kasa toplam hedefi alt kapsam sayısıyla ÇARPILMAZ veya bölünmez; hafta bandı ile de çarpılmaz.'
    ),
    'context', jsonb_build_object(
      'existing_approved_active_questions', v_mevcut,
      'existing_questions_with_membership_in_scope', v_mevcut_uyelikli,
      'existing_questions_missing_membership', v_uyelik_eksik,
      'mapping_count_basis', CASE
        WHEN p_outcome_id IS NOT NULL THEN 'question_outcome_mappings (review_status=''approved''); sürüm filtresi curriculum_outcomes üzerinden'
        WHEN p_subtopic_id IS NOT NULL THEN 'question_curriculum_mappings.subtopic_id (review_status=''approved'')'
        WHEN p_topic_id IS NOT NULL THEN 'question_curriculum_mappings.topic_id (review_status=''approved'')'
        ELSE 'kapsam filtresi yok — sınıf+ders(+zorluk) genel sayım; eşleme şartı uygulanmadı'
      END,
      'mapping_gap_note', 'Eşlemesiz onaylı soru, konu/alt konu/kazanım filtreli kapsamda SAYILMAZ; ancak üyelik eksikleriyle birlikte ayrı görünür. Eşleme onayı (review_status) ayrı insan kararıdır.',
      'staging_candidates_in_scope_total', v_aday_total,
      'staging_candidates_validating', v_aday_validating,
      'staging_candidates_needs_review', v_aday_review,
      'staging_not_stock_note', 'Staging adayları ve devam eden işler STOK SAYILMAZ; onaylanıp üyelik yazılırsa açığın o kadarı kapanır — tekrar üretim riski buradan görünür.',
      'pending_ai_jobs', v_jobs_pending,
      'pending_ai_jobs_scope_note', 'ai_jobs satırlarının kapsam (konu/hafta) bağı şemada yoktur; sayım geneldir.'
    ),
    'recommendation', jsonb_build_object(
      'recommended_generation_count', v_generation,
      'recommended_current_generation', v_gen_current,
      'recommended_review_generation', v_gen_review,
      'difficulty_split', 'tanimsiz — zorluk dağılımı tanımlı kararla mevcut DEĞİL; otomatik eşit dağıtım YAPILMAZ (uydurma yok).',
      'is_binding_quantity', false,
      'binding_note', 'Bu öneri planlama hesabıdır; "kesin üretilecek miktar" DEĞİLDİR. İnsan üretim onayı (request → approve → dispatch → job) ayrı adımlardır ve bu görevde mevcut DEĞİLDİR.'
    ),
    'calculation_details', jsonb_build_object(
      'formula_version', 'vault-demand-v1-preview (057 DB-applied aynası)',
      'repo_drift_note', 'REPO 057 DOSYASI DRİFTLİ: repo satır 754-763 pencere sorgusu w.target_question_count kolonunu okur; bu kolon question_vault_activation_windows tablosunda YOK (048 + gerçek DB şeması). DB''de uygulanan gerçek tanım vault.metadata.target_question_count + pencere içindeki hafta durumu okur. Repo 057 senkronizasyonu ayrı dar iştir (WP-08 kapsamında işaretli).',
      'week_multiplication_guard', 'Hafta bandı ve pencere hedefi hedefle ÇARPILMAZ; activation_target bant içindeki pencere durumuna göre 0 veya defined_vault_target olur.'
    )
  );
END;
$$;


REVOKE ALL
  ON FUNCTION public.preview_question_generation_demand(smallint, uuid, uuid, text, text, integer, integer, text, uuid, uuid, uuid, integer, integer)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.preview_question_generation_demand(smallint, uuid, uuid, text, text, integer, integer, text, uuid, uuid, uuid, integer, integer)
  TO authenticated, service_role;

COMMIT;
