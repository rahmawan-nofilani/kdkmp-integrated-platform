import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

const ALLOWED_EMAIL_OTP_TYPES = new Set<EmailOtpType>([
  "signup",
  "invite",
  "magiclink",
  "recovery",
  "email_change",
  "email",
]);

export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get("token_hash");
  const rawType = request.nextUrl.searchParams.get("type");

  const redirectTo = request.nextUrl.clone();
  redirectTo.search = "";

  if (!tokenHash || !rawType || !ALLOWED_EMAIL_OTP_TYPES.has(rawType as EmailOtpType)) {
    redirectTo.pathname = "/auth/error";
    redirectTo.searchParams.set("reason", "invalid-link");
    return NextResponse.redirect(redirectTo);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: rawType as EmailOtpType,
  });

  if (error) {
    redirectTo.pathname = "/auth/error";
    redirectTo.searchParams.set("reason", "verification-failed");
    return NextResponse.redirect(redirectTo);
  }

  // Invite and recovery flows require the user to establish a password.
  if (rawType === "invite" || rawType === "recovery") {
    redirectTo.pathname = "/set-password";
    return NextResponse.redirect(redirectTo);
  }

  redirectTo.pathname = "/dashboard";
  return NextResponse.redirect(redirectTo);
}
