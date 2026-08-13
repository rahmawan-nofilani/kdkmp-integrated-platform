# ZC-4C Archive Integrity Hardening + Synthetic Packaging Dry-Run

Status: **IMPLEMENTATION UNDER REVIEW / REAL ARCHIVE WRITER NOT ACTIVATED**.

ZC-4C hardens the ZC-4B archive metadata registry and proves the package format with synthetic data only. It does not archive, move, prune, delete, purge, or detach any operational KDKMP row.

## 1. Scope

ZC-4C closes three integrity gaps before any real archive writer may be designed:

1. a non-null archive package size must be strictly greater than zero;
2. a written archive destination object key must be non-empty and non-whitespace;
3. a recovery test cannot become `PASSED` unless minimum row-count and package-integrity evidence is explicitly true.

The phase also introduces a local-only packaging dry-run using synthetic POS data.

## 2. Explicit safety boundary

Not activated by ZC-4C:

- reading real DEVELOPMENT business rows for archive packaging;
- writing `system_archive_runs` or `system_archive_recovery_tests` from an archive automation;
- moving operational data out of Supabase;
- deleting/pruning hot rows;
- partition detach/drop;
- object purge or retention cleanup;
- automatic archive scheduling;
- Cloudflare R2;
- paid object storage;
- billing changes;
- production data onboarding;
- `ELIGIBLE_FOR_PRUNE`.

Any future destructive pruning still requires separate explicit owner authorization after verified archive, read-back, reconciliation, recovery, hold controls, and rollback planning.

## 3. Generated migration identity

The reviewed SQL contract is:

`database/drafts/zc4c_archive_integrity_hardening.sql`

Pinned Supabase CLI `2.113.0` generated:

`database/migrations/20260813100013_zc4c_archive_integrity_hardening.sql`

Expected SHA-256:

`7946a597bb3b77d7c9cbb95146f3629b3ed54be68ff40b2fc3b8ef52a7a38abd`

The migration file must remain byte-identical to the reviewed draft. Database Migration CI fails closed if the path, SHA-256, or byte identity changes unexpectedly.

## 4. Database hardening contract

### Positive package size

`system_archive_runs.size_bytes` may remain `NULL` before packaging, but any non-null value must be greater than zero. The archive state-machine trigger separately rejects `PACKAGED` or later when `size_bytes` is null or non-positive.

### Non-blank destination identity

`object_key` may remain `NULL` before writing, but when present it cannot be empty or whitespace. `WRITTEN` or later still requires an assigned storage provider plus a nonblank object key.

### PASSED recovery evidence

Minimum version-1 evidence for `system_archive_recovery_tests.status = 'PASSED'` is:

```json
{
  "row_count_checks": {
    "row_counts_match": true
  },
  "integrity_checks": {
    "sha256_match": true,
    "decryptable": true
  }
}
```

Archive-class-specific recovery may require additional controls. The generic registry minimum is deliberately small but fail-closed: false, missing, non-object, or empty evidence cannot become `PASSED`.

## 5. Synthetic dry-run package contract

The CI dry-run uses only hardcoded synthetic POS rows created inside the disposable GitHub runner. It does not query Supabase.

The flow is:

1. create three synthetic closed POS rows;
2. freeze source row count and content SHA-256;
3. reconcile synthetic gross and payment totals;
4. create the inner source manifest;
5. create a deterministic tar/gzip payload;
6. generate an ephemeral random passphrase in runner memory;
7. encrypt with AES-256-CBC + PBKDF2 at 200,000 iterations;
8. record encrypted byte size and SHA-256;
9. assign a local-only dry-run object identity;
10. copy the encrypted package into a separate local read-back directory;
11. verify encrypted size and SHA-256 from that copy;
12. decrypt and extract locally;
13. verify recovered manifest SHA, content SHA, and source/recovered row counts;
14. produce recovery evidence satisfying the ZC-4C minimum contract;
15. remove the temporary workspace automatically.

No package is uploaded as a GitHub Artifact by the dry-run workflow. The package and ephemeral passphrase disappear with the runner workspace.

## 6. Inner and outer manifest boundary

ZC-4C deliberately separates two identities to avoid self-referential hashing:

- the **inner source manifest** is inside the encrypted payload and describes the synthetic source boundary, row count, source content SHA, schema version, and reconciliation totals;
- the **outer archive identity** records the final encrypted package size, encrypted SHA-256, object key, source-manifest SHA, and recovery/reconciliation metadata.

The final encrypted package SHA cannot be embedded inside the same payload whose bytes it hashes. The authoritative final package SHA therefore belongs in the outer registry/destination identity, while the inner source manifest proves the content that was packaged.

## 7. CI gates

A ZC-4C PR must pass all applicable gates on the same reviewed head:

- **Application CI** — dependency install, production dependency audit, typecheck, build;
- **Database Migration CI** — pinned CLI, migration SHA/byte identity, clean replay with the documented historical CI fixture, RLS/grant/index checks, ZC-4B state machine, ZC-4C negative integrity tests;
- **Archive Package Dry-Run CI** — synthetic-only guard, encrypted packaging, local read-back, decryptability, content/manifest checksum, reconciliation, and recovery evidence.

The earlier pinned migration-generator proof is supporting evidence for the exact migration filename and SHA.

## 8. DEVELOPMENT activation boundary

Merging this PR does not itself apply ZC-4C to Supabase DEVELOPMENT.

When repository review is complete, the DEVELOPMENT apply must use the exact merged migration version rather than creating a new remote migration timestamp. The apply path must:

- use pinned Supabase CLI `2.113.0`;
- use the existing protected DEVELOPMENT database connection secret;
- inspect remote migration history first;
- run a dry-run of pending migrations;
- fail closed unless the only intended pending migration is `20260813100013_zc4c_archive_integrity_hardening`;
- apply without seeds, resets, or destructive database commands;
- verify the exact migration version after apply;
- re-check archive table row counts, constraints, functions, RLS/grants, and Supabase advisors.

A separate controlled workflow/checkpoint will implement this apply step after the repository PR is merged.

## 9. Definition of done for ZC-4C

ZC-4C is complete only when:

- the generated migration is merged after all CI gates pass;
- post-merge CI on `main` passes;
- the exact migration version is applied to DEVELOPMENT through the controlled pinned-CLI path;
- DEVELOPMENT migration history matches the repository version;
- registry row counts remain unchanged unless explicitly expected;
- post-apply security/performance verification finds no ZC-4C regression;
- evidence is recorded in Zero-Cost tracker #58.

Even then, **real archive writer execution and all pruning remain inactive**.
