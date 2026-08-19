"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function activateInvitedUser(formData: FormData) {
  const tokenHash = String(formData.get("token_hash") ?? "").trim();
  const type = String(formData.get("type") ?? "").trim();

  if (!tokenHash || type !== "invite") {
    redirect("/auth/error?reason=invalid-link");
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: "invite",
  });

  if (error) {
    redirect("/auth/error?reason=verification-failed");
  }

  redirect("/set-password");
}
