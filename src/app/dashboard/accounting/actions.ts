"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

type RpcResult = { data: unknown; error: { message: string } | null };

type AccountingCommandRpc = (
  fn:
    | "create_manual_journal_draft"
    | "validate_manual_journal"
    | "authorize_manual_journal_post"
    | "post_manual_journal"
    | "create_manual_journal_reversal_draft"
    | "validate_manual_journal_reversal"
    | "authorize_manual_journal_reversal"
    | "post_manual_journal_reversal"
    | "soft_close_accounting_period"
    | "hard_close_accounting_period",
  args: Record<string, unknown>,
) => Promise<RpcResult>;

function commandError(message: string) {
  if (message.includes("ACCOUNTING_PERIOD_NOT_ACCESSIBLE")) return "period-access";
  if (message.includes("ACCOUNTING_PERIOD_NOT_OPEN")) return "period-closed";
  if (message.includes("ACCOUNTING_PERIOD_NOT_SOFT_CLOSED")) return "period-not-soft-closed";
  if (message.includes("ACCOUNTING_PERIOD_NOT_ENDED")) return "period-not-ended";
  if (message.includes("ACCOUNTING_PERIOD_MANAGE_DENIED")) return "period-manage-denied";
  if (message.includes("ACCOUNTING_PERIOD_CLOSE_REASON_REQUIRED")) return "period-close-reason-required";
  if (message.includes("ACCOUNTING_PERIOD_HAS_UNPOSTED_JOURNALS")) return "period-has-unposted";
  if (message.includes("ACCOUNTING_PERIOD_HAS_OPEN_APPROVALS")) return "period-has-approvals";
  if (message.includes("ACCOUNTING_PERIOD_HAS_UNRESOLVED_RECONCILIATION")) return "period-has-reconciliation";
  if (message.includes("ACCOUNTING_PERIOD_HAS_UNBALANCED_POSTED_JOURNAL")) return "period-has-unbalanced";
  if (message.includes("ACCOUNTING_PERIOD_SOFT_CLOSE_EVIDENCE_MISSING")) return "period-soft-evidence-missing";
  if (message.includes("ACCOUNTING_PERIOD_CLOSE_ACTOR_SEPARATION_REQUIRED")) return "period-close-separation";
  if (message.includes("ACCOUNTING_ENTRY_DATE_OUTSIDE_PERIOD")) return "date-outside-period";
  if (message.includes("ACCOUNTING_SCOPE_DENIED")) return "scope-denied";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_BALANCED")) return "not-balanced";
  if (message.includes("ACCOUNTING_JOURNAL_ACCOUNT_INVALID")) return "account-invalid";
  if (message.includes("ACCOUNTING_JOURNAL_LINES_INVALID")) return "lines-invalid";
  if (message.includes("ACCOUNTING_MAKER_CHECKER_VIOLATION")) return "maker-checker";
  if (message.includes("ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION")) return "maker-checker-poster";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_DRAFT")) return "not-draft";
  if (message.includes("ACCOUNTING_JOURNAL_NOT_VALIDATED")) return "not-validated";
  if (message.includes("ACCOUNTING_REVERSAL_REASON_REQUIRED")) return "reversal-reason-required";
  if (message.includes("ACCOUNTING_REVERSAL_SOURCE_NOT_POSTED")) return "reversal-source-not-posted";
  if (message.includes("ACCOUNTING_REVERSAL_MANUAL_SOURCE_REQUIRED")) return "reversal-source-manual";
  if (message.includes("ACCOUNTING_REVERSAL_ALREADY_EXISTS")) return "reversal-exists";
  if (message.includes("ACCOUNTING_REVERSAL_DATE_BEFORE_SOURCE")) return "reversal-date-before-source";
  if (message.includes("ACCOUNTING_REVERSAL_JOURNAL_REQUIRED")) return "reversal-journal-required";
  if (message.includes("ACCOUNTING_REVERSAL_NOT_VALIDATED")) return "reversal-not-validated";
  if (message.includes("ACCOUNTING_REVERSAL_APPROVAL_MISSING")) return "reversal-approval-missing";
  if (message.includes("ACCOUNTING_REVERSAL_APPROVAL_NOT_OPEN")) return "reversal-approval-not-open";
  if (message.includes("ACCOUNTING_REVERSAL_BOARD_AUTHORIZATION_REQUIRED")) return "reversal-authorization-required";
  if (message.includes("ACCOUNTING_REVERSAL_POSTER_NOT_AUTHORIZING_BOARD_ACTOR")) return "reversal-poster-not-authorizer";
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
  const { error } = await rpc("create_manual_journal_draft", {
    p_accounting_period_id: periodId,
    p_entry_date: entryDate,
    p_description: description,
    p_lines: [
      { account_id: debitAccountId, debit: amount, credit: 0, memo: description },
      { account_id: creditAccountId, debit: 0, credit: amount, memo: description },
    ],
    p_idempotency_key: `accounting-ui-create-${crypto.randomUUID()}`,
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
  const { error } = await commandRpc(supabase)("validate_manual_journal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-validate-${crypto.randomUUID()}`,
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
  const { error: authorizationError } = await rpc("authorize_manual_journal_post", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-authorize-${crypto.randomUUID()}`,
    p_reason: reason,
    p_conflict_declared: true,
  });
  if (authorizationError) redirect(`/dashboard/accounting?error=${commandError(authorizationError.message)}`);

  const { error: postError } = await rpc("post_manual_journal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-post-${crypto.randomUUID()}`,
    p_reason: reason,
  });
  if (postError) redirect(`/dashboard/accounting?error=${commandError(postError.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=posted");
}

export async function createManualJournalReversalAction(formData: FormData) {
  await requirePermission("ACCOUNTING_DRAFT_CREATE");
  const originalJournalId = String(formData.get("original_journal_entry_id") ?? "").trim();
  const periodId = String(formData.get("accounting_period_id") ?? "").trim();
  const entryDate = String(formData.get("entry_date") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!originalJournalId || !periodId || !entryDate || !reason) redirect("/dashboard/accounting?error=reversal-reason-required");

  const { supabase } = await requireAccessContext();
  const { error } = await commandRpc(supabase)("create_manual_journal_reversal_draft", {
    p_original_journal_entry_id: originalJournalId,
    p_accounting_period_id: periodId,
    p_entry_date: entryDate,
    p_reason: reason,
    p_idempotency_key: `accounting-ui-reversal-create-${crypto.randomUUID()}`,
  });
  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=reversal-created");
}

export async function validateManualJournalReversalAction(formData: FormData) {
  await requirePermission("ACCOUNTING_VALIDATE");
  const journalEntryId = String(formData.get("journal_entry_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!journalEntryId) redirect("/dashboard/accounting?error=invalid-journal");

  const { supabase } = await requireAccessContext();
  const { error } = await commandRpc(supabase)("validate_manual_journal_reversal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-reversal-validate-${crypto.randomUUID()}`,
    p_reason: reason || null,
  });
  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=reversal-validated");
}

export async function authorizeAndPostManualJournalReversalAction(formData: FormData) {
  await requirePermission("ACCOUNTING_POST");
  const journalEntryId = String(formData.get("journal_entry_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const conflictDeclared = formData.get("conflict_declared") === "on";
  if (!journalEntryId) redirect("/dashboard/accounting?error=invalid-journal");
  if (!reason) redirect("/dashboard/accounting?error=reversal-reason-required");
  if (!conflictDeclared) redirect("/dashboard/accounting?error=conflict-required");

  const { supabase } = await requireAccessContext();
  const rpc = commandRpc(supabase);
  const { error: authorizationError } = await rpc("authorize_manual_journal_reversal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-reversal-authorize-${crypto.randomUUID()}`,
    p_reason: reason,
    p_conflict_declared: true,
  });
  if (authorizationError) redirect(`/dashboard/accounting?error=${commandError(authorizationError.message)}`);

  const { error: postError } = await rpc("post_manual_journal_reversal", {
    p_journal_entry_id: journalEntryId,
    p_idempotency_key: `accounting-ui-reversal-post-${crypto.randomUUID()}`,
    p_reason: reason,
  });
  if (postError) redirect(`/dashboard/accounting?error=${commandError(postError.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=reversal-posted");
}

export async function softCloseAccountingPeriodAction(formData: FormData) {
  await requirePermission("ACCOUNTING_PERIOD_MANAGE");
  const periodId = String(formData.get("accounting_period_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!periodId || !reason) redirect("/dashboard/accounting?error=period-close-reason-required");

  const { supabase } = await requireAccessContext();
  const { error } = await commandRpc(supabase)("soft_close_accounting_period", {
    p_accounting_period_id: periodId,
    p_idempotency_key: `accounting-ui-soft-close-${crypto.randomUUID()}`,
    p_reason: reason,
  });
  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=period-soft-closed");
}

export async function hardCloseAccountingPeriodAction(formData: FormData) {
  await requirePermission("ACCOUNTING_POST");
  const periodId = String(formData.get("accounting_period_id") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const conflictDeclared = formData.get("conflict_declared") === "on";
  if (!periodId || !reason) redirect("/dashboard/accounting?error=period-close-reason-required");
  if (!conflictDeclared) redirect("/dashboard/accounting?error=conflict-required");

  const { supabase } = await requireAccessContext();
  const { error } = await commandRpc(supabase)("hard_close_accounting_period", {
    p_accounting_period_id: periodId,
    p_idempotency_key: `accounting-ui-hard-close-${crypto.randomUUID()}`,
    p_reason: reason,
    p_conflict_declared: true,
  });
  if (error) redirect(`/dashboard/accounting?error=${commandError(error.message)}`);
  revalidatePath("/dashboard/accounting");
  redirect("/dashboard/accounting?success=period-hard-closed");
}
