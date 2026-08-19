import { NextRequest, NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const RUN_KEY = "la21FjSFCdYngxq18UxQpzM24IAevtfCPAry6OWjRrRY1lSx9F66gtJKddDgGU4h";
const DEVELOPMENT_ORG_CODE = "DEMO-KDKMP-DEV";
const FINANCE_EMAIL = "nofilanirahmawan+uat-fin@gmail.com";
const UAT_PO_NUMBER = "PO-20260819-0DF2F8DD";
const EXACT_INVOICE = "UAT-INV-G6-MATCH-001";
const MISMATCH_INVOICE = "UAT-INV-G6-MISMATCH-001";

type RoleRelation = { code?: string | null } | Array<{ code?: string | null }> | null;
type RpcResult = { data: unknown; error: { message: string } | null };
type MatchRpc = (fn: "create_match_supplier_invoice", args: {
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
}) => Promise<RpcResult>;

function noStoreJson(body: unknown, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}

function tokenHashFromActionLink(actionLink: string | null | undefined) {
  if (!actionLink) return null;
  const parsed = new URL(actionLink);
  return parsed.searchParams.get("token") ?? parsed.searchParams.get("token_hash");
}

function roleCodesFromRelation(relation: RoleRelation) {
  const rows = Array.isArray(relation) ? relation : relation ? [relation] : [];
  return rows.map((role) => role.code).filter((code): code is string => Boolean(code));
}

function commandRpc(client: unknown): MatchRpc {
  const rpc = (client as { rpc: { bind: (value: unknown) => unknown } }).rpc;
  return rpc.bind(client) as MatchRpc;
}

export async function GET(request: NextRequest) {
  if (request.nextUrl.searchParams.get("key") !== RUN_KEY) {
    return noStoreJson({ error: "not-found" }, 404);
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!supabaseUrl || !publishableKey) {
    return noStoreJson({ error: "supabase-not-configured" }, 500);
  }

  const admin = createAdminClient();

  const { data: organization, error: organizationError } = await admin
    .from("organizations")
    .select("id,code")
    .eq("code", DEVELOPMENT_ORG_CODE)
    .maybeSingle();
  if (organizationError || !organization) {
    return noStoreJson({ error: "development-org-not-found" }, 500);
  }

  const { data: usersPage, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersError) return noStoreJson({ error: "auth-user-lookup-failed" }, 500);
  const authUser = usersPage.users.find((user) => user.email?.toLowerCase() === FINANCE_EMAIL);
  if (!authUser) return noStoreJson({ error: "finance-auth-user-not-found" }, 404);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id,organization_id,status")
    .eq("auth_user_id", authUser.id)
    .maybeSingle();
  if (profileError || !profile || profile.organization_id !== organization.id || profile.status !== "ACTIVE") {
    return noStoreJson({ error: "finance-profile-invalid" }, 403);
  }

  const now = new Date().toISOString();
  const { data: roleAssignments, error: roleError } = await admin
    .from("user_roles")
    .select("roles(code)")
    .eq("profile_id", profile.id)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`);
  if (roleError) return noStoreJson({ error: "finance-role-lookup-failed" }, 500);
  const roleCodes = (roleAssignments ?? []).flatMap((assignment) =>
    roleCodesFromRelation(assignment.roles as RoleRelation),
  );
  if (roleCodes.length !== 1 || roleCodes[0] !== "FINANCE_OFFICER") {
    return noStoreJson({ error: "finance-role-invalid", roleCodes }, 403);
  }

  const { data: po, error: poError } = await admin
    .from("purchase_orders")
    .select("id,po_number,status")
    .eq("organization_id", organization.id)
    .eq("po_number", UAT_PO_NUMBER)
    .maybeSingle();
  if (poError || !po) return noStoreJson({ error: "uat-po-not-found" }, 404);
  if (po.status !== "RECEIVED") return noStoreJson({ error: "uat-po-not-received", status: po.status }, 409);

  const { data: lines, error: linesError } = await admin
    .from("purchase_order_lines")
    .select("id,ordered_quantity,unit_price")
    .eq("purchase_order_id", po.id)
    .order("line_no");
  if (linesError || !lines || lines.length !== 1) {
    return noStoreJson({ error: "uat-po-line-invalid" }, 500);
  }

  const line = lines[0];
  const orderedQuantity = Number(line.ordered_quantity);
  const unitPrice = Number(line.unit_price);
  if (!Number.isFinite(orderedQuantity) || !Number.isFinite(unitPrice) || orderedQuantity <= 0 || unitPrice < 0) {
    return noStoreJson({ error: "uat-po-line-value-invalid" }, 500);
  }

  const { data: generated, error: generateError } = await admin.auth.admin.generateLink({
    type: "recovery",
    email: FINANCE_EMAIL,
  });
  if (generateError) return noStoreJson({ error: "finance-recovery-generation-failed" }, 500);

  const tokenHash = tokenHashFromActionLink(generated.properties?.action_link);
  if (!tokenHash) return noStoreJson({ error: "finance-recovery-token-missing" }, 500);

  const financeClient = createSupabaseClient(supabaseUrl, publishableKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  const { data: verified, error: verifyError } = await financeClient.auth.verifyOtp({
    token_hash: tokenHash,
    type: "recovery",
  });
  if (verifyError || !verified.session || !verified.user || verified.user.email?.toLowerCase() !== FINANCE_EMAIL) {
    return noStoreJson({ error: "finance-session-verification-failed" }, 500);
  }

  const rpc = commandRpc(financeClient);
  const invoiceDate = new Date().toISOString().slice(0, 10);

  const matched = await rpc("create_match_supplier_invoice", {
    p_purchase_order_id: po.id,
    p_invoice_number: EXACT_INVOICE,
    p_invoice_date: invoiceDate,
    p_lines: [{
      purchase_order_line_id: line.id,
      quantity: orderedQuantity,
      unit_price: unitPrice,
      description: "Release-1 DEVELOPMENT UAT exact three-way match",
    }],
    p_idempotency_key: "uat-g6-finance-match-001",
  });
  if (matched.error) {
    await financeClient.auth.signOut();
    return noStoreJson({ error: "exact-match-failed", detail: matched.error.message }, 500);
  }

  const mismatch = await rpc("create_match_supplier_invoice", {
    p_purchase_order_id: po.id,
    p_invoice_number: MISMATCH_INVOICE,
    p_invoice_date: invoiceDate,
    p_lines: [{
      purchase_order_line_id: line.id,
      quantity: Math.max(0, orderedQuantity - 1),
      unit_price: unitPrice + 1000,
      description: "Release-1 DEVELOPMENT UAT intentional mismatch — DO NOT PAY",
    }],
    p_idempotency_key: "uat-g6-finance-mismatch-001",
  });
  if (mismatch.error) {
    await financeClient.auth.signOut();
    return noStoreJson({ error: "mismatch-evidence-failed", detail: mismatch.error.message }, 500);
  }

  await financeClient.auth.signOut();

  const { data: invoices, error: invoiceReadError } = await admin
    .from("supplier_invoices")
    .select("invoice_number,status,matching_status,total_amount")
    .eq("purchase_order_id", po.id)
    .in("invoice_number", [EXACT_INVOICE, MISMATCH_INVOICE])
    .order("invoice_number");
  if (invoiceReadError) return noStoreJson({ error: "invoice-evidence-read-failed" }, 500);

  return noStoreJson({
    status: "completed",
    po_number: UAT_PO_NUMBER,
    finance_email: FINANCE_EMAIL,
    invoices,
  });
}
