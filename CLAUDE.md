# Altın Kalemler - Eğitim ve Yarışma Platformu

## Proje Özeti

Altın Kalemler, 1-12. sınıf öğrencileri için tasarlanmış eğitici bir yarışma platformudur. Öğrenciler konu bazlı antrenman yapabilir, gerçek zamanlı yarışmalara katılabilir ve liglerde sıralama yarışıtabilirler.

## Teknoloji Stack

- **Frontend**: Next.js 16 (App Router) + TypeScript
- **Styling**: Tailwind CSS
- **Backend**: Supabase (PostgreSQL, Auth, Realtime, Storage)
- **Real-time**: Supabase Realtime (WebSocket)

## Mimari Prensipler

### 1. Ölçeklenebilirlik
- 32.000+ soru, hedef 100.000+
- Sınıf bazlı dinamik puan sistemi
- Modüler yapıda yeni özellik eklenebilirliği

### 2. Güvenlik
- Supabase Auth (password_hash uygulama tarafında tutulmaz)
- Server-side süre ölçümü (client timestamp'e güvenilmez)
- Anti-cheat: answer_received_at - sent_at

### 3. İleride Çoklu Dil Desteği
- İlk sürüm sadece Türkçe
- UI metinleri merkezi tutulacak, i18n'e hazır

---

## Abonelik ve Ödeme Sistemi

### Durum
- **Mimari hazır**, tablolar tanımlandı
- **Henüz implement edilmedi**
- **Sprint 1 kapsamı dışında**

### Tablolar

#### plans
Her plan satırı tek bir satılabilir paketi temsil eder.

```sql
plans (
  id, name, slug,
  price DECIMAL,              -- Free için 0
  currency VARCHAR(3),
  billing_interval: 'free' | 'monthly' | 'yearly',
  display_order, is_active, is_popular,
  created_at, updated_at
)
```

#### subscriptions
Kullanıcı abonelik kayıtları.

```sql
subscriptions (
  id, user_id, plan_id, status,
  started_at, expires_at, auto_renew,
  cancelled_at, cancel_reason,
  provider, provider_subscription_id, provider_customer_id,
  created_at, updated_at
)
```

**Kurallar:**
- Free plan için subscription kaydı zorunlu DEĞİL
- Kullanıcının aktif subscription'ı yoksa = free plan erişimi
- Bir kullanıcı aynı anda sadece bir ücretli plana abone olabilir

```sql
-- Partial unique index
-- Kullanıcının aynı anda yalnızca bir aktif subscription'ı olabilir
-- Free plan için subscription kaydı oluşturulmaz (aktif subscription yoksa = free plan)
CREATE UNIQUE INDEX idx_subscriptions_one_active 
  ON subscriptions(user_id) 
  WHERE status = 'active';
```

#### entitlements
Plan bazlı özellik erişimleri (tek doğruluk kaynağı).

```sql
entitlements (
  id, plan_id, feature_key, feature_value, created_at
)
```

**Entitlement Keys:**
- `unlimited_practice`: boolean
- `advanced_stats`: boolean
- `premium_leagues`: boolean
- `extra_cosmetics`: boolean
- `premium_question_sets`: boolean
- `daily_question_limit`: number (-1 = sınırsız)
- `competition_per_day`: number (-1 = sınırsız)

#### billing_events
Ödeme/yenileme/iptal/iade olaylarının kaydı.

```sql
billing_events (
  id, user_id, subscription_id,
  event_type, amount, currency,
  provider, provider_event_id, provider_metadata,
  metadata, created_at
)
```

### Gelecek Entegrasyonlar
- Stripe (web ödemeleri)
- Google Play Billing (Android)
- App Store (iOS)

### Önemli Kurallar

| Kural | Açıklama |
|-------|----------|
| Ücretsiz her zaman çalışır | Free plan tüm kullanıcılar için varsayılan |
| Entitlement tek kaynak | Özellikler `entitlements` tablosundan kontrol edilir |
| Kolay paket ekleme | Yeni plan için sadece `plans` + `entitlements` kaydı |
| Kod değişikliği yok | Yeni paketler için uygulama kodu güncellenmez |

---

## Klasör Yapısı

```
src/
├── app/
│   ├── (auth)/          # Giriş, kayıt, şifre sıfırlama
│   ├── (student)/       # Öğrenci sayfaları (antrenman, yarışma, profil)
│   ├── (admin)/         # Admin paneli
│   └── api/             # API routes
├── components/
│   ├── ui/              # Temel UI bileşenleri
│   ├── forms/           # Form bileşenleri
│   ├── student/         # Öğrenci özel bileşenleri
│   └── admin/           # Admin özel bileşenleri
├── lib/
│   ├── supabase/        # Supabase client
│   ├── utils/           # Yardımcı fonksiyonlar
│   └── constants/       # Sabitler
├── hooks/               # Custom hooks
├── types/               # TypeScript tipleri
└── styles/              # Global stiller
```

---

## Git Workflow

- Her feature yeni branch'te geliştirilir
- Main branch'e doğrudan commit atılmaz
- Commit mesajları convention-based: `feat:`, `fix:`, `refactor:`

---

## Notlar

- Henüz veritabanı tabloları oluşturulmadı
- Henüz auth ekranları yapılmadı
- Henüz yarışma, soru import, AI veya avatar sistemi kodlanmadı

---

## AI Management & QA Team - Gelecek Planı

Amaç:
Altın Kalemler projesi ilerledikçe AI tabanlı yönetim, test, kalite ve raporlama ekibi kurulacak.

Planlanan roller:
- AI Project Manager
  - sprint ve görev takibi
  - önceliklendirme
  - risk ve ilerleme raporu

- AI Technical Lead / Architecture Reviewer
  - mimari bütünlüğü kontrol eder
  - yeni özelliklerin mevcut sistemi bozup bozmadığını değerlendirir

- AI QA / Test Engineer
  - unit, integration ve E2E test senaryoları hazırlar
  - testleri çalıştırır
  - sonuçları raporlar

- AI Bug Analyzer
  - hataları tekrar üretir
  - kök neden analizi yapar
  - düzeltme önerir

- AI Regression Tester
  - düzeltmelerden sonra eski çalışan özelliklerin bozulmadığını kontrol eder

- AI Competition Simulation Tester
  - çok sayıda sanal yarışma çalıştırır
  - puan, süre, pas, beraberlik, bağlantı kopması ve edge-case senaryolarını test eder
  - ileride dart ve diğer görsel yarışma simülasyonlarını da doğrular

- AI Security Reviewer
  - Supabase RLS
  - Auth
  - admin yetkileri
  - anti-cheat
  - secret/key güvenliği
  alanlarını denetler

- AI UX Reviewer
  - mobil ve web arayüzünü
  - yaş grubuna uygunluk
  - kullanılabilirlik
  - erişilebilirlik
  açısından değerlendirir

- AI Content QA
  - soru doğruluğu
  - cevap doğruluğu
  - sınıf/konu eşleşmesi
  - AI tarafından üretilen soru kalitesi
  alanlarını değerlendirir

- AI Finance Analyst
  - maliyet tahmini
  - ücretsiz/premium senaryolar
  - gelir-gider
  - kullanıcı başı maliyet
  - başabaş analizi
  hazırlar
  - gerçek ödeme veya harcama yapma yetkisi yoktur

- AI Management Reporter
  - diğer AI rollerinden gelen sonuçları haftalık/aylık yönetim raporuna dönüştürür

Yetki prensipleri:
- AI ajanları aynı yetkiye sahip olmamalı.
- Test ajanı production kodunu doğrudan değiştirmemeli.
- Bug Analyzer çözüm önerebilir ancak kritik değişiklikleri kullanıcı onayı olmadan uygulamamalı.
- Finance Analyst gerçek para harcayamaz veya ödeme başlatamaz.
- Kritik mimari, güvenlik, ödeme ve production değişikliklerinde kullanıcı onayı zorunlu olmalı.

Önerilen uygulama sırası:
1. Şimdi sadece mimari not
2. Temel ürün ve yarışma motoru
3. QA/Test + Bug Analyzer + Regression Tester
4. Competition Simulation Tester + Security Reviewer
5. UX + Content QA
6. Finance Analyst + Management Reporter
