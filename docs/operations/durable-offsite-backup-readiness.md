# Durable Off-site Backup Readiness — Zero-Cost DEVELOPMENT

Status: **DESIGN READY / DESTINATION NOT ACTIVATED**.

This document defines the activation gates for durable off-site retention without enabling Cloudflare R2, paid storage, destructive pruning, or automatic deletion. It does not claim that a durable off-site copy exists today.

## Current proven baseline

The DEVELOPMENT backup pipeline has already demonstrated the full validation chain:

`logical dump -> isolated restore -> row-count comparison -> FK validation -> encryption -> GitHub Artifact upload -> artifact download/read-back -> encrypted SHA-256 -> decrypt -> inner FILES.sha256 -> manifest validation -> VERIFIED`.

GitHub Artifact remains the short-retention transport/safety layer with `retention-days: 7`. It is not classified as the durable off-site destination.

The first scheduled dispatcher successfully invoked the proven workflow. That historical run was recorded as `MANUAL` because the backup workflow did not yet accept a retention-class input. The backup remains valid; its immutable terminal registry row must not be rewritten. After the retention-class hardening PR, scheduled dispatches request `DAILY`, and the encrypted manifest/read-back validation must confirm the same class before the run can become `VERIFIED`.

## Retention policy

Target policy remains:

- **DAILY 7** — one verified backup per day, short-retention layer active through GitHub Artifact.
- **WEEKLY 4** — select one already-verified daily backup per ISO week for durable off-site preservation; activation is **BLOCKED** until a durable destination passes all gates below.
- **MONTHLY 12** — select one already-verified daily backup per calendar month for durable off-site preservation; activation is **BLOCKED** until a durable destination passes all gates below.

Weekly and monthly classes are retention selections, not a reason to create extra database dumps. Reusing an already-verified daily backup reduces unnecessary Actions usage and avoids duplicate load on the DEVELOPMENT database.

There is **no destructive expiration job** in this phase. Rotation means identifying which copies are required by policy, not deleting older copies automatically.

## Durable destination activation gates

A destination may be called `DURABLE_OFFSITE_VERIFIED` only after all of these conditions pass:

1. **Independent failure domain** — the durable copy is outside the operational Supabase database and is not dependent solely on the same ephemeral GitHub Actions artifact lifecycle.
2. **Zero-cost boundary** — activation must not require a paid plan, billing enablement, paid object storage, or an automatic upgrade path. Cloudflare R2 remains explicitly disabled unless the owner later authorizes it.
3. **Encrypted-only transfer** — only the `.tar.gz.enc` backup and its checksum sidecar may leave the runner. Plaintext SQL, decrypted tar files, database credentials, and encryption passphrases must never be uploaded.
4. **Identity match** — destination object identity records the source backup run number, retention class, encrypted SHA-256, size in bytes, and source manifest identity.
5. **Write acknowledgement is insufficient** — upload/copy success alone never marks a durable copy verified.
6. **Independent read-back** — the object must be read back from the destination and its encrypted SHA-256 and size must exactly match the source verified backup.
7. **Decryptability and inner integrity** — read-back must decrypt on an ephemeral trusted runner and pass `FILES.sha256` plus manifest identity checks.
8. **Restore lineage** — the selected source backup must already have a `PASSED` isolated restore test; a copy of an unverified source cannot become durable merely because the copy itself is readable.
9. **Fail closed** — any mismatch leaves the durable-copy attempt failed/not verified; no checksum, restore, or read-back gate may be bypassed to force success.
10. **No destructive lifecycle action** — no hot-data pruning, archive deletion, backup deletion, or destination object purge is activated by this readiness stage.

## Provider-neutral durable-copy contract

Any future destination adapter must implement the following logical flow:

1. Resolve one source `system_backup_runs` row whose status is `VERIFIED`.
2. Confirm the requested retention selection (`WEEKLY` or `MONTHLY`) and retain the original backup-run identity.
3. Obtain only the encrypted artifact and checksum from the approved source transport.
4. Copy/upload to the approved off-site destination without exposing secrets or plaintext.
5. Record destination object identifier, provider class, size, SHA-256, source backup ID, retention selection, and copy timestamp.
6. Download/read the durable destination object back independently.
7. Verify encrypted checksum and size.
8. Decrypt only in ephemeral storage, verify the internal checksum registry and manifest, then securely remove plaintext working files.
9. Mark the durable copy verified only after all checks pass.

The provider implementation must not silently fall back to a paid destination when a free quota is exhausted or unavailable. It must stop and require an explicit owner decision.

## Candidate destination status

- **Cloudflare R2:** `NOT AUTHORIZED / NOT ACTIVATED`.
- **Other paid cloud object storage:** `NOT AUTHORIZED`.
- **Manual external/offline storage:** `CANDIDATE FOR CONTROLLED PILOT`, but not considered active until its custody, encryption, checksum, read-back, and recovery procedure is tested and documented.
- **GitHub Artifact:** `ACTIVE SHORT-RETENTION TRANSPORT`, not durable off-site retention.

No destination is promoted to active by this document.

## Activation evidence required

Before weekly/monthly durable retention is enabled, retain evidence of:

- destination approval and zero-cost confirmation;
- first encrypted copy success;
- source and destination SHA-256 equality;
- source and destination byte-size equality;
- destination read-back success;
- decryptability and inner checksum success;
- manifest/source backup identity match;
- source restore status `PASSED`;
- documented recovery procedure from the durable destination;
- one controlled restore drill starting from the durable destination copy.

Only after those checks pass should weekly 4 / monthly 12 be changed from `BLOCKED` to active.

## Operational decision for this phase

Proceed with daily scheduled verified backups and measure artifact growth. Keep GitHub Artifact retention at seven days. Do not create a second paid storage dependency merely to satisfy the weekly/monthly target. The next durable-retention step is destination selection and a controlled encrypted-copy/read-back pilot, not automatic retention deletion.
