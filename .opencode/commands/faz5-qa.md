---
description: Faz 5 salt okunur güvenlik ve QA kontrolü
agent: faz5-security-qa
subtask: false
model: opencode/x-preview-f-free
---

# Faz 5 QA Kontrolü

Faz 5 migration 077-080 için kanonik rapor üzerinden salt okunur güvenlik ve QA sonucu doğrulaması yap.

## Kurallar

- Kanonik kaynak: `docs/reports/latest-faz5-security-validation.md`
- DB reset **yalnızca açık insan onayıyla** çalıştırılır; kendiliğinden asla.
- FAIL/hata durumunda hiçbir değişiklik yapmadan DUR; kanıtları (test kimlikleri, hata mesajları, SQL durum kodları) tam çıktıyla raporla.
- Production erişimi, `.env`/secret dosyaları ve git yazma işlemleri (commit/push/reset/checkout/clean) KESİNLİKLE YASAK.
- Beklenen nihai sonuç: **15 PASS / 0 FAIL**.
- Bu komut varsayılan olarak hiçbir DB, Docker, psql veya shell komutu çalıştırmaz. Gerçek retest yalnız kullanıcı açıkça RETEST_APPROVED yazarsa ve ayrıca izin verirse değerlendirilebilir.
