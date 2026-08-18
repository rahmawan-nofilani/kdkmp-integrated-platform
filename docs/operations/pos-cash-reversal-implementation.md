# POS CASH Reversal — Operational DEVELOPMENT Checkpoint

Date: 2026-08-18
Canonical backend merge: PR #107 -> `main`
Migration reconciliation merge: PR #108 -> `main`
Fail-closed UI merge: PR #109 -> `main`
Environment: DEVELOPMENT
Production cutover: NOT AUTHORIZED

## Purpose

Provide a controlled full void/reversal flow for an already `COMPLETED` CASH_POS sale without rewriting the historical commercial transaction, original POS receipt, original inventory issue, original posted journal, or original POS cash movement.

## Atomic result

A successful reversal creates, in one PostgreSQL transaction:

1. a `sales_returns` record linked to the original completed sale;
2. a new `REFUND` payment intent and CASH_POS refund attempt;
3. a `RETURN_IN` inventory movement linked through `reversal_of_movement_id` to the original `SALE_ISSUE`;
4. a reversing journal linked through `reversal_of_entry_id` to the original POSTED sale journal, using `DRAFT -> VALIDATED -> POSTED`;
5. a `CASH_REFUND` / `OUT` POS cash movement linked to the original `CASH_SALE` movement;
6. a new authoritative `pos_refund_receipts` record linked to the original POS receipt;
7. reversal of the original payment allocation and transition of the original payment intent/attempt from `SETTLED` to `REFUNDED`;
8. transition of the original sale workflow from `COMPLETED` to `VOIDED` while immutable business content remains unchanged;
9. an audit event containing the controlled reversal identifiers and reason.

If any leg fails, the command transaction fails and no partial reversal is allowed.

## Authorization and cash controls

- Execution requires privileged `SALES_VOID` and `POS_SHIFT_MANAGE`.
- Owner policy approved baseline `SALES_VOID` for `MANAGER` only.
- `CASHIER` remains denied `SALES_VOID`.
- No other baseline role receives `SALES_VOID` through the approved policy migration.
- Refund cash must use the requesting actor's own `OPEN` POS shift on an `ACTIVE` terminal in the same organization/node/unit as the original sale.
- Tracked drawer cash (`opening_cash + POSTED IN - POSTED OUT`) must cover the refund amount.
- No direct browser writes to authoritative sale, inventory, journal, payment, return, receipt, or cash tables are introduced.

## Repository implementation

Authoritative implementation includes:

- `database/migrations/20260818023718_pos_cash_reversal_controlled_void.sql`
  - controlled command table, RLS and indexes;
  - authoritative refund receipt;
  - private validated atomic trigger;
  - public security-invoker RPC `reverse_cash_pos_sale`;
  - reversal uniqueness and idempotency guards.
- `database/migrations/20260818044251_pos_cash_reversal_manager_sales_void_policy.sql`
  - codifies owner-approved MANAGER-only `SALES_VOID` baseline policy;
  - idempotently inserts the MANAGER mapping;
  - fails closed if a non-MANAGER baseline mapping already exists at this migration point;
  - explicitly verifies CASHIER remains denied.
- `src/types/pos-reversal.ts`
  - typed command, refund receipt and seven-output RPC contract.
- `src/app/dashboard/pos/reversal-actions.ts`
  - server-side validation and safe operational error mapping.
- `src/app/dashboard/pos/reversal.tsx`
  - permission-aware Void/Refund confirmation UI.
- `src/app/dashboard/pos/reversal.module.css`
  - isolated reversal UI styling.
- `database/tests/pos_cash_reversal_fixture.sql`
  - minimal local-CI-only posting-account fixture.
- `database/tests/pos_cash_reversal_rollback.sql`
  - synthetic authenticated full-reversal + idempotent retry + immutability assertions, followed by `ROLLBACK`.
- `database/tests/pos_cash_reversal_negative.sql`
  - synthetic fail-closed permission/state/shift/cash/source checks, followed by `ROLLBACK`.
- `database/tests/pos_cash_reversal_role_policy.sql`
  - proves exactly one MANAGER mapping and zero non-MANAGER/CASHIER mappings after full migration replay.
- `.github/workflows/pos-cash-reversal-ci.yml`
  - isolated full migration replay and focused rollback execution using pinned Supabase CLI `2.113.0`.

## Repository verification

The repository CI model proves:

- full migration chain replay succeeds in disposable local Supabase;
- MANAGER-only `SALES_VOID` policy is reproducible from migrations;
- CASHIER and all other baseline roles remain denied `SALES_VOID`;
- positive full CASH reversal produces all seven authoritative result IDs;
- same-key retry is idempotent;
- exact CASH_REFUND, RETURN_IN mirror, reversing journal and refund receipt are created together;
- original payment/allocation transitions are controlled;
- original sale/receipt/inventory/journal/cash evidence is preserved;
- fail-closed matrix rejects missing permission, missing shift permission, invalid sale state/reason, invalid shift/terminal, insufficient drawer cash and missing original CASH_SALE;
- expected failures leave no partial reversal artifacts.

For the legacy negative matrix, focused CI removes the MANAGER role mapping only inside the disposable local CI database after separately proving the approved role policy. This preserves the original no-baseline-role negative scenarios without weakening the repository policy or any remote environment.

## Supabase DEVELOPMENT status

The canonical reversal SQL was authorized and successfully applied to Supabase DEVELOPMENT project `qdxybbcksjivcidsupbd` on 2026-08-18.

Post-apply verification confirmed:

- `public.pos_refund_receipts` exists and RLS is enabled;
- `public.pos_cash_reversal_commands` exists and RLS is enabled;
- `public.reverse_cash_pos_sale(uuid,uuid,text,text,text)` exists;
- reversal trigger exists;
- `anon` cannot execute the RPC;
- `authenticated` can execute the RPC only through application permission/RLS controls.

Owner subsequently authorized the operational role policy in DEVELOPMENT. Verification confirmed:

- `MANAGER` has exactly one baseline `SALES_VOID` mapping;
- `CASHIER` has zero mappings;
- all other baseline roles have zero mappings;
- `SALES_VOID` remains privileged;
- an ACTIVE Manager passes `SALES_VOID` and `POS_SHIFT_MANAGE` gates and reaches later business validation;
- safe smoke using nonexistent transaction identifiers produced no reversal command or refund-receipt artifacts.

No persistent synthetic positive reversal was forced into DEVELOPMENT because the current active Manager had no own OPEN POS shift. Positive end-to-end reversal is already covered transactionally in disposable CI; real operational execution remains subject to the same own-OPEN-shift, active-terminal, drawer-cash and source-integrity gates.

Security Advisor produced no new POS-reversal-specific security finding after schema apply. The existing Auth leaked-password-protection warning remains separate. Performance Advisor continues to show broader DEVELOPMENT index/RLS optimization backlog.

## Migration history reconciliation

The repository reversal migration remains canonical as:

`database/migrations/20260818023718_pos_cash_reversal_controlled_void.sql`

When originally applied through the Supabase connector, DEVELOPMENT migration history recorded:

- remote version: `20260818035938`;
- remote name: `20260818023718_pos_cash_reversal_controlled_void`.

This is treated as metadata-version drift, not a second migration. The canonical file must not be renamed or rewritten, and the remote history row must not be edited solely to force timestamp equality.

Authoritative reconciliation record:

`database/migration-reconciliations/20260818_pos_cash_reversal.md`

The MANAGER-only policy migration is idempotent against the already-authorized DEVELOPMENT role mapping and exists to make fresh repository migration replay reproduce the approved policy.

## Operational exposure

The Void/Refund button is permission-aware and only renders for a user who has both `SALES_VOID` and `POS_SHIFT_MANAGE` plus an own `OPEN` shift. The backend remains the final authority even if UI state is stale.

For the current baseline policy:

- MANAGER may become eligible when the Manager has an own OPEN POS shift and all backend business conditions pass;
- CASHIER cannot become eligible because CASHIER lacks `SALES_VOID`;
- the action is full CASH void/refund only, not partial return/refund;
- QRIS and bank-transfer refunds are outside this slice.

## Remaining POS work after this slice

The full CASH reversal operational foundation is considered complete in DEVELOPMENT once the MANAGER-only repository migration passes CI and merges.

Issue #51 must remain open for:

- trusted QRIS/BANK_TRANSFER backend/provider confirmation and reconciliation;
- controlled partial return/refund beyond full CASH void;
- optional offline draft queue/conflict handling for later hybrid clients, with offline final payment confirmation prohibited.

Deeper source-integrity variants remain candidates for additional CI hardening, including wrong scope, source payment/receipt/inventory/journal corruption, missing OPEN accounting period, semantic idempotency conflicts and second independent reversal attempts.

## Explicit boundary

- CASHIER remains denied `SALES_VOID`;
- `ACCOUNTING_POST` is unchanged;
- no production database action or KDKMP production cutover is authorized;
- no QRIS/bank-transfer provider activation;
- no partial return/refund activation;
- no paid-service activation;
- automatic Vercel Git deployments for the project named `kdkmp-development` are DEVELOPMENT integration activity, not KDKMP production cutover.
