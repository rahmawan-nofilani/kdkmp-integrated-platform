"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function requestPasswordRecovery(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();

  if (!email) {
    redirect("/forgot-password?error=missing");
  }

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email);

  // Intentionally use the same response regardless of whether the address exists
  // or the provider accepts the request, to avoid exposing account membership.
  redirect("/forgot-password?sent=1");
}
