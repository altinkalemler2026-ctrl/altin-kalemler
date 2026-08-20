import fs from "node:fs";
import path from "node:path";
import ExcelJS from "exceljs";
import { createClient } from "@supabase/supabase-js";

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

function integerValue(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }

  const numeric = Number(
    String(value).trim(),
  );

  if (!Number.isFinite(numeric)) {
    return null;
  }

  return Math.trunc(numeric);
}

function legacyCodeValue(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === "number") {
    return String(
      Math.trunc(value),
    );
  }

  const text = String(value).trim();

  if (!text) {
    return null;
  }

  const numeric = Number(text);

  if (Number.isFinite(numeric)) {
    return String(
      Math.trunc(numeric),
    );
  }

  return text;
}

function comparisonKey(
  gradeLevel: number,
  subjectName: string,
  legacyCode: string,
  topicName: string,
) {
  return [
    gradeLevel,
    subjectName
      .toLocaleLowerCase("tr-TR")
      .trim(),
    legacyCode.trim(),
    topicName
      .toLocaleLowerCase("tr-TR")
      .trim(),
  ].join("|");
}

async function main() {
  loadEnvFile(
    path.resolve(
      process.cwd(),
      ".env.local",
    ),
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
    process.argv[2] ??
    "./legacy-questions.xlsx";

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

  const topicSheet =
    workbook.getWorksheet("KONU KODU");

  if (!topicSheet) {
    throw new Error(
      '"KONU KODU" sayfası bulunamadı.',
    );
  }

  // ==========================================================
  // Excel KONU KODU sayfası
  //
  // F = Konu kodu
  // G = Ders
  // H = Sınıf
  // I = Konu
  // ==========================================================

  const excelRows: Array<{
    source_name: string;
    grade_level: number;
    subject_name: string;
    topic_name: string;
    subtopic_name: null;
    legacy_code: string;
    is_active: boolean;
  }> = [];

  const seenExcelKeys =
    new Set<string>();

  for (
    let rowNumber = 2;
    rowNumber <= topicSheet.rowCount;
    rowNumber += 1
  ) {
    const row =
      topicSheet.getRow(rowNumber);

    const legacyCode =
      legacyCodeValue(
        cellValue(row, 6),
      );

    const subjectName =
      textValue(
        cellValue(row, 7),
      );

    const gradeLevel =
      integerValue(
        cellValue(row, 8),
      );

    const topicName =
      textValue(
        cellValue(row, 9),
      );

    if (
      !legacyCode ||
      !subjectName ||
      !gradeLevel ||
      !topicName
    ) {
      continue;
    }

    if (
      gradeLevel < 1 ||
      gradeLevel > 12
    ) {
      continue;
    }

    const key = comparisonKey(
      gradeLevel,
      subjectName,
      legacyCode,
      topicName,
    );

    if (seenExcelKeys.has(key)) {
      continue;
    }

    seenExcelKeys.add(key);

    excelRows.push({
      source_name:
        "legacy_excel_konu_kodu",

      grade_level:
        gradeLevel,

      subject_name:
        subjectName,

      topic_name:
        topicName,

      subtopic_name:
        null,

      legacy_code:
        legacyCode,

      is_active:
        true,
    });
  }

  console.log(
    `Excel'de bulunan benzersiz taxonomy kaydı: ${excelRows.length}`,
  );

  // ==========================================================
  // Mevcut DB kayıtlarını al.
  // Böylece script tekrar çalıştırılırsa duplicate üretmez.
  // ==========================================================

  const {
    data: existingRows,
    error: existingError,
  } = await supabase
    .from("legacy_taxonomy")
    .select(
      "grade_level, subject_name, legacy_code, topic_name",
    );

  if (existingError) {
    throw new Error(
      `Mevcut taxonomy kayıtları okunamadı: ${existingError.message}`,
    );
  }

  const existingKeys =
    new Set<string>();

  for (
    const row of existingRows ?? []
  ) {
    if (
      row.grade_level === null ||
      !row.subject_name ||
      !row.legacy_code ||
      !row.topic_name
    ) {
      continue;
    }

    existingKeys.add(
      comparisonKey(
        row.grade_level,
        row.subject_name,
        row.legacy_code,
        row.topic_name,
      ),
    );
  }

  const rowsToInsert =
    excelRows.filter(
      (row) =>
        !existingKeys.has(
          comparisonKey(
            row.grade_level,
            row.subject_name,
            row.legacy_code,
            row.topic_name,
          ),
        ),
    );

  console.log(
    `DB'de zaten bulunan: ${
      excelRows.length -
      rowsToInsert.length
    }`,
  );

  console.log(
    `Eklenecek yeni kayıt: ${rowsToInsert.length}`,
  );

  // ==========================================================
  // 500'lük parçalar halinde ekle.
  // ==========================================================

  const chunkSize = 500;

  let insertedCount = 0;

  for (
    let index = 0;
    index < rowsToInsert.length;
    index += chunkSize
  ) {
    const chunk =
      rowsToInsert.slice(
        index,
        index + chunkSize,
      );

    const {
      error: insertError,
    } = await supabase
      .from("legacy_taxonomy")
      .insert(chunk);

    if (insertError) {
      throw new Error(
        `Taxonomy ekleme hatası: ${insertError.message}`,
      );
    }

    insertedCount +=
      chunk.length;

    console.log(
      `Eklenen: ${insertedCount}/${rowsToInsert.length}`,
    );
  }

  const {
    count: totalCount,
    error: countError,
  } = await supabase
    .from("legacy_taxonomy")
    .select(
      "*",
      {
        count: "exact",
        head: true,
      },
    );

  if (countError) {
    throw new Error(
      `Son kayıt sayısı okunamadı: ${countError.message}`,
    );
  }

  console.log("");
  console.log(
    "======================================",
  );

  console.log(
    `Excel benzersiz kayıt: ${excelRows.length}`,
  );

  console.log(
    `Yeni eklenen: ${insertedCount}`,
  );

  console.log(
    `DB toplam taxonomy: ${totalCount ?? 0}`,
  );

  console.log(
    "======================================",
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});