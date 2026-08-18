"use server";

import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { createAdminClient } from "@/lib/supabase/admin";

const ASSIGNABLE_ROLES = new Set(["CASHIER", "TELLER", "FINANCE_OFFICER", "SUPERVISOR"]);

type AdminRpcResult = { data: unknown; error: { message: string } | null };

type AccessCommand =
  | "UPDATE_USER"
  | "SUSPEND_USER"
  | "ARCHIVE_USER"
  | "ASSIGN_ROLE"
  | "ASSIGN_SCOPE";

function text(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

function safeKey(formData: FormData) {
  const supplied = text(formData, "idempotency_key");
  return supplied || `access-ui-${crypto.randomUUID()}`;
}

function accessRedirect(kind: "error" | "success", code: string): never {
  redirect(`/dashboard/access?${kind}=${encodeURIComponent(code)}`);
}

async function requireManagerContext(requiredPermissions: Array<"USER_CREATE" | "USER_UPDATE" | "USER_SUSPEND" | "USER_ARCHIVE" | "ROLE_ASSIGN" | "SCOPE_ASSIGN">) {
  for (const permission of requiredPermissions) await requirePermission(permission);
  const context = await requireAccessContext();
  if (!context.profile.organization_id) accessRedirect("error", "actor-scope");
  return context;
}

function mapDbError(message: string) {
  const known = [
    "ACCESS_ADMIN_SELF_ADMIN_DENIED",
    "ACCESS_ADMIN_PROTECTED_ROLE_DENIED",
    "ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE",
    "ACCESS_ADMIN_SCOPE_ESCALATION_DENIED",
    "ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED",
    "ACCESS_ADMIN_SUSPEND_BEFORE_ARCHIVE_REQUIRED",
    "ACCESS_ADMIN_TARGET_NOT_ACTIVE",
    "ACCESS_ADMIN_ARCHIVED_IMMUTABLE",
    "ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED",
    "ACCESS_ADMIN_ACTIVE_BOARD_ALREADY_EXISTS",
    "ACCESS_ADMIN_UAT_DEVELOPMENT_ONLY",
    "ACCESS_ADMIN_IDEMPOTENCY_CONFLICT",
  ];
  return known.find((code) => message.includes(code))?.toLowerCase().replaceAll("access_admin_", "").replaceAll("_", "-") ?? "command-failed";
}

async function executeCommand(
  actorProfileId: string,
  command: AccessCommand,
  args: {
    targetProfileId: string;
    fullName?: string;
    phone?: string | null;
    roleCode?: string;
    dataScopeId?: string;
    reason: string;
    idempotencyKey: string;
  },
) {
  const admin = createAdminClient();
  const rpc = admin.rpc.bind(admin) as unknown as (fn: string, args: Record<string, unknown>) => Promise<AdminRpcResult>;
  const { error } = await rpc("execute_access_admin_command", {
    p_actor_profile_id: actorProfileId,
    p_command_type: command,
    p_target_auth_user_id: null,
    p_target_profile_id: args.targetProfileId,
    p_full_name: args.fullName ?? null,
    p_phone: args.phone ?? null,
    p_role_code: args.roleCode ?? null,
    p_data_scope_id: args.dataScopeId ?? null,
    p_reason: args.reason,
    p_idempotency_key: args.idempotencyKey,
  });
  if (error) accessRedirect("error", mapDbError(error.message));
}

export async function inviteOperationalUserAction(formData: FormData) {
  const { profile } = await requireManagerContext(["USER_CREATE", "ROLE_ASSIGN", "SCOPE_ASSIGN"]);
  const email = text(formData, "email").toLowerCase();
  const fullName = text(formData, "full_name");
  const phone = text(formData, "phone");
  const roleCode = text(formData, "role_code").toUpperCase();
  const dataScopeId = text(formData, "data_scope_id");
  const reason = text(formData, "reason");
  const idempotencyKey = safeKey(formData);

  if (!email || !email.includes("@") || !fullName || !reason || !dataScopeId || !ASSIGNABLE_ROLES.has(roleCode)) {
    accessRedirect("error", "invalid-invite");
  }

  const admin = createAdminClient();
  const { data: invite, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName },
  });
  if (inviteError || !invite.user?.id) {
    console.error("Access invitation failed", inviteError?.message ?? "missing invited user");
    accessRedirect("error", "invite-failed");
  }

  const rpc = admin.rpc.bind(admin) as unknown as (fn: string, args: Record<string, unknown>) => Promise<AdminRpcResult>;
  const { error } = await rpc("execute_access_admin_command", {
    p_actor_profile_id: profile.id,
    p_command_type: "PROVISION_USER",
    p_target_auth_user_id: invite.user.id,
    p_target_profile_id: null,
    p_full_name: fullName,
    p_phone: phone || null,
    p_role_code: roleCode,
    p_data_scope_id: dataScopeId,
    p_reason: reason,
    p_idempotency_key: idempotencyKey,
  });
  if (error) {
    console.error("Access provisioning failed after Auth invite; invited profile remains fail-closed PENDING if DB command rolled back", error.message);
    accessRedirect("error", mapDbError(error.message));
  }
  accessRedirect("success", "user-invited");
}

export async function updateOperationalUserAction(formData: FormData) {
  const { profile } = await requireManagerContext(["USER_UPDATE"]);
  const targetProfileId = text(formData, "profile_id");
  const fullName = text(formData, "full_name");
  const phone = text(formData, "phone");
  const reason = text(formData, "reason");
  if (!targetProfileId || !fullName || !reason) accessRedirect("error", "invalid-update");
  await executeCommand(profile.id, "UPDATE_USER", { targetProfileId, fullName, phone, reason, idempotencyKey: safeKey(formData) });
  accessRedirect("success", "user-updated");
}

export async function suspendOperationalUserAction(formData: FormData) {
  const { profile } = await requireManagerContext(["USER_SUSPEND"]);
  const targetProfileId = text(formData, "profile_id");
  const reason = text(formData, "reason");
  if (!targetProfileId || !reason) accessRedirect("error", "invalid-suspend");
  await executeCommand(profile.id, "SUSPEND_USER", { targetProfileId, reason, idempotencyKey: safeKey(formData) });
  accessRedirect("success", "user-suspended");
}

export async function archiveOperationalUserAction(formData: FormData) {
  const { profile } = await requireManagerContext(["USER_ARCHIVE"]);
  const targetProfileId = text(formData, "profile_id");
  const reason = text(formData, "reason");
  if (!targetProfileId || !reason) accessRedirect("error", "invalid-archive");
  await executeCommand(profile.id, "ARCHIVE_USER", { targetProfileId, reason, idempotencyKey: safeKey(formData) });
  accessRedirect("success", "user-archived");
}

export async function assignOperationalRoleAction(formData: FormData) {
  const { profile } = await requireManagerContext(["ROLE_ASSIGN"]);
  const targetProfileId = text(formData, "profile_id");
  const roleCode = text(formData, "role_code").toUpperCase();
  const reason = text(formData, "reason");
  if (!targetProfileId || !reason || !ASSIGNABLE_ROLES.has(roleCode)) accessRedirect("error", "invalid-role");
  await executeCommand(profile.id, "ASSIGN_ROLE", { targetProfileId, roleCode, reason, idempotencyKey: safeKey(formData) });
  accessRedirect("success", "role-assigned");
}

export async function assignOperationalScopeAction(formData: FormData) {
  const { profile } = await requireManagerContext(["SCOPE_ASSIGN"]);
  const targetProfileId = text(formData, "profile_id");
  const dataScopeId = text(formData, "data_scope_id");
  const reason = text(formData, "reason");
  if (!targetProfileId || !dataScopeId || !reason) accessRedirect("error", "invalid-scope");
  await executeCommand(profile.id, "ASSIGN_SCOPE", { targetProfileId, dataScopeId, reason, idempotencyKey: safeKey(formData) });
  accessRedirect("success", "scope-assigned");
}

export async function bootstrapFirstBoardUatAction(formData: FormData) {
  const { profile } = await requireManagerContext(["USER_CREATE", "ROLE_ASSIGN", "SCOPE_ASSIGN"]);
  const email = text(formData, "email").toLowerCase();
  const fullName = text(formData, "full_name");
  const phone = text(formData, "phone");
  const dataScopeId = text(formData, "data_scope_id");
  const reason = text(formData, "reason");
  const idempotencyKey = safeKey(formData);
  if (!email || !email.includes("@") || !fullName || !dataScopeId || !reason) accessRedirect("error", "invalid-board-bootstrap");

  const admin = createAdminClient();
  const { data: invite, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { full_name: fullName },
  });
  if (inviteError || !invite.user?.id) {
    console.error("First BOARD Auth invitation failed", inviteError?.message ?? "missing invited user");
    accessRedirect("error", "invite-failed");
  }

  const rpc = admin.rpc.bind(admin) as unknown as (fn: string, args: Record<string, unknown>) => Promise<AdminRpcResult>;
  const { error } = await rpc("bootstrap_first_board_uat", {
    p_actor_profile_id: profile.id,
    p_target_auth_user_id: invite.user.id,
    p_full_name: fullName,
    p_phone: phone || null,
    p_data_scope_id: dataScopeId,
    p_reason: reason,
    p_idempotency_key: idempotencyKey,
  });
  if (error) {
    console.error("First BOARD provisioning failed after Auth invite", error.message);
    accessRedirect("error", mapDbError(error.message));
  }
  accessRedirect("success", "first-board-created");
}
