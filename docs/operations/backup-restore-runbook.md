# Zero-Cost Backup & Restore Runbook

**Status:** FOUNDATION — NO AUTOMATIC BACKUP ENABLED YET  
**Environment:** DEVELOPMENT only until Production readiness approval

## 1. What this runbook is for

This runbook defines how KDKMP will create off-site logical database backups, verify that the uploaded object is intact, record the backup in the application registry, and later perform restore drills.

A backup is not considered successful merely because a file was generated.

Target state:

`database dump -> package -> encrypt -> SHA-256 -> off-site upload -> read-back verify -> registry VERIFIED -> periodic restore drill`

## 2. Current state

Already available:

- `system_backup_runs` registry;
- `system_restore_tests` registry;
- state-transition guards;
- Manager/Supervisor read-only access;
- browser users cannot create/update/delete/truncate backup registry rows.

Not yet available:

- Cloudflare R2 account/bucket credentials;
- GitHub backup secrets;
- active backup workflow;
- first verified backup;
- first restore drill;
- automatic retention cleanup.

Do not display backup status as VERIFIED until the real process passes.

## 3. Why use a logical Supabase backup

For Free-plan projects, the target is an explicit logical export created using the Supabase CLI `db dump` workflow rather than assuming managed downloadable daily backups are available.

The intended backup set is:

1. `roles.sql` — custom roles/role information supported by the CLI workflow;
2. `schema.sql` — application schema;
3. `data.sql` — database data.

The Supabase CLI applies Supabase-specific filtering that is safer for migration/restore than a naive raw `pg_dump` of every managed internal object.

## 4. What the database backup does NOT automatically contain

Database backup is not the same as object/file backup.

Files such as:

- POD photos;
- identity-document files;
- uploaded PDFs;
- other R2/object-storage objects

must have a separate object-storage backup/retention strategy when those features become active.

## 5. Owner authorization checkpoint — Cloudflare R2

Before the first off-site automated backup, the project owner must authorize Cloudflare account/R2 setup.

The owner should never send account passwords, R2 secret keys, database passwords, or backup encryption passwords through chat.

Planned user actions:

1. create or sign in to a Cloudflare account;
2. enable R2 Object Storage;
3. create one DEVELOPMENT private bucket, proposed name: `kdkmp-backups-development`;
4. create an R2 API token limited to Object Read & Write on that specific bucket;
5. copy the Access Key ID and Secret Access Key directly into GitHub repository secrets when instructed;
6. never commit credentials into repository files.

R2 has included free monthly usage, but it is a metered service. Zero-Cost Mode therefore uses an internal storage target below the free allowance and requires capacity monitoring. The owner must explicitly approve account/billing/subscription setup if Cloudflare requests it.

## 6. Required GitHub Actions secrets

These names are planned but MUST NOT be populated until the first backup workflow is ready for testing:

- `SUPABASE_DB_URL`
- `BACKUP_ENCRYPTION_KEY`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`

### SUPABASE_DB_URL

Use the Supabase Session Pooler connection string for backup automation when the runner needs IPv4 connectivity, following current Supabase connection guidance.

The database password is part of the connection string and must remain a GitHub secret.

### BACKUP_ENCRYPTION_KEY

Generate a long random value. It must not be identical to the database password, user password, or R2 secret.

If this key is lost, encrypted backups may become unusable. The owner needs an offline recovery copy stored securely outside GitHub.

## 7. Planned backup commands

Conceptual command sequence:

```bash
supabase db dump --db-url "$SUPABASE_DB_URL" -f roles.sql --role-only
supabase db dump --db-url "$SUPABASE_DB_URL" -f schema.sql
supabase db dump --db-url "$SUPABASE_DB_URL" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
```

The exact CLI version will be pinned in the workflow after compatibility testing. Do not use an unpinned `latest` version for Production backup automation.

## 8. Package and encryption design

Proposed package contents:

```text
backup-manifest.json
roles.sql
schema.sql
data.sql
checksums.txt
```

Then:

1. create compressed archive;
2. encrypt the archive using an approved command/library available on the GitHub runner;
3. calculate SHA-256 of the final encrypted object;
4. upload only the encrypted object plus non-sensitive verification metadata if needed.

The encryption implementation must be tested with a restore before it is considered accepted.

## 9. Object key layout

Proposed R2 layout:

```text
backups/
  development/
    2026/
      08/
        daily/
        weekly/
        monthly/
```

Example object key:

`backups/development/2026/08/daily/KDKMP-DEV-20260812T020000Z.tar.gz.enc`

Do not store passwords/secrets in filenames or object metadata.

## 10. Backup manifest minimum fields

- backup run number;
- environment (`DEVELOPMENT` / future `PRODUCTION`);
- start/end timestamps;
- application Git commit SHA;
- latest database migration version;
- backup CLI version;
- retention class;
- file list and original sizes;
- encrypted object size;
- SHA-256;
- selected row-count/control checks;
- storage provider and object key;
- verification result.

Do not put user passwords, tokens, NIK values, or member financial details in the manifest.

## 11. Verification after upload

Minimum verification sequence:

1. upload encrypted backup to R2;
2. issue a HEAD/list check to verify object exists and size matches;
3. download/read back the encrypted object into temporary runner storage for the first implementations;
4. recalculate SHA-256;
5. compare with local SHA-256;
6. only then change registry state from `UPLOADED` to `VERIFIED`.

If verification fails:

- mark the run FAILED;
- keep the previous verified backup;
- do not delete any hot database data;
- notify the operator.

## 12. Retention target

Initial target:

- Daily: 7
- Weekly: 4
- Monthly: 12

Automatic deletion is disabled at first.

Retention automation is introduced only after:

- several successful backup runs;
- storage usage measurement;
- first successful restore drill;
- owner approval of deletion/lifecycle behavior.

## 13. Restore drill

A restore test must use a disposable/local/temporary environment. Never test by overwriting the live database.

Planned flow:

1. choose a VERIFIED backup;
2. download encrypted object;
3. verify SHA-256;
4. decrypt;
5. extract roles/schema/data;
6. create temporary compatible PostgreSQL/Supabase environment;
7. restore in the supported order;
8. run integrity checks;
9. record duration and result in `system_restore_tests`;
10. destroy temporary test environment after evidence is recorded.

Minimum checks after restore:

- migrations/schema objects expected by the application exist;
- member counts match manifest/control values;
- accounting journal references remain consistent;
- inventory movement references remain consistent;
- POS transactions/receipts expected in the backup are readable;
- critical RLS/function definitions are present;
- no real production endpoint is changed.

## 14. Strict zero-card fallback

If the owner does not want to enable any metered service requiring checkout/billing details, the first development backup can be created as an encrypted manual backup and downloaded to an owner-controlled offline location.

This is acceptable as a temporary proof-of-backup step, but it is NOT the preferred automated off-site architecture because:

- manual handling can be forgotten;
- restore evidence is harder to automate;
- retention is harder to enforce;
- one PC/device is not a resilient backup location.

## 15. What happens next

Once owner authorization for Cloudflare R2 is available:

1. create DEVELOPMENT R2 bucket;
2. add scoped credentials to GitHub secrets without exposing them in chat;
3. add a manually-triggered GitHub Actions backup workflow;
4. run first backup;
5. read-back verify;
6. record registry VERIFIED;
7. run first restore drill;
8. only after PASS consider adding a daily schedule.

No Production backup schedule is enabled until the Development sequence above passes.
