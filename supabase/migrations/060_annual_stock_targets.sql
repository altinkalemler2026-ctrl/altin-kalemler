-- ============================================================
-- 059_02_annual_stock_targets.sql
-- Altın Kalemler - Migration 059 Faz 1
--
-- Yıl başı haftalık temel stok hedefleri.
--
-- 059 kuralları:
--   - Yıl başlamadan bütün soru kasaları hazırlanacak.
--   - Haftalık ders temel stok hedefi öğrenci sayısından bağımsız olacak.
--   - Başlangıç minimumu ders/hafta için 300 soru (normal haftalık temel
--     competition / 1v1 stoğu için).
--   - Antrenman Sahası stoğu normal haftalık competition/1v1 stoğundan
--     ayrı tutulmalı.
--   - Ödüllü yarışma stoğu normal haftalık stoktan ayrı tutulmalı.
--   - Kolay/orta/zor dağılımı mevcut lig ve zorluk kurallarına göre
--     ayrıca planlanmalıdır.
--
-- ÖNEMLİ DÜZELTMELER:
--   1. 300 alt sınırı YALNIZCA scope = 'weekly_competition' içindir.
--      rewarded_competition ve training için zorunlu minimum YOKTUR;
--      hedefler bağımsız ve yapılandırılabilir.
--   2. Bu tablo 057 kullanıcı-sayısı demand formülünün yerine GEÇMEZ ve
--      onu yıllık temel stok belirleyicisi yapmaz. 057 planner'ı operasyonel
--      sinyal olarak çalışmaya devam eder; bu tablo yıl başı temel plandır.
--   3. Bu tablo AI üretimini tetiklemez; yalnız insan planlama kaydıdır.
-- ============================================================

begin;


-- ============================================================
-- 1. ANNUAL_STOCK_TARGETS
-- ============================================================

create table if not exists public.annual_stock_targets (
  id uuid primary key default gen_random_uuid(),

  -- RESTRICT: yillik stok plani insan planlama kaydidir; bir curriculum
  -- versiyonu silinirken plan sessizce silinmemeli. Versiyon temizligi
  -- icin once plan kayitlarinin bilincli olarak arsivlenmesi/temizligi gerekir.
  curriculum_version_id uuid not null
    references public.curriculum_versions(id)
    on delete restrict,

  -- Stok ayrımı:
  --   weekly_competition    : normal haftalık temel competition/1v1 stoğu
  --   rewarded_competition  : ödüllü yarışma stoğu (ayrı, yapılandırılabilir)
  --   training              : antrenman sahası stoğu (ayrı, yapılandırılabilir)
  stock_scope text not null
    check (
      stock_scope in (
        'weekly_competition',
        'rewarded_competition',
        'training'
      )
    ),

  grade_level smallint not null
    check (grade_level between 1 and 12),

  subject_id uuid not null
    references public.subjects(id)
    on delete restrict,

  week integer not null
    check (week >= 0 and week <= 52),

  -- Normal haftalık temel stok hedefi.
  -- 059 kuralı: ders/hafta başlangıç minimumu 300.
  -- Bu alt sınır yalnız weekly_competition scope'unda zorunludur;
  -- rewarded_competition ve training hedefleri serbestçe planlanır.
  base_target_count integer not null
    check (base_target_count > 0),

  easy_target_count integer
    check (easy_target_count is null or easy_target_count >= 0),

  medium_target_count integer
    check (medium_target_count is null or medium_target_count >= 0),

  hard_target_count integer
    check (hard_target_count is null or hard_target_count >= 0),

  notes text,

  is_active boolean not null default true,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- 300 minimumu yalnız normal haftalık competition/1v1 stoğu için.
  constraint annual_stock_targets_weekly_base_minimum_300
    check (
      stock_scope <> 'weekly_competition'
      or base_target_count >= 300
    ),

  -- Zorluk kırılımı bilgi amaçlıdır; lig/zorluk mantığına dokunmaz.
  constraint annual_stock_targets_difficulty_within_base
    check (
      coalesce(easy_target_count, 0)
      + coalesce(medium_target_count, 0)
      + coalesce(hard_target_count, 0)
      <= base_target_count
    ),

  constraint annual_stock_targets_unique_cell
    unique (
      curriculum_version_id,
      stock_scope,
      grade_level,
      subject_id,
      week
    )
);

comment on column public.annual_stock_targets.base_target_count is
  'Ders/hafta temel stok hedefi. weekly_competition icin >= 300 zorunlu; rewarded_competition ve training icin bagimsiz/yapilandirilabilir.';

create index if not exists idx_annual_stock_targets_lookup
  on public.annual_stock_targets (
    curriculum_version_id,
    grade_level,
    subject_id,
    week
  );

create index if not exists idx_annual_stock_targets_scope
  on public.annual_stock_targets(stock_scope);

drop trigger if exists trigger_annual_stock_targets_set_updated_at
  on public.annual_stock_targets;

create trigger trigger_annual_stock_targets_set_updated_at
before update on public.annual_stock_targets
for each row
execute function public.set_updated_at();


-- ============================================================
-- 2. RLS
--
-- Stok planı iç operasyon verisidir; öğrenci uygulaması okumaz.
-- RLS enable + hiçbir client policy'si yok -> service_role bypass eder.
-- ============================================================

alter table public.annual_stock_targets
  enable row level security;


-- ============================================================
-- 3. PRIVILEGES
--
-- anon/authenticated: erişim yok (057 planner tabloları deseni).
-- service_role: tam yetki.
-- ============================================================

revoke all on table public.annual_stock_targets from anon, authenticated;

grant select, insert, update, delete
  on public.annual_stock_targets
  to service_role;


commit;
