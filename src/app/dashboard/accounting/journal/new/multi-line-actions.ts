"use server";

import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

type Line = { account_id: string; debit: number; credit: number; memo: string | null };
type RpcResult = { data: unknown; error: { message: string } | null };

function validMoney(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && Math.round(value * 100) === value * 100;
}

export async function createMultiLineJournalDraftAction(formData: FormData) {
  await requirePermission("ACCOUNTING_DRAFT_CREATE");
  const periodId = String(formData.get("accounting_period_id") ?? "").trim();
  const entryDate = String(formData.get("entry_date") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const sourceReference = String(formData.get("source_reference") ?? "").trim();
  const raw = String(formData.get("lines_json") ?? "");
  let lines: Line[];
  try { lines = JSON.parse(raw) as Line[]; } catch { redirect("/dashboard/accounting/journal/new?error=lines-invalid"); }
  if (!periodId || !entryDate || !description || !Array.isArray(lines) || lines.length < 2 || lines.length > 20) redirect("/dashboard/accounting/journal/new?error=invalid-input");

  let debit = 0; let credit = 0;
  for (const line of lines) {
    if (!line || typeof line.account_id !== "string" || !line.account_id || !validMoney(line.debit) || !validMoney(line.credit)) redirect("/dashboard/accounting/journal/new?error=lines-invalid");
    if (!((line.debit > 0 && line.credit === 0) || (line.credit > 0 && line.debit === 0))) redirect("/dashboard/accounting/journal/new?error=lines-invalid");
    if (line.memo !== null && (typeof line.memo !== "string" || line.memo.length > 500)) redirect("/dashboard/accounting/journal/new?error=lines-invalid");
    debit += line.debit; credit += line.credit;
  }
  if (debit <= 0 || Math.abs(debit - credit) >= 0.005) redirect("/dashboard/accounting/journal/new?error=not-balanced");

  const { supabase } = await requireAccessContext();
  const rpc = supabase.rpc.bind(supabase) as unknown as (fn: "create_manual_journal_draft", args: Record<string, unknown>) => Promise<RpcResult>;
  const { error } = await rpc("create_manual_journal_draft", {
    p_accounting_period_id: periodId,
    p_entry_date: entryDate,
    p_description: description,
    p_lines: lines,
    p_idempotency_key: `accounting-ui-multiline-${crypto.randomUUID()}`,
    p_source_reference: sourceReference || null,
  });
  if (error) {
    const message = error.message;
    if (message.includes("ACCOUNTING_JOURNAL_NOT_BALANCED")) redirect("/dashboard/accounting/journal/new?error=not-balanced");
    if (message.includes("ACCOUNTING_JOURNAL_ACCOUNT_INVALID")) redirect("/dashboard/accounting/journal/new?error=account-invalid");
    if (message.includes("ACCOUNTING_JOURNAL_LINES_INVALID")) redirect("/dashboard/accounting/journal/new?error=lines-invalid");
    if (message.includes("ACCOUNTING_PERIOD_NOT_OPEN")) redirect("/dashboard/accounting/journal/new?error=period-closed");
    redirect("/dashboard/accounting/journal/new?error=system");
  }
  redirect("/dashboard/accounting?success=draft-created");
}
