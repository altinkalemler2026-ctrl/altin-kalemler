# Faz 12B — Kazanım ve Alt Konu Yükleme Sonucu

**Tarih:** 2026-09-15
**Durum:** UYGULANDI VE DOĞRULANDI
**Ortam:** lokal Supabase (Docker `supabase_db_yarisma-programi`)

## Özet

Migration 112 (TYMM 2026 G9-11 + OGM 2018 G12 alt konu ve öğrenme çıktısı yüklemesi)
lokal DB'ye uygulandı. 69 alt konu + 85 öğrenme çıktısı eklendi. 5 belirsiz kazanım
(üst simge/bölü/alt simge PDF kaybı) bilinçli olarak **yüklenmedi** — bkz.
`docs/reports/faz12b-belirsiz-kazanimlar.md`.

## Yüklenen Veri

| Sınıf | Alt konu | Kazanım | Kaynak müfredat |
|-------|---------|---------|-----------------|
| 9 | 20 | 20 | TYMM 2026 |
| 10 | 21 | 19 | TYMM 2026 (2 hariç) |
| 11 | 15 | 12 | TYMM 2026 (3 hariç) |
| 12 | 13 | 34 | OGM 2018 |
| **Toplam** | **69** | **85** | |

## Yüklenmeyen (Belirsiz) Kazanımlar

| Kod | Beklenen resmî gösterim |
|-----|-------------------------|
| MAT.10.4.2 | `f(x) = x²` |
| MAT.10.4.4 | `f(x) = 1/x` |
| MAT.11.3.1 | `x ≠ π/2 + kπ` |
| MAT.11.3.3 | `f(x) = aˣ` |
| MAT.11.3.5 | `f(x) = logₐx` |

Tam ayrıntı: `docs/reports/faz12b-belirsiz-kazanimlar.md`

## Doğrulama Sonuçları

| Kontrol | Sonuç |
|---------|-------|
| Migration tek uygulamada hatasız | ✔ (ON_ERROR_STOP=1) |
| Uygulama tekrarı idempotent (çift -f, satır sabit) | ✔ 69/85 |
| Alt konu toplamı | 69 |
| Kazanım toplamı | 85 |
| Per sınıf alt konu/kazanım (9,10,11,12) | 20/20, 21/19, 15/12, 13/34 |
| Slug unique (topic_id, slug) ihlali | 0 |
| Yetim kazanım (subtopic_id → yok) | 0 |
| Yetim alt konu (topic_id → yok) | 0 |
| Rollback (migration 113) işlemi | Test işleminde 69/85 → 0/0, geri uygulama 69/85 ✔ |

## Görülen Geçici Sorunlar (Giderildi)

1. OGM parser: kazanım metinlerine not/alt satır eklenmesi (12.1.2.2 `e sayısının...`, 12.5.3.3 `a)Grafik...`)
   ve PDF sayfa numarası birleşmesi (12.6.1.2 `... yapar. 40`) → `isContinuationLine` kuralı düzeltildi,
   cümle sonu nokta ile devam satırları kabul edilmez oldu.
2. UUID üretimi hatalı uzunluk (`...-001` yerine 12 hane) → padStart(12, "0") düzeltildi.

## Rollback

Migration `113_faz12b_rollback_kazanim_ve_alt_konu.sql`: önce kazanımlar (`id LIKE 'a7%'`), sonra
alt konular (`id LIKE 'a6%'`). Test edildi; Faz 12A ve 15A verisine dokunmaz.

## Kullanılan Dosyalar

- `supabase/migrations/112_faz12b_matematik_kazanim_ve_alt_konu_yukleme.sql` — yükleme (uygulandı)
- `supabase/migrations/113_faz12b_rollback_kazanim_ve_alt_konu.sql` — rollback (hazır, uygulanmadı)
- `docs/reports/faz12b-belirsiz-kazanimlar.md` — belirsiz kazanımlar

## Not

Bu faz yalnızca DB yüklemesidir; kod/UI değişikliği yapılmadı, commit/push yapılmadı.