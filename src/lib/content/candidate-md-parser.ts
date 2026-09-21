/**
 * Markdown aday soru paketi deterministik ayrıştırıcı (Faz 22).
 *
 * Kurallar:
 *  - Yalnız `### AK-...` başlıklı bloklar aday kabul edilir.
 *  - Blok içinde metadata `**Etiket:** değer` biçiminde; etiket allowlist'i
 *    dar tutulmuştur (bkz. ALLOWED_MD_KEYS). Bilinmeyen etiket, tablo
 *    satırı, görev/PER satırı, geçersiz seçenek harfi ve blok dışı serbest
 *    metin "paket-dışı içerik" bulgusu olarak SAYILIR — içerik asla taşınmaz,
 *    yalnız tür ve satır numarası kaydedilir.
 *  - Seçenekler tek harfle başlayan satırlardır (A) ... A. ...).
 *  - Çözüm adımları `**Çözüm:**` görüldükten SONRA gelen "1. ..." satırlardır.
 *  - Soru metni, ilk seçenek satırına kadar toplanır.
 *  - Sınıf seviyesi `## N. sınıf` başlığından; yoksa `**Sınıf:**` etiketinden;
 *    yoksa kazanım kodundan (ör. MAT.9.1.1) türetilir.
 *  - Zorluk Türkçe etiketle (kolay/orta/zor) veya İngilizce adlarıyla
 *    MD_DIFFICULTY_ALIASES üzerinden normalleşir.
 *  - Ayrıştırıcı İÇERİK ÜRETMEZ: document'te olmayan hiçbir alan uydurulmaz.
 *    Ders adı (subject_ref) ve durum yalnız dökümandaki etiketlerden alınır.
 *
 * Deterministik: girdi aynıysa çıktı birebir aynıdır (harici durum yok).
 */

import type {
  CandidateMdPackageV11,
  CandidateMdParseResult,
  CandidateQuestionMdV11,
  MdOutOfPackageItem,
  MdOutOfPackageKind,
} from "./candidate-md-types"

import {
  CANDIDATE_MD_SCHEMA_VERSION,
  MD_DIFFICULTY_ALIASES,
} from "./candidate-md-types"

const AK_HEADING_RE = /^###\s+AK-([A-Za-z0-9][A-Za-z0-9-]*)\s*$/
const SECTION_GRADE_RE = /^##\s+(?:Sınıf\s*)?(\d{1,2})(?:\s|\.|$)/i
const ANY_HEADING_RE = /^#+\s/
const METADATA_RE = /^\*\*([^*]+):\*\*\s*(.*)$/
const OPTION_RE = /^([A-E])[.\)]\s*(.*)$/
const INVALID_LETTER_OPTION_RE = /^([F-Z])[.\)]\s/
const STEP_RE = /^(\d{1,2})[.\)]\s+(.*)$/
const BANNER_RE = /\*\*(Yayınlanamaz|Yayınlanabilir)[^*]*\*\*/i
const DIFFICULTY_RE = /\b(kolay|orta|zor|easy|medium|hard)\b/i
const SECONDS_RE = /(\d+)\s*(?:saniye|sn)/i
const KIND_RE = /^(?:\d{1,2}[.)]\s*)?(?:per|g[oö]rev|task)\b/i

interface BlockState {
  clientQuestionId: string
  startLine: number
  subjectRef: string | null
  grade: number | null
  outcomeCodes: string[]
  editorialSubtopic: string | null
  hasVisual: boolean | null
  questionText: string[]
  options: Partial<Record<string, string>>
  optionsSeen: boolean
  correctAnswer: string | null
  difficulty: string | null
  solveTimeSeconds: number | null
  method: string | null
  steps: CandidateQuestionMdV11["solution"]["steps"]
  result: string | null
  justification: string | null
  commonMistakes: string[]
  validationRequestedStatus: string | null
  inSolution: boolean
}

interface ParseContext {
  lines: string[]
  packageSubjectRef: string | null
  packageStatus: string | null
  producerId: string | null
  packageGrade: number | null
  publicationAllowed: boolean
  sectionGrade: number | null
  questions: CandidateQuestionMdV11[]
  outOfPackage: MdOutOfPackageItem[]
  notes: string[]
  activeBlock: BlockState | null
}

function isBlank(line: string): boolean {
  return line.trim() === ""
}

function isSeparator(line: string): boolean {
  return /^-{3,}\s*$/.test(line.trim())
}

function isTableRow(line: string): boolean {
  return line.trim().startsWith("|")
}

function extractOutcomeCodes(value: string): string[] {
  const out: string[] = []
  const seen = new Set<string>()
  for (const match of value.matchAll(/\b[A-Z]{2,}\.?[0-9]+(?:\.[0-9]+){1,}\b/g)) {
    const code = match[0]
    const trimmed = code.endsWith(".") ? code.slice(0, -1) : code
    if (!seen.has(trimmed)) {
      seen.add(trimmed)
      out.push(trimmed)
    }
  }
  return out
}

function gradeFromOutcomeCode(code: string | null): number | null {
  if (!code) return null
  const m = code.match(/\.([0-9]{1,2})(?:\.|$)/)
  if (!m) return null
  const grade = Number(m[1])
  return grade >= 1 && grade <= 12 ? grade : null
}

function buildQuestion(state: BlockState, context: ParseContext): CandidateQuestionMdV11 {
  const codes = state.outcomeCodes
  const primary = codes.length === 1 ? codes[0] : null
  const additional = codes.length > 1 ? codes.slice(1) : []

  const grade = state.grade ?? context.sectionGrade ?? gradeFromOutcomeCode(primary)

  if (grade === null) {
    context.notes.push(
      `soru_${state.clientQuestionId}: sınıf seviyesi bulunamadı`
    )
  }

  return {
    client_question_id: state.clientQuestionId,
    grade_level: grade,
    subject_ref: state.subjectRef ?? context.packageSubjectRef,
    subject_id: null,
    outcome_code: primary,
    additional_outcome_codes: additional,
    editorial_subtopic: state.editorialSubtopic,
    has_visual: state.hasVisual,
    question_text: state.questionText.join(" ").trim(),
    options: state.options,
    correct_answer: state.correctAnswer,
    difficulty: state.difficulty,
    cognitive_type: null,
    estimated_solve_time_seconds: state.solveTimeSeconds,
    solution: {
      method: state.method,
      steps: state.steps,
      result: state.result,
      correctAnswerJustification: state.justification,
      commonMistakes: state.commonMistakes,
    },
    validation_requested_status: state.validationRequestedStatus,
  }
}

function addOutOfPackage(
  context: ParseContext,
  kind: MdOutOfPackageKind,
  line: number
): void {
  context.outOfPackage.push({ kind, line })
}

function finalizeBlock(context: ParseContext): void {
  if (!context.activeBlock) return
  context.questions.push(buildQuestion(context.activeBlock, context))
  context.activeBlock = null
}

function handlePackageMetadata(
  context: ParseContext,
  key: string,
  value: string,
  line: number
): void {
  const normalized = key.trim().toLowerCase()
  if (normalized === "ders") {
    context.packageSubjectRef = value.trim() || null
  } else if (normalized === "durum") {
    context.packageStatus = value.trim().toLowerCase() || null
  } else if (normalized === "üretici") {
    context.producerId = value.trim() || null
  } else if (normalized === "sınıf") {
    const g = Number(value.trim())
    if (Number.isInteger(g) && g >= 1 && g <= 12) context.packageGrade = g
  } else {
    addOutOfPackage(context, "unknown_metadata_line", line)
  }
}

function handleQuestionMetadata(
  state: BlockState,
  key: string,
  value: string,
  context: ParseContext,
  line: number
): void {
  const normalized = key.trim().toLowerCase()
  const v = value.trim()
  switch (normalized) {
    case "kapsam": {
      const parts = v.split("·").map((p) => p.trim())
      state.outcomeCodes.push(...extractOutcomeCodes(v))
      if (parts.length > 1) {
        state.editorialSubtopic = parts.slice(1).join(" · ") || null
      }
      break
    }
    case "ders":
      state.subjectRef = v || null
      break
    case "tahmin": {
      const difficultyMatch = v.match(DIFFICULTY_RE)
      if (difficultyMatch) {
        state.difficulty =
          MD_DIFFICULTY_ALIASES[difficultyMatch[1].toLowerCase()] ?? null
      }
      const secondsMatch = v.match(SECONDS_RE)
      if (secondsMatch) state.solveTimeSeconds = Number(secondsMatch[1])
      break
    }
    case "doğru cevap":
    case "doğru seçenek": {
      const m = v.match(/([A-E])/)
      if (m) state.correctAnswer = m[1].toUpperCase()
      break
    }
    case "çözüm":
      state.inSolution = true
      break
    case "çeldirici odağı":
      if (v) state.commonMistakes.push(v)
      break
    case "durum":
      state.validationRequestedStatus = v.toLowerCase() || null
      break
    case "sınıf": {
      const g = Number(v)
      if (Number.isInteger(g) && g >= 1 && g <= 12) state.grade = g
      break
    }
    case "yöntem":
      state.method = v || null
      break
    case "sonuç":
      state.result = v || null
      break
    case "gerekçe":
      state.justification = v || null
      break
    case "görsel":
      state.hasVisual = /^(var|evet|e)\b/i.test(v)
      break
    default:
      addOutOfPackage(context, "unknown_metadata_line", line)
  }
}

function processBlockLine(
  context: ParseContext,
  line: string,
  lineNumber: number
): void {
  const state = context.activeBlock as BlockState
  const trimmed = line.trim()

  if (isSeparator(trimmed) || isBlank(trimmed)) return

  if (isTableRow(trimmed)) {
    addOutOfPackage(context, "table_row", lineNumber)
    return
  }

  const metadata = trimmed.match(METADATA_RE)
  if (metadata) {
    handleQuestionMetadata(state, metadata[1], metadata[2], context, lineNumber)
    return
  }

  const invalidOption = trimmed.match(INVALID_LETTER_OPTION_RE)
  if (invalidOption) {
    addOutOfPackage(context, "invalid_option_letter", lineNumber)
    return
  }

  const option = trimmed.match(OPTION_RE)
  if (option) {
    state.options[option[1].toUpperCase()] = option[2].trim()
    state.optionsSeen = true
    return
  }

  if (KIND_RE.test(trimmed)) {
    addOutOfPackage(context, "task_or_per_line", lineNumber)
    return
  }

  const step = trimmed.match(STEP_RE)
  if (state.inSolution && step) {
    const text = step[2].trim()
    state.steps.push({
      title: `Adım ${state.steps.length + 1}`,
      content: text,
    })
    return
  }

  if (!state.optionsSeen) {
    state.questionText.push(trimmed)
    return
  }

  addOutOfPackage(context, "unparsed_question_content", lineNumber)
}

function handleHeading(
  context: ParseContext,
  line: string,
  lineNumber: number
): void {
  const trimmed = line.trim()

  const ak = trimmed.match(AK_HEADING_RE)
  if (ak) {
    finalizeBlock(context)
    context.activeBlock = {
      clientQuestionId: ak[1],
      startLine: lineNumber,
      subjectRef: null,
      grade: context.packageGrade,
      outcomeCodes: [],
      editorialSubtopic: null,
      hasVisual: null,
      questionText: [],
      options: {},
      optionsSeen: false,
      correctAnswer: null,
      difficulty: null,
      solveTimeSeconds: null,
      method: null,
      steps: [],
      result: null,
      justification: null,
      commonMistakes: [],
      validationRequestedStatus: null,
      inSolution: false,
    }
    return
  }

  finalizeBlock(context)

  const section = trimmed.match(SECTION_GRADE_RE)
  if (section) {
    const g = Number(section[1])
    if (g >= 1 && g <= 12) context.sectionGrade = g
    return
  }

  addOutOfPackage(context, "unknown_heading", lineNumber)
}

function handleOutsideBlock(
  context: ParseContext,
  line: string,
  lineNumber: number
): void {
  const trimmed = line.trim()

  if (isSeparator(trimmed) || isBlank(trimmed)) return

  const banner = trimmed.match(BANNER_RE)
  if (banner) {
    if (banner[1] === "Yayınlanabilir") context.publicationAllowed = true
    if (/needs_review/i.test(trimmed)) context.packageStatus = "needs_review"
    return
  }

  if (trimmed.startsWith("#")) {
    handleHeading(context, line, lineNumber)
    return
  }

  const metadata = trimmed.match(METADATA_RE)
  if (metadata) {
    handlePackageMetadata(context, metadata[1], metadata[2], lineNumber)
    return
  }

  if (isTableRow(trimmed)) {
    addOutOfPackage(context, "table_row", lineNumber)
    return
  }

  if (KIND_RE.test(trimmed)) {
    addOutOfPackage(context, "task_or_per_line", lineNumber)
    return
  }

  addOutOfPackage(context, "free_text_outside_block", lineNumber)
}

/**
 * Markdown dokümanını deterministik bir v1.1 aday paketine ayrıştırır.
 * DB erişimi YOKTUR. Üretici bilgisi dökümanda YOKSA null bırakılır ve
 * preflight tarafından reddedilir (uydurma yok).
 */
export function parseCandidateMd(document: string): CandidateMdParseResult {
  const lines = (document ?? "").split(/\r?\n/)
  const context: ParseContext = {
    lines,
    packageSubjectRef: null,
    packageStatus: null,
    producerId: null,
    packageGrade: null,
    publicationAllowed: false,
    sectionGrade: null,
    questions: [],
    outOfPackage: [],
    notes: [],
    activeBlock: null,
  }

  lines.forEach((rawLine, i) => {
    const lineNumber = i + 1
    const line = rawLine.replace(/\r$/, "")

    if (isBlank(line)) return

    if (context.activeBlock) {
      if (ANY_HEADING_RE.test(line)) {
        handleHeading(context, line, lineNumber)
      } else {
        processBlockLine(context, line, lineNumber)
      }
      return
    }

    handleOutsideBlock(context, line, lineNumber)
  })

  // Kapanmayan blok
  if (context.activeBlock) {
    context.questions.push(buildQuestion(context.activeBlock, context))
    context.activeBlock = null
  }

  const rootErrors: string[] = []
  if (context.questions.length === 0) {
    rootErrors.push("no_candidate_blocks_found")
  }

  const packageData: CandidateMdPackageV11 = {
    schema_version: CANDIDATE_MD_SCHEMA_VERSION,
    origin: "curriculum_original",
    producer: context.producerId ? { id: context.producerId } : null,
    subject_ref: context.packageSubjectRef,
    validation_requested_status: context.packageStatus ?? "needs_review",
    publication_allowed: context.publicationAllowed,
    is_active: false,
    questions: context.questions,
    metadata: {
      out_of_package_count: context.outOfPackage.length,
      out_of_package_kinds: summarizeKinds(context.outOfPackage),
    },
  }

  return {
    ok: rootErrors.length === 0,
    root_errors: rootErrors,
    package: packageData,
    out_of_package: context.outOfPackage,
    out_of_package_count: context.outOfPackage.length,
    parse_notes: context.notes,
  }
}

function summarizeKinds(items: MdOutOfPackageItem[]): string[] {
  const counts = new Map<MdOutOfPackageKind, number>()
  for (const item of items) {
    counts.set(item.kind, (counts.get(item.kind) ?? 0) + 1)
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([kind, count]) => `${kind}:${count}`)
}