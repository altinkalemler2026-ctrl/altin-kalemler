# Faz 5 Güvenlik Doğrulama Raporu (latest-faz5-security-validation)

- **Tarih:** 2026-08-24
- **Ortam:** Yalnız yerel Docker/Supabase (`supabase_db_yarisma-programi`, psql `-U postgres -d postgres -v ON_ERROR_STOP=1`)
- **Durum:** YEŞİL — QA suite 15 PASS / 0 FAIL

## 1. Kapsam ve Gerçek Dosya Adları

| Migration | Gerçek dosya | İçerik |
|---|---|---|
| 077 | `supabase/migrations/077_faz5_snapshot_materialization.sql` | `prepare_competition_pack` artık `competition_questions` snapshot satırlarını atomik yazıyor; difficulty NULL/geçersiz → fail-closed; satır sayısı doğrulaması |
| 078 | `supabase/migrations/078_faz5_league_rating_engine.sql` | `_faz5_apply_competition_points` sabit rating tablosu (win +24 / loss −12); `finalize_competition_if_ready` sonuna tek PERFORM |
| 079 | `supabase/migrations/079_faz5_matchmaking_entry.sql` | Not: plan dokümanındaki "hardening" adıyla değil bu adla geldi. `join_matchmaking_queue` / `leave_matchmaking_queue` giriş RPC'leri (FIFO + advisory lock) |
| 080 | `supabase/migrations/080_faz5_competition_hardening.sql` | Beyaz listeyle SECURITY DEFINER fonksiyonlarda `search_path = ''` hardening |

QA script: `scripts/qa_faz5_local_validation.sql`

## 2. İlk QA Bulguları ve Yapılan Düzeltmeler

Salt okunur inceleme bulguları:

- **F5-01 (ORTA):** T-08 katılımcı olan C(…953)'ü kullanıyor + 077'de "snapshot/paket zaten var" kontrolleri katılımcı kontrolünden önce geldiği için beklenti (42501) asla üretilemezdi. → **Düzeltildi.**
- **T-11/T-12:** Simülasyon rakibi B(…952) idi ama gerçek eşleşen rakip C(…953); ayrıca ilk üyelikte −12 clamp ile 0 yazılacağı için "gerçek −12" senaryosu kurulamıyordu. → **Düzeltildi.**
- **T-13:** Fixture ligleri production seed bantlarıyla (bronze s10, 0-999) çakışıyordu; ayrıca motor `points_at_transition`'a değişim sonrası toplamı yazdığından 95 beklentisi yanlıştı. → **Düzeltildi.**
- **F5-02..04 (BİLGİ/DÜŞÜK):** Dosya adı farkı, 077 difficulty TOCTOU (NOT NULL kısıtı ikinci savunma), 078 `search_path=public` churn — düzeltme gerekmedi.

Yalnızca QA scriptinde yapılan değişiklikler (migration'lara dokunulmadı):

1. **T-08:** Yeni dışlanan kullanıcı D(…954) eklendi; red kanıtı, snapshot'sız izole `F5-QA-T08` (`waiting`) yarışması üzerinde veriliyor.
2. **T-11/T-12:** Cevap simülasyonu B→C; lig fixture sort_order 10/20→1/2; C için ön üyelik seed'i (50 puan, QA5-BRONZ, general); beklentiler `(951,…953)` çiftine çevrildi.
3. **T-13:** `points_at_transition = 119` (motor semantiği: v_after).

## 3. Nihai Doğrulama

- `npx supabase db reset` ✅ — 001-080 tüm migration'lar temiz DB'ye uygulandı.
- QA suite ✅ — **15 PASS / 0 FAIL**, suite TEK transaction içinde çalışıp sonunda `ROLLBACK`; kalıcı test artefaktı yok.

## 4. Kritik Güvenlik Doğrulamaları

| Doğrulama | Test | Sonuç |
|---|---|---|
| Anon `join_matchmaking_queue` EXECUTE reddi | T-01 | PASS (42501) |
| Katılımcı olmayan `prepare_competition_pack` reddi | **T-08** | **PASS** — `42501 Bu yarismanin katilimcisi degilsiniz.` |
| Rating motoru: A +24 / C −12 (before+change=after) | **T-11** | **PASS** (clamp yok) |
| Idempotent finalize: 2 rating kaydı kalır, ikinci puan yok | **T-12** | **PASS** |
| Lig bandı geçişi: 95+24=119 → QA5-GUMUS promotion + history | **T-13** | **PASS** |
| Hardening: beyaz listede `search_path=public` kalmadı | T-14 | PASS |
| ACL: authenticated evet / anon hayır (join+leave) | T-15 | PASS |

Ek olarak statik inceleme onayladı: 069 snapshot guard'ları ve 022 limit trigger'ı korunuyor; 077 satır sayısı doğrulaması mevcut; 078/079'da client/public/anon EXECUTE kapalı; git'te eski migration/.env/secret'e dokunulmamış.

## 5. Git Durumu (bilinen untracked dosyalar)

```
?? .opencode/
?? opencode.json
?? scripts/qa_faz5_local_validation.sql
?? supabase/migrations/077_faz5_snapshot_materialization.sql
?? supabase/migrations/078_faz5_league_rating_engine.sql
?? supabase/migrations/079_faz5_matchmaking_entry.sql
?? supabase/migrations/080_faz5_competition_hardening.sql
?? supabase/snippets/
```

Not: `.opencode/`, `opencode.json`, `supabase/snippets/` workspace araç gürültüsü; commit öncesi içerik kontrolü önerilir.

## 6. Sınır ve Yasaklar Uygulandı

Production erişimi, supabase link/login/db push, git commit/push/reset(git)/checkout/clean ve .env/secret erişimi **hiçbir aşamada yapılmadı**. Tüm işlemler yerel Docker ortamında gerçekleşti.

## 7. Devralma Talimatı (Sonraki Adım)

İki yedek ajan bu raporu okuyarak şuradan devralabilir:

- **Bağlam:** Faz 5 DB katmanı (077-080) doğrulanmış durumda; tek kaynak QA scripti `scripts/qa_faz5_local_validation.sql` (15/15 PASS referansı).
- **Kural 1:** Migration 077-080'e davranışsal müdahale gerekmez; herhangi bir ajan bunu gerektirirse önce bu raporun §2'sindeki bulguları tekrarlayın.
- **Kural 2:** Retest prosedürü: `npx supabase db reset` → `docker cp scripts/qa_faz5_local_validation.sql supabase_db_yarisma-programi:/tmp/` → `docker exec ... psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/...` → OZET satırında 15 PASS / 0 FAIL beklenir.
- **Kural 3:** Beklenti bozulursa (FAIL/hata) dosya değiştirmeden durup tam çıktıyı raporlayın; production/git push ve .env/secret yasaktır.

---

## 8. İzole Validasyon — 2026-08-25

- **UTC timestamp:** 2026-08-25T00:00:00Z (oturum tarihi)
- **Supabase CLI:** v2.115.0
- **Docker:** v29.7.2
- **Geçici project_id:** `faz5validation9702514715ea`
- **Geçici runtime:** `docs/project/ai-handoff/sandbox/selftest/supabase-runtime-9702514715ea4cb3a356a81fa059d2d9`
- **Geçici DB portu:** 55432→5432 (db.port), 55433 (shadow_port)

### Kaynak SHA-256 Değerleri

| Dosya | SHA-256 |
|---|---|
| `077_faz5_snapshot_materialization.sql` | `33ed4f680a8ec905928e89852ae1a2e16ae615294cee8759bed2f2ebac4e3ac8` |
| `078_faz5_league_rating_engine.sql` | `55e912582bba505159a977434f4db7e7387fffedcb2cd90012ed28f9e3dd72cc` |
| `079_faz5_matchmaking_entry.sql` | `a0f5e4d6a9d14407713ae1c5779f049c0b957b733a6c00a17ca7f3f7922c74f5` |
| `080_faz5_competition_hardening.sql` | `c6c3270e13ce8d4895c87f3f97a82d1ec2e38fc49b064f6ffa64fc340ccb33c6` |
| `qa_faz5_local_validation.sql` | `346c4d6cae3ace4fcc97bc75cda59191006e096cfd490fe393f15dc080dbfdab` |

### Sonuçlar

- **db reset --local --no-seed:** exit 0 ✅
- **Migration uygulaması:** 001–080 (050 hariç, kasıtlı boşluk) temiz uygulandı ✅
- **077–080 uygulama:** Doğrulandı ✅
- **QA suite:** T-01–T-15: **15 PASS / 0 FAIL** ✅
- **db lint --local --level error:** exit 0 ✅ (1 pre-existing error: `private.submit_originality_review` → `copyright_risk` sütunu mevcut değil — 077–080 kapsamı dışı)
- **Production kullanılmadı:** ✅
- **Mevcut yerel DB'ye dokunulmadı:** ✅ (yalnız geçici container)
- **İzole ortam temizlendi:** Devam ediyor (STEP 11)

### Notlar

- 050 numaralı migration repoda hiç var olmamış; kasıtlı boşluk olarak doğrulandı (git tarihçesi, belgeler, `supabase migration list --local` ile onaylandı).
- DB lint bulgusu (`copyright_risk` sütunu) önceden var olan şema uyumsuzluğu; 077–080 migration'larından kaynaklanmıyor.
