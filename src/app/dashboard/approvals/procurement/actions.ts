"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

type RpcResult = { data: unknown; error: { message: string } | null };

type ProcurementApprovalRpc = (
  fn: "approve_purchase_order",
  args: {
    p_purchase_order_id: string;
    p_idempotency_key: string;
    p_reason: string;
    p_conflict_declared: boolean;
  },
) => Promise<RpcResult>;

function commandRpc(client: unknown): ProcurementApprovalRpc {
  const rpc = (client as { rpc: { bind: (value: unknown) => unknown } }).rpc;
  return rpc.bind(client) as ProcurementApprovalRpc;
}

function commandError(message: string) {
  if (message.includes("PROCUREMENT_PERMISSION_DENIED")) return "permission-denied";
  if (message.includes("PROCUREMENT_SCOPE_DENIED")) return "scope-denied";
  if (message.includes("PROCUREMENT_APPROVAL_REQUEST_MISSING")) return "approval-missing";
  if (message.includes("PROCUREMENT_APPROVAL_NOT_OPEN")) return "approval-not-open";
  if (message.includes("PROCUREMENT_REQUESTER_CANNOT_APPROVE")) return "requester-cannot-approve";
  if (message.includes("PROCUREMENT_CONFLICT_DECLARATION_REQUIRED")) return "conflict-required";
  if (message.includes("PROCUREMENT_APPROVAL_REASON_REQUIRED")) return "reason-required";
  if (message.includes("PROCUREMENT_ENTITY_NOT_PENDING_APPROVAL")) return "not-pending";
  if (message.includes("PROCUREMENT_IDEMPOTENCY_CONFLICT")) return "idempotency";
  return "system";
}

export async function approvePurchaseOrderAction(formData: FormData) {
  await requirePermission("PURCHASE_APPROVE");

  const purchaseOrderId = String(formData.get("purchase_order_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const conflictDeclared = formData.get("conflict_declared") === "true";

  if (!purchaseOrderId) redirect("/dashboard/approvals/procurement?error=invalid-po");
  if (!reason || reason.length > 500) redirect("/dashboard/approvals/procurement?error=reason-required");
  if (!conflictDeclared) redirect("/dashboard/approvals/procurement?error=conflict-required");

  const { supabase } = await requireAccessContext();
  const { error } = await commandRpc(supabase)("approve_purchase_order", {
    p_purchase_order_id: purchaseOrderId,
    p_idempotency_key: `procurement-ui-approve-po-${crypto.randomUUID()}`,
    p_reason: reason,
    p_conflict_declared: true,
  });

  if (error) redirect(`/dashboard/approvals/procurement?error=${commandError(error.message)}`);

  revalidatePath("/dashboard/approvals");
  revalidatePath("/dashboard/approvals/procurement");
  redirect("/dashboard/approvals/procurement?success=approved");
}
