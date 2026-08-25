---
description: Sandbox yazma testi - birincil yazar
agent: ai-sandbox-writer-primary
subtask: false
model: opencode/x-preview-f-free
---

# Sandbox Write Primary

Yalnızca şu dosyayı oluştur veya üzerine yaz: `docs/project/ai-handoff/sandbox/primary-result.json`

Dosya içeriği TAM OLARAK şununla sınırlıdır:

```json
{
  "schema_version": 1,
  "test_type": "sandbox_write_failover",
  "writer": "primary",
  "model": "opencode/x-preview-f-free",
  "status": "PASS",
  "scope": "docs/project/ai-handoff/sandbox-only",
  "production_accessed": false,
  "db_command_ran": false,
  "git_write_ran": false,
  "real_project_files_changed": false
}
```

## Kurallar

- Yalnızca kendi sonuç dosyanı yaz; başka hiçbir dosya oluştur/düzenle/sil (`fallback-result.json` dahil).
- Shell/bash YASAK; dosyayı yalnızca yerleşik write aracıyla yaz.
- Dosya zaten varsa içeriği tamamen üzerine yaz.
- Production, DB, Docker, Supabase, git, ağ ve `.env`/secret erişimi YASAK.
- Yazma tamamlandığında `SANDBOX_PRIMARY_RESULT_WRITTEN` yaz ve dur; yazamıyorsan `SANDBOX_PRIMARY_RESULT_FAILED` yaz ve dur.
