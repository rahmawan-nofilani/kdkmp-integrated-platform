# First DEVELOPMENT Backup Drill — Owner Setup

**Environment:** DEVELOPMENT only  
**Storage mode:** GitHub Actions encrypted artifact, 7-day retention  
**R2:** disabled  
**Schedule:** manual trigger only

## Purpose

This is the first proof that the KDKMP DEVELOPMENT database can be exported, encrypted, restored into an isolated local Supabase environment, and verified before any automatic schedule or Cloudflare R2 integration is enabled.

The workflow is `.github/workflows/manual-backup-restore-drill.yml`.

## What the workflow does

1. creates a real `system_backup_runs` registry row;
2. dumps roles, schema, data, and migration history using the Supabase CLI;
3. records selected source row counts;
4. starts an isolated local Supabase stack in the GitHub runner;
5. restores the dump into that isolated target;
6. compares selected source/restored row counts, including `auth.users`;
7. checks that no public/app_private foreign keys are left unvalidated;
8. records the restore drill as PASSED or FAILED;
9. packages the dump files and manifest;
10. encrypts the package with AES-256-CBC + PBKDF2;
11. calculates SHA-256;
12. uploads only the encrypted package and checksum as a private GitHub Actions artifact for 7 days;
13. marks the backup VERIFIED only after the artifact upload step succeeds.

If any required step fails, the backup registry is marked FAILED. The workflow never restores into the live DEVELOPMENT database.

## Two GitHub repository secrets required

The owner must create these secrets directly in GitHub. Never paste either value into chat, issues, source code, or screenshots.

### 1. `SUPABASE_DB_URL`

Use the **Session pooler** connection string from the DEVELOPMENT Supabase project.

Path in Supabase Dashboard:

**Project → Connect → Session pooler**

The connection string must contain the database password. If the password is unknown, reset the database password in Supabase Database Settings first and then use the new password in the Session pooler string.

Example format only:

`postgresql://postgres.PROJECT_REF:PASSWORD@POOLER_HOST:5432/postgres`

Do not use this example literally.

### 2. `BACKUP_ENCRYPTION_PASSPHRASE`

Create a unique passphrase of at least 24 characters. Recommended: 32+ random characters.

Rules:

- must not be the Supabase password;
- must not be the GitHub password;
- must not be a user login password;
- save one recovery copy in the owner's password manager/offline secure record;
- losing this passphrase means encrypted backup artifacts may be unrecoverable.

## Where to create GitHub secrets

Repository:

`rahmawan-nofilani/kdkmp-integrated-platform`

Open:

**Settings → Secrets and variables → Actions → New repository secret**

Create exactly:

- `SUPABASE_DB_URL`
- `BACKUP_ENCRYPTION_PASSPHRASE`

GitHub masks secret values in normal workflow logs. Do not echo or print them manually.

## How the first run will be started

After both secrets exist:

1. open the repository **Actions** tab;
2. select **Manual Backup & Restore Drill**;
3. choose **Run workflow** on `main`;
4. wait for the job to complete;
5. do not download/open anything until the workflow result is reviewed.

The first run is intentionally manual. No daily schedule will be enabled until the first backup and restore drill both pass.

## Success criteria

A first drill is accepted only if all of the following are true:

- workflow conclusion: SUCCESS;
- backup registry status: VERIFIED;
- restore registry status: PASSED;
- selected row counts match source and isolated restore target;
- encrypted artifact exists;
- encrypted object SHA-256 is recorded;
- no plaintext SQL is uploaded as an artifact;
- live DEVELOPMENT data is not changed by the restore test.

## Important limitations

This first fallback stores the encrypted artifact in GitHub Actions for only 7 days. It proves backup/restore mechanics, but it is not yet the long-term off-site retention design.

Cloudflare R2 remains disabled until the owner explicitly accepts the metered/billing model. No paid plan or domain is required for this drill.
