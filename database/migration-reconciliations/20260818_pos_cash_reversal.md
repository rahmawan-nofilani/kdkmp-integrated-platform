# POS CASH Reversal — DEVELOPMENT Migration History Reconciliation

Date observed: 2026-08-18
Environment: Supabase DEVELOPMENT
Project ref: `qdxybbcksjivcidsupbd`
Repository branch for this record: `agent/pos-reversal-migration-reconciliation`

## Purpose

Record a non-destructive mapping between the canonical repository migration and the version recorded by the Supabase `apply_migration` connector when the already-reviewed SQL was applied to DEVELOPMENT.

This file is **metadata only**. It is not a migration, must never be copied into `database/migrations/`, and must never be executed against any database.

## Canonical repository migration

- Path: `database/migrations/20260818023718_pos_cash_reversal_controlled_void.sql`
- Repository migration version: `20260818023718`
- Canonical migration basename: `20260818023718_pos_cash_reversal_controlled_void`
- Source branch merged through PR #107.
- Main merge commit: `6cdedc6a500f960598d7ecfe2fe0d133c65ea11b`.
- SQL source used for DEVELOPMENT apply: exact blob from `main`; no rewritten SQL was used.

## DEVELOPMENT migration-history observation

The Supabase connector successfully applied the canonical SQL, but remote migration history recorded:

- Remote recorded version: `20260818035938`
- Remote recorded name: `20260818023718_pos_cash_reversal_controlled_void`
- Apply result: SUCCESS

Therefore the repository timestamp and the remote history version are not identical even though the applied SQL source is the canonical repository migration.

## Reconciliation rule

Treat the following as one logical applied migration in DEVELOPMENT:

`repository 20260818023718` ↔ `DEVELOPMENT history 20260818035938 / name 20260818023718_pos_cash_reversal_controlled_void`

Do **not**:

- rename or rewrite the canonical repository migration;
- edit or delete the already-recorded remote migration-history row;
- create a second executable migration containing the same POS reversal DDL;
- re-apply the canonical SQL solely to make timestamps match.

Any future migration-history comparison for DEVELOPMENT must consult this record before declaring this specific version difference to be unapplied drift.

## Post-apply verification observed

After apply, DEVELOPMENT verification confirmed:

- `public.pos_refund_receipts` exists with RLS enabled;
- `public.pos_cash_reversal_commands` exists with RLS enabled;
- `public.reverse_cash_pos_sale(uuid,uuid,text,text,text)` exists;
- reversal trigger exists;
- `anon` has no RPC execute privilege;
- `authenticated` has RPC execute privilege subject to application permission/RLS gates;
- baseline role mappings for `SALES_VOID` remain zero;
- fail-closed smoke test left zero reversal command and zero refund receipt artifacts.

Security Advisor showed no new POS-reversal-specific security finding. The existing Auth warning for leaked-password protection remains separate from this migration. Performance Advisor observations are tracked as normal DEVELOPMENT backlog; newly created reversal indexes may appear unused until workload exists.

## Boundary

This reconciliation record does not authorize any role grant, additional Supabase mutation, manual deployment, provider activation, production action, or production cutover.
