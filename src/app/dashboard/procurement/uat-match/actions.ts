"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

const DEVELOPMENT_ORG_CODE = "DEMO-KDKMP-DEV";
const UAT_PO_NUMBER = "PO-20260819-0DF2F8DD";

type RpcResult = { data: unknown; error: { message: string } | null };
type MatchRpc = (
  fn: "create_match_supplier_invoice",
  args: {
    p_purchase_order_id: string;
    p_invoice_number: string;
    p_invoice_date: string;
    p_lines: Array<{
      purchase_order_line_id: string;
      quantity: number;
      unit_price: number;
      description: string;
    }>;
    p_idempotency_key: string;
  },
) => Promise<RpcResult>;

function commandRpc(client: unknown): MatchRpc {
  const rpc = (client as { rpc: { bind: (value: unknown) => unknown } }).rpc;
  return rpc.bind(client) as MatchRpc;
}

function errorCode(message: string) {
  if (message.includes("PROCUREMENT_PERMISSION_DENIED") || message.includes("PROCUREMENT_MATCH_DENIED")) return "permission-denied";
  if (message.includes("PROCUREMENT_SCOPE_DENIED")) return "scope-denied";
  if (message.includes("PROCUREMENT_PO_NOT_INVOICE_MATCHABLE")) return "po-not-matchable";
  if (message.includes("PROCUREMENT_INVOICE_LINE_INVALID")) return "invalid-line";
  if (message.includes("PROCUREMENT_IDEMPOTENCY_CONFLICT")) return "idempotency";
  return "system";
}

export async function runUatThreeWayMatchAction() {
  await requirePermission("PURCHASE_INVOICE_CREATE");
  await requirePermission("PURCHASE_MATCH");

  const { profile, supabase } = await requireAccessContext();
  if (!profile.organization_id) redirect("/dashboard/procurement/uat-match?error=scope-denied");

  const { data: organization, error: orgError } = await supabase
    .from("organizations")
    .select("code")
    .eq("id", profile.organization_id)
    .maybeSingle();

  if (orgError || organization?.code !== DEVELOPMENT_ORG_CODE) {
    redirect("/dashboard/procurement/uat-match?error=development-only");
  }

  const { data: po, error: poError } = await supabase
    .from("purchase_orders")
    .select("id,po_number,status")
    .eq("organization_id", profile.organization_id)
    .eq("po_number", UAT_PO_NUMBER)
    .maybeSingle();

  if (poError || !po) redirect("/dashboard/procurement/uat-match?error=po-missing");
  if (po.status !== "RECEIVED") redirect("/dashboard/procurement/uat-match?error=po-not-matchable");

  const { data: lines, error: lineError } = await supabase
    .from("purchase_order_lines")
    .select("id,ordered_quantity,unit_price")
    .eq("purchase_order_id", po.id)
    .order("line_no");

  if (lineError || !lines || lines.length !== 1) redirect("/dashboard/procurement/uat-match?error=invalid-line");

  const line = lines[0];
  const orderedQuantity = Number(line.ordered_quantity);
  const unitPrice = Number(line.unit_price);
  if (!Number.isFinite(orderedQuantity) || !Number.isFinite(unitPrice) || orderedQuantity <= 0 || unitPrice < 0) {
    redirect("/dashboard/procurement/uat-match?error=invalid-line");
  }

  const rpc = commandRpc(supabase);
  const invoiceDate = new Date().toISOString().slice(0, 10);

  const matched = await rpc("create_match_supplier_invoice", {
    p_purchase_order_id: po.id,
    p_invoice_number: "UAT-INV-G6-MATCH-001",
    p_invoice_date: invoiceDate,
    p_lines: [{
      purchase_order_line_id: line.id,
      quantity: orderedQuantity,
      unit_price: unitPrice,
      description: "Release-1 DEVELOPMENT UAT exact three-way match",
    }],
    p_idempotency_key: "uat-g6-finance-match-001",
  });

  if (matched.error) redirect(`/dashboard/procurement/uat-match?error=${errorCode(matched.error.message)}`);

  const mismatchQuantity = Math.max(0, orderedQuantity - 1);
  const mismatch = await rpc("create_match_supplier_invoice", {
    p_purchase_order_id: po.id,
    p_invoice_number: "UAT-INV-G6-MISMATCH-001",
    p_invoice_date: invoiceDate,
    p_lines: [{
      purchase_order_line_id: line.id,
      quantity: mismatchQuantity,
      unit_price: unitPrice + 1000,
      description: "Release-1 DEVELOPMENT UAT intentional mismatch — DO NOT PAY",
    }],
    p_idempotency_key: "uat-g6-finance-mismatch-001",
  });

  if (mismatch.error) redirect(`/dashboard/procurement/uat-match?error=${errorCode(mismatch.error.message)}`);

  revalidatePath("/dashboard/procurement");
  revalidatePath("/dashboard/procurement/uat-match");
  redirect("/dashboard/procurement/uat-match?success=completed");
}
