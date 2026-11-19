# AK-SEC-GRADE-04 — Auth Callback Patch Kontrollü Canlı Kod Aktarımı

**Görev:** AK-SEC-GRADE-03'de doğrulanmış yamanın açık onaylı, tek seferlik canlı çalışma
ağacı aktarımı · **Önceki faz:** AK-SEC-GRADE-03 PASS/GO
**Sonuç:** **PASS — aktarım tamamlandı, canlı uygulama sağlıklı, canlı DB'de zero değişim** · GÜVENLİ DUR

Kanıt dizini: `/tmp/opencode/ag04-evidence/` (0700, dosyalar 0600; Git dışı)

---

## 1. Ön Kontrol — PASS (P1–P12)

| # | Kontrol | Sonuç |
|---|---|---|
| P1 | Dizin = git toplevel (`/home/selami/yarisma-programi`) | PASS |
| P2 | HEAD `f3ba0373…` değişmedi; dirty 699 giriş kaydedildi (`02_status_once.txt`) | PASS |
| P3 | Hedef dosyaların önce SHA-256'sı kaydedildi (aşağıda) | PASS |
| P4 | Patch SHA-256: `e122f79b6de24fa2f6f1fa468fa2031f4e4367c48aff49ff6044450d026c6543` | PASS |
| P5/P5b | Blob ön-görüntüleri (`403dd72`/`1224573`) patch index başlıklarıyla birebir; patch, GRADE-03'ün doğrulanmış izole kopyasından yeniden üretildi → **BYTE_BIREBIR_ES** | PASS |
| P6 | Patch yalnız 2 izinli dosyayı etkiliyor (`route.ts`, `route.test.ts`) | PASS |
| P7 | `git apply --check` → OK (ön kontrolde ve uygulama anında taze) | PASS |
| P8 | WIP: `route.ts` zaten `M` (Eyl-4 satır-ucu WIP; `ignoreDuplicates` 0 kez → düzeltme önceden YOK); `route.test.ts` temiz. Patch pre-görüntüsü bu WIP haliyle birebir → **çakışma YOK** | PASS |
| P9 | Salt-okunur canlı DB: hist **max=165, h166=0** | PASS |
| P10 | 3000: `next-server v16.3.8` pid 3901927 (ağaç 3901914/3901915/3901927, 17 Kas 14:11:33 başlangıç) — görev öncesiyle aynı kimlik, sağlıklı dinliyor | PASS |
| P11 | `.env.local` okuma kanalı motor tarafından engelli → **değer okunmadı/okunmayacak**; bağlantı canlı smoke ile doğrulandı (bkz. §8; sınırlı-kosul, smoke ile kapandı) | PASS(kosullu) |
| P12 | `next dev` aktif → hot-reload gözlendi (§7), restart yok | PASS |

## 2–3. SHA-256 Değerleri (önce → sonra)

| Dosya | Önce | Sonra |
|---|---|---|
| `route.ts` | `a126f8a2db384a0454c45819369e1dc60f63e5351aa4d46e824127f4a85dd168` | `376a7600d5d61a6a82416bd41e8d2b490b88399bd09049b5df94227abe03db35` |
| `route.test.ts` | `ebd2995e1b3165edbcd56240f90914c713c2a6170c0373ff1b793d97b71e3957` | `5777f91fc7d060ce7d8d28419a38ed27716a965867fde0525b6624c6cb0c3a70` |

- Uygulama anında SHA-kayması kontrolü → **yok**; `ALREADY_APPLIED` → **hayır** (bayrak önceden yoktu, tek uygulama).
- Her iki dosya uygulama sonrası **GRADE-03'ün test edilmiş kopyasıyla bayt bayt aynı** (`diff` boş) — doğrulanmamış ara durum yok.

## 4. Değişen Dosyaların Tam Listesi

`git status --porcelain` önce/sonra delta'sı = **tek satır**: `M src/app/(auth)/auth/callback/route.test.ts`
(`route.ts` zaten M-WIP girişteydi; içerik değişikliği yamadan geldi.) Başka hiçbir dosya
değişmedi — vitest/tsc/eslint koşumları da iz bırakmadı (`02_status_final.txt`).

## 5. WIP Koruma Kanıtı

- Yedekler: `/tmp/opencode/ag04-evidence/route.ts.bak` + `route.test.ts.bak` — kaynakla
  **SHA-256 birebir** (`sha_once.txt` ↔ `sha_bak.txt`), kullanıcı WIP halini (satır uçları)
  olduğu gibi içerir, Git izlenmeyen 0700 dizinde, kaynak dosyalardan ayrı adlandırma (`.bak`).
- Kullanıcının diğer ~697 WIP girişine dokunulmadı (status delta tek satır).
- Geri dönüş gerekmedi; gerekirse tek güvenli yol: `.bak` dosyalarının geri konması + SHA teyidi.

## 6. Test Sonuçları (canlı ağaçta)

| Kontrol | Sonuç |
|---|---|
| `route.test.ts` (vitest) | **10/10 PASS** — sözleşme kilidi (`ignoreDuplicates:true` beklemesi) dahil davranış testi |
| `tsc --noEmit --incremental false` | **rc=0** (tsbuildinfo'ya dokunulmadı) |
| ESLint (iki dosya) | **rc=0** |
| 166 güvenlik (E1–E10, N-1…N-8) ve 165 kota (qa165 50/50) | GRADE-03/02 kanıtları referans — bu görevde SQL/migration kaynakları değişmedi (yalnız 2 TS dosyası), tekrarlanmadı (görev m.8) |

## 7. Hot-Reload ve Next.js Süreç Kimliği

- Aynı süreç ağacı kesintisiz: pid 3901914/3901915/3901927, `etime` sürekliliği (restart YOK, kill YOK).
- `GET /auth/callback` (codesuz → exchange/DB yoluna girmeden erken dönmesi garanti) →
  **307 `/login?error=auth_callback`**: route yeni kodla derlenip servis edildi.
- Kanıt: `.next/static/chunks/3y07x_ao-ksd_.js`, `.next/server/chunks/_1phn2mr._.js`,
  `.next/server/chunks/ssr/_0k0enk8._.js` içinde `ignoreDuplicates` mevcut.
- Hot-reload başarısızlığı/temizleme ihtiyacı doğmadı; `.next` silinmedi.

## 8. HTTP Smoke + Servis Sağlığı

| Uç | Sonuç |
|---|---|
| `/login` | 200 |
| `/competition` (korumalı) | 307 → `/login` (auth redirect doğru) |
| `/dashboard` (korumalı) | 307 → `/login` |
| `/auth/callback` (sahte OAuth kodu GÖNDERİLMEDİ) | 307 → `/login?error=auth_callback` |
| Supabase stack | 5/5 konteyner Up; `db` ve `kong` healthy — uygulama→Kong→DB yolu smoke'ta canlı |
| Log | Dev stdout dosyaya yazılmıyor (doğrudan `sh -c next dev`); yeni hata kanıtı yerine HTTP 200/307 yanıtları + derlenmiş chunk'lar + konteyner sağlığı kullanıldı; rapor hiçbir secret/cookie/token değeri içermiyor |

## 9–10. Canlı DB Değişmezlik + 166 Kanıtı

Aktarım sonrası salt-okunur ölçüm (önce ölçümle birebir):
`auth.users=9 · student_profiles=7 · profilsiz=2 · queue=1 · kota_events=0 ·
hist max=165 · h166=0` → **canlı DB'de tek satır değişmedi; Migration 166 uygulanmadı**
(taslak dosyası da değişmedi — migration klasörlerinde delta yok).

## 11. PASS / FAIL / GAP

- **PASS:** Ön kontrol · patch kimliği · uygulama (tek apply, hunk farkı yok) · WIP koruma ·
  hot-reload · smoke · DB değişmezlik · dar regresyon (10/10, tsc 0, eslint 0).
- **FAIL:** yok.
- **GAP:** yok (P11 kanal kısıtı smoke ile kapatıldı; yeni GAP açılmadı).
  GAP-SEC-G03 artık **KAPANDI** (kod canlı ağaçta). GAP-SEC-01 canlıda hâlâ
  AÇIK — kapanışı Migration 166'nın uygulanmasına bağlı.

## 12. Sonraki Aşama — GO / NO-GO

**GO — Migration 166 canlı uygulaması teknik olarak hazır.** Uygulama tarafı
(GAP-SEC-G03) kapandı; BC kanıtı yamanın pre-166 şemasında da çalıştığını gösterdiği için
sıra güvenli: sıradaki tek adım **AK-SEC-GRADE-02 rapor §5 planıyla Migration 166 canlı
uygulaması** — bu **ayrı açık kullanıcı onayı** gerektirir (yedek + SHA + FINAL_166 +
salt-okunur post-kanıtlar). Ayrıca commit/push hâlâ ayrı izin bekliyor (bu görevde
`git add/commit` yapılmadı; iki dosya WIP olarak çalışma ağacında).
