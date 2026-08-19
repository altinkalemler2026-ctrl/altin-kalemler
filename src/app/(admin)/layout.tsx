import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

type PermissionRpc = (
  functionName: "teacher_review_admin_has_permission",
  args: {
    p_permission_code: string;
  },
) => Promise<{
  data: boolean | null;
  error: {
    message: string;
  } | null;
}>;

export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
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
    redirect("/login");
  }

  const rpc =
    supabase.rpc.bind(
      supabase,
    ) as unknown as PermissionRpc;

  const {
    data: canViewQuestions,
    error: permissionError,
  } =
    await rpc(
      "teacher_review_admin_has_permission",
      {
        p_permission_code:
          "questions.view",
      },
    );

  if (
    permissionError ||
    canViewQuestions !== true
  ) {
    redirect("/dashboard");
  }

  return <>{children}</>;
}