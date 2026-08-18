import type {
  ClaimedAiJob,
  JsonObject,
  JsonValue,
} from "./types.ts";

function asObject(
  value: JsonValue | undefined,
): JsonObject {
  if (
    value &&
    typeof value === "object" &&
    !Array.isArray(value)
  ) {
    return value as JsonObject;
  }

  return {};
}

function asString(
  value: JsonValue | undefined,
): string | null {
  return typeof value === "string"
    ? value
    : null;
}

function asNumber(
  value: JsonValue | undefined,
): number | null {
  return typeof value === "number"
    ? value
    : null;
}

function asBoolean(
  value: JsonValue | undefined,
): boolean | null {
  return typeof value === "boolean"
    ? value
    : null;
}

export type AiGenerationPrompt = {
  systemPrompt: string;
  userPrompt: string;
};

export function buildAiGenerationPrompt(
  job: ClaimedAiJob,
): AiGenerationPrompt {
  const input =
    job.input_data;

  const generationRequirements =
    asObject(
      input["generation_requirements"],
    );

  const curriculumRequirements =
    asObject(
      input["curriculum_requirements"],
    );

  const solveTimeRequirements =
    asObject(
      input["solve_time_requirements"],
    );

  const qualityRequirements =
    asObject(
      input["quality_requirements"],
    );

  const diversityRequirements =
    asObject(
      input["diversity_requirements"],
    );

  const copyrightRequirements =
    asObject(
      input["copyright_requirements"],
    );

  const reviewRequirements =
    asObject(
      input["review_requirements"],
    );

  const requestedQuestionCount =
    asNumber(
      input["requested_question_count"],
    ) ?? 1;

  const gradeLevel =
    asNumber(
      curriculumRequirements[
        "grade_level"
      ],
    );

  const subjectId =
    asString(
      curriculumRequirements[
        "subject_id"
      ],
    );

  const topicId =
    asString(
      curriculumRequirements[
        "topic_id"
      ],
    );

  const subtopicId =
    asString(
      curriculumRequirements[
        "subtopic_id"
      ],
    );

  const outcomeId =
    asString(
      curriculumRequirements[
        "outcome_id"
      ],
    );

  const curriculumVersionId =
    asString(
      curriculumRequirements[
        "curriculum_version_id"
      ],
    );

  const difficulty =
    asString(
      generationRequirements[
        "difficulty"
      ],
    );

  const cognitiveLevel =
    asString(
      generationRequirements[
        "cognitive_level"
      ],
    );

  const questionType =
    asString(
      generationRequirements[
        "question_type"
      ],
    );

  const minSolveTime =
    asNumber(
      solveTimeRequirements[
        "minimum_seconds"
      ],
    );

  const maxSolveTime =
    asNumber(
      solveTimeRequirements[
        "maximum_seconds"
      ],
    );

  const requiresVisual =
    asBoolean(
      asObject(
        generationRequirements[
          "visual_requirements"
        ],
      )["requires_visual"],
    );

  const systemPrompt =
    [
      "Sen Altın Kalemler eğitim platformu için özgün soru üreten bir AI soru üretim ajanısın.",
      "",
      "Kesin kurallar:",
      "- Yalnızca istenen sınıf ve ders seviyesine uygun soru üret.",
      "- Mevcut kaynak sorularını kelime, isim veya sayı değiştirerek yeniden yazma.",
      "- Her soru özgün olmalıdır.",
      "- Her sorunun tek ve kesin bir doğru cevabı olmalıdır.",
      "- Doğru cevap bağımsız olarak çözülebilir olmalıdır.",
      "- Soru dili açık, yaş seviyesine uygun ve dilbilgisel olarak düzgün olmalıdır.",
      "- Telif riski oluşturabilecek kaynak taklidi yapma.",
      "- Üretim sonucu production'a yayınlanmaz; yalnızca staging alanına gider.",
      "- Ticari kullanım izni bu aşamada verilmez.",
      "- Bağımsız cevap, müfredat, süre, özgünlük ve insan incelemesi daha sonra yapılacaktır.",
      "",
      "Yanıt yalnızca geçerli JSON olmalıdır.",
      "Markdown, açıklama veya kod bloğu kullanma.",
    ].join("\n");

  const userPrompt =
    [
      "Aşağıdaki üretim isteğine göre soru üret.",
      "",
      `İstenen soru sayısı: ${requestedQuestionCount}`,
      `Sınıf: ${gradeLevel ?? "belirtilmemiş"}`,
      `Ders ID: ${subjectId ?? "belirtilmemiş"}`,
      `Müfredat sürüm ID: ${curriculumVersionId ?? "belirtilmemiş"}`,
      `Konu ID: ${topicId ?? "belirtilmemiş"}`,
      `Alt konu ID: ${subtopicId ?? "belirtilmemiş"}`,
      `Kazanım ID: ${outcomeId ?? "belirtilmemiş"}`,
      `Zorluk: ${difficulty ?? "belirtilmemiş"}`,
      `Bilişsel seviye: ${cognitiveLevel ?? "belirtilmemiş"}`,
      `Soru tipi: ${questionType ?? "belirtilmemiş"}`,
      `Minimum hedef çözüm süresi: ${minSolveTime ?? "belirtilmemiş"} saniye`,
      `Maksimum hedef çözüm süresi: ${maxSolveTime ?? "belirtilmemiş"} saniye`,
      `Görsel gerekli: ${requiresVisual === null ? "belirtilmemiş" : requiresVisual ? "evet" : "hayır"}`,
      "",
      "Kalite gereksinimleri:",
      JSON.stringify(
        qualityRequirements,
        null,
        2,
      ),
      "",
      "Çeşitlilik gereksinimleri:",
      JSON.stringify(
        diversityRequirements,
        null,
        2,
      ),
      "",
      "Telif/özgünlük gereksinimleri:",
      JSON.stringify(
        copyrightRequirements,
        null,
        2,
      ),
      "",
      "İnceleme gereksinimleri:",
      JSON.stringify(
        reviewRequirements,
        null,
        2,
      ),
      "",
      "Zorunlu JSON formatı:",
      JSON.stringify(
        {
          schema_version: "1.0",
          questions: [
            {
              client_question_id:
                "provider-generated-id",
              question_text:
                "Soru metni",
              options: {
                A: "Seçenek A",
                B: "Seçenek B",
                C: "Seçenek C",
                D: "Seçenek D",
                E: "Opsiyonel seçenek E",
              },
              correct_answer:
                "A | B | C | D | E",
              difficulty:
                "easy | medium | hard",
              cognitive_type:
                "learning | comprehension | application",
              primary_question_type:
                "multiple_choice",
              is_new_generation:
                true,
              has_visual:
                false,
              estimated_solve_time_seconds:
                20,
              solution: {
                explanation:
                  "Kısa çözüm açıklaması",
                final_answer:
                  "C",
              },
              analysis: {
                grade_fit_requires_review:
                  true,
                curriculum_fit_requires_review:
                  true,
                originality_requires_review:
                  true,
                copyright_review_required:
                  true,
              },
              metadata: {},
            },
          ],
        },
        null,
        2,
      ),
    ].join("\n");

  return {
    systemPrompt,
    userPrompt,
  };
}