import fs from "node:fs";
import path from "node:path";
import ExcelJS from "exceljs";
import { createClient } from "@supabase/supabase-js";

type TopicLookup = {
  gradeLevel: number;
  subjectName: string;
  topicCode: string;
  topicName: string;
};

type ImportPayload = {
  import_batch_id: string;
  source_row_number: number;
  raw_data: Record<string, unknown>;

  raw_exam_track: string | null;
  raw_grade_level: string | null;
  raw_subject_name: string | null;

  raw_topic_code: string | null;
  raw_topic_name: string | null;

  raw_test_code: string | null;
  raw_question_number: string | null;

  raw_answer: string | null;
  raw_difficulty: string | null;
  raw_quality_level: string | null;
  raw_cognitive_type: string | null;

  raw_primary_question_type: string | null;
  raw_secondary_question_type: string | null;

  raw_new_generation: string | null;
  raw_link: string | null;

  metadata: Record<string, unknown>;
};

function loadEnvFile(filePath: string) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const content = fs.readFileSync(
    filePath,
    "utf8",
  );

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();

    if (
      !line ||
      line.startsWith("#") ||
      !line.includes("=")
    ) {
      continue;
    }

    const separatorIndex =
      line.indexOf("=");

    const key = line
      .slice(
        0,
        separatorIndex,
      )
      .trim();

    let value = line
      .slice(
        separatorIndex + 1,
      )
      .trim();

    if (
      (
        value.startsWith('"') &&
        value.endsWith('"')
      ) ||
      (
        value.startsWith("'") &&
        value.endsWith("'")
      )
    ) {
      value =
        value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] =
        value;
    }
  }
}

function cellValue(
  row: ExcelJS.Row,
  columnNumber: number,
): unknown {
  const cell =
    row.getCell(columnNumber);

  if (
    typeof cell.value === "object" &&
    cell.value !== null &&
    "result" in cell.value
  ) {
    return cell.value.result;
  }

  return cell.value;
}

function textValue(
  value: unknown,
): string | null {
  if (
    value === null ||
    value === undefined
  ) {
    return null;
  }

  const text =
    String(value).trim();

  return text || null;
}

function integerText(
  value: unknown,
): string | null {
  if (
    value === null ||
    value === undefined
  ) {
    return null;
  }

  if (
    typeof value === "number"
  ) {
    return String(
      Math.trunc(value),
    );
  }

  const text =
    String(value).trim();

  if (!text) {
    return null;
  }

  const numeric =
    Number(text);

  if (
    !Number.isFinite(numeric)
  ) {
    return text;
  }

  return String(
    Math.trunc(numeric),
  );
}

function parseLimit(
  value: string | undefined,
): number | "all" {
  if (!value) {
    return 10;
  }

  const normalized =
    value
      .trim()
      .toLowerCase();

  if (
    normalized === "all"
  ) {
    return "all";
  }

  const numeric =
    Number(normalized);

  if (
    !Number.isInteger(numeric) ||
    numeric <= 0
  ) {
    throw new Error(
      'Limit geçersiz. Örnek: 1000 veya "all".',
    );
  }

  return numeric;
}

function isQuestionRow(
  row: ExcelJS.Row,
): boolean {
  const testCode =
    textValue(
      cellValue(row, 10),
    );

  const questionNumber =
    integerText(
      cellValue(row, 11),
    );

  return Boolean(
    testCode &&
    questionNumber,
  );
}

async function getExactStatusCount(
  supabase: any,
  batchId: string,
  status: string,
): Promise<number> {
  const {
    count,
    error,
  } =
    await supabase
      .from(
        "excel_question_import_rows",
      )
      .select(
        "id",
        {
          count: "exact",
          head: true,
        },
      )
      .eq(
        "import_batch_id",
        batchId,
      )
      .eq(
        "normalization_status",
        status,
      );

  if (error) {
    throw new Error(
      `${status} sayısı okunamadı: ${error.message}`,
    );
  }

  return count ?? 0;
}

async function getExactBatchRowCount(
 supabase: any,
  batchId: string,
): Promise<number> {
  const {
    count,
    error,
  } =
    await supabase
      .from(
        "excel_question_import_rows",
      )
      .select(
        "id",
        {
          count: "exact",
          head: true,
        },
      )
      .eq(
        "import_batch_id",
        batchId,
      );

  if (error) {
    throw new Error(
      `Batch toplam satır sayısı okunamadı: ${error.message}`,
    );
  }

  return count ?? 0;
}

async function main() {
  loadEnvFile(
    path.resolve(
      process.cwd(),
      ".env.local",
    ),
  );

  const supabaseUrl =
    process.env
      .NEXT_PUBLIC_SUPABASE_URL;

  const serviceRoleKey =
    process.env
      .SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL bulunamadı.",
    );
  }

  if (!serviceRoleKey) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY bulunamadı.",
    );
  }

  const excelPath =
    process.argv[2];

  if (!excelPath) {
    throw new Error(
      "Excel dosya yolu eksik.",
    );
  }

  const limit =
    parseLimit(
      process.argv[3],
    );

  const resolvedExcelPath =
    path.resolve(
      excelPath,
    );

  if (
    !fs.existsSync(
      resolvedExcelPath,
    )
  ) {
    throw new Error(
      `Excel bulunamadı: ${resolvedExcelPath}`,
    );
  }

  const supabase =
    createClient(
      supabaseUrl,
      serviceRoleKey,
      {
        auth: {
          persistSession:
            false,

          autoRefreshToken:
            false,
        },
      },
    );

  const workbook =
    new ExcelJS.Workbook();

  console.log(
    "Excel dosyası okunuyor...",
  );

  await workbook.xlsx.readFile(
    resolvedExcelPath,
  );

  const questionSheet =
    workbook.getWorksheet(
      "Soru verileri",
    );

  const topicSheet =
    workbook.getWorksheet(
      "KONU KODU",
    );

  if (!questionSheet) {
    throw new Error(
      '"Soru verileri" sayfası bulunamadı.',
    );
  }

  if (!topicSheet) {
    throw new Error(
      '"KONU KODU" sayfası bulunamadı.',
    );
  }

  // ==========================================================
  // TOPIC LOOKUP
  // ==========================================================

  const topicLookup =
    new Map<
      string,
      TopicLookup[]
    >();

  for (
    let rowNumber = 2;
    rowNumber <=
      topicSheet.rowCount;
    rowNumber += 1
  ) {
    const row =
      topicSheet.getRow(
        rowNumber,
      );

    const topicCode =
      integerText(
        cellValue(row, 6),
      );

    const subjectName =
      textValue(
        cellValue(row, 7),
      );

    const gradeText =
      integerText(
        cellValue(row, 8),
      );

    const topicName =
      textValue(
        cellValue(row, 9),
      );

    if (
      !topicCode ||
      !subjectName ||
      !gradeText ||
      !topicName
    ) {
      continue;
    }

    const gradeLevel =
      Number(gradeText);

    if (
      !Number.isInteger(
        gradeLevel,
      ) ||
      gradeLevel < 1 ||
      gradeLevel > 12
    ) {
      continue;
    }

    const existing =
      topicLookup.get(
        topicCode,
      ) ?? [];

    existing.push({
      gradeLevel,
      subjectName,
      topicCode,
      topicName,
    });

    topicLookup.set(
      topicCode,
      existing,
    );
  }

  // ==========================================================
  // QUESTION ROWS
  // ==========================================================

  const allQuestionRows:
    number[] = [];

  for (
    let rowNumber = 2;
    rowNumber <=
      questionSheet.rowCount;
    rowNumber += 1
  ) {
    const row =
      questionSheet.getRow(
        rowNumber,
      );

    if (
      isQuestionRow(row)
    ) {
      allQuestionRows.push(
        rowNumber,
      );
    }
  }

  const sourceRowNumbers =
    limit === "all"
      ? allQuestionRows
      : allQuestionRows.slice(
          0,
          limit,
        );

  if (
    sourceRowNumbers.length ===
    0
  ) {
    throw new Error(
      "Soru satırı bulunamadı.",
    );
  }

  console.log(
    `Excel'de bulunan soru satırı: ${allQuestionRows.length}`,
  );

  console.log(
    `Bu çalıştırmada işlenecek: ${sourceRowNumbers.length}`,
  );

  console.log(
    `Mod: ${
      limit === "all"
        ? "TÜMÜ"
        : limit
    }`,
  );

  // ==========================================================
  // IMPORT BATCH
  // ==========================================================

  const {
    data: batch,
    error: batchError,
  } =
    await supabase
      .from(
        "import_batches",
      )
      .insert({
        batch_type:
          "excel",

        status:
          "processing",

        total_items:
          sourceRowNumbers.length,

        processed_items:
          0,

        success_items:
          0,

        error_items:
          0,
      })
      .select("id")
      .single();

  if (
    batchError ||
    !batch
  ) {
    throw new Error(
      `Import batch oluşturulamadı: ${
        batchError?.message ??
        "bilinmeyen hata"
      }`,
    );
  }

  console.log("");
  console.log(
    `Import batch: ${batch.id}`,
  );
  console.log("");

  // ==========================================================
  // BULK INSERT
  //
  // 500 soru = 1 HTTP isteği.
  // ==========================================================

  const insertChunkSize =
    500;

  let insertedCount =
    0;

  for (
    let startIndex = 0;
    startIndex <
      sourceRowNumbers.length;
    startIndex +=
      insertChunkSize
  ) {
    const chunkRowNumbers =
      sourceRowNumbers.slice(
        startIndex,
        startIndex +
          insertChunkSize,
      );

    const payload:
      ImportPayload[] = [];

    for (
      const rowNumber
      of chunkRowNumbers
    ) {
      const row =
        questionSheet.getRow(
          rowNumber,
        );

      const rawExamTrack =
        textValue(
          cellValue(row, 1),
        );

      const rawPreparer =
        textValue(
          cellValue(row, 3),
        );

      const rawSourceType =
        textValue(
          cellValue(row, 4),
        );

      const rawBookName =
        textValue(
          cellValue(row, 5),
        );

      const rawSubjectName =
        textValue(
          cellValue(row, 6),
        );

      const rawPageNumber =
        integerText(
          cellValue(row, 8),
        );

      const rawTestNumber =
        integerText(
          cellValue(row, 9),
        );

      const rawTestCode =
        textValue(
          cellValue(row, 10),
        );

      const rawQuestionNumber =
        integerText(
          cellValue(row, 11),
        );

      const rawAnswer =
        textValue(
          cellValue(row, 12),
        );

      const rawTopicCode =
        integerText(
          cellValue(row, 13),
        );

      const rawPrimaryQuestionType =
        integerText(
          cellValue(row, 14),
        );

      const rawSecondaryQuestionType =
        integerText(
          cellValue(row, 15),
        );

      const rawCognitiveType =
        integerText(
          cellValue(row, 16),
        );

      const rawDifficulty =
        integerText(
          cellValue(row, 17),
        );

      const rawQuality =
        integerText(
          cellValue(row, 18),
        );

      const rawNewGeneration =
        textValue(
          cellValue(row, 19),
        );

      const rawLink =
        textValue(
          cellValue(row, 20),
        );

      const topicCandidates =
        rawTopicCode
          ? topicLookup.get(
              rawTopicCode,
            ) ?? []
          : [];

      const matchingTopics =
        rawSubjectName
          ? topicCandidates.filter(
              (
                candidate,
              ) =>
                candidate.subjectName
                  .localeCompare(
                    rawSubjectName,
                    "tr",
                    {
                      sensitivity:
                        "base",
                    },
                  ) === 0,
            )
          : topicCandidates;

      const topicMatch =
        matchingTopics.length === 1
          ? matchingTopics[0]
          : null;

      const rawGradeLevel =
        topicMatch
          ? String(
              topicMatch.gradeLevel,
            )
          : textValue(
              cellValue(row, 2),
            );

      const rawTopicName =
        topicMatch
          ? topicMatch.topicName
          : textValue(
              cellValue(row, 7),
            );

      payload.push({
        import_batch_id:
          batch.id,

        source_row_number:
          rowNumber,

        raw_data: {
          excel_row_number:
            rowNumber,

          preparer:
            rawPreparer,

          source_type:
            rawSourceType,

          book_name_or_category:
            rawBookName,

          page_number:
            rawPageNumber,

          test_number:
            rawTestNumber,

          original_subject:
            rawSubjectName,

          original_topic_code:
            rawTopicCode,

          original_topic_name:
            rawTopicName,

          link:
            rawLink,

          topic_lookup_candidate_count:
            topicCandidates.length,

          topic_lookup_matching_count:
            matchingTopics.length,

          topic_lookup_resolved:
            topicMatch !== null,

          source_file_name:
            path.basename(
              resolvedExcelPath,
            ),

          total_excel_question_rows:
            allQuestionRows.length,
        },

        raw_exam_track:
          rawExamTrack,

        raw_grade_level:
          rawGradeLevel,

        raw_subject_name:
          rawSubjectName,

        raw_topic_code:
          rawTopicCode,

        raw_topic_name:
          rawTopicName,

        raw_test_code:
          rawTestCode,

        raw_question_number:
          rawQuestionNumber,

        raw_answer:
          rawAnswer,

        raw_difficulty:
          rawDifficulty,

        raw_quality_level:
          rawQuality,

        raw_cognitive_type:
          rawCognitiveType,

        raw_primary_question_type:
          rawPrimaryQuestionType,

        raw_secondary_question_type:
          rawSecondaryQuestionType,

        raw_new_generation:
          rawNewGeneration,

        raw_link:
          rawLink,

        metadata: {
          loader_version:
            "legacy-excel-bulk-v2",

          source_sheet:
            "Soru verileri",
        },
      });
    }

    const {
      error: insertError,
    } =
      await supabase
        .from(
          "excel_question_import_rows",
        )
        .insert(payload);

    if (insertError) {
      throw new Error(
        `Toplu insert hatası: ${insertError.message}`,
      );
    }

    insertedCount +=
      payload.length;

    console.log(
      `RAW insert: ${insertedCount}/${sourceRowNumbers.length}`,
    );
  }

  // ==========================================================
  // BULK NORMALIZATION
  //
  // Her çağrıda DB içinde 1000 satır.
  // ==========================================================

  console.log("");
  console.log(
    "Toplu normalizasyon başlıyor...",
  );

  let normalizedProcessed =
    0;

  let remaining =
    sourceRowNumbers.length;

  while (
    remaining > 0
  ) {
    const {
      data,
      error,
    } =
      await supabase.rpc(
        "normalize_excel_question_import_batch",
        {
          p_batch_id:
            batch.id,

          p_limit:
            1000,
        },
      );

    if (error) {
      throw new Error(
        `Toplu normalize hatası: ${error.message}`,
      );
    }

    if (!data) {
      throw new Error(
        "Toplu normalize sonucu boş döndü.",
      );
    }

    const processed =
      Number(
        data.processed ?? 0,
      );

    remaining =
      Number(
        data.remaining ?? 0,
      );

    normalizedProcessed +=
      processed;

    console.log(
      `Normalize: ${normalizedProcessed}/${sourceRowNumbers.length} | Kalan: ${remaining}`,
    );

    if (
      processed === 0 &&
      remaining > 0
    ) {
      throw new Error(
        "Pending kayıt var fakat normalizer ilerleyemedi.",
      );
    }
  }

  // ==========================================================
  // FINAL COUNTS
  //
  // ÖNEMLİ:
  // Satırları SELECT ile çekmiyoruz.
  // Supabase/PostgREST varsayılan 1000 satır limitine
  // takılmamak için exact COUNT kullanıyoruz.
  // ==========================================================

  const [
    totalRowCount,
    normalizedCount,
    needsReviewCount,
    quarantinedCount,
    pendingCount,
  ] =
    await Promise.all([
      getExactBatchRowCount(
        supabase,
        batch.id,
      ),

      getExactStatusCount(
        supabase,
        batch.id,
        "normalized",
      ),

      getExactStatusCount(
        supabase,
        batch.id,
        "needs_review",
      ),

      getExactStatusCount(
        supabase,
        batch.id,
        "quarantined",
      ),

      getExactStatusCount(
        supabase,
        batch.id,
        "pending",
      ),
    ]);

  const processedItems =
    normalizedCount +
    needsReviewCount +
    quarantinedCount;

  const errorItems =
    needsReviewCount +
    quarantinedCount +
    pendingCount;

  const finalStatus =
    pendingCount > 0
      ? "processing"
      : (
          errorItems > 0
            ? "completed_with_errors"
            : "completed"
        );

  const {
    error:
      batchUpdateError,
  } =
    await supabase
      .from(
        "import_batches",
      )
      .update({
        total_items:
          totalRowCount,

        processed_items:
          processedItems,

        success_items:
          normalizedCount,

        error_items:
          errorItems,

        status:
          finalStatus,

        completed_at:
          pendingCount === 0
            ? new Date().toISOString()
            : null,
      })
      .eq(
        "id",
        batch.id,
      );

  if (batchUpdateError) {
    throw new Error(
      `Batch güncellenemedi: ${batchUpdateError.message}`,
    );
  }

  // ==========================================================
  // FINAL OUTPUT
  // ==========================================================

  console.log("");
  console.log(
    "======================================",
  );

  console.log(
    `Batch ID: ${batch.id}`,
  );

  console.log(
    `Excel soru satırı: ${allQuestionRows.length}`,
  );

  console.log(
    `İşlenen: ${totalRowCount}`,
  );

  console.log(
    `Normalized: ${normalizedCount}`,
  );

  console.log(
    `Needs review: ${needsReviewCount}`,
  );

  console.log(
    `Quarantined: ${quarantinedCount}`,
  );

  console.log(
    `Pending: ${pendingCount}`,
  );

  console.log(
    `Durum: ${finalStatus}`,
  );

  console.log(
    "======================================",
  );
}

main().catch(
  (error) => {
    console.error(error);
    process.exit(1);
  },
);