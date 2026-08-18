# POS CASH Reversal — Repository Implementation Checkpoint

Date: 2026-08-18
Branch: `agent/pos-cash-reversal`
Environment authority: repository-only. No Supabase apply and no deploy authorized.

## Purpose

Add a controlled full void/reversal flow for an already `COMPLETED` CASH_POS sale without editing historical commercial, payment, inventory, accounting, receipt, or cash records.

## Intended atomic result

A successful reversal must create all of the following in one PostgreSQL transaction:

1. `sales_returns` record linked to the original completed sale;
2. new `REFUND` payment intent and CASH_POS refund attempt;
3. `RETURN_IN` inventory movement linked through `reversal_of_movement_id` to the original `SALE_ISSUE`;
4. POSTED reversing journal linked through `reversal_of_entry_id` to the original POSTED sale journal;
5. `CASH_REFUND` / `OUT` POS cash movement linked through `reversal_of_movement_id` to the original `CASH_SALE` movement;
6. original payment lifecycle moves from SETTLED to REFUNDED only after every reversal leg succeeds;
7. original sale workflow status moves from `COMPLETED` to `VOIDED` while all original content remains unchanged;
8. an audit log records the controlled reversal identifiers and reason.

If any leg fails, the whole command must roll back.

## Authorization boundary

- Execution requires privileged permission `SALES_VOID`.
- This slice does **not** map `SALES_VOID` to Cashier, Manager, Supervisor, Admin, or any other role.
- A separate owner/policy checkpoint must decide who may void a completed sale.
- Refund cash requires an OPEN POS shift in the same organization/node/unit as the original sale.
- No direct browser writes to authoritative sale, inventory, journal, payment, return, or cash tables are introduced.

## Idempotency

The command uses one external idempotency key and stores all generated reversal identifiers. Retry with the same actor/sale/shift/reason must return the already-generated result rather than duplicate money, stock, journal, or audit effects. A second independent completed reversal for the same sale must be rejected.

## Current repository state

Implemented on the branch:

- `database/drafts/pos_cash_reversal_controlled_flow.sql`
  - review draft only; not a migration;
  - controlled command table + RLS;
  - private validated trigger;
  - public security-invoker RPC;
  - reversal uniqueness guards.
- `src/types/pos-reversal.ts`
  - typed command/RPC contract.
- `src/app/dashboard/pos/reversal-actions.ts`
  - server-side validation and safe user-facing error mapping.

No UI trigger/button is exposed yet.

## Why the SQL remains under `database/drafts/`

The project requires migration files to be generated through the pinned Supabase CLI rather than assigning a timestamp manually. The current execution environment does not have the pinned CLI available, and the attempted `npx` path did not complete. The draft therefore stays non-executable in repository migration history until the canonical generator path is available.

## Required checks before migration promotion

- generate canonical migration basename through pinned Supabase CLI;
- clean-replay the full repository migration chain in disposable Supabase;
- verify every new FK has a covering index;
- positive full cash reversal test;
- idempotent retry test;
- duplicate independent reversal rejection;
- permission denial test without `SALES_VOID`;
- closed/wrong-scope refund-shift rejection;
- non-COMPLETED and non-CASH_POS rejection;
- exact mirror verification for journal debit/credit;
- exact reverse verification for inventory quantity/lot/cost;
- original sale, lines, receipt, original journal, original inventory movement, and original cash movement remain unchanged;
- transaction rollback test leaves persistent test artifacts at zero;
- Supabase Security Advisor adds no new finding;
- Application CI and Database Migration CI pass before merge.

## Explicit non-scope for this checkpoint

- no Supabase DEVELOPMENT write/apply;
- no production database action;
- no Cloudflare or Vercel deploy;
- no QRIS or bank-transfer refund;
- no partial item return/refund;
- no role grant for `SALES_VOID`;
- no production cutover;
- no paid-service activation.
