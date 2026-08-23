# Faz 3 — Training UI Dikey Dilim Doğrulama Raporu

**Tarih:** 23 Ağustos 2026 (Rev. 2 — final review B1–B5 düzeltmeleri sonrası)
**Kapsam:** `/training` ders seçimi + `/training/[subjectId]` çözüm oturumu ekranları, server-only servis katmanı, test altyapısı ve tam doğrulama döngüsü.
**Başlangıç commit'i:** `fe2d362` (Faz 3 foundation) · **Bu çalışmanın sonunda da `fe2d362`** — commit/push YAPILMADI (görev kuralı).

---

## 1. Özet Karar

| Alan | Sonuç |
| --- | --- |
| TypeScript (`tsc --noEmit`) | ✅ 0 hata |
| ESLint (bu görevin tüm dosyaları) | ✅ 0 hata / 0 uyarı |
| Vitest birim + bileşen + action katmanı | ✅ 36/36 |
| Vitest entegrasyon (gerçek RPC, gerçek auth) | ✅ 2/2 |
| **Vitest toplam** | ✅ **38/38** |
| SQL regresyon Faz 1 / 2 / 3 | ✅ 34/34 · 49/49 · 34/34, `kalan=0` |
| Test verisi kalıntısı | ✅ 0 |
| Gizli veri sızıntı taraması | ✅ `correct_answer`/`legacy_question_key` işaretçileri payload'da yok |
| Final review bulguları (B1–B5) | ✅ Tamamı düzeltildi ve yeniden doğrulandı |

**KARAR: ONAY — dikey dilim tanımlanan kabul kriterlerini sağlıyor; final review bulguları kapandı.**

---

## 2. Değiştirilen / Eklenen Dosyalar

### Yeni — uygulama kodu
| Dosya | İçerik |
| --- | --- |
| `src/lib/training/types.ts` | DTO'lar (`TrainingQuestion`, `WeeklyUsage`, `WeeklyUsageSnapshot`, `QuestionSelection`, `SubmitAnswerInput/Result`) + `isChoiceLetter`/`isAttemptAction` tip koruyucuları |
| `src/lib/training/errors.ts` | Türkçe hata eşlemesi (`mapTrainingError`), dönem-kapalı tespiti (`isPeriodClosedError`), oturum-süresi mesajı |
| `src/lib/training/service.ts` | Server-only DI servisi: `listTrainingSubjects`, `fetchWeeklyUsage`, `selectTrainingQuestions`, `submitTrainingAttempt`; izin-listesi mapper'lar; clamp fonksiyonları; `TrainingValidationError` |
| `src/app/(student)/training/actions.ts` | `'use server'` ince aksiyonlar — istemciden asla `user_id`/doğruluk bilgisi alınmaz |
| `src/app/(student)/training/page.tsx` | Ders listesi + haftalık kullanım; dönem kapalıysa fail-closed Türkçe banner |
| `src/app/(student)/training/[subjectId]/page.tsx` | Soru kuyruğu yükleme; `params: Promise<{subjectId}>` (Next 16); uuid regex kapısı |
| `src/components/student/TrainingSession.tsx` | İstemci oturum bileşeni + `SessionTimer` alt bileşeni (aşağıda) |

### Değiştirilen
| Dosya | Değişiklik |
| --- | --- |
| `src/app/layout.tsx` | `lang="tr"` + metadata başlığı |
| `src/app/(student)/layout.tsx` | Merkezi oturum koruması: `getUser()` boşsa `/login` redirect |
| `src/app/(student)/dashboard/page.tsx` | "Konu Çalış" kartı `/training` bağlantısına taşındı |
| `package.json` + lock | Sadece frontend test bağımlılıkları eklendi (vitest, @testing-library/*, jsdom) + `"test": "vitest run"` |

### Yeni — test altyapısı ve testler
- `vitest.config.ts` (jsdom ortamı, `@` alias, `globals:false`)
- `src/test/setup.ts` (jest-dom + `afterEach(cleanup)`)
- `src/lib/training/service.test.ts`, `errors.test.ts`
- `src/components/student/TrainingSession.test.tsx` (12 test)
- `src/lib/training/integration.local.test.ts` (gerçek Supabase'e karşı uçtan uca akış)

### Yeni — migration
- `supabase/migrations/072_subjects_read_grant.sql`: `GRANT SELECT ON public.subjects TO authenticated` + anon'dan geri alma. RLS zaten açık, `subjects_read_active` politikası mevcut; bu migration yalnızca Postgres seviyesi yetki eksikğini kapatır.

---

## 3. Mimari ve Güvenlik Kararları

1. **Sunucu-tek doğruluk kaynağı:** `submitTrainingAttemptAction` oturumu `auth.getUser()` ile çözer; istemci `user_id` gönderemez. Sonuç (`correct/wrong`) yalnızca RPC yanıtından okunur; istemciden gelen seçim yalnızca `p_choice` olarak iletilir.
2. **İzin-listesi payload:** `mapQuestionPayload` yalnızca `id, question_code, grade_level, subject_id, question_text, option_a..e, difficulty, has_visual, estimated_solve_time_seconds` alanlarını taşır. `correct_answer`, `legacy_question_key` ve diğer her şey düşürülür. Entegrasyon testinde 5 soruya `TUI-GIZLI-DOGRU-CEVAP-Qx` imzaları `legacy_question_key`'e eklenmiş ve serileştirilmiş seçim içinde bu imzaların + `"correct_answer"` anahtar adının geçmediği doğrulanmıştır.
3. **client_key idempotency:** Anahtar soru başına ilk gönderimde üretilir, ref içinde saklanır; ağ hatasında yeniden deneme AYNI anahtarla yapılır. `duplicate:true` yanıtı başarı sayılır, ikinci attempt çağrısı yapılmaz ve kullanıcıya tek seferlik Türkçe bilgi verilir.
4. **Fail-closed dönem:** `select_training_questions` `reason` döndüğünde (geçerli akademik hafta yoksa) rastgele soru gösterilmez; `role="alert"` Türkçe banner basılır.
5. **Hata eşleme:** DB hataları (42501 kimlik, P0001 öğrenci bağlamı, dönem bulunamadı) kullanıcı dostu Türkçe mesajlara maplenir; beklenmeyen hata genel mesaja düşer.
6. **React kuralları uyumu:** Sayaç mantığı `SessionTimer` alt bileşenine taşındı — `key={question.id}` ile soru başına taze mount; `Date.now()` render sırasında değil effect/olay tarafında çağrılır; effect gövdesinde senkron `setState` yoktur.

## 4. Erişilebilirlik (Türkçe UI)

- `lang="tr"` kök seviyede.
- Seçenek grubu: `fieldset > legend(sr-only)` + `role="radiogroup"` `aria-label="Cevap seçenekleri"`; klavye ile Tab + Ok tuşlarıyla seçim yapılabilir (otomatik test).
- Tüm etkileşimli hedefler `min-h-11` (≥44px).
- Canlı bölge: `aria-live` durum metni ("Doğru — sonraki soruya geçiliyor." vb.) ve hata `role="alert"`.
- Geri sayım `aria-label="Kalan süre N saniye"` ile duyurulur; özet ekranında sayaçlar etiketlidir.

## 5. Test Sonuçları

### 5.1 Birim + Bileşen + Action katmanı (36/36)
- Servis mapper'ları: izin listesi dışı alan düşürülür (gizli imza sızıntısı yok), clamp davranışları, RPC argüman sözleşmesi (anahtar kümesi tam beş; `user_id` yok), negatif süre → 0.
- Hata eşleme: bilinen DB hataları doğru Türkçe mesaj; **PostgrestError düz nesne şekli de eşlenir**.
- Bileşen: render/a11y/radiogroup, **görünür seçili durum (`has-[:checked]`, peer-checked kalıntısı yok)**, seçim+Cevapla `{choice:'B', action yok}`, klavye seçimi, ağ hatasında aynı client_key ile retry, duplicate:true tek çağrı + özet, Pas/Boş aksiyonları, geri sayım ve otomatik `timeout` (**sr-only "Kalan süre N saniye" metniyle**), boş soru listesinde fail-closed.
- Action katmanı: doğrulama hatası özel Türkçe mesajla döner (B2), oturum yoksa oturum mesajı, geçerli gönderim `user_id` olmadan RPC'ye gider, DB hatası ham metin sızmadan çevrilir.

### 5.2 Entegrasyon (gerçek yerel Supabase) — 2/2
Akış: admin API ile test öğrencisi → SQL fixture (ders/müfredat/hafta/konu/kazanım/5 onaylı soru/practice kasa üyeliği) → gerçek login → ders listesi → 5 soru seçimi (`weekly.newQuestionsUsed=5`) → doğru cevap (attempt#1) → aynı client_key ile retry (`duplicate:true`, aynı attempt_id) → yanlış/pas/boş/zaman-aşımı → haftalık kullanım=5 → SQL assert: tam 5 attempt → temizlik → kalıntı 0 (yeniden deneme penceresiyle).

### 5.3 SQL QA Regresyonu (db reset sonrası)
| Süit | Geçen | Kalan |
| --- | --- | --- |
| qa_faz1_local_validation.sql | 34/34 | 0 |
| qa_faz2_local_validation.sql | 49/49 | 0 |
| qa_faz3_local_validation.sql | 34 PASS / 0 FAIL | 0 |

## 6. Döngüde Düzeltilen Hatalar

1. `questions_correct_answer_check`: fixture'ta sentinel yerine A–E harfleri; gizlilik imzası `legacy_question_key`'e (kısıtsız, payload dışı) taşındı → unique çakışması için `-Q1..Q5` soneki.
2. Mapping INSERT'te `subtopic_id` uuid cast eksikliği.
3. Bileşende Cevapla düğmesi `selected` durumunu göndermiyordu (seçimsiz submit) → `{choice: selected}`.
4. Tek harf regex'in çoklu label eşleşmesi → `getAllByRole('radio')`.
5. RTL auto-cleanup vitest `globals:false` altında çalışmadığı için `afterEach(cleanup)` eklendi.
6. Fake-timer kararsızlığı: `shouldAdvanceTime:true` korunup zaman assertions toleranslı hale getirildi.
7. ESLint `react-hooks/purity` + `set-state-in-effect`: timer `SessionTimer` bileşenine taşındı, `useRef(Date.now())` kaldırıldı, başlangıç zamanı effect'te ref'e yazılır.
8. subjects tablosunda authenticated'a SELECT yetkisi yoktu → migration 072.

### Rev. 2 — Final review bulguları (B1–B5)

9. **B1:** Seçili şıkta görünür durum yoktu (`peer-checked` input'un kardeşi olmadığı için ölüydü). Label'a `has-[:checked]:border-gray-900 has-[:checked]:bg-gray-50` eklendi; `peer-checked:` kaldırıldı. Yeni test: seçili label `has-[:checked]` sınıflarını taşır, içinde checked input vardır, diğerlerinde yoktur.
10. **B2:** Action katmanındaki `error.name === "TrainingValidationError"` karşılaştırması hiç eşleşmiyordu (`name` kalıtımla `"Error"`). `instanceof TrainingValidationError` ile değiştirildi. Yeni `actions.test.ts` (5 test): doğrulama hatası ÖZEL Türkçe mesajla döner ve RPC'ye gitmez.
11. **B3:** Kullanılmayan `finishedRef` kaldırıldı — davranış değişmedi (gönderim zaten `submittingRef` + unmount ile korunuyordu).
12. **B4:** Geri sayım artık yalnızca `aria-label`'a bağlı değil: `<span class="sr-only">Kalan süre N saniye</span>` güvenilir ekran-okuyucu metni olarak eklendi; görsel sayaç korundu. İlgili test sorguları güncellendi.
13. **B5:** `/training` sayfasında `listTrainingSubjects` hatası yakalanıp Türkçe "Dersler yüklenemedi" fail-closed kartına çevrildi (haftalık kullanım davranışıyla tutarlı).
14. **Bonus (B2 testi yakaladı):** supabase-js hataları `Error` örneği değil düz `PostgrestError` nesnesidir; `errorText()` artık `{message}` taşıyan nesneleri de okur. Aksi halde gerçek DB hataları (dönem kapalı, 42501) UI'da her zaman genel mesaja düşecekti. Birim test eklendi.

## 7. Lint / Tip Durumu

- Bu görevin dosyaları: **temiz**.
- Repoda görev dışı, ÖNCEDEN VAR olan lint ihlalleri (dokunulmadı): `scripts/import-legacy-excel.ts`, `src/ai-worker/invalid-test-provider.ts`, `src/ai-worker/test-job-output-validator.ts`, `supabase/.temp/**` (üretilen). Toplam repo geneli 211 problem bu dosyalardan gelir; ayrıca `supabase/snippets/` klasörü kasıtlı olarak dışarıda bırakıldı.

## 8. Git / Çalışma Alanı Tespiti

- `git log`: HEAD hâlâ `fe2d362`. Commit/push/reset-checkout YAPILMADI.
- Değişiklikler çalışma ağacında: 6 modified + yeni training/test/migration dosyaları. `.opencode/`, `opencode.json`, `supabase/snippets/` dokunulmamış.

## 9. Kalan Riskler / Notlar

- `npx supabase status` bazı ikincil servislerin (imgproxy, pooler) durduğuna dair bilgi basar; testleri etkilemez.
- Entegrasyon testi yalnızca `npm run test` ile lokal Docker varken koşar; CI'da service container gerekecektir.
- Öğrenci layout koruması sunucu bileşeninde redirect ile sağlanıyor; derin bağlantılar proxy middleware'iyle de desteklenir.

**Sonuç:** Kabul kriterlerinin tamamı doğrulandı; dikey dilim yerelde uçtan uca çalışıyor ve güvenlik sözleşmesi (izin-listesi payload, user_id enjeksiyonu yok, client_key idempotency, fail-closed dönem) testlerle sabitlendi.

---

## 10. Rev. 2 — Final Review Düzeltme ve Yeniden Doğrulama Kaydı

Final read-only review (güvenlik + kod + UX) 2 düzeltme-bloklayıcı (B1, B2) ve 3 iyileştirme bulgusu (B3–B5) raporlamıştı; tümü bu revizyonda kapatıldı:

| Bulgu | Dosya | Çözüm | Doğrulama |
| --- | --- | --- | --- |
| B1 görünür seçim durumu | `TrainingSession.tsx` | `has-[:checked]:border-gray-900 has-[:checked]:bg-gray-50`; ölü `peer-checked:` kaldırıldı | Yeni test: seçili label sınıflarını taşır + checked input içerir; diğerleri içermez |
| B2 action hata ayrıştırma | `training/actions.ts` | `instanceof TrainingValidationError` | Yeni `actions.test.ts`: özel Türkçe mesaj döner, RPC çağrılmaz |
| B3 ölü `finishedRef` | `TrainingSession.tsx` | Kaldırıldı (davranış değişikliği yok) | Mevcut 12 davranış testi aynen geçti |
| B4 timer duyurulabilirliği | `TrainingSession.tsx` | sr-only "Kalan süre N saniye" metni; görsel sayaç korundu | Timer testi güncel metin üzerinden doğrular |
| B5 ders listesi hatası | `training/page.tsx` | try/catch + Türkçe "Dersler yüklenemedi" kartı | Kod incelemesi; weekly usage ile aynı `mapTrainingError` yolu |
| Bonus: PostgrestError eşlemesi | `errors.ts` | `errorText()` düz `{message}` nesnelerini okur | Yeni birim testi (P0001 dönem hatası + permission denied) |

### Rev. 2 doğrulama koşuları
- `npx tsc --noEmit` → 0 hata.
- ESLint (tüm görev dosyaları) → 0 problem.
- `npx vitest run` → **5 dosya / 38 test → 38 PASS / 0 FAIL**.
- SQL QA: Faz 1 **34/34**, Faz 2 **49/49**, Faz 3 **34 PASS / 0 FAIL**, üçünde de `kalan=0`.
- Kalıntı taraması (`TUI-%` sorular/dersler/kullanıcı/hafta/müfredat) → **0**.

### Rev. 2 git / teslim teyidi
- `git log`: HEAD hâlâ `fe2d362` — **commit/push/reset/checkout yapılmadı**.
- Migration 072 ve 001–071'e rev. 2'de dokunulmadı; `.env*`, secret'lar, `.opencode/`, `opencode.json`, `supabase/snippets/`, `scripts/import-legacy-excel.ts` değişmedi.
- Production/link/login/db push işlemi yapılmadı.

**Nihai karar: ONAY — commit için hazır** (yukarıdaki §10 dahil, final review'daki kesin dosya listesiyle).
