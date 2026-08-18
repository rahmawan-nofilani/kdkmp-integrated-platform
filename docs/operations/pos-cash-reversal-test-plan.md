# POS CASH Reversal — Verification Plan

Status: official repository migration exists; positive/idempotent rollback proof is automated. No Supabase DEVELOPMENT apply, manual deploy, merge, or production action is authorized by this document.

## Test target

All database behavior must be exercised against a disposable local/CI Supabase database reconstructed from the repository migration chain. Synthetic business rows must run inside a transaction and end in `ROLLBACK`.

The permanent focused workflow is `.github/workflows/pos-cash-reversal-ci.yml`, pinned to Supabase CLI `2.113.0`.

## Positive rollback proof — automated and passing

`database/tests/pos_cash_reversal_rollback.sql` currently proves:

- authenticated/RLS RPC execution with temporary explicit `SALES_VOID` + `POS_SHIFT_MANAGE` grants only inside the disposable transaction;
- an own OPEN refund shift with adequate tracked drawer cash;
- a synthetic COMPLETED CASH_POS sale with settled payment, allocation, SALE_ISSUE, posted balanced journal, CASH_SALE and original receipt;
- `reverse_cash_pos_sale` creates all seven result identifiers:
  - `sales_return_id`;
  - refund payment intent ID;
  - refund payment attempt ID;
  - RETURN_IN inventory movement ID;
  - reversing journal ID;
  - CASH_REFUND movement ID;
  - refund receipt ID;
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

## Authorization invariants

The repository migration itself must never map `SALES_VOID` to a role. Test permissions are temporary explicit user grants inside a disposable transaction only.

Runtime execution requires both `SALES_VOID` and `POS_SHIFT_MANAGE`; the refund shift must belong to the requester, be OPEN, use an ACTIVE terminal, be in the same scope as the source sale, and have sufficient tracked cash.

## Accounting assertions

A reversal journal must be created `DRAFT`, transition through `VALIDATED`, then become `POSTED` in an OPEN accounting period on the reversal date. Every original line must be mirrored on the same account with debit/credit swapped. The original POSTED journal remains immutable.

## Inventory assertions

A reversal movement starts `DRAFT` and ends `POSTED`. `RETURN_IN` lines mirror the original `SALE_ISSUE` lines and return stock to the original warehouse node as AVAILABLE. The original issue remains immutable.

## Cash and payment assertions

Tracked drawer cash is:

`opening_cash + POSTED IN movements - POSTED OUT movements`.

A successful full CASH void creates exactly one POSTED `CASH_REFUND` / `OUT` equal to the original sale total and linked through `reversal_of_movement_id`. Original settled payment state is not changed until all new reversal legs exist atomically.

## Remaining negative/fail-closed matrix

These cases remain required before any recommendation to expose the feature operationally:

1. actor lacks `SALES_VOID`;
2. actor lacks `POS_SHIFT_MANAGE`;
3. sale is not COMPLETED;
4. source is not a qualifying CASH_POS completion;
5. refund shift is closed or missing;
6. refund shift belongs to another cashier;
7. refund shift is outside sale scope;
8. refund terminal is not ACTIVE;
9. tracked drawer cash is insufficient;
10. original cash movement is missing/mismatched;
11. original inventory movement/lines are missing/mismatched;
12. original journal/lines are missing;
13. original payment intent/attempt/allocation are missing/mismatched;
14. original receipt is missing/mismatched;
15. no OPEN accounting period exists on reversal date;
16. reason code/note violates validation rules;
17. a second independent reversal key targets a sale already voided/returning;
18. an idempotency key is reused with different request semantics.

Every negative scenario must prove that no partial refund, stock return, journal, return receipt, or audit success artifact remains.

## Repository gates

Completed:

- canonical migration basename generated with pinned Supabase CLI;
- migration promoted to `database/migrations/20260818023718_pos_cash_reversal_controlled_void.sql`;
- full migration-chain replay passed in Database Migration CI;
- Application CI and OpenNext Build Proof passed after migration introduction;
- focused positive/idempotent rollback CI passed.

Still required before operational exposure:

- expand automated fail-closed coverage for the negative matrix above;
- review security/performance advisor impact after an authorized DEVELOPMENT apply;
- decide by owner/policy who may receive `SALES_VOID`;
- expose UI only after the database and permission policy are actually available in the target environment.

Supabase DEVELOPMENT apply, merge, production, payment-provider activation, and manual deploy are separate authorization boundaries.
