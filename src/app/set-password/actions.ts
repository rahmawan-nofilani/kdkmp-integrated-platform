"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

const MIN_PASSWORD_LENGTH = 12;

export async function setPassword(formData: FormData) {
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("password_confirmation") ?? "");

  if (password.length < MIN_PASSWORD_LENGTH) {
    redirect("/set-password?error=too-short");
  }

  if (password !== confirmation) {
    redirect("/set-password?error=mismatch");
  }

  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();

  if (claimsError || !claimsData?.claims?.sub) {
    redirect("/login?error=session-expired");
  }

  const { error } = await supabase.auth.updateUser({ password });

  if (error) {
    redirect("/set-password?error=update-failed");
  }

  // Authentication is established, but operational authorization is separate.
  // The user will remain blocked until a profile and active role are provisioned.
  redirect("/access-pending");
}
