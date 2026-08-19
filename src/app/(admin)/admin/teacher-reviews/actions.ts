"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type HumanDecision =
  | "approved"
  | "rejected"
  | "needs_revision";

type DecisionResult = {
  review_run_id: string;
  decision: HumanDecision;
  performed_by: string;
  correction_proposal_id: string | null;
  correction_applied: boolean;
  production_publication: boolean;
};

type DecisionRpc = (
  functionName: "decide_teacher_review",
  args: {
    p_review_run_id: string;
    p_decision: HumanDecision;
    p_correction_proposal_id: string | null;
    p_notes: string | null;
  },
) => Promise<{
  data: DecisionResult | null;
  error: {
    message: string;
    details?: string;
    hint?: string;
    code?: string;
  } | null;
}>;

export async function decideTeacherReviewAction(
  formData: FormData,
): Promise<void> {
  const reviewRunId =
    String(
      formData.get(
        "review_run_id",
      ) ?? "",
    ).trim();

  const correctionProposalIdValue =
    String(
      formData.get(
        "correction_proposal_id",
      ) ?? "",
    ).trim();

  const decision =
    String(
      formData.get(
        "decision",
      ) ?? "",
    ).trim() as HumanDecision;

  const notes =
    String(
      formData.get(
        "notes",
      ) ?? "",
    ).trim();

  if (!reviewRunId) {
    throw new Error(
      "Review run id eksik.",
    );
  }

  if (
    decision !== "approved" &&
    decision !== "rejected" &&
    decision !== "needs_revision"
  ) {
    throw new Error(
      "Geçersiz insan inceleme kararı.",
    );
  }

  const supabase =
    await createClient();

  const {
    data: userData,
    error: userError,
  } =
    await supabase.auth.getUser();

  if (
    userError ||
    !userData.user
  ) {
    throw new Error(
      "İnsan inceleme kararı için giriş yapılmış kullanıcı gereklidir.",
    );
  }

  const rpc =
    supabase.rpc.bind(
      supabase,
    ) as unknown as DecisionRpc;

  const {
    error,
  } =
    await rpc(
      "decide_teacher_review",
      {
        p_review_run_id:
          reviewRunId,

        p_decision:
          decision,

        p_correction_proposal_id:
          correctionProposalIdValue
            ? correctionProposalIdValue
            : null,

        p_notes:
          notes
            ? notes
            : null,
      },
    );

  if (error) {
    throw new Error(
      `Teacher Review kararı kaydedilemedi: ${error.message}`,
    );
  }

  revalidatePath(
    "/admin/teacher-reviews",
  );
}