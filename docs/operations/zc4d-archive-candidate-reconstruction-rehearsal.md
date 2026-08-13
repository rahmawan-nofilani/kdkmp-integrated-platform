# ZC-4D Archive Candidate & Reconstruction Rehearsal

Status: **REHEARSAL READY / REAL ARCHIVE EXECUTION NOT ACTIVATED**

## Purpose

ZC-4D proves the archive boundary before any real archive writer is allowed. It extends ZC-4C from “can a synthetic package be encrypted and read back?” to “can the system select only eligible closed-period relational records, preserve their cross-domain relationships, reconstruct them, and reconcile them after read-back?”

This phase is intentionally non-destructive and synthetic-only.

## DEVELOPMENT read-only preflight — 2026-08-13

A read-only aggregate check against Supabase DEVELOPMENT showed:

- accounting periods: `1` total;
- `HARD_CLOSED` accounting periods: `0`;
- sales transactions: `0`;
- payment intents: `0`;
- payment attempts: `0`;
- inventory movements: `2`, both `POSTED`;
- journal entries: `0`;
- archive runs: `0`;
- archive recovery tests: `0`.

Therefore ZC-4D must **not** manufacture a real candidate from DEVELOPMENT. A posted inventory movement by itself is insufficient. A real POS archive unit remains blocked until its accounting period is `HARD_CLOSED` and every dependent transaction control passes.

## Versioned eligibility contract

The rehearsal introduces:

`config/archive/zc4d-pos-transaction-eligibility-v1.json`

The archive unit remains:

`tenant/cooperative + archive class + hard-closed source period`

For `POS_TRANSACTION`, the versioned rehearsal contract requires:

1. sale status `COMPLETED`;
2. sync status `SYNCED`;
3. completion timestamp inside the selected source period;
4. no reversal reference;
5. payment intent `SETTLED`;
6. payment attempt `SETTLED`;
7. inventory movement present and `POSTED`;
8. no inventory reversal reference;
9. journal entry `POSTED`;
10. no journal reversal reference;
11. accounting period `HARD_CLOSED`;
12. balanced journal debit and credit totals.

The future real-data selector must add the remaining production gates already defined by the archive policy, including legal/audit/dispute/fraud/regulatory holds and full reconciliation evidence. ZC-4D does not activate those real-data gates or weaken them.

## Synthetic negative cases

The rehearsal deliberately contains eight synthetic sales: two valid candidates and six records that must be rejected.

The rejected cases cover:

- payment-pending sale;
- completed sale whose offline sync is still `PENDING`;
- completed sale outside the source period and linked to an `OPEN` accounting period;
- voided/reversed sale;
- completed sale with an unbalanced journal;
- completed sale with a missing inventory movement.

CI requires the expected candidate set to be exactly `SALE-001` and `SALE-002`, and requires the six negative cases to remain rejected. This prevents a future change from silently broadening archive eligibility.

## Relational package scope

Only accepted candidate records and their dependencies are packaged. The rehearsal reconstructs nine logical datasets:

- accounting periods;
- sales transactions;
- sales transaction lines;
- payment intents;
- payment attempts;
- inventory movements;
- inventory movement lines;
- journal entries;
- journal lines.

The package also contains:

- `candidate-selection-evidence.json`;
- `source-manifest.json`.

Rejected business rows are not packaged; only their synthetic IDs and rejection reasons appear in selection evidence.

## Manifest and integrity gates

For every selected dataset the source manifest records:

- row count;
- canonical content SHA-256;
- archive eligibility policy version;
- source period and timezone;
- application commit SHA;
- selection-evidence SHA-256;
- cross-domain control totals;
- `real_data_execution=BLOCKED`;
- `prune_authorization=NOT_GRANTED`.

The ZC-4D script proves:

1. deterministic candidate selection;
2. canonical JSONL output;
3. deterministic plaintext `tar.gz` bytes across two independent builds in the same run;
4. local-only package read-back SHA equality;
5. recovered per-table row counts and SHA-256 values;
6. no orphan sales/payment/inventory/accounting relationships;
7. payment totals reconcile to selected sales totals;
8. journal debit and credit totals reconcile to selected sales totals;
9. recovered candidate IDs match the source candidate set.

Any mismatch fails closed.

## Encryption remains a composed ZC-4C gate

ZC-4D deliberately does not duplicate the cryptography implementation already reviewed in ZC-4C.

`Archive Candidate Reconstruction Rehearsal CI` invokes the existing `scripts/archive/zc4c-package-dry-run.sh` after the ZC-4D relational reconstruction passes. This separately proves that the already-reviewed encrypted package contract still succeeds with:

- AES-256-CBC;
- PBKDF2 with 200,000 iterations;
- positive encrypted package size;
- encrypted SHA-256 verification;
- local-only encrypted read-back;
- decryptability;
- recovered content and manifest verification.

This composition keeps candidate/reconstruction logic and cryptographic packaging logic modular while requiring both gates to pass on the same PR head.

## Real-data blockers remain explicit

The policy deliberately contains `real_data_execution = BLOCKED`.

Before any real archive writer can be considered, separate reviewed work must still provide:

- legal/audit/dispute/fraud/regulatory hold evaluation against real records;
- a genuinely eligible `HARD_CLOSED` source period;
- an explicitly approved durable archive destination;
- authorization and least-privilege execution identity;
- read-back and reconstruction verification against that destination;
- operational runbook and exception handling;
- explicit owner authorization for any future hot-data pruning.

Technical archive eligibility must never be treated as deletion authorization.

## CI safety boundary

`Archive Candidate Reconstruction Rehearsal CI` is repository-only and synthetic-only. Its ZC-4D safety gate rejects database/network/remote-storage client capabilities and destructive SQL/file-removal capabilities in the reconstruction script.

The workflow does **not**:

- connect to Supabase;
- query real business rows;
- insert or update archive registry rows;
- call external storage;
- upload the generated package as a GitHub Artifact;
- move hot data;
- delete, prune, purge, truncate, or drop data;
- activate Cloudflare R2;
- activate paid storage or billing;
- create a production archive writer;
- grant pruning authorization.

The DEVELOPMENT figures documented above were gathered separately through read-only operator verification, not by the CI rehearsal.

## Completion criteria

ZC-4D rehearsal is complete only when, on the same reviewed PR head:

- Application CI passes;
- Archive Candidate Reconstruction Rehearsal CI passes;
- candidate selection proves exactly `2` accepted and `6` rejected synthetic sales;
- relational reconstruction proves all `9` selected datasets;
- the reused ZC-4C encrypted package gate also passes;
- the PR diff contains no database migration or real-data executor;
- the package is not published or retained;
- `real_data_execution=BLOCKED` and `prune_eligible=false` remain proven.
