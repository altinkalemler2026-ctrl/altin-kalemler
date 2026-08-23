-- 072: Öğrencilerin /training ders listesi için subjects tablosuna okuma yetkisi.
-- RLS + subjects_read_active politikası mevcut; yalnızca authenticated rolüne
-- SELECT yetkisi verilmektedir (anon erişimi yoktur).

grant select on public.subjects to authenticated;

revoke all on public.subjects from anon;
