"use server";

import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { createAdminClient } from "@/lib/supabase/admin";

function text(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

function activationPath(actionLink: string | null | undefined, type: "invite" | "recovery") {
  if (!actionLink) return null;
  const parsed = new URL(actionLink);
  const tokenHash = parsed.searchParams.get("token") ?? parsed.searchParams.get("token_hash");
  if (!tokenHash) return null;
  return `/activate?token_hash=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(type)}`;
}

export async function generateUatRecoveryLinkAction(formData: FormData) {
  await requirePermission("USER_UPDATE");
  const { profile: actorProfile } = await requireAccessContext();
  const email = text(formData, "email").toLowerCase();

  if (!actorProfile.organization_id || !email || !email.includes("@")) {
    redirect("/dashboard/access/uat-recovery?error=invalid-request");
  }

  const admin = createAdminClient();
  const { data: usersPage, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersError) {
    console.error("UAT recovery user lookup failed", usersError.message);
    redirect("/dashboard/access/uat-recovery?error=lookup-failed");
  }

  const authUser = usersPage.users.find((user) => user.email?.toLowerCase() === email);
  if (!authUser) redirect("/dashboard/access/uat-recovery?error=user-not-found");

  const { data: targetProfile, error: profileError } = await admin
    .from("profiles")
    .select("id,organization_id,status")
    .eq("auth_user_id", authUser.id)
    .maybeSingle();

  if (profileError || !targetProfile) {
    console.error("UAT recovery profile lookup failed", profileError?.message ?? "missing profile");
    redirect("/dashboard/access/uat-recovery?error=profile-not-found");
  }

  if (targetProfile.organization_id !== actorProfile.organization_id || targetProfile.status !== "ACTIVE") {
    redirect("/dashboard/access/uat-recovery?error=scope-denied");
  }

  const now = new Date().toISOString();
  const { data: roleAssignments, error: roleError } = await admin
    .from("user_roles")
    .select("roles(code)")
    .eq("profile_id", targetProfile.id)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`);

  if (roleError) {
    console.error("UAT recovery role lookup failed", roleError.message);
    redirect("/dashboard/access/uat-recovery?error=lookup-failed");
  }

  const roleCodes = (roleAssignments ?? []).map((assignment) => assignment.roles?.code).filter(Boolean);
  if (roleCodes.includes("MANAGER") || roleCodes.includes("BOARD")) {
    redirect("/dashboard/access/uat-recovery?error=protected-user");
  }

  const { data: generated, error: generateError } = await admin.auth.admin.generateLink({
    type: "recovery",
    email,
  });

  if (generateError) {
    console.error("UAT recovery link generation failed", generateError.message);
    redirect("/dashboard/access/uat-recovery?error=link-failed");
  }

  const path = activationPath(generated.properties?.action_link, "recovery");
  if (!path) redirect("/dashboard/access/uat-recovery?error=link-failed");

  redirect(path);
}
