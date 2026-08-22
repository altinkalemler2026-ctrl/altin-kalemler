-- ============================================================
-- 059_01_curriculum_schedule_profiles.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Yıllık müfredat işleme sırası profilleri (konu -> hafta açılışı)
--
-- 059 kuralları:
--   - Konu/kazanım müfredatta işlenmeden o soru öğrenciye sorulamaz.
--   - Farklı okul veya kurumların konu işleme sıraları desteklenmeli.
--   - Varsayılan MEB planı bulunmalı.
--   - Okul/kurum profili aynı kazanımı farklı haftalarda açabilmeli.
--   - Antrenman Sahası: önceden işlenmiş konular tekrar çalışılabilmeli,
--     antrenman soruları haftanın geçmesiyle zorunlu olarak kapanmamalı.
--
-- Hafta aralığı standardı (mevcut sistem ile aynı):
--   start_week : INCLUSIVE  -> week >= start_week
--   end_week   : EXCLUSIVE  -> week < end_week
--   end_week NULL             -> açık uçlu
--
-- ÖNEMLİ SEMANTİK AYRIM:
--   end_week YALNIZCA "güncel içerik / o hafta işlenen konu" penceresini
--   sınırlar. Antrenman erişimi start_week'ten itibaren KALICI olarak
--   açılır; end_week geçse bile daha önce işlenmiş konu antrenmanda
--   tekrar çalışılabilir. Bu migration training erişimini kapatmaz.
--
-- Mevcut tablolar yeniden oluşturulmaz; yalnız bağlantı katmanı eklenir.
-- leagues / puanlama yapılarına dokunulmaz.
-- ============================================================

begin;


-- ============================================================
-- 1. CURRICULUM_VERSIONS.IS_DEFAULT
--
-- Varsayılan MEB planı işaretçisi.
-- Her eğitim yılı için en fazla bir varsayılan versiyon olabilir.
-- ============================================================

alter table public.curriculum_versions
  add column if not exists is_default boolean not null default false;

comment on column public.curriculum_versions.is_default is
  'Varsayılan (MEB) yıllık plan işareti. Eğitim yılı başına en fazla bir satır true olabilir.';

create unique index if not exists idx_curriculum_versions_one_default_per_year
  on public.curriculum_versions(academic_year)
  where is_default = true;

create index if not exists idx_curriculum_versions_default_lookup
  on public.curriculum_versions(academic_year, is_default)
  where is_default = true;


-- ============================================================
-- 2. CURRICULUM_SCHEDULE_PROFILES
--
-- Okul / kurum bazlı konu işleme sırası profilleri.
-- NULL olmayan varsayılan profil = MEB standart sıralaması.
-- ============================================================

create table if not exists public.curriculum_schedule_profiles (
  id uuid primary key default gen_random_uuid(),

  code text not null unique,
  name text not null,
  description text,

  curriculum_version_id uuid not null
    references public.curriculum_versions(id)
    on delete restrict,

  is_default boolean not null default false,
  is_active boolean not null default true,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint curriculum_schedule_profiles_default_must_be_active
    check (is_default = false or is_active = true)
);

create unique index if not exists idx_curriculum_schedule_profiles_one_default
  on public.curriculum_schedule_profiles(curriculum_version_id)
  where is_default = true;

create index if not exists idx_curriculum_schedule_profiles_version
  on public.curriculum_schedule_profiles(curriculum_version_id);

create index if not exists idx_curriculum_schedule_profiles_active
  on public.curriculum_schedule_profiles(is_active);

drop trigger if exists trigger_curriculum_schedule_profiles_set_updated_at
  on public.curriculum_schedule_profiles;

create trigger trigger_curriculum_schedule_profiles_set_updated_at
before update on public.curriculum_schedule_profiles
for each row
execute function public.set_updated_at();


-- ============================================================
-- 3. STUDENT_PROFILES.SCHEDULE_PROFILE_ID
--
-- Öğrencinin hangi okul/kurum sırasını izlediği.
-- NULL ise uygulama varsayılan (MEB) profili kullanır.
-- Alan sunucu tarafından yönetilir; istemci değişikliği
-- bölüm 7'deki guard trigger ile DB düzeyinde engellenir.
-- ============================================================

alter table public.student_profiles
  add column if not exists schedule_profile_id uuid
  references public.curriculum_schedule_profiles(id)
  on delete set null;

create index if not exists idx_student_profiles_schedule_profile
  on public.student_profiles(schedule_profile_id);


-- ============================================================
-- 4. CURRICULUM_SCHEDULE_ITEMS
--
-- Konu / alt konu / kazanım -> hafta açılışı.
--
-- Hafta aralığı: start_week inclusive, end_week exclusive.
--   güncel içerik penceresi:
--     week >= start_week and (end_week is null or week < end_week)
--
-- Antrenman erişimi (059 kuralı):
--     week >= start_week
--   end_week antrenman erişimini KAPATMAZ. Konu bir kez
--   start_week'te açıldıktan sonra antrenmanda kalıcıdır.
-- ============================================================

create table if not exists public.curriculum_schedule_items (
  id uuid primary key default gen_random_uuid(),

  schedule_profile_id uuid not null
    references public.curriculum_schedule_profiles(id)
    on delete cascade,

  grade_level smallint not null
    check (grade_level between 1 and 12),

  subject_id uuid not null
    references public.subjects(id)
    on delete cascade,

  topic_id uuid
    references public.topics(id)
    on delete cascade,

  subtopic_id uuid
    references public.subtopics(id)
    on delete cascade,

  outcome_id uuid
    references public.curriculum_outcomes(id)
    on delete cascade,

  -- INCLUSIVE. Konunun ilk işlendiği hafta.
  -- Aynı zamanda antrenman erişiminin kalıcı olarak açıldığı haftadır.
  start_week integer not null
    check (start_week >= 0),

  -- EXCLUSIVE. Yalnızca güncel içerik / öğretim penceresi üst sınırı.
  -- NULL ise açık uçlu. Antrenman erişimini etkilemez.
  end_week integer
    check (end_week is null or end_week > start_week),

  is_active boolean not null default true,

  notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint curriculum_schedule_items_target_required
    check (
      topic_id is not null
      or outcome_id is not null
    )
);

create unique index if not exists idx_curriculum_schedule_items_unique
  on public.curriculum_schedule_items (
    schedule_profile_id,
    grade_level,
    subject_id,
    topic_id,
    subtopic_id,
    outcome_id,
    start_week
  )
  nulls not distinct;

-- Sıcak yol: seçim/antrenman açılış sorguları bu indeksi sürücü olarak kullanır.
create index if not exists idx_curriculum_schedule_items_lookup
  on public.curriculum_schedule_items (
    schedule_profile_id,
    grade_level,
    subject_id,
    start_week
  );

create index if not exists idx_curriculum_schedule_items_topic
  on public.curriculum_schedule_items(topic_id);

create index if not exists idx_curriculum_schedule_items_outcome
  on public.curriculum_schedule_items(outcome_id);

drop trigger if exists trigger_curriculum_schedule_items_set_updated_at
  on public.curriculum_schedule_items;

create trigger trigger_curriculum_schedule_items_set_updated_at
before update on public.curriculum_schedule_items
for each row
execute function public.set_updated_at();


-- ============================================================
-- 5. RLS
--
-- Çizelge verisi öğrenci uygulamasının sorulabilir kapsam
-- hesabında okuyacağı referans veridir; yazım service_role'dadır.
-- ============================================================

alter table public.curriculum_schedule_profiles
  enable row level security;

alter table public.curriculum_schedule_items
  enable row level security;

drop policy if exists curriculum_schedule_profiles_read_active
  on public.curriculum_schedule_profiles;

create policy curriculum_schedule_profiles_read_active
on public.curriculum_schedule_profiles
for select
to authenticated
using (is_active = true);

drop policy if exists curriculum_schedule_items_read_active
  on public.curriculum_schedule_items;

create policy curriculum_schedule_items_read_active
on public.curriculum_schedule_items
for select
to authenticated
using (is_active = true);


-- ============================================================
-- 6. PRIVILEGES
--
-- authenticated: yalnız okuma.
-- anon: erişim yok.
-- service_role: tam yetki.
-- ============================================================

revoke all on table public.curriculum_schedule_profiles from anon, authenticated;
revoke all on table public.curriculum_schedule_items from anon, authenticated;

grant select
  on public.curriculum_schedule_profiles
  to authenticated;

grant select
  on public.curriculum_schedule_items
  to authenticated;

grant select, insert, update, delete
  on public.curriculum_schedule_profiles
  to service_role;

grant select, insert, update, delete
  on public.curriculum_schedule_items
  to service_role;


-- ============================================================
-- 7. STUDENT_PROFILES.SCHEDULE_PROFILE_ID GUARD
--
-- student_profiles üzerinde authenticated için geniş UPDATE yetkisi
-- (001 update_own policy + default table privileges) vardır.
--
-- Neden REVOKE UPDATE (schedule_profile_id) YETMEZ:
--   Tablo genelinde verilmiş UPDATE yetkisi sütun bazlı revoke'ı
--   geçersiz kılar (column grant tablo grant'ının alt kümesidir;
--   tablo grant'ı varken sütun revoke etkisizdir). Tablo geneli
--   UPDATE'i geri alıp sütun sütun grant vermek ise yeni eklenen
--   kolonları sessizce kırar.
--
-- Çözüm: BEFORE INSERT OR UPDATE guard trigger.
--   - SECURITY INVOKER zorunludur; SECURITY DEFINER olsaydı
--     current_user fonksiyon sahibine döner ve kontrol anlamsızlaşır.
--   - current_user kontrolü güvenilir rolleri tanır:
--       service_role        -> sunucu tarafı doğrudan yazım
--       postgres/supabase_admin -> migration + SECURITY DEFINER
--                                 server fonksiyonları (güvenilir
--                                 sunucu yolu)
--     PostgREST istekleri authenticator bağlantısında SET LOCAL ROLE
--     ile authenticated/anon olarak çalışır; istemci bu rollere
--     üye olmadığından onları taklit edemez.
--   - UPDATE: schedule_profile_id değişimi güvenilir olmayan rolde
--     engellenir.
--   - INSERT: güvenilir olmayan rol NULL OLMAYAN değer atayamaz
--     (kendi profiline kendini okul profili atama açığı kapanır);
--     NULL atama serbesttir -> MEB varsayılan planı.
-- ============================================================

create or replace function public.guard_student_schedule_profile_change()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then

    if tg_op = 'INSERT'
       and new.schedule_profile_id is not null
    then
      raise exception
        'schedule_profile_id yalnizca service_role / sunucu tarafi tarafindan atanabilir.'
        using errcode = 'insufficient_privilege';
    end if;

    if tg_op = 'UPDATE'
       and new.schedule_profile_id is distinct from old.schedule_profile_id
    then
      raise exception
        'schedule_profile_id yalnizca service_role / sunucu tarafi tarafindan degistirilebilir.'
        using errcode = 'insufficient_privilege';
    end if;

  end if;

  return new;
end;
$$;

drop trigger if exists trigger_student_profiles_guard_schedule_profile
  on public.student_profiles;

create trigger trigger_student_profiles_guard_schedule_profile
before insert or update on public.student_profiles
for each row
execute function public.guard_student_schedule_profile_change();

-- Trigger fonksiyonu dogrudan RPC yuzeyine cikmaz.
-- (025 default privileges da zaten yeni fonksiyonlarda EXECUTE'u
-- PUBLIC/anon/authenticated'dan alir; burada acikça tekrarlanir.)
revoke execute
on function public.guard_student_schedule_profile_change()
from public, anon, authenticated;


commit;
