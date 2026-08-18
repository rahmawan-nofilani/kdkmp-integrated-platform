# POS CASH Reversal — Repository Test Plan

Status: repository-only design/test contract. No DEVELOPMENT apply and no deploy are authorized by this document.

## Purpose

Validate the controlled full CASH_POS void flow before the SQL drafts are promoted into a generated Supabase migration.

The test target must be a disposable local/CI Supabase database created from the full repository migration chain. Test business rows must be synthetic and every behavioral test must run inside a transaction that is rolled back.

## Required positive scenario

Create or reuse the existing synthetic POS fixture, then complete exactly one CASH_POS sale through the same public `complete_cash_pos_sale` command used by the application.

Capture immutable-content fingerprints before reversal for:

- original sale commercial fields and timestamps except workflow status/updated_at;
- sales transaction lines;
- original POS receipt;
- original SALE_ISSUE movement and its lines;
- original POSTED journal and its lines;
- original CASH_SALE movement.

Grant `SALES_VOID` only inside the disposable test transaction to the synthetic actor used by the test. The repository migration itself must not map `SALES_VOID` to any role.

Open/retain an own OPEN POS shift with enough tracked drawer cash, then call `reverse_cash_pos_sale` with a fixed idempotency key.

The command must produce exactly one of each:

- `sales_returns` row with status `POSTED`;
- refund `payment_intents` row;
- refund `payment_attempts` row;
- `RETURN_IN` inventory movement linked by `reversal_of_movement_id`;
- reversing POSTED journal linked by `reversal_of_entry_id`;
- `CASH_REFUND` / `OUT` POS cash movement linked to the original CASH_SALE;
- `pos_refund_receipts` row linked to original sale and original POS receipt;
- one `pos_cash_reversal_commands` row containing all result IDs;
- one audit event `POS_CASH_SALE_VOIDED`.

## Accounting assertions

The reversing journal must be created through `DRAFT -> VALIDATED -> POSTED` and must post into an accounting period that is OPEN on the reversal date.

For every original journal line, the reversal must contain the same account and exact opposite debit/credit amounts. Sum debit must equal sum credit and be greater than zero.

The original POSTED journal must remain unchanged.

## Inventory assertions

The reversal movement must start DRAFT and end POSTED.

Each RETURN_IN line must mirror the exact original SALE_ISSUE line for item, base UOM, lot, warehouse node, quantity, base quantity, and unit cost. The returned stock must enter AVAILABLE at the same warehouse node from which the sale issued it.

The original SALE_ISSUE movement and lines must remain unchanged.

## Cash assertions

The refund must use the requesting actor's own OPEN shift and ACTIVE terminal. Before execution, tracked drawer cash is:

`opening_cash + POSTED IN movements - POSTED OUT movements`.

The command must reject a refund larger than that tracked amount.

A successful refund creates exactly one POSTED `CASH_REFUND` movement with direction `OUT`, amount equal to the original sale total, and `reversal_of_movement_id` equal to the original CASH_SALE movement.

## Payment assertions

The original payment intent/attempt must start `SETTLED` and end `REFUNDED` only after all new reversal legs exist.

The original allocated sale payment allocation must end `REVERSED`.

The refund payment intent/attempt must be CASH_POS, amount equal to the original sale total, and settle only within the same atomic transaction.

## Receipt assertions

The original POS receipt must not be changed.

A new refund receipt must contain a unique refund number, original sale ID, original receipt ID, refund shift/terminal, refund payment references, CASH_REFUND movement ID, amount, currency, reason code, and issued timestamp.

## Sale-state assertions

The original sale is not copied or rewritten. Commercial values, source links, receipt reference, sold/completed timestamps, and lines remain unchanged.

Only the allowed workflow state changes from `COMPLETED` to `VOIDED` plus `updated_at` may change on the original sale.

## Idempotency assertions

Calling the RPC again with the same actor, sale, shift, reason, note, and exact same idempotency key must return the already-created result IDs and create no duplicate financial, inventory, journal, receipt, or audit records.

A second independent idempotency key for the same already-voided sale must fail closed.

Reusing an idempotency key with a different sale, shift, reason, or note must fail with `POS_IDEMPOTENCY_CONFLICT`.

## Required negative scenarios

All must leave zero partial reversal records:

1. actor lacks `SALES_VOID`;
2. actor lacks `POS_SHIFT_MANAGE`;
3. sale is not COMPLETED;
4. sale is not POS/CASH_POS;
5. refund shift is closed/missing;
6. refund shift belongs to another cashier;
7. refund shift is outside sale scope;
8. terminal is not ACTIVE;
9. tracked drawer cash is insufficient;
10. original cash movement is missing/mismatched;
11. original inventory movement/lines are missing/mismatched;
12. original journal/lines are missing;
13. original payment intent/attempt/allocation are missing/mismatched;
14. original receipt is missing/mismatched;
15. no OPEN accounting period exists on reversal date;
16. reason code/note violates validation rules.

## Rollback proof

At the end of each positive/negative test transaction execute ROLLBACK. Persistent DEVELOPMENT or CI fixture counts must return to their baseline.

The repository test must never depend on production data and must never contact payment providers.

## Promotion gates

Before promotion from draft SQL into `database/migrations/`:

- generate the canonical migration filename using the project's pinned Supabase CLI, never a hand-invented timestamp;
- replay the complete migration chain in a disposable database;
- execute the positive and negative rollback tests above;
- confirm every new FK has a covering index;
- run Supabase security/performance advisors and ensure no new security finding is introduced;
- run Application CI and Database Migration CI on the same reviewed commit.

Only after those gates pass may a separate owner authorization be requested for any Supabase DEVELOPMENT apply. Production and deploy remain separate authorization boundaries.
