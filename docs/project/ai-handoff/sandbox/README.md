# AI Handoff Sandbox (Write Failover Test Alanı)

Bu klasör, **izole sandbox** yazma-failover testine ayrılmıştır. Buradaki hiçbir
dosya gerçek proje kodunun parçası değildir ve hiçbir sonuç gerçek proje
dosyalarına otomatik UYGULANMAZ.

## Amaç

Ox Alpha (birincil) ve MiMo (yedek) modellerinin, yalnızca bu sandbox klasörüne
yazabilen sıkı izinlerle çalışabildiğini kanıtlamak. Global
`execution_policy.automatic_write_failover` ayarı `false` olarak KALIR; bu test
o ayarın açılması anlamına GELMEZ.

## Katılımcılar ve Dosyalar

| Rol | Model | Ajan | Komut | Tek yazma hedefi |
|---|---|---|---|---|
| Primary | `opencode/x-preview-f-free` | `.opencode/agents/ai-sandbox-writer-primary.md` | `.opencode/commands/ai-sandbox-write-primary.md` | `sandbox/primary-result.json` |
| Fallback | `opencode/mimo-v2.5-free` | `.opencode/agents/ai-sandbox-writer-fallback.md` | `.opencode/commands/ai-sandbox-write-fallback.md` | `sandbox/fallback-result.json` |

Çalıştırıcı: `scripts/opencode_write_failover_sandbox.ps1`

## Sonuç Dosyası Sözleşmesi

Her yazar kendi dosyasına tam olarak şu şemayı yazar:

```json
{
  "schema_version": 1,
  "test_type": "sandbox_write_failover",
  "writer": "primary | fallback",
  "model": "gerçek model kimliği",
  "status": "PASS",
  "scope": "docs/project/ai-handoff/sandbox-only",
  "production_accessed": false,
  "db_command_ran": false,
  "git_write_ran": false,
  "real_project_files_changed": false
}
```

## Güvenceler

- Her ajanın `edit` izni önce `"*": deny`, sonra yalnızca kendi sonuç dosyasına
  `allow` şeklindedir (son eşleşen kural kazanır). Diğer tüm edit yolları kapalıdır.
- Ajanlarda `bash`, `external_directory`, `task`, `todowrite`, `webfetch`,
  `websearch` tamamen `deny`'dir.
- Production, DB, Docker, Supabase, git yazma ve `.env`/secret erişimi her iki
  ajan için de kesinlikle yasaktır.
- Çalıştırıcı script birincil başarısız olsa bile `primary-result.json`
  dosyasını SİLMEZ, yedek sonuçla BİRLEŞTİRMEZ.
- Otomatik merge, patch uygulama, rename, move, delete veya promotion ASLA yapılmaz.
- Script ağ, DB, Docker, Supabase veya git komutu ÇALIŞTIRMaz;
  `Invoke-Expression`/`Start-Process` kullanmaz.

## Manuel Çalıştırma (insan onaylı)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\opencode_write_failover_sandbox.ps1
# Birincil modeli atlayip dogrudan yedegi test etmek icin:
powershell -ExecutionPolicy Bypass -File scripts\opencode_write_failover_sandbox.ps1 -ForceFallback
```

Ön koşullar: `opencode.cmd`/`opencode` bulunmalı, `scripts/validate_ai_task_state.ps1`
mevcut olmalı ve `current-task.json` içinde `automatic_write_failover` kesinlikle
`false` olmalıdır.

## Exit Kodları

| Kod | Anlam |
|---|---|
| 0 | Başarı (`SANDBOX_PRIMARY_PASS` veya `SANDBOX_FALLBACK_PASS`) |
| 2 | Doğrulama başarısız (`SANDBOX_WRITE_FAILOVER_FAILED`) |
| 3 | Ön koşul eksikliği (`PRECONDITION_MISSING`) |

## Durum

Kurulum aşaması: ajanlar, komutlar ve çalıştırıcı oluşturulmuştur; henüz
hiçbiri ÇALIŞTIRILMAMIŞTIR. İlk çalıştırma insan onayı gerektirir.
