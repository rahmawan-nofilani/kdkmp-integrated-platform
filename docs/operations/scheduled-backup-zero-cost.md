# Zero-Cost Scheduled Backup Policy — DEVELOPMENT

Status: ACTIVE DESIGN BASELINE for DEVELOPMENT.

## Objective

Run one encrypted logical backup every day without changing the restore/read-back workflow that has already passed the DEVELOPMENT drill. The scheduled dispatcher only triggers `.github/workflows/manual-backup-restore-drill.yml` on `main`; the authoritative backup workflow remains responsible for dump, isolated restore, row-count checks, FK checks, encryption, artifact upload, artifact read-back, decryption, inner checksums, manifest verification, and the final `VERIFIED` state.

## Schedule

- Trigger: GitHub Actions schedule.
- Cron: `30 19 * * *` UTC.
- Intended local time: 02:30 WIB (Asia/Jakarta) every day.
- A manual dispatcher trigger remains available for controlled testing.
- Concurrency is non-cancelling. A later dispatcher run must not cancel an earlier one.

GitHub schedule execution can be delayed by the platform. The time is therefore an intended backup window, not a financial posting cut-off or legal timestamp.

## Current retention

The verified backup workflow currently uploads only:

1. `kdkmp-development-<timestamp>.tar.gz.enc`
2. the matching `.sha256` sidecar

GitHub Artifact retention remains 7 days. This provides a rolling short-term DEVELOPMENT safety copy but is not treated as durable off-site retention.

The Zero-Cost target of daily 7 / weekly 4 / monthly 12 is intentionally split into stages:

- Daily 7: enabled through the current GitHub Artifact workflow.
- Weekly 4: NOT YET ACTIVATED as durable retention.
- Monthly 12: NOT YET ACTIVATED as durable retention.

Weekly/monthly retention will only be activated after a separate durable off-site destination and read-back procedure are available without violating the no-paid-service boundary.

## Zero-cost guardrails

- No Cloudflare R2 activation.
- No billing method, paid GitHub Actions upgrade, paid hosting upgrade, or paid domain is required by this workflow.
- No database pruning or archive deletion is performed.
- No plaintext SQL is uploaded as an artifact.
- `BACKUP_ENCRYPTION_PASSPHRASE` and `SUPABASE_DB_URL` remain GitHub Actions secrets and must never be printed or copied into chat/issues.
- The dispatcher uses the repository-scoped `GITHUB_TOKEN` with only `actions: write` and `contents: read` so it can create a `workflow_dispatch` event for the already-reviewed backup workflow.

## Capacity checkpoint

The first successful read-back run produced an encrypted backup of roughly 155 KB and took roughly six minutes end-to-end. At that measured DEVELOPMENT size, one run per day is small relative to the included GitHub Actions allowance, but this is not a permanent capacity guarantee. Backup duration and artifact size must be reviewed as the database grows.

The GitHub connector used during implementation cannot read the account's billing-usage endpoint. Therefore this system must never claim that remaining GitHub quota has been verified automatically.

Before enabling weekly/monthly long retention, review current GitHub Actions usage and measured artifact growth. If measured usage approaches the account's included allowance, preserve the daily verified backup path and move durable copies to an explicitly approved off-site destination instead of silently enabling paid usage.

## Success criteria for a scheduled backup

A dispatcher success only means that GitHub accepted the workflow dispatch. The backup itself is successful only when the dispatched `Manual Backup & Restore Drill` run finishes successfully and its registry row shows:

- backup status `VERIFIED`;
- restore status `PASSED`;
- artifact read-back `PASSED`;
- encrypted artifact SHA-256 recorded;
- source and restored row counts match;
- zero unvalidated foreign keys in the checked schemas.

A dispatcher failure or backup failure must be investigated; it must not be converted into a false success or bypassed by weakening `ON_ERROR_STOP`, restore verification, or read-back checks.

## Next stage

After the first scheduled run succeeds, implement durable off-site retention registration and a measured rotation plan for weekly 4 / monthly 12. GitHub Artifact remains a temporary transport/short-retention layer, not the final backup destination.
