/**
 * Faz 4 admin paneli genel mesaj ve etiketleri.
 *
 * Salt-okunur görünümler için kullanılan sabit metinler. Genişletilebilir
 * görünümler (kullanıcı yönetimi vb.) bu fazda veri erişimi olmadığı için
 * eklenmemiştir; ilgili görünüm eklendiğinde buraya etiketi eklenir.
 */

export const ADMIN_GENERAL_MESSAGES = {
  genericError:
    "Yönetim paneli verisi yüklenirken bir sorun oluştu. Lütfen tekrar deneyin.",
  unauthorizedRedirect: "Bu sayfayı görüntülemek için giriş yapmalısınız.",
  noPermission: "Bu sayfayı görüntülemek için yetkiniz yok.",
} as const

export const ADMIN_DASHBOARD_MESSAGES = {
  title: "Yönetim Paneli",
  subtitle:
    "Altın Kalemler yönetim kontrol paneli. Salt-okunur özet ve gezinme.",
  publishedQuestions: "Yayındaki sorular",
  publishedQuestionsHint:
    "Onaylanmış ve aktif soru bankasından okunur (öğrencilerin gördüğü küme).",
  reviewQueue: "İnceleme kuyruğu",
  stagingQuestions: "Staging sorular",
  tyt: "TYT",
  ayt: "AYT",
  metricUnavailable:
    "Bu metrik şu an okunamıyor. Veri erişimi bu ölçümü desteklemiyor.",
  usersCount: "Toplam kullanıcı",
  navTitle: "Bölümler",
} as const

export const ADMIN_NAV_ITEMS = [
  {
    title: "Soru Bankası",
    description: "Yayındaki soruları listele, filtrele ve görüntüle (salt okunur).",
    href: "/admin/questions",
  },
  {
    title: "Akademik Takvim",
    description: "Akademik yıl ve hafta kayıtlarını yönetin.",
    href: "/admin/academic-calendar",
  },
  {
    title: "Kullanıcılar",
    description: "Kayıtlı kullanıcıları listele ve görüntüle (salt okunur).",
    href: "/admin/users",
  },
  {
    title: "Öğretmen İncelemeleri",
    description: "Öğretmen inceleme akışına erişin.",
    href: "/admin/teacher-reviews",
  },
] as const

export const ADMIN_QUESTIONS_MESSAGES = {
  title: "Soru Bankası",
  subtitle:
    "Yetkili yönetici için tüm soru yaşam döngüsü durumları. Salt-okunur görünüm; düzenleme bu fazda yapılmaz.",
  backToDashboard: "Panele dön",
  empty: "Bu filtrelerle eşleşen soru bulunamadı.",
  filterLabel: "Filtrele",
  allExamTracks: "Tüm sınavlar",
  allGrades: "Tüm sınıflar",
  allDifficulties: "Tüm zorluklar",
  allSubjects: "Tüm dersler",
  allApprovalStatuses: "Tüm durumlar",
  allActivity: "Tümü",
  approvalStatusLabel: "Onay durumu",
  isActiveLabel: "Aktiflik",
  statusApproved: "Onaylı",
  statusPending: "Beklemede",
  statusDraft: "Taslak",
  statusRejected: "Reddedildi",
  activeYes: "Aktif",
  activeNo: "Pasif",
  difficultyEasy: "Kolay",
  difficultyMedium: "Orta",
  difficultyHard: "Zor",
  subjectLabel: "Ders",
  examTrackLabel: "Sınav",
  gradeLabel: "Sınıf",
  difficultyLabel: "Zorluk",
  questionCode: "Soru kodu",
  searchLabel: "Ara (soru kodu veya metni)",
  listError:
    "Soru listesi şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  detailError:
    "Soru bilgileri şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  subjectLoadError:
    "Ders listesi şu anda okunamadı; ders filtresi geçici olarak kullanılamıyor.",
  sortLabel: "Sıralama",
  sortNewest: "En yeni",
  sortOldest: "En eski",
  paginationLabel: "Sayfalama",
  prevPage: "Önceki",
  nextPage: "Sonraki",
  copyrightRisk: "Telif riski",
  noCorrectAnswer: "Doğru cevap yok",
  noQuestionText: "Soru metni yok",
} as const

export const ADMIN_QUESTION_DETAIL_MESSAGES = {
  notFound: "Soru bulunamadı.",
  detailError:
    "Soru bilgileri şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  backToList: "Soru listesine dön",
  optionsTitle: "Seçenekler",
  metadataTitle: "Künye",
  subject: "Ders",
  grade: "Sınıf",
  examTrack: "Sınav",
  difficulty: "Zorluk",
  difficultyEasy: "Kolay",
  difficultyMedium: "Orta",
  difficultyHard: "Zor",
  correctAnswer: "Doğru cevap",
  solveTime: "Tahmini çözüm süresi",
  solveTimeUnit: "sn",
  qualityLevel: "Kalite seviyesi",
  ownership: "Sahiplik durumu",
  license: "Lisans durumu",
  approvalStatus: "Onay durumu",
  activeStatus: "Aktiflik",
  statusApproved: "Onaylı",
  statusPending: "Beklemede",
  statusDraft: "Taslak",
  statusRejected: "Reddedildi",
  activeYes: "Aktif",
  activeNo: "Pasif",
  noQuestionText: "Soru metni yok",
} as const

export const ADMIN_USERS_MESSAGES = {
  title: "Kullanıcılar",
  subtitle:
    "Kayıtlı kullanıcı listesi. Salt-okunur görünüm; düzenleme bu fazda yapılmaz.",
  backToDashboard: "Panele dön",
  empty: "Bu filtrelerle eşleşen kullanıcı bulunamadı.",
  notFound: "Kullanıcı bulunamadı.",
  searchLabel: "Ara (takma ad)",
  gradeLabel: "Sınıf",
  allGrades: "Tüm sınıflar",
  filterLabel: "Filtrele",
  nickname: "Takma ad",
  grade: "Sınıf",
  created: "Kayıt tarihi",
  points: "Puan",
  monthlyPoints: "Aylık puan",
  visibility: "Görünürlük",
  visible: "Görünür",
  hidden: "Gizli",
  notSet: "Belirtilmemiş",
  detailTitle: "Kullanıcı Detayı",
  backToList: "Kullanıcı listesine dön",
  profileFields: "Profil Bilgileri",
  leagueInfo: "Liga Bilgisi",
  league: "Liga",
  character: "Karakter",
  avatar: "Avatar",
  noLeague: "Lig ataaması yok",
  noCharacter: "Karakter belirtilmemiş",
  noAvatar: "Avatar belirtilmemiş",
  gradeLevel: "Sınıf seviyesi",
  lastUpdated: "Son güncelleme",
  classYears: "Sınıf",
  listError:
    "Kullanıcı listesi şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  detailError:
    "Kullanıcı bilgileri şu anda okunamadı. Lütfen daha sonra tekrar deneyin.",
  sortLabel: "Sıralama",
  sortNewest: "En yeni",
  sortOldest: "En eski",
  paginationLabel: "Sayfalama",
  prevPage: "Önceki",
  nextPage: "Sonraki",
} as const
