<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

<!-- BEGIN:codebase-memory-usage -->

# Codebase Memory usage

Bir görev mimariyi, bağımlılıkları veya etki alanını ilgilendiriyorsa önce codebase-memory ile proje ve ilgili sembolleri sorgula. Yalnız gerekli kaynak dosyalarını doğrudan oku. Negatif veya kapsamlı iddialarda index coverage kontrolü yap. Harita eski veya eksikse bunu raporla.

<!-- END:codebase-memory-usage -->

<!-- BEGIN:ALTIN-KALEMLER-ANA-SOZLESME -->

# ALTIN KALEMLER — ZORUNLU OTURUM SÖZLEŞMESİ

Her oturumun EN BAŞINDA `docs/project/altin-kalemler-ana-sozlesme.md`
dosyasını oku ve uygula. Bu dosya ana ürün sözleşmesi ve faz planıdır
(sürüm 1.0, 3 Eylül 2026). Zorunlu başlıklar:

- Ürün sabitleri: Türkiye / Türkçe / Matematik / yalnız öğrenci deneyimi +
  gerekli admin; öğretmen, veli, okul, B2B paneli ve Almanya yok
- Sınıf ≠ kişisel seviye ≠ lig; öğrenci yalnız kendi grade_level içeriğini
  görür; sınıflar arası profil/sıralama/ligi görmez
- Yarışma puanı / lig rating / XP / yıldız / rozet / seri ayrı değerlerdir;
  harcanabilir yalnız yıldızdır; ekonomi kurulmadan sahte UI gösterilmez
- V1 puan matrisi ve lig +24/−12/0 sözleşmesi ürün kararı olmadan değişmez
- Çalışma protokolü: her fazın başında salt-okunur gerçeklik kontrolü;
  kullanıcı modified/untracked dosyaları dokunulmaz; reset/clean/restore/
  checkout/rebase/amend/force-push yasak; hosted Supabase'e anlık açık izinsiz
  dokunma yok; ana stack'te db reset yok; DB QA benzersiz ad/port/disposable
  ortamda, Docker envanter karşılaştırmalı; secret okunmaz; testlerde yalnız
  deterministik sahte fixture; en küçük güvenli değişiklik; test gevşetme/skip
  yasak; hata başına en fazla 3 kontrollü deneme → BLOCKED
- UI: doğal Türkçe (ASCII Türkçesi yok), lang="tr", a11y (klavye, görünür
  focus, aria-live, ≥44px hedef), 375×812 + 768×1024 + 1440×900, koyu tema
  bitmeden tema seçici yok, sahte buton yok
- Git: her faz tek yerel commit; commit yalnız tüm kontroller yeşilken;
  push için her fazda ayrıca açık kullanıcı izni; push sonrası aynı SHA'da
  CI completed/success olmadan faz bitmiş sayılmaz
- Faz yürütme: bir oturum = bir faz; faz sonunda nihai rapor + dur;
  sonraki faza "devam" onayı olmadan geçilmez; BLOCKED/PARTIAL_SUCCESS
  raporlanır; kota uyarısında güvenli noktada durulur

<!-- END:ALTIN-KALEMLER-ANA-SOZLESME -->

<!-- BEGIN:ALTIN-KALEMLER-MUHENDISLIK-AJANLARI -->

# ALTIN KALEMLER — MÜHENDİSLİK AJANLARI VE ÇALIŞMA DÜZENİ

Roller `.opencode/agents/` içinde tanımlıdır ve KORUNUR: `engineering-software-architect`,
`engineering-backend-architect`, `engineering-frontend-developer`. Bu blok ortak
kuralları, güncel görev checkpoint'ini ve ihtiyaç halinde okunan çalışma yönergelerini
tanımlar.

## Kısa Ortak Kurallar (tüm mühendislik ajanları)

1. Önce salt-okunur gerçeklik kontrolü: `git status/diff/log` + kod tabanı gerçeği +
   ana sözleşme + checkpoint dosyası. Varsayım yerine kanıt; negatif iddia varsa
   codebase-memory coverage kontrolü yap.
2. Kullanıcının verdiği uygulama görevi, kapsam içindeki gerekli dosya
   düzenlemelerini (kod, migration, DB) kapsar — her düzenlemede tekrar onay
   istenmez. Salt-okunur analiz görevleri salt-okunur kalır; izin/production
   sınırları ve permission guard GEVŞETİLMEZ. **COMMIT/PUSH KESİNLİKLE YASAK.**
3. Production/remote ve bot entegrasyonu YASAK; `.env*`, `*.pem`, `*.key`,
   `secrets/**` okunmaz; ana stack (`supabase_db_yarisma-programi`) sıfırlanmaz;
   failover/sandbox ajanlarının dosyalarına dokunulmaz.
4. Yetki disiplini: bir görevde TEK ilgili ajan çalışır; üçü aynı anda koşmaz.
   Uzmanlık eşlemesi: mimari/trade-off → `engineering-software-architect`;
   DB/SQL/API/migration → `engineering-backend-architect`;
   UI/a11y/responsive/Türkçe → `engineering-frontend-developer`.
5. Test gevşetme/skip yasak; en küçük güvenli değişiklik; hata başına ≤3 kontrollü
   deneme → BLOCKED olarak raporla.

## Güncel Görev Checkpoint'i (2026-09-12)

- **Faz 11: KAPANDI.** Kod commit `def58d0`; CI run `34603306306` → SUCCESS.
- Ajan/hafıza paketinin kapanışı bekleniyor.
- **Faz 12: HENÜZ BAŞLAMADI** — açık "devam" onayı beklenir.
- Kanonik görev durumu: `docs/project/ai-handoff/current-task.json`; anlaşmazlık
  hâlinde faz raporu + git log gerçeği geçerlidir.

## İhtiyaç Halinde Okunan Çalışma Yönergeleri

- Mimari/tasarım: `docs/project/altin-kalemler-ana-sozlesme.md` (ürün sabitleri + faz
  planı) + codebase-memory graph (`search_graph` / `trace_path` / `get_code_snippet`).
- Kod (Next.js): bu Next sürümü standart eğitiminle aynı DEĞİL — sürüme bağlı veya
  belirsiz bir API kullanacağın zaman ilgili resmî belgeyi oku
  (`node_modules/next/dist/docs/`, üstteki `nextjs-agent-rules`); her görevde tüm
  belgeleri yeniden Okuma zorunluluğu yok.
- DB/SQL: `supabase/migrations/` zinciri + mevcut QA scriptleri; doğrulama benzersiz
  ad/port ile disposable ortamda, Docker envanter karşılaştırmalı.

<!-- END:ALTIN-KALEMLER-MUHENDISLIK-AJANLARI -->
