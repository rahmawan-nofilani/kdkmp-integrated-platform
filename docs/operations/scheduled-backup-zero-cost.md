# Zero-Cost Scheduled Backup Policy — DEVELOPMENT

Status: ACTIVE for daily scheduling; durable weekly/monthly off-site retention remains blocked pending an approved destination.

## Objective

Run one encrypted logical backup every day without weakening the restore/read-back workflow that has already passed the DEVELOPMENT drill. The scheduled dispatcher triggers `.github/workflows/manual-backup-restore-drill.yml` on `main`; the authoritative backup workflow remains responsible for dump, isolated restore, row-count checks, FK checks, encryption, artifact upload, artifact read-back, decryption, inner checksums, manifest verification, and the final `VERIFIED` state.

## Schedule

- Trigger: GitHub Actions schedule.
- Cron: `30 19 * * *` UTC.
- Intended local time: 02:30 WIB (Asia/Jakarta) every day.
- A manual dispatcher trigger remains available for controlled testing.
- Concurrency is non-cancelling. A later dispatcher run must not cancel an earlier one.

GitHub schedule execution can be delayed by the platform. The time is therefore an intended backup window, not a financial posting cut-off or legal timestamp.

The first scheduled dispatcher has already completed successfully and triggered a successful full backup/restore/read-back run. That historical backup was recorded as retention class `MANUAL` because the proven backup workflow did not yet accept a retention-class input. The terminal audit row is intentionally left unchanged. After the retention-class hardening change, the scheduler explicitly requests `DAILY`, and the backup manifest/read-back gate verifies the same class.

## Current retention

The verified backup workflow uploads only:

1. `kdkmp-development-<timestamp>.tar.gz.enc`
2. the matching `.sha256` sidecar

GitHub Artifact retention remains 7 days. This provides a rolling short-term DEVELOPMENT safety copy but is not treated as durable off-site retention.

The Zero-Cost target of daily 7 / weekly 4 / monthly 12 is intentionally split into stages:

- Daily 7: scheduled and short-retention transport active; future scheduled registry entries are classified `DAILY` after this hardening change.
- Weekly 4: DESIGN READY but NOT ACTIVATED as durable retention.
- Monthly 12: DESIGN READY but NOT ACTIVATED as durable retention.

Weekly/monthly retention will only be activated after a separate durable off-site destination and independent read-back procedure pass the gates in `docs/operations/durable-offsite-backup-readiness.md` without violating the no-paid-service boundary.

## Zero-cost guardrails

- No Cloudflare R2 activation.
- No billing method, paid GitHub Actions upgrade, paid hosting upgrade, or paid domain is required by this workflow.
- No database pruning, backup pruning, archive deletion, or automatic purge is performed.
- No plaintext SQL is uploaded as an artifact.
- `BACKUP_ENCRYPTION_PASSPHRASE` and `SUPABASE_DB_URL` remain GitHub Actions secrets and must never be printed or copied into chat/issues.
- The dispatcher uses the repository-scoped `GITHUB_TOKEN` with only `actions: write` and `contents: read` so it can create a `workflow_dispatch` event for the already-reviewed backup workflow.
- A scheduled dispatch passes `retention_class=DAILY`; manual runs default to `MANUAL` unless a controlled retention class is deliberately selected.

## Capacity checkpoint

The first successful read-back run produced an encrypted backup of roughly 155 KB and took roughly six minutes end-to-end. At that measured DEVELOPMENT size, one run per day is small relative to the included GitHub Actions allowance, but this is not a permanent capacity guarantee. Backup duration and artifact size must be reviewed as the database grows.

The implementation has not automatically verified the account's remaining billing quota. Therefore the system must never claim that remaining GitHub quota has been verified automatically.

Before enabling weekly/monthly durable retention, review current Actions usage and measured artifact growth. If measured usage approaches the included allowance, preserve the daily verified backup path and use only an explicitly approved zero-cost off-site destination instead of silently enabling paid usage.

## Success criteria for a scheduled backup

A dispatcher success only means that GitHub accepted the workflow dispatch. The backup itself is successful only when the dispatched `Manual Backup & Restore Drill` run finishes successfully and its registry/manifest evidence shows:

- retention class `DAILY` for scheduled runs;
- backup status `VERIFIED`;
- restore status `PASSED`;
- artifact read-back `PASSED`;
- encrypted artifact SHA-256 recorded;
- source and restored row counts match;
- zero unvalidated foreign keys in the checked schemas;
- manifest retention class matches the requested retention class.

A dispatcher failure or backup failure must be investigated; it must not be converted into a false success or bypassed by weakening `ON_ERROR_STOP`, restore verification, checksum validation, or read-back checks.

## Durable off-site next stage

GitHub Artifact remains a temporary transport/short-retention layer, not the final backup destination. The durable-readiness contract is documented separately and deliberately does not activate any provider.

The next controlled step is to select a genuinely zero-cost destination and prove encrypted copy + independent destination read-back + checksum/decryption/manifest validation + restore recovery. Until that succeeds, weekly 4 / monthly 12 remain blocked rather than being falsely reported as active.
