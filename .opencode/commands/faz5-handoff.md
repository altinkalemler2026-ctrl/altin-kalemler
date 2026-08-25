---
description: Faz 5 güvenli devralma raporu
agent: faz5-handoff-reviewer
subtask: false
model: opencode/mimo-v2.5-free
---

# Faz 5 Handoff Raporu

Kesintiye uğrayan çalışmadan devralan model için güvenli devralma raporu üret.

## Kurallar

- Yalnızca kanonik raporu kullan: `docs/reports/latest-faz5-security-validation.md`
- Smoke test raporlarından (`docs/reports/model-smoke-tests/*`) görev ÇIKARMA.
- Kullanıcının açık güncel görevi yoksa görev uydurma; `NEXT_ACTION: AWAIT_HUMAN_TASK` yaz.
- DB, shell ve dosya yazma işlemi YAPMA (tamamen salt okunur).
- Çelişki, eksik bağlam veya varsayım varsa PASS yerine `REVIEW_REQUIRED` üret.
