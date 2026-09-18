-- ============================================================
-- 110_faz15_training_gating.sql
-- Altin Kalemler - FAZ 15A: Kontrollü Antrenman Erişimi
--   ve Tek Soru Akışı
--
-- AMAÇ:
--   Öğrenci yalnız (a) takvimde açılmış (start_week gelen, end_week
--   KAPATMAYAN), (b) öğretmen "konu işlendi" onayı almış ve
--   (c) bağlı önkoşulları tamamlanmış kapsamdan soru çözer.
--   Sorular BİRER BİRER sunulur; kuyruk sunucu-otoriterdir;
--   yenileme/geri yeni soru tüketmez ve soru atlatamaz.
--
-- KAPSAM DIŞI (bilinçli ürün kararı, kullanıcı kısıtı):
--   - 300/400 haftalık toplam deneme limitleri ve kapanış sorusu
--   - yapısal özgünlük denetimi ve toplu batch audit-orchestrator
--   - PDF/OCR/AI üretim ve video sağlayıcı değişikliği
--   - hosted / remote DB erişimi; commit-push YOK (yerel uygulama)
--
-- SÖZLEŞME:
--   1) Mevcut RPC'ler (select_training_questions,
--      select_targeted_review_questions, get_attempt_feedback vb.)
--      TAMAMEN korunur; bu migration YALNIZCA yeni yapı ekler ve
--      CREATE OR REPLACE ile hiçbir mevcut imzayı değiştirmez.
--   2) Fail-closed: öğretmen onayı veya önkoşul yoksa soru
--      metni/seçenekleri istemciye ASLA dönmez; yalnız kilit nedeni
--      döner. Kilit nedenleri ayrıştırılır:
--      takvim_gelmedi | konu_islenmedi | onkosul_eksik |
--      gecersiz_kapsam | stok_yok | haftalik_kota_doldu |
--      gunluk_kota_doldu
--   3) Kimlik parametre olarak alınmaz; tüm RPC'ler auth.uid()'den
--      türetir. Öğrenci istemcisi ne tablolara (no write policy) ne
--      de admin RPC'lerine (yetki kapısı) yazabilir.
--   4) Önkoşul tamamlama kuralı (dökümante):
--      requirement_level='required' + review_status='approved' önkoşul,
--      öğrencinin önkoşul konusunda onaylı eşleştirmeli en az 1 doğru
--      TRAINING denemesi varsa tamamlanmış sayılır. Kazanım kendi
--      topic_id üzerinden önkoşul kurallarına çapılır.
--   5) Tek transaction: baştan hata migration'in tamamını geri alır.
-- ============================================================

begin;

-- ============================================================
-- 1. TABLOLAR
-- ============================================================

-- 1a. KONU İŞLENDİ ONAYI (öğretmen/öncü yetkili admin)
create table if not exists public.curriculum_teaching_approvals (
  id uuid primary key default gen_random_uuid(),
  academic_year text not null,
  schedule_item_id uuid not null
    references public.curriculum_schedule_items(id)
    on delete cascade,
  status text not null default 'approved'
    check (status in ('approved', 'rejected')),
  approved_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint curriculum_teaching_approvals_uniq
    unique (academic_year, schedule_item_id)
);

comment on table public.curriculum_teaching_approvals is
  '"Konu islendi" ogretmen onayi. Akademik yil + schedule item bazinda;
takvim haftasinin gelmesi otomatik onay VERMEZ (fail-closed).';

create index if not exists idx_curriculum_teaching_approvals_lookup
  on public.curriculum_teaching_approvals(academic_year, schedule_item_id);

drop trigger if exists trigger_curriculum_teaching_approvals_set_updated_at
  on public.curriculum_teaching_approvals;
create trigger trigger_curriculum_teaching_approvals_set_updated_at
  before update on public.curriculum_teaching_approvals
  for each row execute function public.set_updated_at();

alter table public.curriculum_teaching_approvals enable row level security;

drop policy if exists curriculum_teaching_approvals_read_active
  on public.curriculum_teaching_approvals;
create policy curriculum_teaching_approvals_read_active
  on public.curriculum_teaching_approvals
  for select to authenticated
  using (status = 'approved');

revoke all on table public.curriculum_teaching_approvals
  from anon, authenticated;
grant select on public.curriculum_teaching_approvals
  to authenticated;
grant select, insert, update, delete
  on public.curriculum_teaching_approvals
  to service_role;

-- 1b. TEK SORU AKIŞI KUYRUĞU (sunucu-otoriter)
create table if not exists public.student_training_queues (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  topic_id uuid references public.topics(id) on delete set null,
  outcome_id uuid references public.curriculum_outcomes(id) on delete set null,
  question_order integer not null check (question_order >= 0),
  status text not null default 'queued'
    check (status in ('queued', 'answered')),
  created_at timestamptz not null default now(),
  constraint student_training_queues_uniq
    unique (user_id, subject_id, question_id)
);

comment on table public.student_training_queues is
  '"Tek soru akisi" kuyrugu. Secim aninda exposure + haftalik/gunluk kota
tuketimi yapilir (104 ile ayni anlam), secilen sorular buraya yazilir;
yenileme/geri YENIDEN secim YAPMAZ ve soru atlatamaz. Yazim yalniz
sunucu RPC fonksiyonlari (security definer) tarafindan yapilir.';

create index if not exists idx_student_training_queues_active
  on public.student_training_queues(user_id, subject_id, status, question_order);

alter table public.student_training_queues enable row level security;

drop policy if exists student_reads_own_training_queues
  on public.student_training_queues;
create policy student_reads_own_training_queues
  on public.student_training_queues
  for select to authenticated
  using (user_id = auth.uid());

revoke all on table public.student_training_queues
  from anon, authenticated;
grant select on public.student_training_queues
  to authenticated;
grant select, insert, update, delete
  on public.student_training_queues
  to service_role;

-- ============================================================
-- 2. ÖZEL YARDIMCILAR
-- ============================================================

-- 2a. Kilit payload üretici (kilit kodu + Türkçe-ASCII mesaj +
--     haftalık/günlük anlık görüntü).
create or replace function public._faz15_lock_payload(
  p_kind text,
  p_year text,
  p_week integer,
  p_subject_id uuid,
  p_daily_left integer,
  p_weekly_left integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message text;
begin
  v_message := case p_kind
    when 'takvim_gelmedi' then
      'Bu derste takvimde henuz islenen konu acilmadi; sorular kilitli.'
    when 'konu_islenmedi' then
      'Konu icin ogretmen "islendi" onayi bekleniyor; sorular kilitli.'
    when 'onkosul_eksik' then
      'Onkosul konular tamamlanmadigi icin bu kapsam kilitli.'
    when 'gecersiz_kapsam' then
      'Secili konu/kazanim bu donemde calisilamaz.'
    when 'stok_yok' then
      'Bu kapsam icin su anda cozulebilir soru bulunamadi.'
    when 'haftalik_kota_doldu' then
      'Bu ders icin haftalik yeni soru hakkin doldu; tekrar sorularla devam edebilirsin.'
    when 'gunluk_kota_doldu' then
      'Gunluk 500 soru hakkin doldu; yarin tekrar deneyebilirsin.'
    else
      'Soru akisi gecici olarak kilitli.'
  end;

  return jsonb_build_object(
    'lock', jsonb_build_object('kind', p_kind, 'message', v_message),
    'weekly', jsonb_build_object(
      'academic_year', p_year,
      'week', p_week,
      'subject_id', p_subject_id,
      'new_questions_used', greatest(500 - greatest(p_weekly_left, 0), 0),
      'limit', 500
    ),
    'daily_remaining', greatest(p_daily_left, 0)
  );
end;
$$;

-- 2b. Kuyruk ilerleme sayıları (yalnız okuma; kilit yok).
create or replace function public._faz15_queue_progress(
  p_user uuid,
  p_subject uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tot integer;
  v_ans integer;
  v_rem integer;
begin
  select count(*),
         count(*) filter (where status = 'answered'),
         count(*) filter (where status = 'queued')
    into v_tot, v_ans, v_rem
    from public.student_training_queues q
   where q.user_id = p_user
     and q.subject_id = p_subject;

  return jsonb_build_object(
    'queue_total', coalesce(v_tot, 0),
    'answered_total', coalesce(v_ans, 0),
    'queue_remaining', coalesce(v_rem, 0)
  );
end;
$$;

-- 2c. Günlük kalan (yalnız okuma; kilit yok).
create or replace function public._faz15_daily_remaining(
  p_user uuid,
  p_day date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer;
begin
  select 500 - coalesce((
    select c.questions_used
      from public.student_daily_question_counters c
     where c.user_id = p_user and c.quota_day = p_day
  ), 0) into v_left;
  return greatest(v_left, 0);
end;
$$;

-- 2d. Haftalık kalan (yalnız okuma; kilit yok).
create or replace function public._faz15_weekly_remaining(
  p_user uuid,
  p_year text,
  p_week integer,
  p_subject uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_left integer;
begin
  select 500 - coalesce((
    select c.new_questions_used
      from public.student_weekly_counters c
     where c.user_id = p_user
       and c.academic_year = p_year
       and c.week = p_week
       and c.subject_id = p_subject
  ), 0) into v_left;
  return greatest(v_left, 0);
end;
$$;

-- ============================================================
-- 3. _FAZ15_ELIGIBLE_SCOPE
--
-- Öğrencinin KENDİ sınıf/dönem kapsamını adım adım hesaplar ve
-- kilit nedenlerini ayrıştırır:
--   1) takvim_gelmedi  : start_week <= v_week olan hiç kapsam yok
--   2) konu_islenmedi  : takvimde açılmış ama hiçbiri öğretmen onaylı değil
--   3) onkosul_eksik   : onaylı ama önkoşulları tamamlanmamış
--   4) gecersiz_kapsam : verilen konu/kazanım filtresi uygun değil
-- Kilit YOKSA eligible topic/outcome kümeleri döner.
-- ============================================================

create or replace function public._faz15_eligible_scope(
  p_subject_id uuid,
  p_topic_id uuid default null,
  p_outcome_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user           uuid;
  v_grade          smallint;
  v_profile        uuid;
  v_version        uuid;
  v_ctx_year       text;
  v_year           text;
  v_week           integer;
  v_topics         uuid[];
  v_outcomes       uuid[];
  v_app_topics     uuid[];
  v_app_outcomes   uuid[];
  v_elig_topics    uuid[];
  v_elig_outcomes  uuid[];
  v_lock_kind      text;
  v_daily_left     integer;
  v_weekly_left    integer;
  v_need_qt        integer;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  v_daily_left := public._faz15_daily_remaining(
    v_user, public._faz9_local_day(now())
  );
  v_weekly_left := public._faz15_weekly_remaining(
    v_user, v_year, v_week, p_subject_id
  );

  -- (a) Takvimde açılmış kapsam (start_week INCLUSIVE; end_week antrenmanı KAPATMAZ).
  select array_agg(distinct t order by t) into v_topics
    from (
      select si.topic_id as t
        from public.curriculum_schedule_items si
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.start_week <= v_week
         and si.topic_id is not null
      union
      select st.topic_id
        from public.curriculum_schedule_items si
        join public.subtopics st on st.id = si.subtopic_id
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.start_week <= v_week
         and si.subtopic_id is not null
    ) rt;

  select array_agg(distinct t order by t) into v_outcomes
    from (
      select si.outcome_id as t
        from public.curriculum_schedule_items si
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.start_week <= v_week
         and si.outcome_id is not null
    ) ro;

  if coalesce(array_length(v_topics, 1), 0) = 0
     and coalesce(array_length(v_outcomes, 1), 0) = 0 then
    v_lock_kind := 'takvim_gelmedi';
    return public._faz15_lock_payload(
      v_lock_kind, v_year, v_week, p_subject_id,
      v_daily_left, v_weekly_left
    );
  end if;

  -- (b) "Konu işlendi" onayı (academic_year eşleşmeli; approved yalnız).
  select array_agg(distinct t order by t) into v_app_topics
    from (
      select si.topic_id as t
        from public.curriculum_schedule_items si
        join public.curriculum_teaching_approvals a
          on a.schedule_item_id = si.id
         and a.academic_year = v_year
         and a.status = 'approved'
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.topic_id is not null
      union
      select st.topic_id
        from public.curriculum_schedule_items si
        join public.curriculum_teaching_approvals a
          on a.schedule_item_id = si.id
         and a.academic_year = v_year
         and a.status = 'approved'
        join public.subtopics st on st.id = si.subtopic_id
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.subtopic_id is not null
    ) ra;

  select array_agg(distinct t order by t) into v_app_outcomes
    from (
      select si.outcome_id as t
        from public.curriculum_schedule_items si
        join public.curriculum_teaching_approvals a
          on a.schedule_item_id = si.id
         and a.academic_year = v_year
         and a.status = 'approved'
       where si.schedule_profile_id = v_profile
         and si.grade_level = v_grade
         and si.subject_id = p_subject_id
         and si.is_active = true
         and si.outcome_id is not null
      union
      select o.id
        from public.curriculum_outcomes o
       where o.topic_id = any(coalesce(v_app_topics, '{}'))
         and o.subject_id = p_subject_id
         and o.grade_level = v_grade
         and o.is_active = true
    ) rb;

  if coalesce(array_length(v_app_topics, 1), 0) = 0
     and coalesce(array_length(v_app_outcomes, 1), 0) = 0 then
    v_lock_kind := 'konu_islenmedi';
    return public._faz15_lock_payload(
      v_lock_kind, v_year, v_week, p_subject_id,
      v_daily_left, v_weekly_left
    );
  end if;

  -- (c) Önkoşul kapısı: required + approved önkoşullar tamamlanmalı.
  --     Tamamlama: önkoşul konusunda onaylı eşleştirmeli en az 1 doğru
  --     TRAINING denemesi.
  v_elig_topics := array(
    select u
      from unnest(coalesce(v_app_topics, '{}')) u
     where not exists (
       select 1
         from public.curriculum_prerequisites pr
        where pr.curriculum_version_id = v_version
          and pr.requirement_level = 'required'
          and pr.review_status = 'approved'
          and (pr.target_topic_id = u
               or pr.target_subtopic_id in (
                 select s.id from public.subtopics s where s.topic_id = u
               ))
          and coalesce(
                pr.prerequisite_topic_id,
                (select s2.topic_id
                   from public.subtopics s2
                  where s2.id = pr.prerequisite_subtopic_id)
              ) is not null
          and not exists (
            select 1
              from public.student_question_attempts a
              join public.question_curriculum_mappings cm
                on cm.question_id = a.question_id
               and cm.curriculum_version_id = v_version
               and cm.review_status = 'approved'
               and cm.topic_id = coalesce(
                     pr.prerequisite_topic_id,
                     (select s2.topic_id
                        from public.subtopics s2
                       where s2.id = pr.prerequisite_subtopic_id)
                   )
             where a.user_id = v_user
               and a.attempt_context = 'training'
               and a.result = 'correct'
          )
     )
  );

  v_elig_outcomes := array(
    select u
      from unnest(coalesce(v_app_outcomes, '{}')) u
      join public.curriculum_outcomes co on co.id = u
     where not exists (
       select 1
         from public.curriculum_prerequisites pr
        where pr.curriculum_version_id = v_version
          and pr.requirement_level = 'required'
          and pr.review_status = 'approved'
          and co.topic_id is not null
          and (pr.target_topic_id = co.topic_id
               or pr.target_subtopic_id in (
                 select s.id from public.subtopics s where s.topic_id = co.topic_id
               ))
          and coalesce(
                pr.prerequisite_topic_id,
                (select s2.topic_id
                   from public.subtopics s2
                  where s2.id = pr.prerequisite_subtopic_id)
              ) is not null
          and not exists (
            select 1
              from public.student_question_attempts a
              join public.question_curriculum_mappings cm
                on cm.question_id = a.question_id
               and cm.curriculum_version_id = v_version
               and cm.review_status = 'approved'
               and cm.topic_id = coalesce(
                     pr.prerequisite_topic_id,
                     (select s2.topic_id
                        from public.subtopics s2
                       where s2.id = pr.prerequisite_subtopic_id)
                   )
             where a.user_id = v_user
               and a.attempt_context = 'training'
               and a.result = 'correct'
          )
     )
  );

  -- (d) Konu/kazanım filtresi: öğrencinin KENDİ eligible kapsamında
  --     doğrulanır; dışı fail-closed karmaşık neden ile döner.
  if p_topic_id is not null then
    if not (p_topic_id = any(coalesce(v_elig_topics, '{}'))) then
      if not (p_topic_id = any(coalesce(v_topics, '{}'))) then
        v_lock_kind := 'takvim_gelmedi';
      elsif not (p_topic_id = any(coalesce(v_app_topics, '{}'))) then
        v_lock_kind := 'konu_islenmedi';
      else
        v_lock_kind := 'onkosul_eksik';
      end if;
      return public._faz15_lock_payload(
        v_lock_kind, v_year, v_week, p_subject_id,
        v_daily_left, v_weekly_left
      );
    end if;
    v_elig_topics := array[p_topic_id];
    v_elig_outcomes := '{}';
  elsif p_outcome_id is not null then
    if not (p_outcome_id = any(coalesce(v_elig_outcomes, '{}'))) then
      if not (p_outcome_id = any(coalesce(v_outcomes, '{}'))) then
        v_lock_kind := 'takvim_gelmedi';
      elsif not (p_outcome_id = any(coalesce(v_app_outcomes, '{}'))) then
        v_lock_kind := 'konu_islenmedi';
      else
        v_lock_kind := 'onkosul_eksik';
      end if;
      return public._faz15_lock_payload(
        v_lock_kind, v_year, v_week, p_subject_id,
        v_daily_left, v_weekly_left
      );
    end if;
    v_elig_outcomes := array[p_outcome_id];
    v_elig_topics := '{}';
  end if;

  if coalesce(array_length(v_elig_topics, 1), 0) = 0
     and coalesce(array_length(v_elig_outcomes, 1), 0) = 0 then
    v_lock_kind := 'onkosul_eksik';
    return public._faz15_lock_payload(
      v_lock_kind, v_year, v_week, p_subject_id,
      v_daily_left, v_weekly_left
    );
  end if;

  -- Kilit YOK (ready): 'lock' anahtari BILEREK EKLENMEZ. Eklenen JSON
  -- null, `->'lock' is not null` kontrolune SQL NULL gibi davranmaz
  -- (jsonb null <> SQL NULL); aksi halde calisilabilir donem icin dahi
  -- parent fonksiyonlar yanlislikla locked dalina duser.
  return jsonb_build_object(
    'schedule_reached', true,
    'approved_nonempty', true,
    'topics', to_jsonb(coalesce(v_elig_topics, '{}')),
    'outcomes', to_jsonb(coalesce(v_elig_outcomes, '{}')),
    'academic_year', v_year,
    'week', v_week,
    'weekly_remaining', v_weekly_left,
    'daily_remaining', v_daily_left
  );
end;
$$;

revoke execute
  on function public._faz15_eligible_scope(uuid, uuid, uuid)
  from public, anon, authenticated;

revoke execute
  on function public._faz15_lock_payload(text, text, integer, uuid, integer, integer)
  from public, anon, authenticated;

revoke execute
  on function public._faz15_queue_progress(uuid, uuid)
  from public, anon, authenticated;

revoke execute
  on function public._faz15_daily_remaining(uuid, date)
  from public, anon, authenticated;

revoke execute
  on function public._faz15_weekly_remaining(uuid, text, integer, uuid)
  from public, anon, authenticated;

-- ============================================================
-- 4. ANTRENMAN SORU AKIŞI RPC'LERİ (tek soru, sunucu-otoriter)
-- ============================================================

-- 4a. DURUM: aktif kuyruk varsa GÜNCEL soruyu verir (yenileme/geri
--     güvenli); kuyruk yoksa eligible/kilitli durumunu hesaplar.
--     HİÇBİR yazma / tüketim / rate-limit uygulamaz.
create or replace function public.get_training_session_state(
  p_subject_id uuid,
  p_topic_id uuid default null,
  p_outcome_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user  uuid;
  v_qid   uuid;
  v_scope jsonb;
  v_q     jsonb;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  select q.question_id into v_qid
    from public.student_training_queues q
   where q.user_id = v_user
     and q.subject_id = p_subject_id
     and q.status = 'queued'
   order by q.question_order
   limit 1;

  if v_qid is not null then
    select public._faz2_sanitize_question_payload(to_jsonb(qn))
      into v_q
      from public.questions qn
     where qn.id = v_qid;

    return jsonb_build_object(
      'state', 'question',
      'question', v_q,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'lock', null
    );
  end if;

  v_scope := public._faz15_eligible_scope(
    p_subject_id, p_topic_id, p_outcome_id
  );

  if v_scope->'lock' is not null then
    return jsonb_build_object(
      'state', 'locked',
      'question', null,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'weekly', v_scope->'weekly',
      'lock', v_scope->'lock'
    );
  end if;

  return jsonb_build_object(
    'state', 'ready',
    'question', null,
    'progress', public._faz15_queue_progress(v_user, p_subject_id),
    'topics', v_scope->'topics',
    'outcomes', v_scope->'outcomes',
    'weekly', v_scope->'weekly',
    'lock', null
  );
end;
$$;

-- 4b. BAŞLAT / SÜRDÜR:
--   - Aktif kuyruk varsa (force_new=false) GÜNCEL soruyu döner;
--     YENİDEN seçim ve tüketim YOK (refresh/çift çağrı güvenli).
--   - Kuyruk yoksa: kilit kontrolü, rate-limit (training_select),
--     günlük+haftalık kota kilidi, eligible kapsamdan v_limit seçim
--     (yeni önce, tekrar sonra), exposure + sayaç tüketimi (104 ile
--     aynı anlam), kuyruğa yazma, İLK soru döner.
--   - force_new=true: mevcut kuyruk silinir, yeni oturum açar.
create or replace function public.start_training_session(
  p_subject_id uuid,
  p_limit integer default 10,
  p_topic_id uuid default null,
  p_outcome_id uuid default null,
  p_force_new boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user          uuid;
  v_limit         integer;
  v_grade         smallint;
  v_profile       uuid;
  v_version       uuid;
  v_ctx_year      text;
  v_year          text;
  v_week          integer;
  v_day           date;
  v_daily_left    integer;
  v_remaining     integer;
  v_take          integer;
  v_need          integer;
  v_delta         integer;
  v_used          integer;
  v_scope         jsonb;
  v_scope_lock    jsonb;
  v_elig_topics   uuid[];
  v_elig_outcomes uuid[];
  v_new_ids       uuid[];
  v_repeat_ids    uuid[];
  v_all_ids       uuid[];
  v_qid           uuid;
  v_q             jsonb;
  v_count         integer;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  v_limit := coalesce(p_limit, 10);
  if v_limit < 1 or v_limit > 50 then
    raise exception 'p_limit 1..50 araliginda olmalidir.'
      using errcode = '22023';
  end if;

  if p_topic_id is not null and p_outcome_id is not null then
    raise exception 'Yalnizca konu veya kazanim filtresinden biri kullanilabilir.'
      using errcode = 'P0001';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  -- Aktif kuyruk: GÜNCEL soruyu dön (yeni seçim/tüketim YOK).
  v_qid := null;
  select q.question_id into v_qid
    from public.student_training_queues q
   where q.user_id = v_user
     and q.subject_id = p_subject_id
     and q.status = 'queued'
   order by q.question_order
   limit 1;

  if v_qid is not null and not p_force_new then
    select public._faz2_sanitize_question_payload(to_jsonb(qn))
      into v_q
      from public.questions qn
     where qn.id = v_qid;

    return jsonb_build_object(
      'state', 'question',
      'question', v_q,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'lock', null
    );
  end if;

  -- Kapsam kilidi (fail-closed; yazma/tüketim ÖNCESİ).
  v_scope := public._faz15_eligible_scope(
    p_subject_id, p_topic_id, p_outcome_id
  );
  v_scope_lock := v_scope->'lock';
  if v_scope_lock is not null then
    if p_force_new then
      delete from public.student_training_queues q
       where q.user_id = v_user
         and q.subject_id = p_subject_id;
    end if;
    return jsonb_build_object(
      'state', 'locked',
      'question', null,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'weekly', v_scope->'weekly',
      'lock', v_scope_lock
    );
  end if;

  -- Faz 4 sabit-pencere rate limit; seçim işinden ÖNCE.
  perform public._faz4_consume_rate_limit('training_select', 90, 3600);

  -- Günlük kota kilidi (Europe/Istanbul).
  v_day := public._faz9_local_day(now());
  v_daily_left := public._faz9_lock_daily_counter(v_user, v_day);
  v_remaining := public._faz2_lock_weekly_counter(
    v_user, v_year, v_week, p_subject_id
  );

  if v_daily_left <= 0 then
    return jsonb_build_object(
      'state', 'locked',
      'question', null,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'weekly', v_scope->'weekly',
      'lock', jsonb_build_object(
        'kind', 'gunluk_kota_doldu',
        'message', 'Gunluk 500 soru hakkin doldu; yarin tekrar deneyebilirsin.'
      )
    );
  end if;

  v_take := least(v_limit, greatest(v_remaining, 0), v_daily_left);

  v_elig_topics := coalesce((
    select array(select jsonb_array_elements_text(v_scope->'topics')::uuid)
  ), '{}');
  v_elig_outcomes := coalesce((
    select array(select jsonb_array_elements_text(v_scope->'outcomes')::uuid)
  ), '{}');

  -- Aday seçimi: eligible kapsam + aktif + approved + practice üyeliği.
  v_new_ids := coalesce(array(
    select c.qid
      from (
        select q.id as qid,
               exists(
                 select 1 from public.student_question_exposures e
                  where e.user_id = v_user
                    and e.question_id = q.id
               ) as seen
          from public.questions q
         where q.subject_id = p_subject_id
           and q.grade_level = v_grade
           and q.is_active = true
           and q.approval_status = 'approved'
           and exists (
                 select 1
                   from public.question_vault_memberships m
                   join public.question_vaults v
                     on v.id = m.vault_id
                  where m.question_id = q.id
                    and m.membership_status = 'active'
                    and m.practice_eligible = true
                    and v.is_active = true
                    and v.vault_type not in ('competition', 'one_v_one')
              )
           and (
             exists (
               select 1
                 from public.question_curriculum_mappings cm
                where cm.question_id = q.id
                  and cm.curriculum_version_id = v_version
                  and cm.topic_id = any(v_elig_topics)
                  and cm.review_status = 'approved'
             )
             or exists (
               select 1
                 from public.question_outcome_mappings om
                where om.question_id = q.id
                  and om.outcome_id = any(v_elig_outcomes)
                  and om.review_status = 'approved'
             )
           )
      ) c
     where not c.seen
     order by c.qid
     limit v_take
  ), '{}');

  v_need := v_limit - coalesce(array_length(v_new_ids, 1), 0);
  if v_need > 0 then
    v_repeat_ids := coalesce(array(
      select c.qid
        from (
          select q.id as qid,
                 exists(
                   select 1 from public.student_question_exposures e
                    where e.user_id = v_user
                      and e.question_id = q.id
                 ) as seen
            from public.questions q
           where q.subject_id = p_subject_id
             and q.grade_level = v_grade
             and q.is_active = true
             and q.approval_status = 'approved'
             and exists (
                   select 1
                     from public.question_vault_memberships m
                     join public.question_vaults v
                       on v.id = m.vault_id
                    where m.question_id = q.id
                      and m.membership_status = 'active'
                      and m.practice_eligible = true
                      and v.is_active = true
                      and v.vault_type not in ('competition', 'one_v_one')
                )
             and (
               exists (
                 select 1
                   from public.question_curriculum_mappings cm
                  where cm.question_id = q.id
                    and cm.curriculum_version_id = v_version
                    and cm.topic_id = any(v_elig_topics)
                    and cm.review_status = 'approved'
               )
               or exists (
                 select 1
                   from public.question_outcome_mappings om
                  where om.question_id = q.id
                    and om.outcome_id = any(v_elig_outcomes)
                    and om.review_status = 'approved'
               )
             )
        ) c
       where c.seen
       order by c.qid
       limit v_need
    ), '{}');
  else
    v_repeat_ids := '{}';
  end if;

  v_all_ids := array(
    select u from unnest(v_new_ids) u
    union all
    select u from unnest(v_repeat_ids) u
  );

  if coalesce(array_length(v_all_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'state', 'locked',
      'question', null,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'weekly', v_scope->'weekly',
      'lock', jsonb_build_object(
        'kind', case
                  when v_remaining <= 0 and v_daily_left > 0
                    then 'haftalik_kota_doldu'
                  else 'stok_yok'
                end,
        'message', case
                    when v_remaining <= 0 and v_daily_left > 0
                      then 'Bu ders icin haftalik yeni soru hakkin doldu; tekrar sorularla devam edebilirsin.'
                    else 'Bu kapsam icin su anda cozulebilir soru bulunamadi.'
                  end
      )
    );
  end if;

  -- SHOW-TIME atomik yazım: exposure + sayaç tüketimi (104 deseni).
  delete from public.student_training_queues q
   where q.user_id = v_user
     and q.subject_id = p_subject_id;

  v_delta := 0;
  if coalesce(array_length(v_new_ids, 1), 0) > 0 then
    with ins as (
      insert into public.student_question_exposures
        (user_id, question_id, attempt_context)
      select v_user, u, 'training'
        from unnest(v_new_ids) u
      on conflict do nothing
      returning question_id
    )
    select count(*) into v_delta from ins;
  end if;

  if v_delta > 0 then
    perform public._faz2_consume_weekly_capacity(
      v_user, v_year, v_week, p_subject_id, v_delta::integer
    );
  end if;

  perform public._faz9_consume_daily_quota(
    v_user, v_day, coalesce(array_length(v_all_ids, 1), 0)::integer
  );

  insert into public.student_training_queues
    (user_id, subject_id, question_id, question_order, status)
  select v_user, p_subject_id, u, ord, 'queued'
    from unnest(v_all_ids) with ordinality as x(u, ord);

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = v_user
     and c.academic_year = v_year
     and c.week = v_week
     and c.subject_id = p_subject_id;

  select q2.question_id into v_qid
    from public.student_training_queues q2
   where q2.user_id = v_user
     and q2.subject_id = p_subject_id
   order by q2.question_order
   limit 1;

  select public._faz2_sanitize_question_payload(to_jsonb(qn))
    into v_q
    from public.questions qn
   where qn.id = v_qid;

  return jsonb_build_object(
    'state', 'question',
    'question', v_q,
    'progress', public._faz15_queue_progress(v_user, p_subject_id),
    'new_count', coalesce(array_length(v_new_ids, 1), 0),
    'repeat_count', coalesce(array_length(v_repeat_ids, 1), 0),
    'daily', jsonb_build_object(
      'day', v_day,
      'questions_used', (500 - v_daily_left)
        + coalesce(array_length(v_all_ids, 1), 0),
      'limit', 500,
      'remaining', v_daily_left - coalesce(array_length(v_all_ids, 1), 0)
    ),
    'weekly', jsonb_build_object(
      'academic_year', v_year,
      'week', v_week,
      'subject_id', p_subject_id,
      'new_questions_used', coalesce(v_used, 0),
      'limit', 500
    ),
    'lock', null
  );
end;
$$;

-- 4c. SONRAKİ SORU: ilk 'queued' satır p_question_id ile eşleşmezse
--     FAIL-CLOSED (soru atlatılamaz); eşleşirse answered işaretlenir
--     ve bir sonraki kuyruk sorusu döner (yeni tüketim YOK).
create or replace function public.advance_training_session(
  p_subject_id uuid,
  p_question_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user    uuid;
  v_cur     uuid;
  v_ord     integer;
  v_next    uuid;
  v_q       jsonb;
  v_answers integer;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  select q.question_id, q.question_order into v_cur, v_ord
    from public.student_training_queues q
   where q.user_id = v_user
     and q.subject_id = p_subject_id
     and q.status = 'queued'
   order by q.question_order
   limit 1;

  if v_cur is null then
    select count(*) into v_answers
      from public.student_training_queues q
     where q.user_id = v_user
       and q.subject_id = p_subject_id;
    if coalesce(v_answers, 0) = 0 then
      raise exception 'Aktif soru kuyrugu bulunamadi; oturum baslatilmadi.'
        using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'state', 'completed',
      'question', null,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'lock', null
    );
  end if;

  if v_cur <> p_question_id then
    raise exception 'Kuyruk sirasi bozuldu; sayfayi yenileyin.'
      using errcode = 'P0001';
  end if;

  update public.student_training_queues
     set status = 'answered'
   where user_id = v_user
     and subject_id = p_subject_id
     and question_id = v_cur;

  select q.question_id into v_next
    from public.student_training_queues q
   where q.user_id = v_user
     and q.subject_id = p_subject_id
     and q.status = 'queued'
   order by q.question_order
   limit 1;

  if v_next is not null then
    select public._faz2_sanitize_question_payload(to_jsonb(qn))
      into v_q
      from public.questions qn
     where qn.id = v_next;

    return jsonb_build_object(
      'state', 'question',
      'question', v_q,
      'progress', public._faz15_queue_progress(v_user, p_subject_id),
      'lock', null
    );
  end if;

  return jsonb_build_object(
    'state', 'completed',
    'question', null,
    'progress', public._faz15_queue_progress(v_user, p_subject_id),
    'lock', null
  );
end;
$$;

-- ============================================================
-- 5. HEDEFLİ TEKRAR KAPISI
--    select_targeted_review_questions (104) AYNEN korunur; bu gated
--    varyant onun tüm davranışını (hata havuzu önceliği, cooldown,
--    yeni soru doldurma, kota tüketimi, deterministik sıra) korur ve
--    yalnızca öncesine önkoşul + "konu işlendi" kapısı ekler.
-- ============================================================

create or replace function public.select_gated_targeted_review_questions(
  p_subject_id uuid,
  p_outcome_id uuid,
  p_limit integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user       uuid;
  v_limit      integer;
  v_grade      smallint;
  v_profile    uuid;
  v_version    uuid;
  v_ctx_year   text;
  v_year       text;
  v_week       integer;
  v_today      date;
  v_day        date;
  v_daily_left integer;
  v_scope      jsonb;
  v_scope_lock jsonb;
  v_remaining  integer;
  v_wrong_ids  uuid[];
  v_new_ids    uuid[];
  v_all_ids    uuid[];
  v_need       integer;
  v_delta      integer;
  v_used       integer;
  v_payload    jsonb;
  r_row        record;
begin
  v_user := auth.uid();
  if v_user is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  perform public._faz4_consume_rate_limit('targeted_review_select', 30, 3600);

  if p_subject_id is null or p_outcome_id is null then
    raise exception 'Ders ve kazanim zorunludur.'
      using errcode = '22004';
  end if;

  v_limit := coalesce(p_limit, 5);
  if v_limit < 1 or v_limit > 10 then
    raise exception 'p_limit 1..10 araliginda olmalidir.'
      using errcode = '22023';
  end if;

  select * into v_grade, v_profile, v_version, v_ctx_year
    from public._faz2_student_context(v_user);
  if v_grade is null or v_profile is null or v_version is null then
    raise exception 'Ogrenci baglami cozulemedi (profil/mufredat).'
      using errcode = 'P0001';
  end if;

  select * into v_year, v_week from public._faz2_require_period();

  v_today := (current_timestamp at time zone 'utc')::date;
  v_day := public._faz9_local_day(now());
  v_daily_left := public._faz15_daily_remaining(v_user, v_day);

  -- ------------------------------------------------------------------
  -- FAZ 15A KAPISI: hedef kazanım, öğrencinin KENDİ takvim-açılmış +
  -- işlendi-onaylı + önkoşul-tamamlanmış kapsamında olmalı. Değilse
  -- kilit nedeni döner (soru verisi asla dönmez).
  -- ------------------------------------------------------------------
  v_scope := public._faz15_eligible_scope(
    p_subject_id, null, p_outcome_id
  );
  v_scope_lock := v_scope->'lock';
  if v_scope_lock is not null then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', v_scope_lock->>'kind',
      'lock', v_scope_lock,
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500 - v_daily_left,
        'limit', 500,
        'remaining', v_daily_left
      ),
      'weekly', v_scope->'weekly'
    );
  end if;

  v_daily_left := public._faz9_lock_daily_counter(v_user, v_day);
  if v_daily_left <= 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', 'gunluk_kota_doldu',
      'lock', jsonb_build_object(
        'kind', 'gunluk_kota_doldu',
        'message', 'Gunluk 500 soru hakkin doldu; yarin tekrar deneyebilirsin.'
      ),
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500,
        'limit', 500,
        'remaining', 0
      ),
      'weekly', v_scope->'weekly'
    );
  end if;

  v_limit := least(v_limit, v_daily_left);

  -- Hata havuzu (öğrenciye özgü; cooldown 1 UTC günü; deterministik).
  v_wrong_ids := coalesce(array(
    select x.question_id
      from (
        select a.question_id,
               (array_agg(a.result
                          order by a.answered_at desc, a.id))[1]
                 as last_result,
               max(a.answered_at) as last_answered_at
          from public.student_question_attempts a
          join public.question_outcome_mappings om
            on om.question_id = a.question_id
           and om.outcome_id = p_outcome_id
           and om.review_status = 'approved'
          join public.questions q
            on q.id = a.question_id
           and q.is_active = true
           and q.approval_status = 'approved'
           and q.subject_id = p_subject_id
           and q.grade_level = v_grade
         where a.user_id = v_user
           and a.attempt_context = 'training'
         group by a.question_id
      ) x
     where x.last_result <> 'correct'
       and (x.last_answered_at at time zone 'utc')::date < v_today
     order by x.question_id
     limit v_limit
  ), '{}');

  if coalesce(array_length(v_wrong_ids, 1), 0) = 0 then
    return jsonb_build_object(
      'questions', '[]'::jsonb,
      'session_kind', 'targeted_review',
      'outcome_id', p_outcome_id,
      'wrong_review_count', 0,
      'new_count', 0,
      'reason', 'tekrar_gerekmiyor',
      'lock', null,
      'daily', jsonb_build_object(
        'day', v_day,
        'questions_used', 500 - v_daily_left,
        'limit', 500,
        'remaining', v_daily_left
      ),
      'weekly', v_scope->'weekly'
    );
  end if;

  -- Tamamlama: kalan slotlar YENİ görülmemiş sorulardan.
  v_need := v_limit - coalesce(array_length(v_wrong_ids, 1), 0);

  if v_need > 0 then
    v_remaining := public._faz2_lock_weekly_counter(
      v_user, v_year, v_week, p_subject_id
    );

    v_new_ids := coalesce(array(
      select c.qid
        from (
          select q.id as qid,
                 exists(
                   select 1 from public.student_question_exposures e
                    where e.user_id = v_user
                      and e.question_id = q.id
                 ) as seen
            from public.questions q
           where q.subject_id = p_subject_id
             and q.grade_level = v_grade
             and q.is_active = true
             and q.approval_status = 'approved'
             and exists (
                   select 1
                     from public.question_vault_memberships m
                     join public.question_vaults v
                       on v.id = m.vault_id
                    where m.question_id = q.id
                      and m.membership_status = 'active'
                      and m.practice_eligible = true
                      and v.is_active = true
                      and v.vault_type not in ('competition', 'one_v_one')
                )
             and exists (
                   select 1
                     from public.question_outcome_mappings om
                    where om.question_id = q.id
                      and om.outcome_id = p_outcome_id
                      and om.review_status = 'approved'
                )
        ) c
       where not c.seen
       order by c.qid
       limit least(v_need, greatest(v_remaining, 0))
    ), '{}');
  else
    v_new_ids := '{}';
  end if;

  v_all_ids := array(
    select u from unnest(v_wrong_ids) u
    union all
    select u from unnest(v_new_ids) u
  );

  -- Yeni sorular için SHOW-TIME atomik yazım.
  v_delta := 0;
  if coalesce(array_length(v_new_ids, 1), 0) > 0 then
    with ins as (
      insert into public.student_question_exposures
        (user_id, question_id, attempt_context)
      select v_user, u, 'training'
        from unnest(v_new_ids) u
      on conflict do nothing
      returning question_id
    )
    select count(*) into v_delta from ins;
  end if;

  if v_delta > 0 then
    perform public._faz2_consume_weekly_capacity(
      v_user, v_year, v_week, p_subject_id, v_delta::integer
    );
  end if;

  perform public._faz9_consume_daily_quota(
    v_user, v_day, coalesce(array_length(v_all_ids, 1), 0)::integer
  );

  select c.new_questions_used into v_used
    from public.student_weekly_counters c
   where c.user_id = v_user
     and c.academic_year = v_year
     and c.week = v_week
     and c.subject_id = p_subject_id;

  v_payload := '[]'::jsonb;
  for r_row in
    select qn.id, public._faz2_sanitize_question_payload(to_jsonb(qn)) as pb
      from public.questions qn
     where qn.id = any(v_all_ids)
     order by array_position(v_all_ids, qn.id)
  loop
    v_payload := v_payload || jsonb_build_array(r_row.pb);
  end loop;

  return jsonb_build_object(
    'questions', v_payload,
    'session_kind', 'targeted_review',
    'outcome_id', p_outcome_id,
    'wrong_review_count', coalesce(array_length(v_wrong_ids, 1), 0),
    'new_count', coalesce(array_length(v_new_ids, 1), 0),
    'reason', null,
    'lock', null,
    'daily', jsonb_build_object(
      'day', v_day,
      'questions_used', (500 - v_daily_left)
        + coalesce(array_length(v_all_ids, 1), 0),
      'limit', 500,
      'remaining', v_daily_left
        - coalesce(array_length(v_all_ids, 1), 0)
    ),
    'weekly', jsonb_build_object(
      'academic_year', v_year,
      'week', v_week,
      'subject_id', p_subject_id,
      'new_questions_used', coalesce(v_used, 0),
      'limit', 500
    )
  );
end;
$$;

-- ============================================================
-- 6. ADMIN: KONU İŞLENDİ ONAYI RPC'LERİ
-- ============================================================

-- 6a. Onay yazma (yalnız curriculum.manage yetkisi).
create or replace function public.set_curriculum_teaching_approval(
  p_schedule_item_id uuid,
  p_academic_year text,
  p_status text default 'approved',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_row  public.curriculum_teaching_approvals%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if not public.current_user_has_admin_permission('curriculum.manage') then
    raise exception 'curriculum.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_schedule_item_id is null
     or p_academic_year is null
     or p_academic_year = '' then
    raise exception 'Schedule item ve akademik yil zorunludur.'
      using errcode = '22004';
  end if;

  if p_status not in ('approved', 'rejected') then
    raise exception 'p_status approved veya rejected olmalidir.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
      from public.curriculum_schedule_items si
     where si.id = p_schedule_item_id
  ) then
    raise exception 'Schedule item bulunamadi.'
      using errcode = 'P0002';
  end if;

  insert into public.curriculum_teaching_approvals
    (academic_year, schedule_item_id, status, approved_by, notes)
  values
    (p_academic_year, p_schedule_item_id, p_status, v_uid, p_notes)
  on conflict (academic_year, schedule_item_id)
  do update set
    status = excluded.status,
    approved_by = excluded.approved_by,
    notes = excluded.notes,
    updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'academic_year', v_row.academic_year,
    'schedule_item_id', v_row.schedule_item_id,
    'status', v_row.status,
    'notes', v_row.notes,
    'updated_at', v_row.updated_at
  );
end;
$$;

-- 6b. Onay listesi (admin okuma; gelecek admin arayüzü için).
--     NOT: Şu anda "konu işlendi" işaretlemesi için bir ADMIN UI
--     YOKTUR; bu RPC gelecek planlama ekranının veri kıyısıdır.
create or replace function public.list_curriculum_teaching_approvals(
  p_subject_id uuid,
  p_academic_year text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid;
  v_rows jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Kimlik dogrulamasi gerekli.'
      using errcode = '42501';
  end if;

  if not public.current_user_has_admin_permission('curriculum.manage') then
    raise exception 'curriculum.manage yetkisi gerekli.'
      using errcode = '42501';
  end if;

  if p_academic_year is null or p_academic_year = '' then
    raise exception 'Akademik yil zorunludur.'
      using errcode = '22004';
  end if;

  select coalesce(jsonb_agg(row_to_j order by row_to_j->>'grade_level'),
                  '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'schedule_item_id', si.id,
        'grade_level', si.grade_level,
        'topic_id', si.topic_id,
        'topic_name', tp.name,
        'outcome_id', si.outcome_id,
        'outcome_text', co.outcome_text,
        'start_week', si.start_week,
        'status', coalesce(a.status, null),
        'updated_at', a.updated_at
      ) as row_to_j
        from public.curriculum_schedule_items si
        left join public.curriculum_teaching_approvals a
          on a.schedule_item_id = si.id
         and a.academic_year = p_academic_year
        left join public.topics tp on tp.id = si.topic_id
        left join public.curriculum_outcomes co on co.id = si.outcome_id
       where si.subject_id = p_subject_id
         and si.is_active = true
    ) t;

  return jsonb_build_object(
    'subject_id', p_subject_id,
    'academic_year', p_academic_year,
    'items', v_rows
  );
end;
$$;

-- ============================================================
-- 7. ACL TEYİTLERİ (yalnız impersonation-safe envroles ACL'i;
--    mevcut 104/097 ACL'lerine dokunmaz).
-- ============================================================

revoke execute
  on function public.get_training_session_state(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute
  on function public.get_training_session_state(uuid, uuid, uuid)
  to authenticated;

revoke execute
  on function public.start_training_session(uuid, integer, uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute
  on function public.start_training_session(uuid, integer, uuid, uuid, boolean)
  to authenticated;

revoke execute
  on function public.advance_training_session(uuid, uuid)
  from public, anon, authenticated;
grant execute
  on function public.advance_training_session(uuid, uuid)
  to authenticated;

revoke execute
  on function public.select_gated_targeted_review_questions(uuid, uuid, integer)
  from public, anon, authenticated;
grant execute
  on function public.select_gated_targeted_review_questions(uuid, uuid, integer)
  to authenticated;

revoke execute
  on function public.set_curriculum_teaching_approval(uuid, text, text, text)
  from public, anon, authenticated;
grant execute
  on function public.set_curriculum_teaching_approval(uuid, text, text, text)
  to authenticated;

revoke execute
  on function public.list_curriculum_teaching_approvals(uuid, text)
  from public, anon, authenticated;
grant execute
  on function public.list_curriculum_teaching_approvals(uuid, text)
  to authenticated;

comment on function public.get_training_session_state(uuid, uuid, uuid) is
  'FAZ 15A: tek soru antrenman akisi durumu. Active kuyruk varsa guncel soruyu dondurur (yenileme/geri guvenli); yoksa kilit/uygun durumunu hesaplar. Hicbir yazma/tuketim yapmaz.';
comment on function public.start_training_session(uuid, integer, uuid, uuid, boolean) is
  'FAZ 15A: antrenman oturumu baslat/surdur. Aktif kuyruk varsa (force_new=false) yeni secim YAPMAZ. Yeni oturumda eligible kapsam + konu islenme onayi + onkosul kapisi uygulanir; guncel haftalik/gunluk kota ve exposure (104) korunur; sorular kuyruga yazilir ve BIRER BIRER verilir.';
comment on function public.advance_training_session(uuid, uuid) is
  'FAZ 15A: "Sonraki soru". Ilk queued satir p_question_id ile eslesmezse fail-closed (soru atlanamaz); eslesirse answered isaretlenir ve bir sonraki kuyruk sorusu doner (yeni tuketim yok).';
comment on function public.select_gated_targeted_review_questions(uuid, uuid, integer) is
  'FAZ 15A: hedefli tekrar kapisi. 104 select_targeted_review_questions davranisini korur; oncesinde konu islenme onayi + onkosul tamamlama kapisi uygular. Kilitte soru verisi sizmaz.';
comment on function public.set_curriculum_teaching_approval(uuid, text, text, text) is
  'FAZ 15A: "konu islendi" onayini yazar (yil + schedule item). Yalniz curriculum.manage yetkilisi. UI: ilgili admin planlama ekrani bu fazda YOKTUR; RPC gelecek arayuzun veri kiyisidir.';

commit;