# POS CASH Reversal — Verification Plan

Status: official repository migration exists; positive/idempotent and primary fail-closed rollback proofs are automated. No Supabase DEVELOPMENT apply, manual deploy, merge, or production action is authorized by this document.

## Test target

All database behavior is exercised against a disposable local/CI Supabase database reconstructed from the repository migration chain. Synthetic business rows run inside transactions and end in `ROLLBACK`.

The permanent focused workflow is `.github/workflows/pos-cash-reversal-ci.yml`, pinned to Supabase CLI `2.113.0`.

## Positive rollback proof — automated and passing

`database/tests/pos_cash_reversal_rollback.sql` proves:

- authenticated/RLS RPC execution with temporary explicit `SALES_VOID` + `POS_SHIFT_MANAGE` grants only inside the disposable transaction;
- an own OPEN refund shift with adequate tracked drawer cash;
- a synthetic COMPLETED CASH_POS sale with settled payment, allocation, SALE_ISSUE, posted balanced journal, CASH_SALE and original receipt;
- `reverse_cash_pos_sale` creates all seven result identifiers;
- original sale becomes `VOIDED`;
- original payment intent/attempt become `REFUNDED`;
- original payment allocation becomes `REVERSED`;
- sales return becomes `POSTED`;
- refund cash movement is exact `OUT`, linked to original CASH_SALE;
- RETURN_IN header/line mirrors the original inventory issue item/UOM/lot/node/quantity/cost;
- reversing journal is POSTED, linked to the original journal, mirrors debit/credit, and remains balanced;
- refund receipt links original sale and original receipt with the exact refund amount;
- a retry with the same idempotency key returns the same result identifiers and creates only one command;
- original POS receipt, original inventory header, original journal header, and original cash movement fingerprints remain unchanged;
- all synthetic business rows are rolled back.

## Primary fail-closed proof — automated and passing

`database/tests/pos_cash_reversal_negative.sql` currently proves all of the following fail without leaving a reversal command, sales return, cash refund, or source-sale mutation:

1. actor lacks `SALES_VOID`;
2. actor has `SALES_VOID` but lacks `POS_SHIFT_MANAGE`;
3. source sale is not `COMPLETED`;
4. reversal reason is invalid;
5. refund shift is closed;
6. refund shift belongs to another cashier;
7. refund terminal is not ACTIVE;
8. tracked drawer cash is insufficient;
9. original POSTED `CASH_SALE` movement is missing.

The test also asserts that no baseline role receives `SALES_VOID` from this migration.

## Authorization invariants

The repository migration itself must never map `SALES_VOID` to a role. Test permissions are temporary explicit user grants inside disposable transactions only.

Runtime execution requires both `SALES_VOID` and `POS_SHIFT_MANAGE`; the refund shift must belong to the requester, be OPEN, use an ACTIVE terminal, be in the same scope as the source sale, and have sufficient tracked cash.

## Accounting assertions

A reversal journal is created `DRAFT`, transitions through `VALIDATED`, then becomes `POSTED` in an OPEN accounting period on the reversal date. Every original line is mirrored on the same account with debit/credit swapped. The original POSTED journal remains immutable.

## Inventory assertions

A reversal movement starts `DRAFT` and ends `POSTED`. `RETURN_IN` lines mirror the original `SALE_ISSUE` lines and return stock to the original warehouse node as AVAILABLE. The original issue remains immutable.

## Cash and payment assertions

Tracked drawer cash is:

`opening_cash + POSTED IN movements - POSTED OUT movements`.

A successful full CASH void creates exactly one POSTED `CASH_REFUND` / `OUT` equal to the original sale total and linked through `reversal_of_movement_id`. Original settled payment state is not changed until all new reversal legs exist atomically.

## Remaining deep-integrity matrix

These cases remain useful follow-up coverage before operational exposure:

1. refund shift is outside the sale organization/node/unit scope;
2. original CASH_SALE exists but payment-intent/attempt linkage is mismatched;
3. original inventory movement exists but is wrong type/status;
4. original inventory lines are missing/mismatched;
5. original posted journal or its lines are missing/mismatched;
6. original payment allocation is missing/mismatched;
7. original POS receipt is missing/mismatched;
8. no OPEN accounting period exists on the reversal date;
9. reason note exceeds its validation limit;
10. a second independent reversal key targets a sale already voided/returning;
11. an idempotency key is reused with different request semantics.

Every added negative scenario must prove that no partial refund, stock return, journal, refund receipt, or audit success artifact remains.

## Repository gates

Completed:

- canonical migration basename generated with pinned Supabase CLI;
- migration promoted to `database/migrations/20260818023718_pos_cash_reversal_controlled_void.sql`;
- full migration-chain replay passed in Database Migration CI;
- Application CI and OpenNext Build Proof passed after migration introduction;
- focused positive/idempotent rollback CI passed;
- primary 9-case fail-closed rollback matrix passed;
- one-time SQL drafts and migration-name proof workflow were removed after promotion.

Still required before operational exposure:

- decide whether to extend automated coverage into the remaining deep-integrity matrix;
- after a separately authorized DEVELOPMENT apply, run Supabase security/performance advisors and smoke verification;
- decide by owner/policy who may receive `SALES_VOID`;
- expose UI only after the database migration and permission policy are actually available in the target environment.

Supabase DEVELOPMENT apply, merge, production, payment-provider activation, and manual deploy are separate authorization boundaries.
