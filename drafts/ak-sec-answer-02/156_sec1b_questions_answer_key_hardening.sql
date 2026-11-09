-- ============================================================
-- 156_sec1b_questions_answer_key_hardening.sql
-- AK-SEC-ANSWER-02: SEC-1b — public.questions cevap anahtarı
-- tablo-okuma yüzeyinin kapatılması (en dar güvenli dilim)
-- ============================================================
-- ÖN KOŞUL / UYGULAMA SIRASI:
--   155_sec1_answer_key_acl.sql (SEC-1, fonksiyon ACL) ÖNCE uygulanır;
--   bu migration hemen arkasından SAME oturumda koşar. İki migration
--   arasındaki açıklık süresi sıfıra yakın tutulur (tek koşum komutunda
--   art arda uygulanabilir; arada SELECT açığı SEC-1 fonksiyon açığından
--   bağımsızdır, sıralık risk taşımaz).
--
-- SÖZLEŞME:
--   1) İdempotent: tekrar uygulanması sonucu değiştirmez.
--   2) Fail-closed: sonda beklenen matris assert edilir; sapma varsa
--      migration EXCEPTION ile düşer (tek transaction, iz bırakmaz).
--   3) Tek transaction: -1 ile koşulur.
--   4) YENİ GRANT YOK. Fonksiyon/tablo silme yok. Veri değişmez.
--      service_role ve postgres ayrıcalıklarına DOKUNULMAZ.
--
-- KANIT GEREKÇESİ (2026-11-09 salt-okunur canlı denetimi):
--   a) Öğrencinin doğrudan tablo okuması KODDA YOK:
--      src genelinde from("questions") yalnız src/lib/admin/question-bank.ts
--      ve src/lib/admin/admin-dashboard.ts (yönetici modülleri).
--      Öğrenci okuma yollarının tümü SECURITY DEFINER RPC zinciridir:
--      public.get_current_competition_question → private.* (definer, owner),
--      select_training_questions / submit_training_attempt (definer),
--      payload: private.get_competition_question_payload (hassas anahtar
--      blocklist'li). Definer zinciri owner hakkıyla koşar; bu migration
--      anon/authenticated tablo haklarını daraltsa da BOZULMAZ.
--   b) Yönetici paneli DOĞRUDAN SELECT yapar ve correct_answer kolonunu
--      okur (QUESTION_LIST_COLUMNS) → authenticated SELECT HAKKI KALIR;
--      satır görünürlüğü RLS ile yöneticiye sabitlenir.
--   c) Yönetici YAZMALARI private.admin_question_edit (DEFINER, izin
--      kapılı, 089/122) üzerinden; doğrudan tablo INSERT/UPDATE/DELETE
--      kullanıcısı YOK (095 testleri + grep kanıtı). Yazma hakları alınır.
--   d) questions_student_read (004_questions_foundation) approved+active
--      SATIRLARIN TÜM 30 KOLONUNU (correct_answer dahil) her
--      authenticated kullanıcıya açıyordu; 087admin politikayı bilinçli
--      korumuştu. Bugün meşru okuyucusu kalmadığı için BU migration'da
--      KASITLI olarak düşürülür (ürün kararı: öğrenci soruyu yalnız RPC
--      sanitized payload üzerinden görür).
--   e) Kolon düzeyde kayıtlı ek yetkiler (anon+authenticated, 30/30
--      kolonda SELECT/INSERT/UPDATE/REFERENCES) tablo REVOKE'undan
--      BAĞIMSIZDIR; ayrı temizlenir. (Tablo SELECT'i dururken kolon
--      REVOKE'u semptomu tek başına çözmezdi; tersi de yetmezdi —
--      politika + tablo + kolon birlikte kapatılır.)
--
-- ROLLBACK (yalnız açıkça yetkili işlem — yönetici kararı):
--   GRANT SELECT ON public.questions TO authenticated;
--   CREATE POLICY questions_student_read ON public.questions
--     FOR SELECT TO authenticated
--     USING (approval_status = 'approved' AND is_active = true);
--   (Eski kolon-kayıt drifti geri EKLENMEZ; rollback semptomu kapatır.)
-- ============================================================

-- ------------------------------------------------------------
-- 1) Öğrencinin doğrudan tablo-okuma politikası kaldırılır.
--    Kalan tek okuma politikası:
--    'question admins read all questions' (questions.view yöneticisi).
--    → authenticated öğrenci: 0 satır. anon: zaten 0 satır + 0 hak.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS questions_student_read ON public.questions;

-- ------------------------------------------------------------
-- 2) anon: questions üzerinde TAM yetki iptali (meşru erişimi yok).
-- ------------------------------------------------------------
REVOKE ALL ON public.questions FROM anon;

-- ------------------------------------------------------------
-- 3) authenticated: en az ayrıcalık — yalnız SELECT (yönetici paneli
--    doğrudan okuması; satırlar RLS ile questions.view yöneticisinde).
--    Yazma TRUNCATE/REFERENCES/TRIGGER driftten geri gelmişti → alınır.
--    MAINTAIN (PG17 bakım hakkı) de hijyenen alınır; veri okuma hakkı
--    değildir ama sözleşme "yalnız SELECT" der.
-- ------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON public.questions FROM authenticated;

-- PUBLIC'e kayıtlı hak yok; hijyen için yine de garanti edilir.
REVOKE ALL ON public.questions FROM PUBLIC;

-- ------------------------------------------------------------
-- 4) Kolon düzeyinde KAYITLI ek yetki kayıtlarının temizliği.
--    (Tablo REVOKE'u kolon kayıtlarını silmez; PG'de kolon yetkileri
--    ekleyicidir.)
--    QA BULGUSU (2026-11-09, izole kopyada deneysel kanıt):
--      a) REVOKE ALL (kolon) kalıbı kolon SELECT kaydını KALDIRMIYOR;
--         haklar tek tek adlandırılmalıdır.
--      b) authenticated'ın TÜM kolonlarındaki SELECT kayıtları geri
--         alınınca tablo düzeyi SELECT de düşüyor (eş-yaratım bağımlılığı).
--         Yönetici paneli SELECT'i zorunlu olduğundan authenticated'ın
--         kayıtlı kolon-SELECT kayıtlarına DOKUNULMAZ; yalnız YAZMA
--         (INSERT/UPDATE/REFERENCES) kolon kayıtları silinir.
--         Kalan 30 SELECT kaydı, tablo SELECT'iyle zaten aynı etkin
--         haktır ve RLS ile yönetici satırlarına kilitlidir — savunma
--         hattı politika katmanıdır (bkz. adım 1).
--      c) anon/public için 4 hakkın tamamı silinir (anon'da tablo hakkı
--         zaten yok; cascade riski yok).
-- ------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT grantee, column_name
      FROM information_schema.column_privileges
     WHERE table_schema = 'public'
       AND table_name   = 'questions'
       AND grantee IN ('anon','authenticated','public')
  LOOP
    IF r.grantee = 'authenticated' THEN
      EXECUTE format(
        'REVOKE INSERT, UPDATE, REFERENCES (%I) ON public.questions FROM authenticated',
        r.column_name);
    ELSE
      EXECUTE format(
        'REVOKE SELECT, INSERT, UPDATE, REFERENCES (%I) ON public.questions FROM %I',
        r.column_name, r.grantee);
    END IF;
  END LOOP;
END;
$$;

-- ------------------------------------------------------------
-- 5) FAIL-CLOSED ASSERT — beklenen son matris:
--    anon          : hiçbir hak yok (tablo + kolon kaydı 0)
--    authenticated : yalnız SELECT; INSERT/UPDATE/DELETE/TRUNCATE yok
--    service_role  : SELECT durur (dokunulmadı)
--    okuma politikası sayısı = 1, yalnız yönetici politikası
-- ------------------------------------------------------------
DO $$
DECLARE v_cnt int; v_pol text;
BEGIN
  IF has_table_privilege('anon','public.questions','SELECT')
     OR has_column_privilege('anon','public.questions','correct_answer','SELECT') THEN
    RAISE EXCEPTION 'SEC1B fail-closed: anon henuz questions okuyabiliyor'
      USING errcode='P0001';
  END IF;

  IF has_table_privilege('authenticated','public.questions','INSERT')
     OR has_table_privilege('authenticated','public.questions','UPDATE')
     OR has_table_privilege('authenticated','public.questions','DELETE')
     OR has_table_privilege('authenticated','public.questions','TRUNCATE')
     OR has_table_privilege('authenticated','public.questions','MAINTAIN') THEN
    RAISE EXCEPTION 'SEC1B fail-closed: authenticated yazma/tehlikeli haklari duruyor'
      USING errcode='P0001';
  END IF;

  IF NOT has_table_privilege('authenticated','public.questions','SELECT') THEN
    RAISE EXCEPTION 'SEC1B fail-closed: yonetici paneli SELECT hakki kaybedildi'
      USING errcode='P0001';
  END IF;

  IF NOT has_table_privilege('service_role','public.questions','SELECT') THEN
    RAISE EXCEPTION 'SEC1B fail-closed: service_role SELECT hakki kaybedildi'
      USING errcode='P0001';
  END IF;

  SELECT count(*) INTO v_cnt
    FROM information_schema.column_privileges
   WHERE table_schema='public' AND table_name='questions'
     AND (grantee IN ('anon','public')
          OR (grantee = 'authenticated' AND privilege_type <> 'SELECT'));
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'SEC1B fail-closed: yazma/anon kolon kiriligi kaldi: % kayit', v_cnt
      USING errcode='P0001';
  END IF;

  SELECT count(*) INTO v_cnt
    FROM pg_policy
   WHERE polrelid='public.questions'::regclass AND polcmd IN ('r','*');
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'SEC1B fail-closed: okuma politikasi sayisi % (beklenen 1)', v_cnt
      USING errcode='P0001';
  END IF;

  SELECT polname INTO v_pol
    FROM pg_policy
   WHERE polrelid='public.questions'::regclass AND polcmd IN ('r','*')
   LIMIT 1;
  IF v_pol IS DISTINCT FROM 'question admins read all questions' THEN
    RAISE EXCEPTION 'SEC1B fail-closed: kalan politika % (beklenen yonetici politikasi)',
      coalesce(v_pol,'<YOK>') USING errcode='P0001';
  END IF;

  RAISE NOTICE 'SEC1B OK: questions ACL+RLS matrisi beklenen durumunda';
END;
$$;
