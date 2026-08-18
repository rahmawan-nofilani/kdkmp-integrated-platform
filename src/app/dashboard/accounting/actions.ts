"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

type RpcResult = { data: unknown; error: { message: string } | null };

type AccountingCommandRpc = (
  fn: "create_manual_journal_draft" | "validate_manual_journal" | "authorize_manual_journal_post" | "post_manual_journal",
  args: Record<string, unknown>,
) => Promise<RpcResult>;

function commandError(message: string) {
  if (message.includes("ACCOUNTING_PERIOD_NOT_ACCESSIBLE")) return "period-access";
  if (message.includes("ACCOUNTING_PERIOD_NOT_OPEN")) return "period-closed";
  if (message.includes("ACCOUNTING_ENTRY_DATE_OUTSIDE_PERIOD")) return "date-outside-period";
  if (message.includes("ACCOUNTING_SCOPE_DENIED")) return "scope-denied";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_BALANCED")) return "not-balanced";
  if (message.includes("ACCOUNTING_JOURNAL_ACCOUNT_INVALID")) return "account-invalid";
  if (message.includes("ACCOUNTING_JOURNAL_LINES_INVALID")) return "lines-invalid";
  if (message.includes("ACCOUNTING_MAKER_CHECKER_VIOLATION")) return "maker-checker";
  if (message.includes("ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION")) return "maker-checker-poster";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_DRAFT")) return "not-draft";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_VALIDATED")) return "not-validated";
  if (message.includes("ACCOUNTING_POST_DENIED")) return "post-denied";
  if (message.includes("ACCOUNTING_POST_APPROVAL_REQUEST_MISSING")) return "approval-missing";
  if (message.includes("ACCOUNTING_POST_APPROVAL_NOT_OPEN")) return "approval-not-open";
  if (message.includes("ACCOUNTING_CONFLICT_DECLARATION_REQUIRED")) return "conflict-required";
  if (message.includes("ACCOUNTING_POST_REASON_REQUIRED")) return "post-reason-required";
  if (message.includes("ACCOUNTING_POSTER_NOT_AUTHORIZING_BOARD_ACTOR")) return "poster-not-authorizer";
  if (message.includes("ACCOUNTING_IDEMPOTENCY_CONFLICT")) return "idempotency";
  return "system";
}

function commandRpc(client: unknown): AccountingCommandRpc {
  const rpc = (client as { rpc: { bind: (value: unknown) => unknown } }).rpc;
  return rpc.bind(client) as AccountingCommandRpc;
}

export async function createManualJournalDraftAction(formData: FormData) {
  await requirePermission("ACCOUNTING_DRAFT_CREATE");

  const periodId = String(formData.get("accounting_period_id") ?? "").trim();
  const entryDate = String(formData.get("entry_date") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const sourceReference = String(formData.get("source_reference") ?? "").trim();
  const debitAccountId = String(formData.get("debit_account_id") ?? "").trim();
  const creditAccountId = String(formData.get("credit_account_id") ?? "").trim();
  const amount = Number(formData.get("amount") ?? 0);

  if (!periodId || !entryDate || !description || !debitAccountId || !creditAccountId || debitAccountId === creditAccountId || !Number.isFinite(amount) || amount <= 0) {
    redirect("/dashboard/accounting?error=invalid-draft-input");
  }

  const { supabase } = await requireAccessContext();
  const rpc = commandRpc(supabase);
  const idempotencyKey = `accounting-ui-create-${crypto.randomUUID()}`;
  const { error } = await rpc("create_manual_journal_draft", {
    p_accounting_period_id: periodId,
    p_entry_date: entryDate,
    p_description: description,
    p_lines: [
      { account_id: debitAccountId, debit: amount, credit: 0, memo: description },
      { account_id: creditAccountId, debit: 0, credit: amount, memo: description },
    ],
    p_idempotency_key: idempotencyKey,
    p_source_reference: sourceReference || null,
  });

  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);

  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=draft-created");
}

export async function validateManualJournalAction(formData: FormData) {
  await requirePermission("ACCOUNTING_VALIDATE");

  const journalEntryId = String(formData.get("journal_entry_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!journalEntryId) redirect("/dashboard/accounting?error=invalid-journal");

  const { supabase } = await requireAccessContext();
  const rpc = commandRpc(supabase);
  const idempotencyKey = `accounting-ui-validate-${crypto.randomUUID()}`;
  const { error } = await rpc("validate_manual_journal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: idempotencyKey,
    p_reason: reason || null,
  });

  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);

  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=validated");
}

export async function authorizeAndPostManualJournalAction(formData: FormData) {
  await requirePermission("ACCOUNTING_POST");

  const journalEntryId = String(formData.get("journal_entry_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const conflictDeclared = formData.get("conflict_declared") === "on";
  if (!journalEntryId) redirect("/dashboard/accounting?error=invalid-journal");
  if (!reason) redirect("/dashboard/accounting?error=post-reason-required");
  if (!conflictDeclared) redirect("/dashboard/accounting?error=conflict-required");

  const { supabase } = await requireAccessContext();
  const rpc = commandRpc(supabase);
  const authorizationKey = `accounting-ui-authorize-${crypto.randomUUID()}`;
  const postKey = `accounting-ui-post-${crypto.randomUUID()}`;

  const { error: authorizationError } = await rpc("authorize_manual_journal_post", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: authorizationKey,
    p_reason: reason,
    p_conflict_declared: true,
  });
  if (authorizationError) redirect(`/dashboard/accounting?error=${commandError(authorizationError.message)}`);

  const { error: postError } = await rpc("post_manual_journal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: postKey,
    p_reason: reason,
  });
  if (postError) redirect(`/dashboard/accounting?error=${commandError(postError.message)}`);

  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=posted");
}
