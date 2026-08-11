"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asCooperativeClient } from "@/types/cooperative-core";

function errorCode(message: string) {
  if (message.includes("MEMBER_NUMBER_ALREADY_EXISTS")) return "duplicate-number";
  if (message.includes("MEMBER_NAME_REQUIRED")) return "missing-name";
  if (message.includes("KDKMP_NODE_REQUIRED")) return "node-required";
  if (message.includes("MEMBER_STATUS_REASON_REQUIRED")) return "reason-required";
  if (message.includes("MEMBER_STATUS_TRANSITION_NOT_ALLOWED")) return "transition-not-allowed";
  if (message.includes("MEMBER_SCOPE_DENIED")) return "scope-denied";
  return "system";
}

export async function createMemberAction(formData: FormData) {
  await requirePermission("MEMBER_CREATE");
  const fullName = String(formData.get("full_name") ?? "").trim();
  const memberNumber = String(formData.get("member_number") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim();

  if (!fullName) {
    redirect("/dashboard/members?error=missing-name");
  }

  const { supabase } = await requireAccessContext();
  const db = asCooperativeClient(supabase);
  const { error } = await db.rpc("create_member", {
    p_full_name: fullName,
    p_member_number: memberNumber || undefined,
    p_notes: notes || undefined,
  });

  if (error) {
    redirect(`/dashboard/members?error=${errorCode(error.message)}`);
  }

  revalidatePath("/dashboard/members");
  redirect("/dashboard/members?success=created");
}

export async function changeMemberStatusAction(formData: FormData) {
  await requirePermission("MEMBER_STATUS_CHANGE");
  const memberId = String(formData.get("member_id") ?? "").trim();
  const newStatus = String(formData.get("new_status") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  if (!memberId || !newStatus) {
    redirect("/dashboard/members?error=invalid-status-request");
  }

  const { supabase } = await requireAccessContext();
  const db = asCooperativeClient(supabase);
  const { error } = await db.rpc("change_member_status", {
    p_member_id: memberId,
    p_new_status: newStatus,
    p_reason: reason || undefined,
  });

  if (error) {
    redirect(`/dashboard/members?error=${errorCode(error.message)}`);
  }

  revalidatePath("/dashboard/members");
  redirect("/dashboard/members?success=status-updated");
}
