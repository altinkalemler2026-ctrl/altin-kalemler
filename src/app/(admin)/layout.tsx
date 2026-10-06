import type { ReactNode } from "react";

import { redirect } from "next/navigation";

import AdminNav from "@/components/admin/AdminNav";
import { ADMIN_NAV_ITEMS } from "@/lib/admin/admin-panel-messages";
import {
  canAccessAdminNavItem,
  collectAdminNavPermissionCodes,
} from "@/lib/admin/admin-nav";
import { createClient } from "@/lib/supabase/server";

import "./admin-surface.css";

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

/**
 * Admin alanı merkezî oturum + menü kabuğu.
 *
 * Mevcut sunucu korumaları aynen korunur: oturum yoksa /login'e,
 * `questions.view` yetkisi yoksa /dashboard'e yönlendirilir. Menü
 * öğeleri izin tablosundan fail-closed biçimde süzülür; burada
 * hiçbir veri yazma/karar/publish eylemi yoktur, yalnız gezinme.
 */
export default async function AdminLayout({
  children,
}: {
  children: ReactNode;
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
    canViewQuestions !==
      true
  ) {
    redirect("/dashboard");
  }

  const permissionCodes =
    new Set([
      "questions.view",
      ...collectAdminNavPermissionCodes(),
    ]);

  const permissionEntries =
    await Promise.all(
      Array.from(
        permissionCodes,
      ).map(async (code) => {
        const result =
          await rpc(
            "teacher_review_admin_has_permission",
            {
              p_permission_code:
                code,
            },
          );

        return [
          code,
          result.error ===
            null &&
            result.data ===
              true,
        ] as const;
      }),
    );

  const permissions: Record<
    string,
    boolean
  > = {};

  for (
    const [code, allowed] of permissionEntries
  ) {
    permissions[code] =
      allowed;
  }

  const navItems = [
    {
      href: "/admin",
      title: "Yönetim Ana Sayfası",
    },
    ...ADMIN_NAV_ITEMS.filter(
      (item) =>
        canAccessAdminNavItem(
          item.href,
          permissions,
        ),
    ).map((item) => ({
      href: item.href,
      title: item.title,
    })),
  ];

  const userLabel =
    userData.user.email?.trim() ||
    "Yönetici";

  return (
    <>
      <AdminNav
        items={navItems}
        userLabel={userLabel}
      />
      {/*
       * İçerik yüzeyi (F4): admin bağlantılarının klavye odak halkası
       * yalnız bu sarmalayıcı içindeki belirleyiciyle uygulanır.
       */}
      <div className="admin-surface">
        {children}
      </div>
    </>
  );
}