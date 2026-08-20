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

function loadEnvFile(filePath: string) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  const content = fs.readFileSync(filePath, "utf8");

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();

    if (
      !line ||
      line.startsWith("#") ||
      !line.includes("=")
    ) {
      continue;
    }

    const separatorIndex = line.indexOf("=");

    const key = line
      .slice(0, separatorIndex)
      .trim();

    let value = line
      .slice(separatorIndex + 1)
      .trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

function cellValue(
  row: ExcelJS.Row,
  columnNumber: number,
): unknown {
  const cell = row.getCell(columnNumber);

  if (
    typeof cell.value === "object" &&
    cell.value !== null &&
    "result" in cell.value
  ) {
    return cell.result;
  }

  return cell.value;
}

function textValue(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  const text = String(value).trim();

  return text ? text : null;
}

function integerText(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === "number") {
    return String(Math.trunc(value));
  }

  const text = String(value).trim();

  if (!text) {
    return null;
  }

  const numeric = Number(text);

  if (!Number.isFinite(numeric)) {
    return text;
  }

  return String(Math.trunc(numeric));
}

async function main() {
  loadEnvFile(
    path.resolve(process.cwd(), ".env.local"),
  );

  const supabaseUrl =
    process.env.NEXT_PUBLIC_SUPABASE_URL;

  const serviceRoleKey =
    process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL .env.local içinde bulunamadı.",
    );
  }

  if (!serviceRoleKey) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY .env.local içinde bulunamadı.",
    );
  }

  const excelPath =
    process.argv[2];

  if (!excelPath) {
    throw new Error(
      "Excel dosya yolu eksik.",
    );
  }

  const resolvedExcelPath =
    path.resolve(excelPath);

  if (!fs.existsSync(resolvedExcelPath)) {
    throw new Error(
      `Excel dosyası bulunamadı: ${resolvedExcelPath}`,
    );
  }

  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
    {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
    },
  );

  const workbook =
    new ExcelJS.Workbook();

  await workbook.xlsx.readFile(
    resolvedExcelPath,
  );

  const questionSheet =
    workbook.getWorksheet("Soru verileri");

  const topicSheet =
    workbook.getWorksheet("KONU KODU");

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
  // KONU KODU LOOKUP
  //
  // F-I kolonlarını kullanıyoruz:
  // F = Konu kodu
  // G = Ders
  // H = Sınıf
  // I = Konu
  // ==========================================================

  const topicLookup =
    new Map<string, TopicLookup[]>();

  for (
    let rowNumber = 2;
    rowNumber <= topicSheet.rowCount;
    rowNumber += 1
  ) {
    const row =
      topicSheet.getRow(rowNumber);

    const topicCode =
      integerText(cellValue(row, 6));

    const subjectName =
      textValue(cellValue(row, 7));

    const gradeText =
      integerText(cellValue(row, 8));

    const topicName =
      textValue(cellValue(row, 9));

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
      !Number.isInteger(gradeLevel) ||
      gradeLevel < 1 ||
      gradeLevel > 12
    ) {
      continue;
    }

    const entry: TopicLookup = {
      gradeLevel,
      subjectName,
      topicCode,
      topicName,
    };

    const existing =
      topicLookup.get(topicCode) ?? [];

    existing.push(entry);

    topicLookup.set(
      topicCode,
      existing,
    );
  }

  // ==========================================================
  // IMPORT BATCH
  //
  // Şimdilik sadece 10 gerçek Excel satırı.
  // ==========================================================

  const { data: batch, error: batchError } =
    await supabase
      .from("import_batches")
      .insert({
        batch_type: "excel",
        status: "processing",
        total_items: 10,
        processed_items: 0,
        success_items: 0,
        error_items: 0,
      })
      .select("id")
      .single();

  if (batchError || !batch) {
    throw new Error(
      `Import batch oluşturulamadı: ${
        batchError?.message ?? "bilinmeyen hata"
      }`,
    );
  }

  console.log(
    `Import batch: ${batch.id}`,
  );

  let insertedCount = 0;
  let failedCount = 0;

  // Excel satırı 1 başlık.
  // Gerçek kayıtlar 2'den başlıyor.
  // İlk 10 kayıt = 2..11.
  for (
    let rowNumber = 2;
    rowNumber <= 11;
    rowNumber += 1
  ) {
    const row =
      questionSheet.getRow(rowNumber);

    // --------------------------------------------------------
    // Soru verileri kolonları
    //
    //  1 SORU ID
    //  2 SINIF
    //  3 HAZIRLAYAN
    //  4 KAYNAK /KİTAP TÜRÜ
    //  5 KİTAP ADI/KATEGORİ
    //  6 DERS
    //  7 Konu
    //  8 SAYFA NO
    //  9 TEST NO
    // 10 TEST KODU/DOSYA ADI
    // 11 SORU NO
    // 12 CEVAP
    // 13 KAZANIM KODU/KONU KODU
    // 14 SORU TİPİ-1
    // 15 SORU TİPİ-2
    // 16 SORU TÜRÜ
    // 17 ZORLUK SEVİYESİ
    // 18 KALİTE
    // 19 YENİ NESİL
    // 20 Link
    // 21 Sütun1
    // --------------------------------------------------------

    const rawExamTrack =
      textValue(cellValue(row, 1));

    const rawPreparer =
      textValue(cellValue(row, 3));

    const rawSourceType =
      textValue(cellValue(row, 4));

    const rawBookName =
      textValue(cellValue(row, 5));

    const rawSubjectName =
      textValue(cellValue(row, 6));

    const rawPageNumber =
      integerText(cellValue(row, 8));

    const rawTestNumber =
      integerText(cellValue(row, 9));

    const rawTestCode =
      textValue(cellValue(row, 10));

    const rawQuestionNumber =
      integerText(cellValue(row, 11));

    const rawAnswer =
      textValue(cellValue(row, 12));

    const rawTopicCode =
      integerText(cellValue(row, 13));

    const rawPrimaryQuestionType =
      integerText(cellValue(row, 14));

    const rawSecondaryQuestionType =
      integerText(cellValue(row, 15));

    const rawCognitiveType =
      integerText(cellValue(row, 16));

    const rawDifficulty =
      integerText(cellValue(row, 17));

    const rawQuality =
      integerText(cellValue(row, 18));

    const rawNewGeneration =
      textValue(cellValue(row, 19));

    const rawLink =
      textValue(cellValue(row, 20));

    // --------------------------------------------------------
    // Grade ve topic:
    // Excel formülüne güvenmek yerine konu kodundan çözülür.
    // Aynı kod birden fazla ders için varsa ders adıyla daraltılır.
    // --------------------------------------------------------

    const topicCandidates =
      rawTopicCode
        ? topicLookup.get(rawTopicCode) ?? []
        : [];

    const matchingTopics =
      rawSubjectName
        ? topicCandidates.filter(
            (candidate) =>
              candidate.subjectName
                .localeCompare(
                  rawSubjectName,
                  "tr",
                  {
                    sensitivity: "base",
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
        ? String(topicMatch.gradeLevel)
        : textValue(cellValue(row, 2));

    const rawTopicName =
      topicMatch
        ? topicMatch.topicName
        : textValue(cellValue(row, 7));

    const rawData = {
      excel_row_number: rowNumber,

      preparer: rawPreparer,

      source_type: rawSourceType,

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

      smoke_import:
        true,

      smoke_import_limit:
        10,
    };

    const { data: insertedRow, error: insertError } =
      await supabase
        .from("excel_question_import_rows")
        .insert({
          import_batch_id:
            batch.id,

          source_row_number:
            rowNumber,

          raw_data:
            rawData,

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
              "legacy-excel-v1",

            source_sheet:
              "Soru verileri",
          },
        })
        .select("id")
        .single();

    if (
      insertError ||
      !insertedRow
    ) {
      failedCount += 1;

      console.error(
        `Satır ${rowNumber} eklenemedi:`,
        insertError?.message ??
          "bilinmeyen hata",
      );

      continue;
    }

    // --------------------------------------------------------
    // SECURITY DEFINER normalizer:
    // yalnız service_role çalıştırabilir.
    // --------------------------------------------------------

    const {
      data: normalizeResult,
      error: normalizeError,
    } = await supabase.rpc(
      "normalize_excel_question_import_row",
      {
        p_row_id:
          insertedRow.id,
      },
    );

    if (normalizeError) {
      failedCount += 1;

      console.error(
        `Satır ${rowNumber} normalize edilemedi:`,
        normalizeError.message,
      );

      continue;
    }

    insertedCount += 1;

    console.log(
      `Satır ${rowNumber}:`,
      JSON.stringify(
        normalizeResult,
      ),
    );
  }

  const finalStatus =
    failedCount === 0
      ? "completed"
      : "completed_with_errors";

  const { error: updateError } =
    await supabase
      .from("import_batches")
      .update({
        status:
          finalStatus,

        processed_items:
          insertedCount +
          failedCount,

        success_items:
          insertedCount,

        error_items:
          failedCount,

        completed_at:
          new Date().toISOString(),
      })
      .eq(
        "id",
        batch.id,
      );

  if (updateError) {
    throw new Error(
      `Batch özeti güncellenemedi: ${updateError.message}`,
    );
  }

  console.log("");
  console.log(
    "======================================",
  );
  console.log(
    `Batch ID: ${batch.id}`,
  );
  console.log(
    `Başarılı: ${insertedCount}`,
  );
  console.log(
    `Hatalı: ${failedCount}`,
  );
  console.log(
    `Durum: ${finalStatus}`,
  );
  console.log(
    "======================================",
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});