"use server";

import type { EmailOtpType } from "@supabase/supabase-js";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const ALLOWED_TYPES = new Set<EmailOtpType>(["invite", "recovery"]);

export async function activateUser(formData: FormData) {
  const tokenHash = String(formData.get("token_hash") ?? "").trim();
  const rawType = String(formData.get("type") ?? "").trim() as EmailOtpType;

  if (!tokenHash || !ALLOWED_TYPES.has(rawType)) {
    redirect("/auth/error?reason=invalid-link");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: rawType,
  });

  if (error) {
    redirect("/auth/error?reason=verification-failed");
  }

  redirect("/set-password");
}
