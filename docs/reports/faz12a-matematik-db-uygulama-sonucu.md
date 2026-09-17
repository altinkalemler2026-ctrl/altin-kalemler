# Faz 12A — 2026-2027 Matematik Müfredatı DB Uygulama Sonucu

**Tarih:** 15 Eylül 2026
**Kapsam:** Yalnız lokal Supabase DB (`supabase_db_yarisma-programi`)
**Migration:** `supabase/migrations/111_faz12a_2026_2027_matematik_mufredati.sql`

## 1. Özet

2026-2027 matematik müfredatı (TYMM 2026: 9-11; OGM 2018: 12) veri-yükleyen migration ile lokal DB'ye uygulandı. Tüm işlemler `docker exec psql` ile, tek transaksiyon içinde `commit` edildi. Migration idempotent olarak yeniden çalıştırıldı ve doğrulandı (ikinci çalıştırma sıfır yeni satır yarattı).

**Sonuç: SUCCESS** (tüm doğrulama senaryoları yeşil).

## 2. Uygulanan Değişiklikler

| Tablo | İşlem | Satır Sayısı |
|-------|-------|--------------|
| `curriculum_versions` | E2E7-FAZ7 `is_default=false` + INSERT TYMM-2026, OGM-2018 | +2 (toplam 4) |
| `curriculum_schedule_profiles` | E2E7-PROF `is_default=false` + INSERT TYMM-PROF, OGM-PROF | +2 (toplam 4) |
| `academic_weeks` | DELETE eski fixture (44) + INSERT resmî K1-K41 | 41 |
| `topics` | INSERT 24 konu (9α7 + 10α7 + 11α3 + 12α7) | +24 |
| `curriculum_schedule_items` | INSERT 26 satır (9α7 + 10α7 + 11α5 + 12α7) | +26 |
| `curriculum_prerequisites` | INSERT 16 satır (10←9: 7, 11←10: 3, 12 içi: 6) | +16 |
| `student_profiles` | E2E_Ogrenci_A/B → OGM-PROF | 2 öğrenci |

## 3. Veri Detayları

### Versiyonlar ve Profiller
- **TYMM-2026** (`a1000000-...-0000000000c1`): `is_default=true` → 9/10/11 için varsayılan.
- **OGM-2018** (`a1000000-...-0000000000c2`): `is_default=false` → 12. sınıf açık atama.
- **TYMM-PROF** (`a2000000-...-0000000000c1`): varsayılan profil, 19 schedule item.
- **OGM-PROF** (`a2000000-...-0000000000c2`): 12. sınıf profili, 7 schedule item.
- E2E7-FAZ7 versiyon ve profil `is_default=false` yapılarak tek-default kuralı (idx `one_default_per_year`, 059) korundu.

### Academic Weeks (K1-K41)
Resmî MEB 2026-2027 takvimi: **14 Eylül 2026 – 25 Haziran 2027**, 41 hafta.
- Tatil haftaları **K10** (16-23 Kas), **K20** (25 Oca-1 Şub), **K21** (1-8 Şub), **K26** (8-15 Mar) takvim satırı olarak VAR.
- Tatil haftalarına **hiçbir `start_week` ATANMADI** (doğrulama: 0 satır).

### Konular ve Schedule (kanonik T→K)
| Sınıf | Konular | Start haftaları |
|-------|---------|------------------|
| 9 (TYMM) | MAT.9.1 - MAT.9.7 (7) | 1, 7, 14, 16, 24, 30, 36 |
| 10 (TYMM) | MAT.10.1 - MAT.10.7 (7) | 1, 7, 12, 15, 28, 32, 36 |
| 11 (TYMM) | MAT.11.1, MAT.11.2, MAT.11.3 (3) | 1, 5, 16/25/33, sonra 16, 25, 33 |
| 12 (OGM) | 12.1 - 12.7 (7) | 1, 7, 11, 17, 22, 30, 37 |

- `end_week` EXCLUSIVE: sonraki konunun `start_week`'idir; son konu için NULL.
- MAT.11.3 üç ayrı schedule penceresi ile açılır (16→25, 25→33, 33→NULL).
- Hiçbir `start_week` tatil haftasına (10, 20, 21, 26) denk gelmez.

### Önkoşul Zinciri (resmî temel kabul)
16 satır, tümü `requirement_level='required'`, `review_status='approved'`, `source_type='manual'`, `confidence=1.0`:
- 10.1←9.3, 10.2←9.6, 10.3←9.1, 10.4←9.2, 10.5←9.5, 10.6←9.4, 10.7←9.7
- 11.1←10.2, 11.2←10.1, 11.3←10.4
- 12.2←12.1, 12.3←12.2, 12.4←12.3, 12.5←12.4, 12.6←12.5, 12.7←12.6

## 4. Doğrulama Sonuçları (salt-okunur SQL)

| # | Senaryo | Beklenen | Gerçekleşen | Durum |
|---|---------|----------|-------------|-------|
| 1 | Versiyon/profil bağları | TYMM default, OGM değil, E2E7 değil | Uyumlu | GEÇTİ |
| 2 | Act akademik haftalar | 41 satır + 4 tatil | 41+4 | GEÇTİ |
| 3 | Tatil haftalarında start_week YOK | 0 satır | 0 satır | GEÇTİ |
| 4 | Konu sayıları | 9:7, 10:7, 11:3, 12:7 | Aynı | GEÇTİ |
| 5 | Schedule item sayıları | 9:7, 10:7, 11:5, 12:7 | Aynı | GEÇTİ |
| 6 | Öğrenci ataması | E2E_A/B → OGM-PROF | Aynı | GEÇTİ |
| 7 | İdempotency (2. çalıştırma) | 0 yeni satır | 0 yeni satır | GEÇTİ |

## 5. Açık Kararlar ve Notlar (rapor)

1. **Grade-10 MAT.10.4 start_week = K15**, planın grade-10 tablosundaki "K16" yazımına karşı kanonik T→K eşlemesi (T14=K15) esas alındı.
2. **Grade-11 MAT.11.3** tek konu + 3 schedule penceresi olarak yüklendi (konu tablosunda 3 ayrı satır yerine).
3. **FZ15A fixture** (start_week=3) DOKUNULMADI; izole test fixture'i olarak kabul edildi.
4. **`curriculum_teaching_approvals` YÜKLENMEDİ** — öğretmen onayı otomatik verilmez.
5. **`curriculum_outcomes` ve subtopics YÜKLENMEDİ** — resmî outcome_text metinleri raporlarda tam mevcut değildi; tahmin edilmedi.
6. **test1 (`kancaselami@gmail.com`, grade 11)** gerçek görünümlü hesap — profili ATANMADI; eşleme için manuel onay gerekir.
7. **Soru üretimi / soru stoğu YÜKLENMEDİ** — kapsam dışı.

## 6. Rollback

`docs/reports/rollback-faz12a-matematik.sql` dosyasında mevcuttur (çalıştırılmadı). E2E7 varsayılanlığı, fixture academic weeks ve ilk durum geri döndürülebilir.

## 7. Sınırlar ve Durum

- **YALNIZ lokal DB** etkilendi; hosted Supabase'e dokunulmadı.
- Kod / UI değişikliği yok.
- Commit / push YAPILMADI (faz gerekliliği gereği ayrı onay bekler).

**Faz 12A: SUCCESS** — rapor sonlanır; komut beklenmez, kullanıcı onayı gerekir.