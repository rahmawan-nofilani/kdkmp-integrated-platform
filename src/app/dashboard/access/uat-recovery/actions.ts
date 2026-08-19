"use server";

import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { createAdminClient } from "@/lib/supabase/admin";

const DEVELOPMENT_ORG_CODE = "DEMO-KDKMP-DEV";
const UAT_BOARD_EMAIL = "nofilanirahmawan+uat-board@gmail.com";

type RoleRelation = { code?: string | null } | Array<{ code?: string | null }> | null;

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

function roleCodesFromRelation(relation: RoleRelation) {
  const rows = Array.isArray(relation) ? relation : relation ? [relation] : [];
  return rows.map((role) => role.code).filter((code): code is string => Boolean(code));
}

async function activeRoleCodes(
  admin: ReturnType<typeof createAdminClient>,
  profileId: string,
  now: string,
) {
  const { data: roleAssignments, error } = await admin
    .from("user_roles")
    .select("roles(code)")
    .eq("profile_id", profileId)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`);

  if (error) return { roleCodes: [] as string[], error };

  return {
    roleCodes: (roleAssignments ?? []).flatMap((assignment) =>
      roleCodesFromRelation(assignment.roles as RoleRelation),
    ),
    error: null,
  };
}

export async function generateUatRecoveryLinkAction(formData: FormData) {
  await requirePermission("USER_UPDATE");
  const { profile: actorProfile } = await requireAccessContext();
  const email = text(formData, "email").toLowerCase();

  if (!actorProfile.organization_id || !email || !email.includes("@")) {
    redirect("/dashboard/access/uat-recovery?error=invalid-request");
  }

  const admin = createAdminClient();
  const { data: actorOrganization, error: organizationError } = await admin
    .from("organizations")
    .select("code")
    .eq("id", actorProfile.organization_id)
    .maybeSingle();

  if (organizationError || actorOrganization?.code !== DEVELOPMENT_ORG_CODE) {
    redirect("/dashboard/access/uat-recovery?error=development-only");
  }

  const now = new Date().toISOString();
  const actorRoles = await activeRoleCodes(admin, actorProfile.id, now);
  if (actorRoles.error) {
    console.error("UAT recovery actor role lookup failed", actorRoles.error.message);
    redirect("/dashboard/access/uat-recovery?error=lookup-failed");
  }
  if (!actorRoles.roleCodes.includes("MANAGER")) {
    redirect("/dashboard/access/uat-recovery?error=manager-only");
  }

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

  const targetRoles = await activeRoleCodes(admin, targetProfile.id, now);
  if (targetRoles.error) {
    console.error("UAT recovery role lookup failed", targetRoles.error.message);
    redirect("/dashboard/access/uat-recovery?error=lookup-failed");
  }

  if (targetRoles.roleCodes.includes("MANAGER")) {
    redirect("/dashboard/access/uat-recovery?error=protected-user");
  }

  const isDesignatedUatBoard =
    email === UAT_BOARD_EMAIL &&
    targetRoles.roleCodes.length === 1 &&
    targetRoles.roleCodes[0] === "BOARD";

  if (targetRoles.roleCodes.includes("BOARD") && !isDesignatedUatBoard) {
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
