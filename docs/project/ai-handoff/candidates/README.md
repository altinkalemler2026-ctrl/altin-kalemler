# Write Candidate Paketleri (Yalnızca Staging)

Bu klasör, AI modellerinin ürettiği **aday (candidate) değişiklik paketlerinin**
staging alanıdır. Buradaki `*.json` dosyaları gerçek proje dosyalarına
uygulanacak içeriğin **veri taslağıdır**; kod veya yapılandırma değildir.

## Kesin Güvenceler

- **Aday paket yalnızca staging verisidir.** Bir paketin varlığı veya
  doğrulanmış olması hiçbir anlamda değişiklik değildir.
- **Validator PASS etse bile HİÇBİR dosya uygulanmaz.**
  `scripts/validate_ai_write_candidate.ps1` salt okunurdur; decoded içeriği
  diske YAZMAZ, mevcut dosyaları DEĞİŞTİRMEZ, SİLMEZ, TAŞIMAZ.
- **Gerçek uygulama/promotion kapısı henüz YOKTUR.** Aday paketi gerçek
  proje dosyalarına uygulayacak hiçbir kod/kapı tanımlanmamıştır; ileride
  tanımlanırsa ayrı ve açık insan onayı gerekecektir.
- **`execution_policy.automatic_write_failover=false` KALMALIDIR.** Bu klasör
  ve validator bu ayarı asla değiştirmez; ayarın açılması insan onayına tabidir.
- **delete / rename / move / chmod / binary patch / keyfi komut desteği
  YOKTUR.** İlk sürümde yalnızca `create` ve `replace` işlemleri şemalıdır.

## Aday Paket Sözleşmesi (Özet)

- Şema: `docs/project/ai-handoff/write-candidate.schema.json`
  (JSON Schema draft 2020-12, her seviyede `additionalProperties: false`)
- Zorunlu üst alanlar: `schema_version`(1), `task_revision`,
  `canonical_report`, `producer(role|model)`, `status`(READY_FOR_VALIDATION),
  `changes`(1–20), `acceptance_criteria`, `safety`.
- Her change: benzersiz relative `path`, `operation`(create|replace),
  `expected_sha256` (create→null, replace→mevcut dosyanın lowercase hex
  SHA-256'sı), `content_base64`, `content_sha256`.
- Limitler: dosya başına decoded içerik ≤ 2 MiB; toplam ≤ 5 MiB.
- `changes[].path` yalnızca güncel görevin `scope.allowed_paths`
  listesindeki kesin dosya yollarıyla birebir eşleşebilir; `denied_paths`
  kalıpları ile `.env*`/pem/key/secrets yolları kesinlikle reddedilir.

## Manuel Doğrulama (İnsan Onaylı)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate_ai_write_candidate.ps1 -CandidatePath <aday-dosya.json>
```

Aday dosyası yalnızca şu iki dizinin altında olabilir:
`docs/project/ai-handoff/candidates/` veya `docs/project/ai-handoff/sandbox/`.

Exit kodları: `0` = WRITE_CANDIDATE_VALID, `2` = doğrulama hatası
(WRITE_CANDIDATE_ERROR satırları), `3` = ön koşul/dosya/parse hatası.

## Birleşik Self-Test (Tek Komut)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test_ai_write_candidate_pipeline.ps1
```

Beklenen çıktı: `AI_WRITE_CANDIDATE_PIPELINE_PASS`, exit kodu `0`.
Test hatasında `CANDIDATE_SELFTEST_FAILED: STEP_<NN>: <neden>` ile exit `2`;
ön koşul hatasında `CANDIDATE_SELFTEST_PRECONDITION_FAILED` ile exit `3`.

### Adımlar (STEP 01–09)

| Adım | Tür | Doğrulama |
|---|---|---|
| 01 | - | İki PowerShell dosyasının Parser.ParseFile sözdizimi denetimi |
| 02 | Pozitif | Kanonik task-state validator'u (`TASK_STATE_VALID`, exit 0) |
| 03 | Pozitif | Geçerli create adayı → `WRITE_CANDIDATE_VALID` + exit 0 |
| 04 | Negatif | Bozuk `content_sha256` → `WRITE_CANDIDATE_ERROR` + exit 2 |
| 05 | Negatif | `../outside.txt` yol kaçışı → güvenli yol reddi + exit 2 |
| 06 | Negatif | Yanlış `task_revision` → revision uyuşmazlığı + exit 2 |
| 07 | Negatif | `status=awaiting_human_task` fixture → durum kapısı reddi + exit 2 |
| 08 | Negatif | `safety.real_project_files_changed=true` → safety ihlali + exit 2 |
| 09 | - | Uygulanmazlık ve değişmezlik denetimleri |

Pozitif test yalnız gerçekten `WRITE_CANDIDATE_VALID` + exit 0 ile geçer;
her negatif test gerçekten `WRITE_CANDIDATE_ERROR` + exit 2 üretmelidir.
Token veya exit kodu değiştirilerek sahte PASS üretilemez.

### Güvenceler

- **TestMode yalnızca fixture görev durumu içindir:** alternatif
  `-TaskStatePath`, `-TestMode` ile VE `sandbox/selftest/` altında olmadıkça
  kabul edilmez; `-TestMode` olmadan verilirse validator ön koşul hatasıyla
  reddeder. Hiçbir güvenlik kontrolü kapatılmaz veya gevşetilmez.
- **Testler hiçbir adayı gerçek dosyaya UYGULAMAZ:** runtime içindeki
  `target.txt` hiç oluşturulmaz; decoded içerik diske yazılmaz.
- **Runtime klasörleri finally içinde güvenli temizlenir:** silmeden önce
  yolun selftest altında olduğu, adın tam `runtime-<GUID>` biçiminde olduğu
  ve kök dizinlerden biri olmadığı doğrulanır.
- **`automatic_write_failover=false` kalır:** başlangıçta ve STEP 09'da iki
  kez `[bool] false` olarak doğrulanır; kanonik `current-task.json`,
  `task-state.schema.json` ve `write-candidate.schema.json` SHA-256 ile
  değişmezlik denetimine tabidir.
- **Promotion/apply kapısı hâlâ YOKTUR:** bu self-test yalnızca staging
  doğrulamasını test eder; hiçbir koşulda gerçek proje dosyasına uygulama
  yapmaz.

## Sandbox Uygulama Kapısı (Yalnızca Selftest)

`scripts/apply_ai_write_candidate_sandbox.ps1`, validator'dan geçmiş write-candidate
adaylarını **yalnızca** `sandbox/selftest/runtime-<32hex>/` altına uygulayan atomik
kapıdır. Gerçek proje dosyalarına uygulama YASAKTIR ve bu kapı gerçek kaynak
koduna ASLA uygulanamaz.

- **Onay token'ı:** `APPROVE_SANDBOX_CANDIDATE:<task_revision>:<candidate_file_sha256>`
  (aday dosyasının raw byte SHA-256'sı; ordinal tam eşleşme).
- **create:** hedef yok olmalı; temp dosyaya yazım → temp hash doğrulaması →
  atomik `File.Move`; **replace:** preimage SHA-256 zorunlu → atomik
  `File.Replace` (fallback: delete+move); her iki durumda hedef sonrası hash
  candidate ile eşleşmeli.
- **delete/rename/move/chmod desteği YOKTUR.**
- **Transaction/rollback:** tüm değişiklikler önce preflight edilir; tek
  hatada uygulananlar ters sırada geri alınır (create silinir, replace eski
  byte içeriğine döner; her adım hash'le doğrulanır).
- `-InjectFailureAfterWrite` **yalnızca test içindir**: N. başarılı yazımdan
  sonra kontrollü hata üretip rollback'i tetikler.
- **Exit kodları:** `0` APPLIED, `2` REJECTED (aday/token/yol/preimage),
  `3` PRECONDITION_FAILED, `4` ROLLED_BACK, `5` ROLLBACK_FAILED (kritik;
  başka işlem yapılmaz).
- Tek komutlu promotion pipeline testi:
  `powershell -ExecutionPolicy Bypass -File scripts\test_ai_candidate_promotion_pipeline.ps1`
  (STEP 01–10; beklenen: `AI_CANDIDATE_PROMOTION_PIPELINE_PASS`, exit 0).
- **Promotion/apply gerçek proje kapısı HÂLÂ YOKTUR** ve
  `automatic_write_failover=false` kalmalıdır.

### Durum

Apply kapısı ve promotion test script'i kuruludur. Birleşik self-test
sınır-duurumu düzeltmeleri sonrasında **2 düzeltme turu limitine** takılmıştır;
bilinen açık konu: hedef doğrudan runtime klasörü kökünde iken parent-dizin
kontrolünün (`parent == runtimeDir`) izin vermesi gerekmektedir. Test
`PROMOTION_SELFTEST_REVIEW_REQUIRED` durumundadır; insan onayı olmadan ek
düzeltme yapılmamıştır.

## Durum

Şema, salt-okunur validator ve birleşik self-test kurulu; self-test
`AI_WRITE_CANDIDATE_PIPELINE_PASS` (exit 0) ile geçmiştir. Hiçbir aday paket
gerçek dosyaya uygulanmamıştır.
