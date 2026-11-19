-- 152_bulk_gate_kiralama_guard.sql — AK-QV-02A TASLAK (UYGULANMAMIŞTIR)
--
-- Amaç (AK-QV-01 kök neden bulgusu):
--   complete_bulk_gate_task (135) ve requeue_bulk_gate_task (134) sahiplik/lease
--   denetimi YAPMIYOR:
--     * kiralama süresi dolmuş eski işçinin gecikmiş complete'i, yeni işçinin
--       sahiplendiği görevi 'completed'→'failed' çevirebiliyor, claimed_by/lease
--       alanlarını silebiliyor;
--     * requeue, durumu denetlemeden tamamlanmış görevi 'pending'e döndürebiliyor;
--     * ikinci bir tamamlama (aynı ya da yabancı) her seferinde kabul ediliyor.
--   claim_bulk_gate_tasks (134) zaten doğru: süresi dolmamış 'running' alınamaz,
--   süresi dolmuş + hakkı olan yeniden alınabilir (attempt_count<3), dolmuş +
--   hakkı bitmiş 'failed' kapatılır, FOR UPDATE SKIP LOCKED eşzamanlı claim'i
--   engeller. Bu migration claim Sözleşmesini DEĞİŞTİRMEZ.
--
-- Guard sözleşmesi (yalnız iki fonksiyon):
--   G0) p_worker_id ZORUNLUDUR: NULL, boş veya yalnız boşluk içeren token
--       istisna ile reddedilir (ERRCODE 22023). Parametrede DEFAULT NULL
--       YOKTUR → PostgREST, token göndermeyen çağrıyı imza eşleştiremez ve
--       RPC düzeyinde reddeder (fail-closed, AK-QV-02C sıkılaştırması).
--   G1) Yalnız status='running' görev tamamlanabilir / kuyruğa alınabilir.
--       Aksi hâlde istisna DEĞİL, {"ignored": "..."} jsonb döner (idempotent;
--       mükerrer complete zincir adımı ikinci kez açmaz).
--   G2) Sahiplik ZORUNLU: claimed_by birebir eşleşmeli ve kiralama taze
--       olmalı (lease_expires_at > now()). Uyuşmazlık → {"ignored":
--       "foreign_claim" | "lease_expired"} — yeni işçinin sonucu bozulmaz.
--   G3) Eski korumasız imzalar DROP edilir (kapalı kapı bırakılmaz).
--       İMZA SIRASI (AK-QV-02C): PostgreSQL zorunlu parametreden SONRA
--       varsayılanlı parametreye izin VERMEZ ("input parameters after one
--       with a default value must also have defaults"). Bu yüzden
--       p_worker_id sondan 3. sıraya alındı:
--         complete(p_task_id, p_status, p_worker_id, p_error_code=NULL,
--                  p_error_message=NULL)
--         requeue (p_task_id, p_worker_id, p_error_code=NULL,
--                  p_error_message=NULL)
--       Worker PostgREST üzerinden ADLANDIRILMIŞ çağrı yapar → sıradan
--       etkilenmez. Adlandırılmış ama p_worker_id GÖNDERMEYEN çağrı imza
--       eşleşmez → RPC hatası (fail-closed). Eski tip-listeli kimlikler
--       (canlı 4/3 arg + 02B dönemi) CREATE'dan önce DROP edilir.
--
-- Bu dosya yalnız taslak + disposable QA provası içindir. Canlıya kullanıcı
-- onayı ve tek onay paketi olmadan uygulanmaz.
--
-- BAĞIMSIZ DENETİM KOŞULLARI (RealityIntegration, 4 Kas) bu sürüme işlendi:
--   * BEGIN/COMMIT sarmalı (135 kalıbı) — CREATE/DROP/GRANT tek transaction.
--   * p_worker_id DEFAULT NULL gedigi KAPATILDI (AK-QV-02C): default kaldırıldı,
--     G0 doğrulaması eklendi; token'sız/boş token yolu artık yok.
--   * claim'deki p_worker_id boş-string gedigi (134:389) bilinçli KORUNDU
--     (claim sözleşmesi değişmez). Boş token'la claim tuzaksa bile complete/
--     requeue G0'da reddedilir → görev bozulmaz, lease sonrası geri alınır;
--     claim tarafı doğrulaması ayrı izlek dilimidir.

BEGIN;

-- Aynı tip-listeli olası eski kimlikleri kaldır: canlı 135 (4 arg) ve varsa
-- AK-QV-02B dönemi 5 arg (p_worker_id DEFAULT NULL). Adlandırılmış
-- argümanları değişen CREATE OR REPLACE YERİNE İKİNCİ bir yük oluşturur;
-- önce DROP tek kimlik garantiler (transaction içinde görünürlük yok).
DROP FUNCTION IF EXISTS public.complete_bulk_gate_task(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.complete_bulk_gate_task(uuid, text, text, text, text);

CREATE OR REPLACE FUNCTION public.complete_bulk_gate_task(
  p_task_id uuid,
  p_status text,
  p_worker_id text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_next_status text;
  v_next_created boolean := false;
  v_next_role text;
  v_remaining integer := 0;
  v_run_stopped boolean := false;
  v_completed integer := 0;
  v_failed integer := 0;
  v_skipped integer := 0;
  v_run_status text;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  IF p_status NOT IN ('completed', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'Invalid task status.';
  END IF;

  -- G0) Zorunlu, boş olmayan sahiplik token'ı (AK-QV-02C).
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' THEN
    RAISE EXCEPTION 'p_worker_id is required (non-blank).'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_task
  FROM public.admin_bulk_gate_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  -- G1) Yalnızca 'running' görev tamamlanabilir. Tamamlanmış/başarısız
  --     görevin ikinci kez tamamlanması idempotent olarak yok sayılır.
  IF v_task.status <> 'running' THEN
    RETURN jsonb_build_object(
      'ignored', 'not_running',
      'task_id', p_task_id,
      'current_status', v_task.status
    );
  END IF;

  -- G2) Sahiplik + taze kiralama ZORUNLU (token G0'da doğrulandı).
  IF v_task.claimed_by IS DISTINCT FROM p_worker_id THEN
    RETURN jsonb_build_object(
      'ignored', 'foreign_claim',
      'task_id', p_task_id
    );
  END IF;
  IF v_task.lease_expires_at IS NULL OR v_task.lease_expires_at <= now() THEN
    RETURN jsonb_build_object(
      'ignored', 'lease_expired',
      'task_id', p_task_id
    );
  END IF;

  -- ---- Aşağıdaki gövde 135 ile birebir aynıdır (korundu) ----
  UPDATE public.admin_bulk_gate_tasks
  SET
    status = p_status,
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = CASE
      WHEN p_status = 'pending' THEN NULL
      ELSE now()
    END,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id;

  -- Zincir: kapı sıradaki adımı bekliyorsa yeni görev açılır.
  IF p_status = 'completed' THEN
    v_next_role := NULL;

    IF v_task.gate_key = 'answer' THEN
      SELECT consensus_status
      INTO v_next_status
      FROM public.ai_answer_verification_runs
      WHERE id = v_task.gate_run_id;

      IF v_next_status = 'waiting_solver_2' THEN
        v_next_role := 'solver_2';
      END IF;
    ELSE
      IF v_task.gate_key = 'curriculum' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_curriculum_fit_runs
        WHERE id = v_task.gate_run_id;
      ELSIF v_task.gate_key = 'quality' THEN
        SELECT status
        INTO v_next_status
        FROM public.ai_question_quality_runs
        WHERE id = v_task.gate_run_id;
      END IF;

      IF v_next_status = 'waiting_reviewer_2' THEN
        v_next_role := 'reviewer_2';
      END IF;
    END IF;

    IF v_next_role IS NOT NULL THEN
      BEGIN
        INSERT INTO public.admin_bulk_gate_tasks (
          bulk_run_id,
          staging_question_id,
          candidate_position,
          gate_key,
          gate_role,
          status,
          gate_run_id,
          content_snapshot
        )
        VALUES (
          v_task.bulk_run_id,
          v_task.staging_question_id,
          v_task.candidate_position,
          v_task.gate_key,
          v_next_role,
          'pending',
          v_task.gate_run_id,
          v_task.content_snapshot
        )
        ON CONFLICT (bulk_run_id, staging_question_id, gate_key, gate_role)
        DO NOTHING;

        v_next_created := FOUND;
      EXCEPTION
        WHEN unique_violation THEN
          -- Başka bir koşumun bekleyen/çalışan görevi aynı (aday,
          -- kapı, rol) çiftini tutuyor; zincir adımı AÇILMAZ
          -- (mükerrer çalışma oluşmaz; görev tamamlandı kalır).
          v_next_created := false;
      END;
    END IF;
  END IF;

  -- Koşu sayaçları (KOŞU bazlı; tek doğruluk kaynağı DB).
  SELECT
    count(*) FILTER (WHERE t.status IN ('pending', 'running')),
    count(*) FILTER (WHERE t.status = 'completed'),
    count(*) FILTER (WHERE t.status = 'failed'),
    count(*) FILTER (WHERE t.status = 'skipped'),
    COALESCE(bool_or(r.stop_requested), false)
  INTO
    v_remaining,
    v_completed,
    v_failed,
    v_skipped,
    v_run_stopped
  FROM public.admin_bulk_gate_tasks t
  JOIN public.admin_bulk_gate_runs r
    ON r.id = t.bulk_run_id
  WHERE t.bulk_run_id = v_task.bulk_run_id;

  -- Koşu sonu: tüm işler bittiğinde BÜTÜN görevler başarısızsa koşu
  -- 'failed' olur (dürüst izlenebilirlik; kısmi başarı 'completed').
  v_run_status := CASE
    WHEN v_run_stopped THEN 'stopped'
    WHEN v_remaining > 0 THEN 'running'
    WHEN v_completed = 0 AND (v_failed > 0) THEN 'failed'
    ELSE 'completed'
  END;

  UPDATE public.admin_bulk_gate_runs
  SET
    status = v_run_status,
    started_at = COALESCE(started_at, now())
  WHERE id = v_task.bulk_run_id;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', p_status,
    'next_task_created', v_next_created,
    'remaining_task_count', v_remaining,
    'completed_task_count', v_completed,
    'failed_task_count', v_failed,
    'skipped_task_count', v_skipped,
    'run_stopped', v_run_stopped,
    'run_status', v_run_status
  );
END;
$$;

REVOKE ALL
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.complete_bulk_gate_task(uuid, text, text, text, text)
  TO service_role;


-- Aynı gerekçe requeue için: canlı 134 (3 arg) + varsa 02B dönemi 4 arg
-- (arg adları farklı) — önce DROP tek kimlik garantiler.
DROP FUNCTION IF EXISTS public.requeue_bulk_gate_task(uuid, text, text);
DROP FUNCTION IF EXISTS public.requeue_bulk_gate_task(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.requeue_bulk_gate_task(
  p_task_id uuid,
  p_worker_id text,
  p_error_code text DEFAULT NULL,
  p_error_message text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_task record;
  v_attempt integer;
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Service role required.';
  END IF;

  -- G0) Zorunlu, boş olmayan sahiplik token'ı (AK-QV-02C).
  IF p_worker_id IS NULL OR btrim(p_worker_id) = '' THEN
    RAISE EXCEPTION 'p_worker_id is required (non-blank).'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_task
  FROM public.admin_bulk_gate_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Bulk task not found.';
  END IF;

  -- G1) Yalnızca 'running' görev geri kuyruklanabilir; tamamlanmış görev
  --     'pending'e döndürülemez.
  IF v_task.status <> 'running' THEN
    RETURN jsonb_build_object(
      'ignored', 'not_running',
      'task_id', p_task_id,
      'current_status', v_task.status
    );
  END IF;

  -- G2) Sahiplik + taze kiralama ZORUNLU (token G0'da doğrulandı).
  IF v_task.claimed_by IS DISTINCT FROM p_worker_id THEN
    RETURN jsonb_build_object(
      'ignored', 'foreign_claim',
      'task_id', p_task_id
    );
  END IF;
  IF v_task.lease_expires_at IS NULL OR v_task.lease_expires_at <= now() THEN
    RETURN jsonb_build_object(
      'ignored', 'lease_expired',
      'task_id', p_task_id
    );
  END IF;

  UPDATE public.admin_bulk_gate_tasks
  SET
    status = 'pending',
    error_code = p_error_code,
    error_message = p_error_message,
    completed_at = NULL,
    claimed_by = NULL,
    lease_expires_at = NULL
  WHERE id = p_task_id
  RETURNING attempt_count INTO v_attempt;

  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'status', 'pending',
    'attempt_count', v_attempt
  );
END;
$$;

REVOKE ALL
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE
  ON FUNCTION public.requeue_bulk_gate_task(uuid, text, text, text)
  TO service_role;

COMMIT;
