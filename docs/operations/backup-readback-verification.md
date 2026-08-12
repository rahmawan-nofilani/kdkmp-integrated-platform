# Backup Artifact Read-Back Verification

Status: DEVELOPMENT baseline

## Purpose

A backup is not considered fully verified merely because a dump, local restore test, encryption, and artifact upload succeeded. The stored artifact must also be downloaded again from the artifact store, checked for integrity, decrypted using the repository secret, and its internal files verified.

## Toolchain lock

The manual backup and restore drill pins Supabase CLI to `2.113.0` instead of using `supabase@latest`.

Why:
- the first successful DEVELOPMENT backup/restore drill used the stable CLI release available at that time;
- pinning avoids an unrelated future CLI or local-stack image change altering backup/restore behavior without review;
- any CLI upgrade must go through a branch/PR, Application CI, and a new manual backup + restore + read-back drill before being accepted.

## VERIFIED meaning

For this workflow, `system_backup_runs.status = VERIFIED` is allowed only after all of the following succeed:

1. Remote DEVELOPMENT database connectivity is verified.
2. Logical dump files are created.
3. Managed-only role settings are sanitized only in `roles.restore.sql`; original `roles.sql` is preserved.
4. An isolated local Supabase restore succeeds.
5. Selected source and restored row counts match.
6. No unvalidated foreign keys remain in `public` or `app_private`.
7. The backup package is encrypted with AES-256-CBC + PBKDF2 and a repository secret.
8. SHA-256 is calculated for the encrypted object.
9. Only the encrypted object and its checksum are uploaded to GitHub Actions artifacts.
10. The uploaded artifact is downloaded again from GitHub Actions.
11. The downloaded encrypted object's SHA-256 matches the value registered before upload.
12. The downloaded object is successfully decrypted on the ephemeral Actions runner.
13. The decrypted archive contains exactly the expected backup files.
14. `FILES.sha256` validates the internal dump and verification files.
15. `manifest.json` matches the current GitHub run, commit, backup run number, pinned Supabase CLI version, restore status, and source/restored counts.

If any step fails while the backup is non-terminal, the backup registry must transition to `FAILED` rather than `VERIFIED`.

## Plaintext handling

Plaintext SQL and the decrypted tar archive exist only on the ephemeral GitHub Actions runner during the drill. They are never uploaded as artifacts. The read-back verification step installs an EXIT trap to remove the decrypted tar and extracted files on both success and failure.

## Current storage limitation

GitHub Actions artifact retention remains temporary and is not the final durable off-site backup destination. R2 remains disabled until owner authorization. Before production scheduling, an approved durable off-site destination and retention policy are still required.

## Upgrade rule

Do not change the pinned Supabase CLI version directly on `main`. Upgrade through a dedicated PR and repeat a full manual drill. A successful Application CI build alone is not sufficient evidence for backup compatibility.
