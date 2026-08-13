# ZC-4B Archive Registry — Activation Checklist

Status: **SQL CONTRACT REVIEWABLE / MIGRATION NOT GENERATED / DATABASE NOT CHANGED**.

This checklist controls the transition from the reviewed ZC-4B SQL contract to an actual Supabase DEVELOPMENT migration.

The reviewed contract lives at:

`database/drafts/zc4b_archive_registry_foundation.sql`

That file is intentionally **not** under `database/migrations/` and must not be applied directly.

## 1. Why this is split into two steps

The repository requires reviewed migration files, while the current execution environment cannot reliably run the pinned Supabase CLI migration generator. Creating a hand-named migration file would bypass the agreed migration-generation discipline.

Therefore:

- **ZC-4B Contract:** review the exact SQL design without changing Supabase;
- **ZC-4B Activation:** generate the real migration with the approved CLI, copy the reviewed SQL into it, test locally/isolated, run advisors, pass PR CI, merge, then apply to DEVELOPMENT.

This split prevents migration-history drift and avoids direct remote DDL.

## 2. Contract scope

The ZC-4B contract contains metadata registries only:

- `system_archive_runs`;
- `system_archive_recovery_tests`.

It does **not** contain:

- business-row archive execution;
- data movement out of operational tables;
- `DELETE`, pruning, partition detach/drop, purge, or vacuum-reclaim automation;
- archive scheduling;
- Cloudflare R2 activation;
- paid storage activation;
- production data onboarding;
- legal-retention-period automation.

`system_archive_holds` is deliberately deferred. A legal/audit/dispute hold registry affects governance permissions and future pruning eligibility and deserves its own reviewed phase before any destructive control is even considered.

## 3. Security contract

The migration must preserve all of these conditions:

- RLS enabled on every new `public` table;
- authenticated users have SELECT only;
- anon has no access;
- no authenticated INSERT/UPDATE/DELETE grants;
- archive visibility requires `SYSTEM_CAPACITY_VIEW` **and** current organization scope;
- cross-organization/KDKMP metadata leakage is prohibited;
- archive run organization and organization-node identity must match;
- terminal recovery-test records are immutable;
- archive state transitions fail closed;
- `ELIGIBLE_FOR_PRUNE` remains blocked in DEVELOPMENT;
- no public/exposed privileged function is added merely to bypass RLS.

## 4. Integrity contract

An archive run may not progress to trusted states without:

- deterministic source-period identity;
- source schema version;
- application commit identity;
- source row-count metadata;
- reconciliation metadata;
- encrypted package SHA-256;
- package byte size;
- destination provider + object identity before `WRITTEN`;
- independent read-back before `READBACK_VERIFIED`;
- at least one PASSED recovery test before `RECOVERY_VERIFIED`.

A storage write acknowledgement alone is not archive verification.

## 5. Performance contract

Every new foreign key must have a covering index from the first migration so ZC-4B does not add to the existing DEVELOPMENT unindexed-FK advisor backlog.

Required indexes include coverage for:

- `system_archive_runs.organization_id`;
- `system_archive_runs.organization_node_id`;
- `system_archive_recovery_tests.archive_run_id`;
- status/class/source-period operational lookup.

## 6. Required activation sequence

Do not skip or reorder these gates.

1. Confirm repository `main` includes the accepted ZC-4A policy and this reviewed ZC-4B contract.
2. Use the approved/pinned Supabase CLI environment.
3. Confirm the CLI version explicitly.
4. Run `supabase migration new zc4b_archive_registry_foundation`.
5. Copy the reviewed contract into the generated migration file without changing the safety semantics.
6. Start/reset an isolated local Supabase environment and apply all migrations from zero.
7. Verify both new tables, constraints, triggers, RLS policies, grants, and indexes.
8. Run negative authorization tests for anon and ordinary authenticated users.
9. Run a scoped read test proving a permitted user cannot see another organization/KDKMP archive metadata.
10. Test allowed state transitions and all rejected transitions.
11. Prove `RECOVERY_VERIFIED` cannot occur without a PASSED recovery test.
12. Prove `ELIGIBLE_FOR_PRUNE` is rejected.
13. Run Supabase security advisor.
14. Run Supabase performance advisor.
15. Compare advisor results with the pre-ZC-4B baseline; no new security warning or unindexed-FK warning is acceptable from this migration.
16. Commit the generated migration on a dedicated branch.
17. Open a PR; inspect the complete patch.
18. Require Application CI success.
19. Merge with head-SHA guard.
20. Only after merge, apply the exact merged migration to DEVELOPMENT.
21. Query the DEVELOPMENT schema read-only to verify table/policy/index presence.
22. Run advisors again after remote apply and compare with baseline.
23. Record evidence in parent Zero-Cost tracker #58.

## 7. Existing advisor baseline before ZC-4B

Before any ZC-4B DDL, the DEVELOPMENT security advisor reported one pre-existing warning:

- leaked-password protection is disabled in Supabase Auth.

This warning is not caused by ZC-4. It should be handled as a separate authentication-hardening decision rather than mixed into the archive migration.

The performance advisor already reports a substantial pre-existing backlog of unindexed foreign keys and unused indexes in other modules. ZC-4B must not increase that backlog.

## 8. Owner-authorization boundary

ZC-4B metadata registry activation does **not** authorize destructive archiving.

Separate explicit owner authorization is still required before any future change that:

- deletes/prunes hot operational rows;
- activates an archive destination requiring billing/payment commitment;
- activates Cloudflare R2;
- introduces automatic object deletion/purge;
- creates a real-data production environment;
- enables production cutover.

## 9. Definition of done

ZC-4B is complete only after the generated migration has passed local/isolated validation, PR Application CI, merge, controlled DEVELOPMENT apply, post-apply verification, post-apply advisors, and tracker evidence.

Until then the status remains **CONTRACT READY / DATABASE UNCHANGED**.
