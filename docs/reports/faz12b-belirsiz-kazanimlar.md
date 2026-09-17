# Faz 12B — Belirsiz Kazanımlar Raporu

**Tarih:** 2026-09-15
**Durum:** TASLAK — uygulama izni bekleniyor
**Kapsam:** Faz 12B kazanım yükleme (TYMM 2026: 9/10/11 + OGM 2018: 12)

## Özet

Toplam 90 kazanım/öğrenme çıktısı tespit edildi. **85'i** güvenilir metinle migration 112'ye dahil edildi.
**5'i** matematiksel gösterimde üst simge/bölü/alt simge kaybı (PDF metin çıkarma sınırı) nedeniyle
**yüklenmedi** ve aşağıda listelendi. Bu 5 kaydın resmî gösterimi, PDF üzerinde insan/OCR ile
doğrulanmadığı sürece DB'ye yazılmaz (tahmin yok).

## Yükleme Dışı Kazanımlar (5)

Aşağıdaki kazanımlar, TYMM 2026 PDF'ten metin çıkarımında **üst simge / bölme / alt simge**
gösterimleri düzleştirilmiş olarak geldiği için **yüklenmedi**. Kayıtlı metin şu anki hâliyle
bozuk/eksik gösterim içeriyor; doğru resmî metin PDF üzerinden manuel doğrulama gerektiriyor.

### 1. MAT.10.4.2 (10. sınıf — NİCELİKLER VE DEĞİŞİMLER)
- **Bayrak:** `superscript_x`
- **Çıkarılan metin:**
  `Gerçek sayılarda f(x) = x 2 şeklinde tanımlı karesel referans fonksiyonun nitel özellikleri ...`
- **Beklenen resmî gösterim:** `f(x) = x²` (2 üst simge; PDF satırında "x" ve "2" ayrı satırlarda)
- **Kaynak:** `_tmp_tymm2026.txt` satır 4606-4607 (`MAT.10.4.2. Gerçek sayılarda f(x) = x` + `2 `)

### 2. MAT.10.4.4 (10. sınıf — NİCELİKLER VE DEĞİŞİMLER)
- **Bayrak:** `fraction_1over_x`
- **Çıkarılan metin:**
  `Gerçek sayılarda f(x) = 1 x (x ≠ 0) şeklinde tanımlı rasyonel referans fonksiyonun ...`
- **Beklenen resmî gösterim:** `f(x) = 1/x` (bölü çizgili kesir; "1" ve "x" ayrı satırlarda)
- **Kaynak:** `_tmp_tymm2026.txt` (MAT.10.4.4 bölümü)

### 3. MAT.11.3.1 (11. sınıf — NİCELİKLER VE DEĞİŞİMLER (1))
- **Bayrak:** `pi_superscript`
- **Çıkarılan metin:**
  `f(x) = sinx (x ∈ ℝ), f(x) = cosx (x ∈ ℝ), f(x) = tanx (x ∈ ℝ, x ≠ π 2 + kπ, k ∈ ℤ ) ve f(x) = cotx (x ∈ ℝ, x ≠ kπ, k ∈ ℤ) ...`
- **Beklenen resmî gösterim:** `x ≠ π/2 + kπ` (kesir; "π" ve "2" ayrı satırlarda)
- **Kaynak:** `_tmp_tymm2026.txt` (MAT.11.3.1 bölümü)

### 4. MAT.11.3.3 (11. sınıf — NİCELİKLER VE DEĞİŞİMLER (2))
- **Bayrak:** `exp_a_pow_x`
- **Çıkarılan metin:**
  `Gerçek sayılarda f(x) = a x (a > 0, a ≠ 1) şeklinde tanımlı üstel referans fonksiyonun ...`
- **Beklenen resmî gösterim:** `f(x) = aˣ` (üst simge; "a" ve "x" ayrı satırlarda)
- **Kaynak:** `_tmp_tymm2026.txt` (MAT.11.3.3 bölümü)

### 5. MAT.11.3.5 (11. sınıf — NİCELİKLER VE DEĞİŞİMLER (2))
- **Bayrak:** `log_base`
- **Çıkarılan metin:**
  `f(x) = log a x (a > 0, a ≠ 1, x > 0 ) şeklinde tanımlı logaritmik referans fonksiyonun ...`
- **Beklenen resmî gösterim:** `f(x) = logₐx` (a alt simge; "log", "a", "x" ayrı satırlarda)
- **Kaynak:** `_tmp_tymm2026.txt` (MAT.11.3.5 bölümü)

## Sonuç

Bu 5 kayıt, resmî PDF'in ilgili kısmı **doğrulanıp metin elle düzeltildikten sonra** ek bir
migration ile (idempotent `UPDATE`) yüklenebilir. Şu an yüklemeye tabi değildir.

## Yükleme Onayı Öncesi Notlar

- 85 kazanım + 69 alt konu yüklemesi: migration `112_faz12b_matematik_kazanim_ve_alt_konu_yukleme.sql`
- Onaylanması durumunda bu 5 kayıt DB'de **olmayacak**; yalnızca bu raporda tutulacak.