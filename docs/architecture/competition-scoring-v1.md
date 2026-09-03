# Yarışma Puanlama Sözleşmesi V1 (competition_scoring_v1)

Durum: **Uygulanmış** (migration `094_competition_scoring_v1_seed.sql`).
Bu belge mevcut gerçek uygulamayı anlatır; uygulanmamış gelecek
sistemleri (XP, harcanabilir para, mağaza) uygulanmış gibi göstermez.

## 1. Değer türlerinin ayrımı

| Değer | Gerçek ad | Durum | Bu sözleşmeyle ilişkisi |
|---|---|---|---|
| Yarışma performans puanı | `competition_answers.points_awarded` → `competition_players.total_points` | UYGULANMIŞ | Bu belgenin konusu |
| Lig rating puanı | `student_league_memberships.current_points` (078) | UYGULANMIŞ | Ayrı katman: kazanma +24, kaybetme −12, beraberlik 0 |
| XP / deneyim | — | YOK | Gelecek; yarışma puanından türetilmez |
| Harcanabilir para / cüzdan | `student_wallets` (017) | YALNIZ ŞEMA | Yazan işlem yok; yarışma puanı bakiyeye dönüştürülmez |
| Rozet / avatar / mağaza | 017 tabloları | YALNIZ ŞEMA | Bu sözleşme kapsamı dışı |

## 2. Puan matrisi V1

Yalnız **fallback** (`band_code IS NULL`) satırları seed edilmiştir:

| Sonuç | easy | medium | hard |
|---|---:|---:|---:|
| correct | 100 | 150 | 200 |
| wrong | 0 | 0 | 0 |
| pass | 0 | 0 | 0 |
| timeout | 0 | 0 | 0 |

- Bütün puanlar tam sayıdır; runtime çarpanı/combo/sınıf/lig etkisi yoktur.
- Sınıf (grade 1–12) puana etkisi yoktur: aynı zorluk + bant her sınıfta aynı puanı verir.
- Onaylı süre bandı bulunamayan doğru cevap temel (fallback) puanını alır; yanlış/pas/timeout daima 0'dır.

### Ayrılmış bantlı matris (henüz seed EDİLMEDİ)

Onaylı süre bantları tanımlandığında eklenecek değerler:

| Zorluk | Yavaş/fallback | Normal | Hızlı |
|---|---:|---:|---:|
| Kolay | 100 | 120 | 150 |
| Orta | 150 | 180 | 225 |
| Zor | 200 | 240 | 300 |

Neden şu an yok: şemada (`scoring_time_bands`, 019; `question_scoring_time_bands`, 020)
hiçbir onaylı bant seed'i bulunmamaktadır ve kaynaktek güvenilir bir
milisaniye sınırı sözleşmesi yoktur. Keyfi ms bantı uydurulmamıştır.
Bantlar onaylanana dek tek soru üst sınırı **200**, 5 soruluk yarışma
üst sınırı **1000**'dir; bantlı matris devreye alındığında teorik üst
sınır **1500**'dür (5 × 300 zor-hızlı).

## 3. Çalışma biçimi (sunucu-otoriter)

- İstemci yalnız `competition_question_id` + `submitted_answer` (A–E veya NULL=pas) gönderir (021).
- `time_ms` sunucu saatiyle (`sent_at`/`deadline_at`) hesaplanır; deadline sonrası cevap `timeout`'tur.
- Doğruluk `get_internal_correct_answer` ile sunucu içinden belirlenir; istemciye sızmaz.
- Puan `resolve_competition_points(rule_set, grade, difficulty, result, band)` ile
  `scoring_point_rules`'tan çözülür; satır yoksa 0 (fail-closed).
- `total_points` her cevaptan sonra `competition_answers` toplamından yeniden hesaplanır.
- Aynı soruya ikinci cevap `UNIQUE(competition_question_id, user_id)` ile engellenir → çift puan imkânsız.
- Finalize sonucu `competition_results` snapshot'ına yazılır; kural tablosu sonradan değişse geçmiş sonuç değişmez.
- Lig rating `competition_point_changes('rating')` UNIQUE kısıtıyla finalize başına tek kez uygulanır (078).

## 4. Kural seti yönetimi

- V1 tek aktif set: `competition_scoring_v1` (version '1').
- Eski `faz5_default` pasiftir; 079/082 kurulum seçicisi yalnız aktif
  setler arasında seçim yapar → temiz DB'de seçim V1'dir, belirsizlik yoktur.
- `scoring_point_rules` / `scoring_rule_sets` istemci rollerine kapalıdır
  (RLS + grant yok + 094 REVOKE); kural değişikliği yalnız migration/service-role ile yapılır.
- Admin panelinde kural düzenleme ekranı yoktur.

## 5. Kapsam sınırları

- Bu sözleşme XP, seviye, streak, rozet, avatar, mağaza, envanter veya
  harcanabilir para üretmez; bu katmanlar için ayrı ürün kararı ve
  ayrı sözleşme gerekir.
- Antrenman (10 soru, puan yok) ve yarışma (≤5 soru) havuzları ayrı kalır.
