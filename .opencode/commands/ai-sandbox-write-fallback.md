---
description: Sandbox yazma testi - yedek yazar
agent: ai-sandbox-writer-fallback
subtask: false
model: opencode/mimo-v2.5-free
---

# Sandbox Write Fallback

Yalnızca şu dosyayı oluştur veya üzerine yaz: `docs/project/ai-handoff/sandbox/fallback-result.json`

Dosya içeriği TAM OLARAK şununla sınırlıdır:

```json
{
  "schema_version": 1,
  "test_type": "sandbox_write_failover",
  "writer": "fallback",
  "model": "opencode/mimo-v2.5-free",
  "status": "PASS",
  "scope": "docs/project/ai-handoff/sandbox-only",
  "production_accessed": false,
  "db_command_ran": false,
  "git_write_ran": false,
  "real_project_files_changed": false
}
```

## Kurallar

- Yalnızca kendi sonuç dosyanı yaz; başka hiçbir dosya oluştur/düzenle/sil (`primary-result.json` dahil; onu okuma/silme/birleştirme DENEME).
- Shell/bash YASAK; dosyayı yalnızca yerleşik write aracıyla yaz.
- Dosya zaten varsa içeriği tamamen üzerine yaz.
- Production, DB, Docker, Supabase, git, ağ ve `.env`/secret erişimi YASAK.
- Yazma tamamlandığında `SANDBOX_FALLBACK_RESULT_WRITTEN` yaz ve dur; yazamıyorsan `SANDBOX_FALLBACK_RESULT_FAILED` yaz ve dur.
