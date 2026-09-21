# Faz 22 Nihai Rapor

**Tarih:** 2026-09-20 (kapanış: 2026-09-21)
**Model:** big-pickle (opencode)
**Sorumlu:** selami

---

## 1. Sonuç Özeti

| Metrik | Değer |
|---|---|
| **Durum** | ✅ BAŞARILI |
| Migration | 123_faz22_candidate_md_intake_v11.sql (854 satır) + **124_faz22_candidate_md_curriculum_spec_link.sql** (kapanış; 123'e dokunulmadı) |
| Migration durumu | UYGULANDI + QA **iki izole disposable klonda** (`supabase_db_qa-faz22-r1` port 61422, `supabase_db_qa-faz22-r2` port 62422, default bridge) |
| Migration hedefi | Ana stack / hosted **DOKUNULMADI**; disposable containerlar QA sonrası temizlik için bekliyor |
| Bu oturumda eklenen | `public.register_candidate_md_batch` SECURITY INVOKER sarmalayıcı (117 deseni) + kapanışta 124 ile **outcome→spec→staging atomik zinciri** (118 köprüsü) |
| DB QA (scripts/qa_candidate_md_intake_123_local.sql) | ✅ Round 1: **67/67 PASS, 0 FAIL** · Round 2: **67/67 PASS, 0 FAIL** (her iki klonda) |
| vitest (candidate-md-intake.test.ts) | ✅ 23/23 |
| tsc --noEmit | ✅ 0 hata |
| eslint | ✅ 0 hata (8 mevcut uyarı, faz dosyalarında değil) |
| Production build | ✅ `next build` başarılı (24 sayfa) |
| QA bulguları | 4 hata **script kaynaklı** (migration değişmedi); 1 gözlem rapora işlendi |
| Git | Commit YAPILMADI (onay bekleniyor) |
| Push | YAPILMADI |

---

## 2. Görev Kapsamı

**Eski (duran) görev taşıma:** migration 123, candidate-md (v1.1) paket
alımının SQL tarafını implemente ediyordu; bu oturumda:

1. Migration 123'e **public RPC sarmalayıcısı eklendi** — PostgREST yalnız
   `public, graphql_public` şemalarını açtığından (`supabase/config.toml`
   satır 13) facade'ın `rpc("register_candidate_md_batch", {p_payload})`
   çağrısı (`src/lib/content/candidate-md-intake.ts:206-209`) için 117
   deseniyle birebir aynı `LANGUAGE sql SECURITY INVOKER SET search_path=''`
   sarmalayıcı yazıldı; `REVOKE FROM PUBLIC, anon` + `GRANT EXECUTE TO
   authenticated, service_role`. Asıl yetki kapısı private fonksiyonda.
2. **İki-round disposable SQL QA** — 16 maddelik karma (happy-path + security)
   suite, her round ayrı temiz `public.ecr.aws/supabase/postgres:17.6.1.155`
   klonunda 001–124 zinciri `ALL_MIGRATIONS_OK` sonrası tek transaction +
   ROLLBACK ile çalıştırıldı. Kapanışta suite T-17..T-21 + MAT.5.1/5.2
   fixture ile 67'ye genişletildi.
3. **Kod doğrulama** — candidate-md birim testleri + tsc + eslint + build.

Migration 123'ün sözleşmesi (doğrulanan): `private.register_candidate_md_batch`
SECURITY DEFINER, `search_path=''`; kapı `auth.role()='service_role'` VEYA
`ai.manage`/`questions.approve`; 8 kök P0001 kontrolü (payload JSON objesi,
schema_version '1.1', origin 'curriculum_original', producer id, publication/
is_active engeli, paket durumu approved engeli, boş questions); aday düzeyi
hata kodları (opsiyonlar/cevap/kazanım/zorluk/süre/çözüm/derstekrarı);
gerçek evren duplicate (questions + staging + aynı batch) `IF v_is_valid`
kapılı; staging'e `staging_source='external_producer'`, güvenli alanlar
(`ownership='ai_original'`, `license='pending'`, ticari=false, copyright
'unknown', `staging_status='validating'`), `candidate_md_v11` metadata;
final durumlar rejected / partially_valid / ingested; tekrar gönderim
yalnız response'ta `already_received`.

### Kapanış (çıktı köprüsü, 2026-09-21)

Migration 123'e dokunulmadan, append-only 124 ile `private.register_candidate_md_batch`
yeniden tanımlandı ve §3'teki "generation-spec bağı yok" bulgusu kapatıldı:

1. **Outcome çözümü fail-closed:** subject çözümünden sonra `outcome_code`
   `curriculum_outcomes` + `curriculum_versions` + `curriculum_topics`
   üzerinden çözülür; yoksa / `is_active=false` / çözülemezse → `rejected`
   + `outcome_not_found`; o aday için spec/staging ilişkisi **hiç kurulmaz**
   (yarım ilişki yok).
2. Her geçerli adayda `ai_generation_specs` satırı: `desired_count=1`,
   `status='ready'`, `outcome_id` bağlı, `difficulty`/`cognitive_type`/solve
   time, constraints içinde `source='external_producer'` + tam provenance
   (origin, producer_id, producer_model, batch_id, client_question_id,
   outcome_code).
3. Staging satırı `generation_spec_id`, `proposed_curriculum_version_id`,
   `proposed_topic_id`, `proposed_subtopic_id` + metadata'da
   `required_outcome_id`/`generation_spec_id`/`curriculum_version_id` taşır.
4. Denetim kapıları (`start_answer_verification`,
   `start_curriculum_fit_verification`) spec bağlı adayda hamle yapmadan
   `waiting_solver_1`/`waiting_reviewer_1` + `automatic_publication_allowed=false`
   ile sorunsuz açılır.
5. v1.0 geriye uyum korunur: `public.register_candidate_question_batch` yolu da
   spec+zinciri kurar; DTO dış yüzü ikincil ID'leri sızdırmaz (T-21).

---

## 3. QA Bulguları ve Düzeltmeler

Round 1'de 4 test FAIL'di; **dördü de migration değil QA-script kaynaklıydı**
(migration'a hiç dokunulmadı, en küçük güvenli değişiklik):

| Test | Kök neden | Düzeltme |
|---|---|---|
| T-03c | İdrar sayacı beklentisi `= 2` yazılmıştı; `already_received` ek satır yazmaz (gerçek: 1) | `count(*) = 2` → `= 1` |
| T-08a | `solution: {}` bir *object* olduğundan 123 `solution_zorunlu` yerine alt-alan hataları üretiyor (doğru davranış) | Fixture JSON `null`'a çekildi → `solution_zorunlu` tetiklendi |
| T-10a | `_qa_q123_has_err` yalnız `validation_status='invalid'`'e bakıyordu; duplicate adaylar `='duplicate'` taşır | filter `IN ('invalid','duplicate')` |
| T-15a | `pg_get_function_identity_arguments(p.oid) = 'jsonb'` beklentisi yanlıştı; gerçek `p_payload jsonb` (DB'de doğrulandı) | `'p_payload jsonb'` |

**Raporlanan gözlemler (düzeltme değil, bulgu):**

- ~~**Generation-spec bağı yok:**~~ **KAPANDI** — kapanış oturumunda migration
  124 ile outcome→spec→staging atomik zinciri eklendi (bkz. "Kapanış" bölümü,
  §2). 123'e dokunulmadı; 124 append-only. Staging, 034 curriculum-fit
  kapısının "Generation spec is required" koşulu için gereken
  `generation_spec_id` + outcome bağını artık taşır.
- **subject_ambiguous collation'a bağlı:** evren/alt-eylem testi
  (T-09e) iki satırın `lower(btrim(name))` ile çarpışmasına dayanır;
  disposable klonda `en_US.UTF-8` collation case-sensitive olduğu için
  çalışır (`case_eq=f, space_eq=f, norm_eq=t`). Case-folding collation
  kullanan bir DB'de `subjects_name_key` zaten çarpışmayı bloklar, o zaman
  ambiguous yolu erişilemez olur — savunmacı kod, davranış değişmez.

---

## 4. Doğrulama Sonuçları

| Kontrol | Komut | Sonuç |
|---|---|---|
| Faz 22 birim test | `npx vitest run src/lib/content/candidate-md-intake.test.ts` | ✅ 23/23 |
| tip kontrolü | `npx tsc --noEmit` | ✅ 0 hata |
| lint | `npx eslint .` | ✅ 0 hata |
| DB QA Round 1 | `apply_mig_tmp.sh` + `psql -f qa_candidate_md_intake_123_local.sql` (r1, port 61422) | ✅ 67 PASS / 0 FAIL |
| DB QA Round 2 | aynı script (r2, port 62422) | ✅ 67 PASS / 0 FAIL |
| Production build | `npm run build` | ✅ başarılı (24 sayfa) |

QA kapsamı (her iki roundda da):

```
T-01  idempotent happy-path: ingested, batch v1.0/curriculum_original,
      2 staging external_producer + güvenli alanlar, kanonik Matematik uuid,
      4 deterministic validation, audit, oop metadata              7/7
T-02  9 kök P0001 reddi (null/array/1.0/ai_generated/boş producer/
      publication_allowed/is_active/approved durum/boş questions)  9/9
T-03  already_received + yeni batch/staging yok                    3/3
T-04  options: obje değil, E boş, tekrar eden seçenek              3/3
T-05  correct_answer: aralık dışı, boş seçeneğe işaret             2/2
T-06  outcome: boş/format/ek kazanım, grade, zorluk, negatif süre  6/6
T-07  aday durumu (approved → candidate_durum_not_importable)      1/1
T-08  çözüm: zorunlu/yöntem/≥2 adım/sonuç/gerekçe/çeldirici        6/6
T-09  ders: yok/uuid formatı/alan yok/pasif/ambiguous/kanonik      6/6
T-10  gerçek evren duplicate + rejected muafiyeti                  2/2
T-11  paket içi metin + client_question_id duplicate               2/2
T-12  kapı: service_role ✓ admin ✓ izinsiz P0001 ✗                3/3
T-13  durum akışı: hepsi invalid / karma / pending                3/3
T-14  audit + yalnız yazılanlar için validation                    2/2
T-15  public wrapper: INVOKER+grant matrisi, service_role rpc,
      izinsiz P0001, anon 42501                                    4/4
T-16  oop metadata, hiçbir yerde otomatik yayın/islem yok,
      promote edilmiş external_producer yok                        3/3
T-17  kazanım→spec→staging atomik zinciri kuruldu                  1/1
T-18  Faz 118 spec sözleşmesi + provenance tek/ready               1/1
T-19  denetim kapıları spec bağlı adayda sorunsuz açılıyor         1/1
T-20  çözülemeyen/pasif kazanım fail-closed + yarım ilişki yok     1/1
T-21  v1.0 geriye uyum: spec+zincir, DTO iç yapı sızdırmaz         1/1
TOPLAM 67 | 67 | 0
```

**QA kurulum notları:**
- `apply_mig_tmp.sh` deseniyle 001–124 her iki klona `psql -U supabase_admin
  -d postgres -v ON_ERROR_STOP=1` ile uygulandı → `ALL_MIGRATIONS_OK`
  (EXIT=0 her iki round).
- Suite tek transaction içinde çalışıp `ROLLBACK` ile biter — hiçbir test
  artefaktı kalıcı değildir.
- Fixture admin `99770000-...0901` (super_admin) ve izinsiz `...0902`; rol
  simülasyonu `set local role` + `request.jwt.claims` GUC setiyle.
- Kapanış fixture'ı: `MAT.5.1` aktif / `MAT.5.2` pasif kazanımlar (seed 111/112
  yalnız 9–12. sınıf içermesi nedeniyle); T-21'de gerçek `MAT.9.1.1`
  (id `a7090000-0000-4000-8000-000000000001`) kullanılır.

---

## 5. Çalıştırılmayan / Yapılmayan İşler

- **Ana stack / hosted'e migration UYGULANMADI** — kullanıcı yasağı
  gereği; 123 + 124 yalnız izole disposable klonlarda uygulandı/QA edildi.
- **Commit yapılmadı** (açık izin istenecek); **Push yapılmadı**.
- Kotadaki değişiklikler (öğrenci alanı tema/training/review, globals.css,
  readme vb.) dahil hiçbir "görev dışı" dosyaya dokunulmadı; yalnız Faz 22
  kapsamı değişti.

---

## 6. Git Durumu

- Çalışma HEAD: Faz 21 commit'i (`c7e29dc`).
- Faz 22 değişiklikleri commit değil:
  - `supabase/migrations/123_faz22_candidate_md_intake_v11.sql` (untracked;
    bu oturumda **public sarmalayıcı eklendi**; kapanışta dokunulmadı)
  - `supabase/migrations/124_faz22_candidate_md_curriculum_spec_link.sql`
    (untracked; kapanış migration'ı — 118 generation-spec köprüsü)
  - `scripts/qa_candidate_md_intake_123_local.sql` (untracked; 4 fix +
    kapanış T-17..T-21 + MAT.5.1/5.2 fixture)
  - `src/lib/content/candidate-md-intake.ts` / `candidate-md-intake.test.ts`
    / `candidate-md-parser.ts` / `candidate-md-preflight.ts` /
    `candidate-md-types.ts` (untracked; facade katmanı)
- Faz 21 raporunda listelenen diğer değişiklikler bu oturumda elle
  değiştirilmedi.

---

## 7. Sonraki Adımlar

1. `supabase_db_qa-faz22-r1` / `r2` disposable containerlarının silinmesi için
   kullanıcı onayı alınır (port 61422/62422; iki QA turu tamamlandı).
2. Commit onayı al (yalnız Faz 22 dosyaları: 123, 124, QA script, facade
   katmanı) → ardından push onayı.
3. Üretim DB'ye migration 123 + 124 alımı ürün/dağıtım kararıyla ayrıca
   planlanır.