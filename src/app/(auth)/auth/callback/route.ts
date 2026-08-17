import { NextRequest, NextResponse } from "next/server"
import { createClient } from "@/lib/supabase/server"

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url)
  const code = requestUrl.searchParams.get("code")

  if (!code) {
    return NextResponse.redirect(
      new URL("/login?error=auth_callback", requestUrl.origin)
    )
  }

  const supabase = await createClient()

  const { error: exchangeError } =
    await supabase.auth.exchangeCodeForSession(code)

  if (exchangeError) {
    return NextResponse.redirect(
      new URL("/login?error=auth_callback", requestUrl.origin)
    )
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError || !user) {
    return NextResponse.redirect(
      new URL("/login?error=auth_user", requestUrl.origin)
    )
  }

  const nickname = user.user_metadata?.nickname
  const gradeLevel = Number(user.user_metadata?.grade_level)

  if (
    typeof nickname !== "string" ||
    nickname.trim().length === 0 ||
    !Number.isInteger(gradeLevel) ||
    gradeLevel < 1 ||
    gradeLevel > 12
  ) {
    return NextResponse.redirect(
      new URL("/login?error=profile_data", requestUrl.origin)
    )
  }

  const { error: profileError } = await supabase
    .from("student_profiles")
    .upsert(
      {
        id: user.id,
        nickname: nickname.trim(),
        grade_level: gradeLevel,
      },
      {
        onConflict: "id",
      }
    )

  if (profileError) {
    return NextResponse.redirect(
      new URL("/login?error=profile_setup", requestUrl.origin)
    )
  }

  return NextResponse.redirect(new URL("/", requestUrl.origin))
}