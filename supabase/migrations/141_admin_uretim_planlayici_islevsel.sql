-- ============================================================
-- 141_admin_uretim_planlayici_islevsel.sql
-- Altın Kalemler — ADMIN-PAGE-01B: /admin/uretim-planlayici işlevsel
-- tamamlama BACKEND dilimi (DAR, additive)
--
-- Kapsam:
--   1) preview_uretim_planlayici_scope_rows — ÇOKLU kapsam seçimi için
--      SATIR BAZLI salt-okunur (STABLE, yazmasız) stok/ihtiyaç
--      önizlemesi. 136 formül aynası ve stok kapsamları BİREBİR
--      KORUNUR; kasa hedefi (final_target_inventory) alt kapsama
--      KATLANMAZ/çarpılmaz; kasa KULLANICI SEÇİMİNE açıktır (ORDER BY
--      id ile gizli kasa seçimi YASAKTIR ve yapılmaz).
--   2) uretim_planlayici_list_academic_years / _list_academic_weeks —
--      DAR takvim okuma; izin: planner perms (ai.manage VEYA
--      questions.approve) VEYA calendar.manage. SALT-OKUNUR;
--      calendar.manage yazma yetkisini hesaba otomatik VERMEZ.
--   3) uretim_planlayici_list_vaults — DAR kasa listesi (planner
--      perms; yalnız aktif kasalar; seçim için).
--   4) uretim_planlayici_save_plan — plan kaydetme (YAZMA; gerçek
--      talep başlatma DEĞİL): mevcut zincir kullanılır
--      (calculate_question_vault_demand → snapshot,
--      create_question_generation_request → pending_approval,
--      mükerrer koruma mevcut) + dağılım satırları ai_generation_spec
--      içine VAR OLAN vault_shortage anahtarları korunarak merge
--      edilir. approve_question_generation_request ÇAĞRILMAZ;
--      onay/üretim ayrı insan işlemidir.
--
-- Sözleşme notları:
--   - Yalnız YENİ fonksiyonlara REVOKE/GRANT uygulanır; mevcut
--     roller/izinler DEĞİŞMEZ. Idempotent (create or replace);
--     BEGIN/COMMIT içinde tek transaction.
--   - Tüm yeni fonksiyonlar SECURITY DEFINER + search_path='' +
--     iç izin kontrolü (fail-closed) + Türkçe hata mesajları.
--   - 300 taban (weekly_competition planlama tabanı; 060:93-98),
--     500 tüketim tavanı (öğrenci/ders/hafta; 068) ve batch 20
--     birimleri karıştırılmaz; yalnız 136 notlarıyla taşınır.
--   - Bilinen açık: repo 057 dosyası driftli (dosya içi
--     calculate_question_vault_demand w.target_question_count okur;
--     DB'de uygulanan gerçek tanım vault.metadata okur — bkz. 136
--     repo_drift_note). save_plan DB'deki gerçek tanımı kullanır.
--     CI-temiz zincirde 057 gövde uzlaştırması WP-02 kapsamında ayrı
--     dar iştir; bu migration eski dosyalara DOKUNMAZ.
-- ============================================================

BEGIN;

-- ============================================================
-- 1) ÇOKLU KAPSAM SATIR BAZLI ÖNİZLEME (STABLE — YAZMASIZ)
--
-- Satır kümesi = seçilen boyut listelerinin Kartezyen çarpımı
-- (NULL/boş liste = o boyutta filtre yok = tek 'wildcard' satır).
-- Her satırda eşleme önceliği (136 sözleşmesi):
--   kazanım seçili  → question_outcome_mappings (approved; sürüm
--                     filtresi curriculum_outcomes üzerinden)
--   alt konu seçili → question_curriculum_mappings.subtopic_id
--   konu seçili     → question_curriculum_mappings.topic_id
--   hiçbiri         → sınıf+ders(+zorluk) genel sayım
-- DISTINCT question_id (LEFT JOIN) — çoklu eşleme şişirmez; aynı soru
-- birden çok kazanıma/temaya bağlı olsa da satır içinde TEK SAYILIR.
-- Satır bazlı sayılar satırlar arasında ÇAKIŞABİLİR (kesim kümesi);
-- küme toplamları 'set_totals' bloğunda BİRLİK (DISTINCT) ile
-- mükersersiz verilir.
-- ============================================================

CREATE OR REPLACE FUNCTION public.preview_uretim_planlayici_scope_rows(
  p_vault_id uuid,
  p_stock_scope text DEFAULT 'weekly_competition',
  p_inventory_scope text DEFAULT 'practice',
  p_week_from integer DEFAULT 1,
  p_week_to integer DEFAULT 1,
  p_grades smallint[] DEFAULT NULL,
  p_subject_ids uuid[] DEFAULT NULL,
  p_topic_ids uuid[] DEFAULT NULL,
  p_subtopic_ids uuid[] DEFAULT NULL,
  p_outcome_ids uuid[] DEFAULT NULL,
  p_difficulties text[] DEFAULT NULL,
  p_curriculum_version_id uuid DEFAULT NULL,
  p_target_override integer DEFAULT NULL,
  p_active_student_count integer DEFAULT 0,
  p_limit integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  v_vault record;
  v_policy record;
  v_policy_source text;
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
  v_defined_target integer := 0;
  v_is_active boolean := false;
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

  v_set_filtered boolean := false;

  v_limit integer;

  v_row record;
  v_row_index integer := 0;
  v_rows_out jsonb := '[]'::jsonb;
  v_total_rows integer := 0;
  v_truncated boolean := false;

  v_row_total integer;
  v_row_kasali integer;
  v_row_kasasiz integer;
  v_row_target integer;
  v_row_target_basis text;
  v_row_shortage integer;
  v_row_coverable integer;
  v_row_new_need integer;
  v_row_recommended integer;
  v_row_mapping_basis text;
  v_row_note text;
  v_aday_total integer;
  v_aday_validating integer;
  v_aday_review integer;

  v_set record;
  v_set_stg integer;
  v_jobs integer := 0;
BEGIN
  -- ------------------------------------------------------------
  -- Yetki (fail-closed): service_role VEYA planner izni.
  -- ------------------------------------------------------------
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Üretim planlayıcı için admin yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  -- ------------------------------------------------------------
  -- Kasa: KULLANICI SEÇİMİ.
  -- ------------------------------------------------------------
  IF p_vault_id IS NULL THEN
    RAISE EXCEPTION 'Kasa (vault) seçimi gerekli.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_vault
  FROM public.question_vaults v
  WHERE v.id = p_vault_id
    AND v.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aktif kasa bulunamadı.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_stock_scope NOT IN ('weekly_competition','rewarded_competition','training') THEN
    RAISE EXCEPTION 'Geçersiz stok kapsamı.'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_inventory_scope NOT IN ('practice','competition','one_v_one','exam') THEN
    RAISE EXCEPTION 'Geçersiz kasa/kullanım kapsamı.'
      USING ERRCODE = 'P0001';
  END IF;
  IF NOT (
    (p_inventory_scope = 'practice' AND v_vault.allow_practice = true)
    OR (p_inventory_scope = 'competition' AND v_vault.allow_competition = true)
    OR (p_inventory_scope = 'one_v_one' AND v_vault.allow_one_v_one = true)
    OR (p_inventory_scope = 'exam' AND v_vault.allow_exam = true)
  ) THEN
    RAISE EXCEPTION 'Seçilen kasa bu kullanım kapsamını desteklemiyor.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_grades IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_grades) AS gg(g)
    WHERE gg.g IS NULL OR gg.g < 1 OR gg.g > 12
  ) THEN
    RAISE EXCEPTION 'Geçersiz sınıf listesi (1-12).'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_difficulties IS NOT NULL AND EXISTS (
    SELECT 1 FROM unnest(p_difficulties) AS dd(d)
    WHERE dd.d IS NULL OR dd.d NOT IN ('easy','medium','hard','mixed')
  ) THEN
    RAISE EXCEPTION 'Geçersiz zorluk listesi.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_subject_ids IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM unnest(p_subject_ids) AS ss(id) WHERE ss.id IS NULL) THEN
      RAISE EXCEPTION 'Geçersiz ders listesi.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(p_subject_ids) AS ss(id)
      WHERE NOT EXISTS (SELECT 1 FROM public.subjects x WHERE x.id = ss.id)
    ) THEN
      RAISE EXCEPTION 'Seçilen dersten biri bulunamadı.' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_topic_ids IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM unnest(p_topic_ids) AS tt(id) WHERE tt.id IS NULL) THEN
      RAISE EXCEPTION 'Geçersiz konu listesi.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(p_topic_ids) AS tt(id)
      WHERE NOT EXISTS (SELECT 1 FROM public.topics x WHERE x.id = tt.id)
    ) THEN
      RAISE EXCEPTION 'Seçilen konulardan biri bulunamadı.' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_subtopic_ids IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM unnest(p_subtopic_ids) AS st(id) WHERE st.id IS NULL) THEN
      RAISE EXCEPTION 'Geçersiz alt konu listesi.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(p_subtopic_ids) AS st(id)
      WHERE NOT EXISTS (SELECT 1 FROM public.subtopics x WHERE x.id = st.id)
    ) THEN
      RAISE EXCEPTION 'Seçilen alt konulardan biri bulunamadı.' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_outcome_ids IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM unnest(p_outcome_ids) AS oo(id) WHERE oo.id IS NULL) THEN
      RAISE EXCEPTION 'Geçersiz kazanım listesi.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (
      SELECT 1 FROM unnest(p_outcome_ids) AS oo(id)
      WHERE NOT EXISTS (SELECT 1 FROM public.curriculum_outcomes x WHERE x.id = oo.id)
    ) THEN
      RAISE EXCEPTION 'Seçilen kazanumlardan biri bulunamadı.' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_target_override IS NOT NULL AND p_target_override <= 0 THEN
    RAISE EXCEPTION 'Geçersiz hedef (target_override).'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_week_from IS NULL OR p_week_from < 0 OR p_week_from > 52 THEN
    RAISE EXCEPTION 'Geçersiz hafta aralığı.'
      USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(p_week_to, p_week_from) < p_week_from
     OR COALESCE(p_week_to, p_week_from) > p_week_from + 52 THEN
    RAISE EXCEPTION 'Geçersiz hafta aralığı.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_active_student_count IS NULL OR p_active_student_count < 0 THEN
    RAISE EXCEPTION 'Geçersiz aktif öğrenci sayısı.'
      USING ERRCODE = 'P0001';
  END IF;

  v_limit := COALESCE(p_limit, 50);
  IF v_limit < 1 THEN
    v_limit := 50;
  END IF;
  v_limit := LEAST(v_limit, 200);

  -- ------------------------------------------------------------
  -- Policy + 057/136 FORMÜL AYNASI (birebir korunur).
  -- Policy kaydı yoksa 057 tablo DEFAULT'leri "önerilen varsayılan"
  -- etiketiyle kullanılır; kayıt AÇILMAZ (STABLE yazmasız).
  -- ------------------------------------------------------------
  SELECT * INTO v_policy
  FROM public.question_vault_demand_policies p
  WHERE p.vault_id = p_vault_id
    AND p.is_active = true
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
  ELSE
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

  v_diversity := round(
    1 + log(10::numeric, GREATEST(COALESCE(p_active_student_count, 0) + 1, 1)::numeric)
        * v_diversity_weight,
    4
  );

  v_base := v_weekly_questions::numeric * v_repeat_weeks::numeric;

  v_dynamic := ceil(v_base * v_diversity * v_safety)::integer;
  v_dynamic := GREATEST(v_dynamic, v_floor);

  -- DEFINED VAULT TARGET: vault.metadata.target_question_count
  -- (057 DB-applied tanım aynası; 136:228-236 ile aynı).
  SELECT CASE
    WHEN v_vault.metadata ? 'target_question_count'
         AND (v_vault.metadata ->> 'target_question_count') ~ '^[0-9]+$'
    THEN (v_vault.metadata ->> 'target_question_count')::integer
    ELSE 0
  END
  INTO v_defined_target;

  -- ACTIVE WINDOW (bant varyantı; 136:242-259 aynası; çarpan yok).
  SELECT EXISTS (
    SELECT 1
    FROM public.question_vault_activation_windows w
    WHERE w.vault_id = p_vault_id
      AND w.is_enabled = true
      AND EXISTS (
        SELECT 1
        FROM generate_series(
          COALESCE(p_week_from, 1),
          COALESCE(p_week_to, COALESCE(p_week_from, 1))
        ) AS g(wk)
        WHERE w.start_week <= g.wk
          AND g.wk < w.end_week
      )
  )
  INTO v_is_active;

  v_activation_target := CASE WHEN v_is_active THEN v_defined_target ELSE 0 END;

  v_set_filtered :=
       (p_topic_ids IS NOT NULL AND cardinality(p_topic_ids) > 0)
    OR (p_subtopic_ids IS NOT NULL AND cardinality(p_subtopic_ids) > 0)
    OR (p_outcome_ids IS NOT NULL AND cardinality(p_outcome_ids) > 0);

  v_final := GREATEST(v_dynamic, v_defined_target, v_floor);

  -- Override KASA TOPLAMINA yalnız alt kapsam filtresi YOKKEN
  -- uygulanır (136:273-286 aynası); alt kapsam seçiliyken override
  -- satır bazında uygulanır (300/floor kırpması alt kapsamda yok).
  IF p_target_override IS NOT NULL AND p_target_override > 0
     AND NOT v_set_filtered THEN
    v_override_applied := p_target_override;
    IF p_stock_scope = 'weekly_competition' AND v_override_applied < 300 THEN
      v_override_applied := 300;
    END IF;
    IF v_override_applied < v_floor THEN
      v_override_applied := v_floor;
    END IF;
    v_final := GREATEST(v_final, v_override_applied);
  END IF;

  -- Kasa TOPLAM uygun üyelik (057:782-808 aynası; 136:291-303).
  SELECT count(*)::integer
  INTO v_actual
  FROM public.question_vault_memberships m
  WHERE m.vault_id = p_vault_id
    AND m.membership_status = 'active'
    AND (
      (p_inventory_scope = 'practice' AND m.practice_eligible = true)
      OR (p_inventory_scope = 'competition' AND m.competition_eligible = true)
      OR (p_inventory_scope = 'one_v_one' AND m.one_v_one_eligible = true)
      OR (p_inventory_scope = 'exam' AND m.exam_eligible = true)
    );

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
  -- Satır kümesi: Kartezyen çarpım; NULL/boş liste = wildcard.
  -- Tavan: p_limit (1..200). Önce TOPLAM satır sayısı sayılır;
  -- fazlası kesilip 'truncated' işaretlenir (uydurma yok).
  -- ------------------------------------------------------------
  SELECT count(*)::integer
  INTO v_total_rows
  FROM (
    SELECT g.g AS g, ss.s AS s, tt.t AS t, st.su AS su, oo.o AS o, dd.d AS d
    FROM unnest(COALESCE(p_grades, ARRAY[NULL]::smallint[])) AS g(g)
    CROSS JOIN unnest(COALESCE(p_subject_ids, ARRAY[NULL]::uuid[])) AS ss(s)
    CROSS JOIN unnest(COALESCE(p_topic_ids, ARRAY[NULL]::uuid[])) AS tt(t)
    CROSS JOIN unnest(COALESCE(p_subtopic_ids, ARRAY[NULL]::uuid[])) AS st(su)
    CROSS JOIN unnest(COALESCE(p_outcome_ids, ARRAY[NULL]::uuid[])) AS oo(o)
    CROSS JOIN unnest(COALESCE(p_difficulties, ARRAY[NULL]::text[])) AS dd(d)
  ) AS src;

  FOR v_row IN
    SELECT src.g, src.s, src.t, src.su, src.o, src.d
    FROM (
      SELECT g.g AS g, ss.s AS s, tt.t AS t, st.su AS su, oo.o AS o, dd.d AS d
      FROM unnest(COALESCE(p_grades, ARRAY[NULL]::smallint[])) AS g(g)
      CROSS JOIN unnest(COALESCE(p_subject_ids, ARRAY[NULL]::uuid[])) AS ss(s)
      CROSS JOIN unnest(COALESCE(p_topic_ids, ARRAY[NULL]::uuid[])) AS tt(t)
      CROSS JOIN unnest(COALESCE(p_subtopic_ids, ARRAY[NULL]::uuid[])) AS st(su)
      CROSS JOIN unnest(COALESCE(p_outcome_ids, ARRAY[NULL]::uuid[])) AS oo(o)
      CROSS JOIN unnest(COALESCE(p_difficulties, ARRAY[NULL]::text[])) AS dd(d)
    ) AS src
    ORDER BY src.g NULLS LAST, src.s NULLS LAST, src.t NULLS LAST,
             src.su NULLS LAST, src.o NULLS LAST, src.d NULLS LAST
    LIMIT v_limit
  LOOP
    v_row_index := v_row_index + 1;

    -- 1) Satır bazlı gerçek stok — 136:335-386 sayım sözleşmesinin
    --    çoklu-kapsam genelleştirmesi. DISTINCT question_id; üyelik
    --    KULLANICININ SEÇTİĞİ kasada aranır (gizli kasa seçimi yok).
    SELECT
      count(DISTINCT q.id)::integer,
      count(DISTINCT q.id) FILTER (WHERE m.id IS NOT NULL)::integer
    INTO v_row_total, v_row_kasali
    FROM public.questions q
    LEFT JOIN public.question_vault_memberships m
      ON m.question_id = q.id
     AND m.vault_id = p_vault_id
     AND m.membership_status = 'active'
     AND (
       (p_inventory_scope = 'practice' AND m.practice_eligible = true)
       OR (p_inventory_scope = 'competition' AND m.competition_eligible = true)
       OR (p_inventory_scope = 'one_v_one' AND m.one_v_one_eligible = true)
       OR (p_inventory_scope = 'exam' AND m.exam_eligible = true)
     )
    WHERE q.is_active = true
      AND q.approval_status = 'approved'
      AND (v_row.g IS NULL OR q.grade_level = v_row.g)
      AND (v_row.s IS NULL OR q.subject_id = v_row.s)
      AND (v_row.d IS NULL OR q.difficulty = v_row.d)
      AND (
        (v_row.o IS NOT NULL AND EXISTS (
          SELECT 1
          FROM public.question_outcome_mappings qom
          JOIN public.curriculum_outcomes co ON co.id = qom.outcome_id
          WHERE qom.question_id = q.id
            AND qom.outcome_id = v_row.o
            AND qom.review_status = 'approved'
            AND (p_curriculum_version_id IS NULL
                 OR co.curriculum_version_id = p_curriculum_version_id)
        ))
        OR (v_row.o IS NULL AND v_row.su IS NOT NULL AND EXISTS (
          SELECT 1
          FROM public.question_curriculum_mappings qcm
          WHERE qcm.question_id = q.id
            AND qcm.subtopic_id = v_row.su
            AND qcm.review_status = 'approved'
            AND (p_curriculum_version_id IS NULL
                 OR qcm.curriculum_version_id = p_curriculum_version_id)
        ))
        OR (v_row.o IS NULL AND v_row.su IS NULL AND v_row.t IS NOT NULL AND EXISTS (
          SELECT 1
          FROM public.question_curriculum_mappings qcm
          WHERE qcm.question_id = q.id
            AND qcm.topic_id = v_row.t
            AND qcm.review_status = 'approved'
            AND (p_curriculum_version_id IS NULL
                 OR qcm.curriculum_version_id = p_curriculum_version_id)
        ))
        OR (v_row.o IS NULL AND v_row.su IS NULL AND v_row.t IS NULL)
      );

    v_row_kasasiz := GREATEST(v_row_total - v_row_kasali, 0);

    -- 2) İnceleme bekleyen staging adayları (STOK SAYILMAZ; 136:429-444 aynası)
    SELECT
      count(*)::integer,
      count(*) FILTER (WHERE s.staging_status = 'validating')::integer,
      count(*) FILTER (WHERE s.staging_status = 'needs_review')::integer
    INTO v_aday_total, v_aday_validating, v_aday_review
    FROM public.ai_question_staging s
    WHERE s.staging_status NOT IN ('rejected','promoted','already_promoted')
      AND (v_row.g IS NULL OR s.grade_level = v_row.g)
      AND (v_row.s IS NULL OR s.subject_id = v_row.s)
      AND (v_row.d IS NULL OR s.proposed_difficulty = v_row.d)
      AND (v_row.t IS NULL OR s.proposed_topic_id = v_row.t)
      AND (v_row.su IS NULL OR s.proposed_subtopic_id = v_row.su)
      AND (v_row.o IS NULL
           OR s.metadata ->> 'required_outcome_id' = v_row.o::text);

    -- 3) Satır hedefi: kullanıcı açık hedefi yoksa 'unknown' (uydurma yok).
    IF p_target_override IS NOT NULL AND p_target_override > 0 THEN
      v_row_target := p_target_override;
      v_row_target_basis := 'kullanıcı açık hedefi (p_target_override; satır bazında; kasa hedefi satıra katlanmadı/bölünmedi)';
    ELSE
      v_row_target := NULL;
      v_row_target_basis := 'unknown — kasa→alt kapsam dağıtım kuralı şemada tanımlı DEĞİL; hedef için p_target_override gerekli';
    END IF;

    IF v_row_target IS NOT NULL THEN
      v_row_shortage := GREATEST(v_row_target - v_row_kasali, 0);
      -- Kasasız uygun sorular (üyelik yazımıyla) kısmi açığı kabedebilir (estimated).
      v_row_coverable := LEAST(v_row_kasasiz, v_row_shortage);
      v_row_new_need := GREATEST(v_row_shortage - v_row_coverable, 0);
      IF v_row_new_need > 0 THEN
        v_row_recommended := ceil(v_row_new_need::numeric / v_batch::numeric)::integer * v_batch;
      ELSE
        v_row_recommended := 0;
      END IF;
    ELSE
      v_row_shortage := NULL;
      v_row_coverable := NULL;
      v_row_new_need := NULL;
      v_row_recommended := NULL;
    END IF;

    v_row_mapping_basis := CASE
      WHEN v_row.o IS NOT NULL
        THEN 'question_outcome_mappings (review_status=''approved''); sürüm filtresi curriculum_outcomes üzerinden'
      WHEN v_row.su IS NOT NULL
        THEN 'question_curriculum_mappings.subtopic_id (review_status=''approved'')'
      WHEN v_row.t IS NOT NULL
        THEN 'question_curriculum_mappings.topic_id (review_status=''approved'')'
      ELSE 'kapsam eşleme filtresi yok — sınıf+ders(+zorluk) genel sayım'
    END;

    v_row_note := CASE
      WHEN v_row.o IS NOT NULL AND (v_row.su IS NOT NULL OR v_row.t IS NOT NULL)
        THEN 'Kazanım seçili: satır sayımı kazanım eşlemesiyle yapıldı; konu/alt konu yalnız etiket (öncelik: kazanım > alt konu > konu).'
      ELSE NULL
    END;

    v_rows_out := v_rows_out || to_jsonb(jsonb_build_object(
      'row_index', v_row_index,
      'grade_level', v_row.g,
      'subject_id', v_row.s,
      'subject_name', (SELECT x.name FROM public.subjects x WHERE x.id = v_row.s),
      'topic_id', v_row.t,
      'topic_name', (SELECT x.name FROM public.topics x WHERE x.id = v_row.t),
      'subtopic_id', v_row.su,
      'subtopic_name', (SELECT x.name FROM public.subtopics x WHERE x.id = v_row.su),
      'outcome_id', v_row.o,
      'outcome_code', (SELECT x.outcome_code FROM public.curriculum_outcomes x WHERE x.id = v_row.o),
      'difficulty', v_row.d,
      'stock', jsonb_build_object(
        'eligible_stock_in_vault', v_row_kasali,
        'eligible_stock_without_vault', v_row_kasasiz,
        'eligible_scope_total', v_row_total,
        'count_basis', 'distinct_question_id',
        'membership_eligibility_scope', p_inventory_scope,
        'mapping_basis', v_row_mapping_basis
      ),
      'candidates', jsonb_build_object(
        'staging_candidates_total', v_aday_total,
        'staging_candidates_validating', v_aday_validating,
        'staging_candidates_needs_review', v_aday_review,
        'staging_status', 'known',
        'staging_not_stock_note', 'Staging adayları STOK SAYILMAZ; onaylanıp üyelik yazılırsa açığın o kadarı kapanır.'
      ),
      'need', jsonb_build_object(
        'row_target', v_row_target,
        'row_target_basis', v_row_target_basis,
        'shortage_count', v_row_shortage,
        'shortage_status', CASE WHEN v_row_target IS NOT NULL THEN 'known' ELSE 'unknown' END,
        'coverable_from_unvaulted_eligible', v_row_coverable,
        'coverable_basis', CASE WHEN v_row_target IS NOT NULL THEN 'estimated' ELSE 'unknown' END,
        'new_generation_need', v_row_new_need,
        'new_generation_need_status', CASE WHEN v_row_target IS NOT NULL THEN 'known' ELSE 'unknown' END,
        'recommended_generation_count', v_row_recommended,
        'recommended_generation_status', CASE WHEN v_row_target IS NOT NULL THEN 'known' ELSE 'unknown' END
      ),
      'note', v_row_note
    ));
  END LOOP;

  v_truncated := v_total_rows > v_row_index;

  -- ------------------------------------------------------------
  -- Küme toplamları (BİRLİK/DISTINCT — çakışan seçimlerde mükerrer
  -- sayım yok). Eşleme kademeleri Kartezyen satır ailesiyle uyumlu:
  -- kazanım ailesi açıkken konu/alt konu ailesi satırda zaten
  -- wildcard'a düşer; birlik kesişim kümesi mantığı korunur.
  -- ------------------------------------------------------------
  SELECT
    count(DISTINCT q.id)::integer AS count,
    count(DISTINCT q.id) FILTER (WHERE m.id IS NOT NULL)::integer AS kasali
  INTO v_set
  FROM public.questions q
  LEFT JOIN public.question_vault_memberships m
    ON m.question_id = q.id
   AND m.vault_id = p_vault_id
   AND m.membership_status = 'active'
   AND (
     (p_inventory_scope = 'practice' AND m.practice_eligible = true)
     OR (p_inventory_scope = 'competition' AND m.competition_eligible = true)
     OR (p_inventory_scope = 'one_v_one' AND m.one_v_one_eligible = true)
     OR (p_inventory_scope = 'exam' AND m.exam_eligible = true)
   )
  WHERE q.is_active = true
    AND q.approval_status = 'approved'
    AND (p_grades IS NULL OR q.grade_level = ANY(p_grades))
    AND (p_subject_ids IS NULL OR q.subject_id = ANY(p_subject_ids))
    AND (p_difficulties IS NULL OR q.difficulty = ANY(p_difficulties))
    AND (
      (p_outcome_ids IS NOT NULL AND cardinality(p_outcome_ids) > 0 AND EXISTS (
        SELECT 1
        FROM public.question_outcome_mappings qom
        JOIN public.curriculum_outcomes co ON co.id = qom.outcome_id
        WHERE qom.question_id = q.id
          AND qom.outcome_id = ANY(p_outcome_ids)
          AND qom.review_status = 'approved'
          AND (p_curriculum_version_id IS NULL
               OR co.curriculum_version_id = p_curriculum_version_id)
      ))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND p_subtopic_ids IS NOT NULL AND cardinality(p_subtopic_ids) > 0 AND EXISTS (
        SELECT 1
        FROM public.question_curriculum_mappings qcm
        WHERE qcm.question_id = q.id
          AND qcm.subtopic_id = ANY(p_subtopic_ids)
          AND qcm.review_status = 'approved'
          AND (p_curriculum_version_id IS NULL
               OR qcm.curriculum_version_id = p_curriculum_version_id)
      ))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND COALESCE(array_length(p_subtopic_ids, 1), 0) = 0
          AND p_topic_ids IS NOT NULL AND cardinality(p_topic_ids) > 0 AND EXISTS (
        SELECT 1
        FROM public.question_curriculum_mappings qcm
        WHERE qcm.question_id = q.id
          AND qcm.topic_id = ANY(p_topic_ids)
          AND qcm.review_status = 'approved'
          AND (p_curriculum_version_id IS NULL
               OR qcm.curriculum_version_id = p_curriculum_version_id)
      ))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND COALESCE(array_length(p_subtopic_ids, 1), 0) = 0
          AND COALESCE(array_length(p_topic_ids, 1), 0) = 0)
    );

  -- Küme staging toplamı (birlik; satır ailesi kademeleriyle uyumlu)
  SELECT count(*)::integer
  INTO v_set_stg
  FROM public.ai_question_staging s
  WHERE s.staging_status NOT IN ('rejected','promoted','already_promoted')
    AND (p_grades IS NULL OR s.grade_level = ANY(p_grades))
    AND (p_subject_ids IS NULL OR s.subject_id = ANY(p_subject_ids))
    AND (p_difficulties IS NULL OR s.proposed_difficulty = ANY(p_difficulties))
    AND (
      (p_outcome_ids IS NOT NULL AND cardinality(p_outcome_ids) > 0
       AND s.metadata ->> 'required_outcome_id' = ANY(
             SELECT x::text FROM unnest(p_outcome_ids) AS x))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND p_subtopic_ids IS NOT NULL AND cardinality(p_subtopic_ids) > 0
          AND s.proposed_subtopic_id = ANY(p_subtopic_ids))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND COALESCE(array_length(p_subtopic_ids, 1), 0) = 0
          AND p_topic_ids IS NOT NULL AND cardinality(p_topic_ids) > 0
          AND s.proposed_topic_id = ANY(p_topic_ids))
      OR (COALESCE(array_length(p_outcome_ids, 1), 0) = 0
          AND COALESCE(array_length(p_subtopic_ids, 1), 0) = 0
          AND COALESCE(array_length(p_topic_ids, 1), 0) = 0)
    );

  -- Devam eden üretim işleri: kapsam bağlantısı şemada YOK → global
  -- sayı AYRI gösterilir (136:447-450 sözleşmesi korunur).
  SELECT count(*)::integer
  INTO v_jobs
  FROM public.ai_jobs j
  WHERE j.status IN ('pending','queued','processing');

  RETURN jsonb_build_object(
    'ok', true,
    'scope', jsonb_build_object(
      'vault_id', p_vault_id,
      'vault_code', v_vault.vault_code,
      'vault_name', v_vault.name,
      'curriculum_version_id', p_curriculum_version_id,
      'stock_scope', p_stock_scope,
      'inventory_scope', p_inventory_scope,
      'week_from', p_week_from,
      'week_to', COALESCE(p_week_to, p_week_from),
      'grades', p_grades,
      'subject_ids', p_subject_ids,
      'topic_ids', p_topic_ids,
      'subtopic_ids', p_subtopic_ids,
      'outcome_ids', p_outcome_ids,
      'difficulties', p_difficulties,
      'target_override_input', p_target_override,
      'active_student_count', p_active_student_count,
      'selection_note', 'Kasa kullanıcı seçimidir; çoklu kasa seçimi bu dilimde DESTEKLENMEZ (tek talep = tek kasa).'
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
    'vault_target', jsonb_build_object(
      'base_student_inventory', v_base,
      'diversity_multiplier', v_diversity,
      'dynamic_target', v_dynamic,
      'defined_vault_target', v_defined_target,
      'is_active_in_week_band', v_is_active,
      'activation_target_count', v_activation_target,
      'minimum_inventory_floor', v_floor,
      'target_override_applied', v_override_applied,
      'final_target_inventory', v_final,
      'actual_eligible_inventory', v_actual,
      'membership_shortage', v_shortage,
      'excess_count', v_excess,
      'current_content_target', v_current_target,
      'review_content_target', v_review_target,
      'recommended_generation_count', v_generation,
      'recommended_current_generation', v_gen_current,
      'recommended_review_generation', v_gen_review,
      'target_folding_note', 'Kasa hedefi tek kez burada gösterilir; alt kapsam satırlarına ÇARPILMADI/BÖLÜNMEDİ (dağıtım kuralı şemada yok).',
      'stock_floor_note', CASE
        WHEN p_stock_scope = 'weekly_competition'
        THEN '300 alt sınırı bu stok kapsamı planlamasında geçerlidir (060:93-98).'
        ELSE 'Bu stok kapsamında taban zorunluluğu yoktur (060:20-21).'
      END,
      'consumption_cap_note', '500 tüketim tavanı (öğrenci/ders/hafta; 068) BU HESABA katılmaz ve tavan olarak kullanılamaz.',
      'week_multiplication_guard', 'Hafta bandı hedefle ÇARPILMAZ; pencere durumu yalnız activation_target''ı açıp kapatır; final MAX ile birleştirilir.'
    ),
    'rows', v_rows_out,
    'set_totals', jsonb_build_object(
      'distinct_eligible_scope_total', (v_set.kasali + GREATEST((v_set.count - v_set.kasali), 0)),
      'distinct_stock_in_vault', v_set.kasali,
      'distinct_stock_without_vault', GREATEST((v_set.count - v_set.kasali), 0),
      'count_basis', 'birlik (DISTINCT question_id; satırlar arası mükerrer sayım yok)',
      'staging_candidates_total', v_set_stg,
      'staging_status', 'known',
      'need_note', 'İhtiyaç (target/shortage) toplamı verilmez: kasa hedefi alt kapsama katlanmadığından satır bazlı değerler butunlukla ''rows'' içindedir.'
    ),
    'pending_ai_jobs', v_jobs,
    'pending_ai_jobs_scope_note', 'ai_jobs satırlarının kapsam (konu/hafta) bağı şemada yoktur; sayım geneldir.',
    'limits', jsonb_build_object(
      'row_limit', v_limit,
      'rows_returned', v_row_index,
      'total_row_count', v_total_rows,
      'truncated', v_truncated
    ),
    'calculation_details', jsonb_build_object(
      'formula_version', 'uretim-planlayici-rows-v1 (136 preview aynası + çoklu kapsam satırları)',
      'stock_scopes', 'weekly_competition/rewarded_competition/training; inventory_scopes: practice/competition/one_v_one/exam',
      'unit_note', '300 taban (weekly_competition), 500 tüketim tavanı, batch 20 ayrı birimlerdir; karıştırılmaz.'
    )
  );
END;
$body$;

-- ============================================================
-- 2) DAR TAKVİM OKUMA (planner perms VEYA calendar.manage)
--
-- Salt-okunur; calendar.manage yetkisi hesaba YAZMA yetkisi
-- otomatik VERMEZ (yazma yolu yalnız 073 mutation RPC'leridir ve
-- calendar.manage ister). Fail-closed 42501.
-- ============================================================

CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_academic_years()
RETURNS TABLE (
  academic_year text,
  week_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
     AND NOT private.current_user_has_admin_permission('questions.approve')
     AND NOT public.academic_calendar_has_permission('calendar.manage')
  THEN
    RAISE EXCEPTION 'Akademik takvimi görüntülemek için planlayıcı veya calendar.manage yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT w.academic_year, count(*)::bigint
    FROM public.academic_weeks w
    GROUP BY w.academic_year
    ORDER BY w.academic_year DESC;
END;
$body$;


CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_academic_weeks(
  p_year text
)
RETURNS TABLE (
  academic_year text,
  week integer,
  starts_at date,
  ends_at date,
  is_started boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  v_year text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT private.current_user_has_admin_permission('ai.manage')
     AND NOT private.current_user_has_admin_permission('questions.approve')
     AND NOT public.academic_calendar_has_permission('calendar.manage')
  THEN
    RAISE EXCEPTION 'Akademik takvimi görüntülemek için planlayıcı veya calendar.manage yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  v_year := btrim(COALESCE(p_year, ''));
  IF v_year = '' THEN
    RAISE EXCEPTION 'Akademik yıl bilgisi boş olamaz.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
    SELECT w.academic_year,
           w.week,
           w.starts_at,
           w.ends_at,
           (w.starts_at <= current_date)
    FROM public.academic_weeks w
    WHERE w.academic_year = v_year
    ORDER BY w.starts_at, w.week;
END;
$body$;

-- ============================================================
-- 3) DAR KASA LİSTESİ (planner perms; yalnız aktif; seçim için)
-- ============================================================

CREATE OR REPLACE FUNCTION public.uretim_planlayici_list_vaults()
RETURNS TABLE (
  vault_id uuid,
  vault_code text,
  name text,
  vault_type text,
  grade_level smallint,
  subject_id uuid,
  subject_name text,
  allow_practice boolean,
  allow_competition boolean,
  allow_one_v_one boolean,
  allow_exam boolean,
  policy_inventory_scope text,
  target_question_count integer,
  target_basis text,
  activation_windows jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $body$
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Üretim planlayıcı için admin yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      v.id,
      v.vault_code,
      v.name,
      v.vault_type,
      v.grade_level,
      v.subject_id,
      sb.name,
      v.allow_practice,
      v.allow_competition,
      v.allow_one_v_one,
      v.allow_exam,
      (SELECT p.inventory_scope
         FROM public.question_vault_demand_policies p
        WHERE p.vault_id = v.id
          AND p.is_active = true
        ORDER BY p.created_at DESC
        LIMIT 1),
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN (v.metadata ->> 'target_question_count')::integer
      END,
      CASE
        WHEN v.metadata ? 'target_question_count'
             AND (v.metadata ->> 'target_question_count') ~ '^[0-9]+$'
        THEN 'vault.metadata.target_question_count'
        ELSE 'unknown'
      END,
      COALESCE(
        (SELECT jsonb_agg(
                  jsonb_build_object(
                    'window_name', w.window_name,
                    'start_week', w.start_week,
                    'end_week', w.end_week,
                    'is_enabled', w.is_enabled)
                  ORDER BY w.start_week NULLS FIRST)
           FROM public.question_vault_activation_windows w
          WHERE w.vault_id = v.id),
        '[]'::jsonb)
    FROM public.question_vaults v
    LEFT JOIN public.subjects sb ON sb.id = v.subject_id
    WHERE v.is_active = true
    ORDER BY v.vault_code
    LIMIT 200;
END;
$body$;

-- ============================================================
-- 4) PLAN KAYDETME (YAZMA; gerçek üretim başlatma DEĞİL)
--
-- Zincir: calculate_question_vault_demand (snapshot YAZAR) →
-- create_question_generation_request (pending_approval; açık talep
-- varsa idempotent döner) → kullanıcı toplam miktarı + dağılım
-- satırları talebe yazılır. approve_question_generation_request
-- ÇAĞRILMAZ. Tek talep = tek kasa (kullanıcı kararı); çoklu kasa
-- seçimi bu dilimde desteklenmez (UI tek kasa seçer).
--
-- Sınırlar (tasarım kararı; DB CHECK'ten türetildi + dar tavan):
--   - toplam 1..2000 (tablo CHECK yalnız >= 0 der; 2000 UI tavanı)
--   - satır sayısı 1..200 (139 p_limit tavanı ile uyumlu)
--   - satır 'selected' >= 0; toplamı kullanıcı miktarına eşit olmalı
--   - önerilen (recommended) bilgilendirme amaçlıdır; zorlamaz
-- ============================================================

CREATE OR REPLACE FUNCTION public.uretim_planlayici_save_plan(
  p_vault_id uuid,
  p_stock_scope text DEFAULT 'weekly_competition',
  p_inventory_scope text DEFAULT 'practice',
  p_week_from integer DEFAULT 1,
  p_week_to integer DEFAULT 1,
  p_active_student_count integer DEFAULT 0,
  p_total_quantity integer DEFAULT NULL,
  p_plan_rows jsonb DEFAULT NULL,
  p_plan_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $body$
DECLARE
  v_vault record;
  v_policy record;
  v_actor uuid;
  v_limit_note text;
  v_open_request_id uuid;
  v_open_status text;
  v_open_current integer;
  v_open_review integer;
  v_open_count integer;
  v_snapshot_id uuid;
  v_demand jsonb;
  v_demand_priority text;
  v_request_id uuid;
  v_row_count integer;
  v_i integer;
  v_row jsonb;
  v_txt text;
  v_clean_rows jsonb := '[]'::jsonb;
  v_row_grade smallint;
  v_row_subject uuid;
  v_row_topic uuid;
  v_row_subtopic uuid;
  v_row_outcome uuid;
  v_row_difficulty text;
  v_row_selected integer;
  v_row_recommended integer;
  v_row_note text;
  v_sum_selected integer := 0;
  v_current integer;
  v_review integer;
  v_note text;
BEGIN
  -- Yetki (fail-closed): service_role VEYA planner izni.
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND NOT (
       private.current_user_has_admin_permission('ai.manage')
       OR private.current_user_has_admin_permission('questions.approve')
     )
  THEN
    RAISE EXCEPTION 'Üretim planlayıcı için admin yetkisi gerekli.'
      USING ERRCODE = '42501';
  END IF;

  v_actor := auth.uid();

  IF p_vault_id IS NULL THEN
    RAISE EXCEPTION 'Kasa (vault) seçimi gerekli.' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_vault
  FROM public.question_vaults v
  WHERE v.id = p_vault_id AND v.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aktif kasa bulunamadı.' USING ERRCODE = 'P0001';
  END IF;

  IF p_stock_scope NOT IN ('weekly_competition','rewarded_competition','training') THEN
    RAISE EXCEPTION 'Geçersiz stok kapsamı.' USING ERRCODE = 'P0001';
  END IF;
  IF p_inventory_scope NOT IN ('practice','competition','one_v_one','exam') THEN
    RAISE EXCEPTION 'Geçersiz kasa/kullanım kapsamı.' USING ERRCODE = 'P0001';
  END IF;
  IF NOT (
    (p_inventory_scope = 'practice' AND v_vault.allow_practice = true)
    OR (p_inventory_scope = 'competition' AND v_vault.allow_competition = true)
    OR (p_inventory_scope = 'one_v_one' AND v_vault.allow_one_v_one = true)
    OR (p_inventory_scope = 'exam' AND v_vault.allow_exam = true)
  ) THEN
    RAISE EXCEPTION 'Seçilen kasa bu kullanım kapsamını desteklemiyor.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_week_from IS NULL OR p_week_from < 0 OR p_week_from > 52 THEN
    RAISE EXCEPTION 'Geçersiz hafta aralığı.' USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(p_week_to, p_week_from) < p_week_from
     OR COALESCE(p_week_to, p_week_from) > p_week_from + 52 THEN
    RAISE EXCEPTION 'Geçersiz hafta aralığı.' USING ERRCODE = 'P0001';
  END IF;

  IF p_active_student_count IS NULL OR p_active_student_count < 0 THEN
    RAISE EXCEPTION 'Geçersiz aktif öğrenci sayısı.' USING ERRCODE = 'P0001';
  END IF;

  IF p_total_quantity IS NULL OR p_total_quantity < 1 OR p_total_quantity > 2000 THEN
    RAISE EXCEPTION 'Toplam miktar 1-2000 arasında olmalı.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_plan_rows IS NULL OR jsonb_typeof(p_plan_rows) <> 'array'
     OR jsonb_array_length(p_plan_rows) = 0 THEN
    RAISE EXCEPTION 'Dağılım satırları (p_plan_rows) boş olamaz.'
      USING ERRCODE = 'P0001';
  END IF;

  v_row_count := jsonb_array_length(p_plan_rows);
  IF v_row_count > 200 THEN
    RAISE EXCEPTION 'Dağılım satır sayısı en fazla 200 olabilir.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Policy: mevcut zincirin ensure yardımcısı (varsayılan policy yoksa açar).
  PERFORM public.ensure_question_vault_demand_policy(p_vault_id);

  SELECT * INTO v_policy
  FROM public.question_vault_demand_policies p
  WHERE p.vault_id = p_vault_id AND p.is_active = true
  ORDER BY p.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Talep politika kaydı oluşturulamadı.'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_inventory_scope <> v_policy.inventory_scope THEN
    RAISE EXCEPTION 'Kasa politika kapsamı (%) ile seçilen kullanım kapsamı (%) uyuşmuyor.',
                    v_policy.inventory_scope, p_inventory_scope
      USING ERRCODE = 'P0001';
  END IF;

  v_i := 0;
  WHILE v_i < v_row_count LOOP
    v_row := p_plan_rows -> v_i;
    IF v_row IS NULL OR jsonb_typeof(v_row) <> 'object' THEN
      RAISE EXCEPTION 'Satır %: geçersiz satır.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;

    -- sınıf (zorunlu)
    IF NOT (v_row ? 'grade_level')
       OR NOT (v_row ->> 'grade_level') ~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'Satır %: geçerli sınıf gerekli.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;
    v_row_grade := (v_row ->> 'grade_level')::smallint;
    IF v_row_grade < 1 OR v_row_grade > 12 THEN
      RAISE EXCEPTION 'Satır %: sınıf 1-12 arasında olmalı.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;

    -- ders (zorunlu)
    v_txt := NULLIF(btrim(COALESCE(v_row ->> 'subject_id', '')), '');
    IF v_txt IS NULL
       OR v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
      RAISE EXCEPTION 'Satır %: geçerli ders kimliği gerekli.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;
    v_row_subject := v_txt::uuid;
    IF NOT EXISTS (SELECT 1 FROM public.subjects x WHERE x.id = v_row_subject) THEN
      RAISE EXCEPTION 'Satır %: ders bulunamadı.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;

    -- konu (opsiyonel)
    v_row_topic := NULL;
    v_txt := NULLIF(btrim(COALESCE(v_row ->> 'topic_id', '')), '');
    IF v_txt IS NOT NULL THEN
      IF v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
        RAISE EXCEPTION 'Satır %: geçersiz konu kimliği.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
      v_row_topic := v_txt::uuid;
      IF NOT EXISTS (SELECT 1 FROM public.topics x WHERE x.id = v_row_topic) THEN
        RAISE EXCEPTION 'Satır %: konu bulunamadı.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- alt konu (opsiyonel)
    v_row_subtopic := NULL;
    v_txt := NULLIF(btrim(COALESCE(v_row ->> 'subtopic_id', '')), '');
    IF v_txt IS NOT NULL THEN
      IF v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
        RAISE EXCEPTION 'Satır %: geçersiz alt konu kimliği.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
      v_row_subtopic := v_txt::uuid;
      IF NOT EXISTS (SELECT 1 FROM public.subtopics x WHERE x.id = v_row_subtopic) THEN
        RAISE EXCEPTION 'Satır %: alt konu bulunamadı.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- kazanım (opsiyonel)
    v_row_outcome := NULL;
    v_txt := NULLIF(btrim(COALESCE(v_row ->> 'outcome_id', '')), '');
    IF v_txt IS NOT NULL THEN
      IF v_txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
        RAISE EXCEPTION 'Satır %: geçersiz kazanım kimliği.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
      v_row_outcome := v_txt::uuid;
      IF NOT EXISTS (SELECT 1 FROM public.curriculum_outcomes x WHERE x.id = v_row_outcome) THEN
        RAISE EXCEPTION 'Satır %: kazanım bulunamadı.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
    END IF;

    -- zorluk (opsiyonel)
    v_row_difficulty := NULLIF(btrim(COALESCE(v_row ->> 'difficulty', '')), '');
    IF v_row_difficulty IS NOT NULL
       AND v_row_difficulty NOT IN ('easy','medium','hard','mixed') THEN
      RAISE EXCEPTION 'Satır %: geçersiz zorluk.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;

    -- seçilen (zorunlu)
    IF NOT (v_row ? 'selected')
       OR NOT (v_row ->> 'selected') ~ '^[0-9]+$' THEN
      RAISE EXCEPTION 'Satır %: geçerli seçilen miktar gerekli.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;
    v_row_selected := (v_row ->> 'selected')::integer;
    IF v_row_selected < 0 OR v_row_selected > 2000 THEN
      RAISE EXCEPTION 'Satır %: seçilen miktar 0-2000 arasında olmalı.', v_i + 1 USING ERRCODE = 'P0001';
    END IF;

    -- önerilen (opsiyonel, bilgilendirme amaçlı; zorlama yok)
    v_row_recommended := NULL;
    v_txt := NULLIF(btrim(COALESCE(v_row ->> 'recommended', '')), '');
    IF v_txt IS NOT NULL THEN
      IF v_txt !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'Satır %: geçersiz önerilen miktar.', v_i + 1 USING ERRCODE = 'P0001';
      END IF;
      v_row_recommended := v_txt::integer;
    END IF;

    v_row_note := NULLIF(btrim(COALESCE(v_row ->> 'note', '')), '');

    v_sum_selected := v_sum_selected + v_row_selected;

    v_clean_rows := v_clean_rows || jsonb_build_object(
      'grade_level', v_row_grade,
      'subject_id', v_row_subject,
      'topic_id', v_row_topic,
      'subtopic_id', v_row_subtopic,
      'outcome_id', v_row_outcome,
      'difficulty', v_row_difficulty,
      'recommended', v_row_recommended,
      'selected', v_row_selected,
      'note', v_row_note
    );

    v_i := v_i + 1;
  END LOOP;

  IF v_sum_selected <> p_total_quantity THEN
    RAISE EXCEPTION 'Dağılım satırlarının seçilen toplamı (%) toplam miktarla (%) uyuşmuyor.',
                    v_sum_selected, p_total_quantity
      USING ERRCODE = 'P0001';
  END IF;

  v_note := NULLIF(btrim(COALESCE(p_plan_note, '')), '');

  -- ------------------------------------------------------------
  -- Açık talep kontrolü (create_question_generation_request davranış
  -- aynası; 057:1174-1193): açık talep varsa YENİ TALEP AÇILMAZ,
  -- mevcut id döner (UI'ya 'created:false').
  -- ------------------------------------------------------------
  SELECT r.id, r.request_status, r.requested_question_count,
         r.current_question_count, r.review_question_count
  INTO v_open_request_id, v_open_status, v_open_count,
       v_open_current, v_open_review
  FROM public.question_generation_requests r
  WHERE r.vault_id = p_vault_id
    AND r.request_status IN (
      'pending_approval','approved','generating','reviewing',
      'awaiting_human_approval','placing'
    )
  ORDER BY r.created_at DESC
  LIMIT 1;

  IF v_open_request_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'created', false,
      'request_id', v_open_request_id,
      'request_status', v_open_status,
      'requested_question_count', v_open_count,
      'current_question_count', v_open_current,
      'review_question_count', v_open_review,
      'snapshot_id', NULL,
      'plan_row_count', v_row_count,
      'plan_selected_total', v_sum_selected,
      'message', 'Bu kasa için açık bir üretim talebi zaten var; yeni talep açılmadı.'
    );
  END IF;

  -- ------------------------------------------------------------
  -- Mevcut zincir: snapshot (YAZAR) → pending_approval talep.
  -- ------------------------------------------------------------
  v_demand := public.calculate_question_vault_demand(
    p_vault_id, p_week_from, p_active_student_count, NULL
  );
  v_snapshot_id := (v_demand ->> 'snapshot_id')::uuid;

  v_current := ceil(
    p_total_quantity::numeric * v_policy.current_content_ratio
  )::integer;
  v_review := GREATEST(p_total_quantity - v_current, 0);

  IF (v_demand ->> 'recommended_generation_count')::integer > 0 THEN
    v_request_id := public.create_question_generation_request(v_snapshot_id);

    -- Kullanıcı toplamı + dağılım satırları: VAR OLAN vault_shortage
    -- anahtarları korunarak merge (counts tutarlı güncellenir).
    UPDATE public.question_generation_requests
    SET requested_question_count = p_total_quantity,
        current_question_count = v_current,
        review_question_count = v_review,
        generation_batch_size = v_policy.generation_batch_size,
        requested_by = v_actor,
        ai_generation_spec = jsonb_set(
                               jsonb_set(
                                 COALESCE(ai_generation_spec, '{}'::jsonb),
                                 '{current_question_count}', to_jsonb(v_current)),
                               '{review_question_count}', to_jsonb(v_review))
                             || jsonb_build_object(
                                  'plan_source', 'uretim_planlayici',
                                  'plan_total_quantity', p_total_quantity,
                                  'plan_rows', v_clean_rows,
                                  'plan_note', v_note,
                                  'plan_scope', jsonb_build_object(
                                    'stock_scope', p_stock_scope,
                                    'inventory_scope', p_inventory_scope,
                                    'week_from', p_week_from,
                                    'week_to', COALESCE(p_week_to, p_week_from),
                                    'active_student_count', p_active_student_count)),
        request_reason = COALESCE(request_reason, '{}'::jsonb)
                         || jsonb_build_object(
                              'planner_stock_scope', p_stock_scope,
                              'planner_week_from', p_week_from,
                              'planner_week_to', COALESCE(p_week_to, p_week_from),
                              'planner_plan_note', v_note),
        updated_at = now()
    WHERE id = v_request_id
      AND request_status = 'pending_approval';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Talep güncellenemedi (durum ara değişmiş olabilir).'
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- ------------------------------------------------------------
    -- Formula önerisi 0 (shortage yok): kullanıcı kararıyla plan
    -- yine pending_approval olarak açılır (kaba zorlama yok).
    -- Tekil-kasa açık talep unique indexi
    -- (idx_question_generation_requests_one_open_per_vault)
    -- mükerrerliği kesin engeller; unique_violation → mevcut id döner.
    -- ------------------------------------------------------------
    v_demand_priority := CASE
      WHEN v_demand ->> 'generation_priority' = 'critical' THEN 'critical'
      WHEN v_demand ->> 'generation_priority' = 'high' THEN 'high'
      WHEN v_demand ->> 'generation_priority' = 'low' THEN 'low'
      ELSE 'normal'
    END;

    BEGIN
      INSERT INTO public.question_generation_requests (
        vault_id, demand_snapshot_id, request_status,
        requested_question_count, current_question_count, review_question_count,
        generation_batch_size, generation_priority, request_reason,
        ai_generation_spec, requested_by
      ) VALUES (
        p_vault_id, v_snapshot_id, 'pending_approval',
        p_total_quantity, v_current, v_review,
        v_policy.generation_batch_size, v_demand_priority,
        jsonb_build_object(
          'shortage_count', (v_demand ->> 'shortage_count')::integer,
          'actual_inventory', (v_demand ->> 'actual_eligible_inventory')::integer,
          'target_inventory', (v_demand ->> 'final_target_inventory')::integer,
          'active_student_count', p_active_student_count,
          'planner_stock_scope', p_stock_scope,
          'planner_week_from', p_week_from,
          'planner_week_to', COALESCE(p_week_to, p_week_from),
          'planner_plan_note', v_note),
        jsonb_build_object(
          'generation_mode', 'vault_shortage',
          'current_question_count', v_current,
          'review_question_count', v_review,
          'use_reference_questions', true,
          'human_final_approval_required', true,
          'auto_vault_placement_after_approval', true,
          'plan_source', 'uretim_planlayici',
          'plan_total_quantity', p_total_quantity,
          'plan_rows', v_clean_rows,
          'plan_note', v_note,
          'plan_scope', jsonb_build_object(
            'stock_scope', p_stock_scope,
            'inventory_scope', p_inventory_scope,
            'week_from', p_week_from,
            'week_to', COALESCE(p_week_to, p_week_from),
            'active_student_count', p_active_student_count)),
        v_actor
      )
      RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT r.id INTO v_request_id
      FROM public.question_generation_requests r
      WHERE r.vault_id = p_vault_id
        AND r.request_status IN (
          'pending_approval','approved','generating','reviewing',
          'awaiting_human_approval','placing'
        )
      ORDER BY r.created_at DESC
      LIMIT 1;
      RETURN jsonb_build_object(
        'ok', true,
        'created', false,
        'request_id', v_request_id,
        'request_status', 'pending_approval',
        'requested_question_count', NULL,
        'current_question_count', NULL,
        'review_question_count', NULL,
        'snapshot_id', v_snapshot_id,
        'plan_row_count', v_row_count,
        'plan_selected_total', v_sum_selected,
        'message', 'Bu kasa için açık bir üretim talebi zaten var; yeni talep açılmadı.'
      );
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'created', true,
    'request_id', v_request_id,
    'request_status', 'pending_approval',
    'requested_question_count', p_total_quantity,
    'current_question_count', v_current,
    'review_question_count', v_review,
    'snapshot_id', v_snapshot_id,
    'plan_row_count', v_row_count,
    'plan_selected_total', v_sum_selected,
    'message', 'Plan pending_approval talebi olarak kaydedildi; üretim için ayrı insan onayı gerekir.'
  );
END;
$body$;


-- ============================================================
-- 5) İZİN MATRİSİ — yalnız YENİ fonksiyonlar; mevcut roller/izinler
--    DEĞİŞMEZ (PUBLIC/anon revoked; authenticated + service_role).
-- ============================================================

REVOKE ALL ON FUNCTION
  public.preview_uretim_planlayici_scope_rows(uuid, text, text, integer, integer, smallint[], uuid[], uuid[], uuid[], uuid[], text[], uuid, integer, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.preview_uretim_planlayici_scope_rows(uuid, text, text, integer, integer, smallint[], uuid[], uuid[], uuid[], uuid[], text[], uuid, integer, integer, integer)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_academic_years()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_academic_years()
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_academic_weeks(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_academic_weeks(text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.uretim_planlayici_list_vaults()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_list_vaults()
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.uretim_planlayici_save_plan(uuid, text, text, integer, integer, integer, integer, jsonb, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.uretim_planlayici_save_plan(uuid, text, text, integer, integer, integer, integer, jsonb, text)
  TO authenticated, service_role;


COMMENT ON FUNCTION public.preview_uretim_planlayici_scope_rows(uuid, text, text, integer, integer, smallint[], uuid[], uuid[], uuid[], uuid[], text[], uuid, integer, integer, integer)
  IS 'ADMIN-PAGE-01B: çoklu kapsam satır bazlı salt-okunur stok/ihtiyaç önizlemesi (136 formül aynası; kasa kullanıcı seçimi).';
COMMENT ON FUNCTION public.uretim_planlayici_list_academic_years()
  IS 'ADMIN-PAGE-01B: akademik yıl listesi (planner perms VEYA calendar.manage; salt-okunur).';
COMMENT ON FUNCTION public.uretim_planlayici_list_academic_weeks(text)
  IS 'ADMIN-PAGE-01B: akademik hafta listesi (planner perms VEYA calendar.manage; salt-okunur).';
COMMENT ON FUNCTION public.uretim_planlayici_list_vaults()
  IS 'ADMIN-PAGE-01B: aktif kasa listesi (planner perms; hedef + aktivasyon pencere bilgisiyle).';
COMMENT ON FUNCTION public.uretim_planlayici_save_plan(uuid, text, text, integer, integer, integer, integer, jsonb, text)
  IS 'ADMIN-PAGE-01B: plan kaydetme — snapshot + pending_approval talep açar; dağılım satırlarını ai_generation_spec''e merge eder; üretim BAŞLATMAZ.';


COMMIT;
