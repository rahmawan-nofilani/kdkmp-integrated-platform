# Zero-Cost Mode — Operating Plan

**Status:** DRAFT FOR IMPLEMENTATION  
**Owner audience:** non-technical project owner / future KDKMP Manager  
**Parent tracker:** GitHub Issue #58

## 1. Objective

Run KDKMP at the initial operating scale with a target recurring infrastructure cost of Rp0/month while maintaining:

- secure authentication and authorization;
- traceable POS and inventory transactions;
- accounting integrity;
- audit history;
- controlled financial-service modules;
- reliable backup and restore;
- a clear upgrade path if free-tier limits are exceeded.

Zero-Cost Mode is a target operating profile, not a guarantee that third-party providers will never change limits or pricing. Provider limits must be re-checked before production cutover and monitored afterward.

## 2. Initial Capacity Assumptions

Initial expected load:

- 2,000 active members;
- about 100 POS transactions/day;
- about 3,000 transactions/month;
- about 36,500 transactions/year.

Design headroom:

- 5,000 members;
- 300 POS transactions/day;
- up to 50 concurrent active operational users as an initial design target.

## 3. Provider Roles

### GitHub

Use for:

- private repository;
- migration/source-of-truth;
- CI;
- operational/architecture documentation;
- later scheduled backup orchestration if capacity and security tests pass.

Never store production secrets in repository files.

### Supabase

Initial role:

- PostgreSQL hot operational database;
- Auth;
- RLS and transaction control;
- transactional RPC/trigger infrastructure.

Initial Development project remains DEMO-only. A separate Production project must be created only after readiness approval.

### Vercel

During Zero-Cost transition:

- current development/preview deployment;
- do not treat Vercel Hobby as the only long-term production dependency;
- minimize preview deployment frequency by batching work.

### Cloudflare

Planned role after pilot:

- Next.js hosting via the officially supported Worker/OpenNext route;
- future R2 archive/backup/file object storage within verified free limits;
- custom domain optional.

Cloudflare is not production until the compatibility test matrix passes.

## 4. Domain Strategy

### Phase A — No paid domain

Use a provider-supplied hostname for development/pilot, such as a Cloudflare-provided `workers.dev` or applicable project hostname.

Benefits:

- Rp0;
- no DNS administration required initially;
- suitable for technical pilot and acceptance tests.

### Phase B — Optional official custom domain

Only after the application becomes operationally important should the owner consider an official custom domain.

Reasons to add one later:

- easier address for staff/members;
- organization branding;
- easier future provider migration because the public hostname stays constant;
- more appropriate for business-critical use.

A custom domain purchase is never automatic and requires owner approval.

## 5. Capacity Traffic-Light Policy

### Database

- GREEN / NORMAL: < 300 MB
- YELLOW / WARNING: 300–350 MB
- ORANGE / ARCHIVE REQUIRED: 350–400 MB
- RED / CRITICAL: 400–450 MB
- EMERGENCY ACTION: before 450 MB

The system must not deliberately wait for a provider hard limit.

### Egress

Engineering target:

- Supabase egress < 3.5 GB/month.

Application practices:

- paginate long lists;
- load summaries instead of full transaction histories;
- never embed image/base64 payloads in JSON;
- use date ranges;
- do not repeatedly download immutable master data when caching is safe.

### Cloudflare dynamic requests

Engineering target:

- < 50,000 dynamic requests/day, leaving a safety margin below the current Free-plan limit.

### R2

Engineering target:

- < 8 GB used storage, leaving capacity below the current free-storage allowance.

## 6. Hot Data Strategy

Keep hot operational data necessary for current operation, including:

- member master/current status;
- organization/IAM/permission/scope;
- current savings and loan positions when authorized;
- open balances/current subledger states;
- active inventory positions;
- open procurement/sales/logistics workflows;
- recent transaction/audit window;
- current accounting periods and control totals;
- archive manifests.

Target hot historical transaction window is initially 120–180 days, but automatic pruning must remain disabled until real-size measurement and retention/legal policy are approved.

## 7. Cold Archive Strategy

Archive packages should be period-based, preferably monthly once a period is eligible.

Example archive contents:

- POS transactions and lines;
- payment events;
- closed POS shifts;
- inventory movements;
- posted journal detail;
- eligible audit history;
- relevant reconciliation metadata.

Archive package metadata must include:

- archive ID;
- source period;
- schema/application version;
- row counts per entity;
- creation timestamp;
- checksum/hash;
- storage object path;
- verification status;
- restore-test status.

No pruning is allowed until archive write + read-back + integrity verification pass.

## 8. Backup Strategy

Backup is separate from archive.

Target generations:

- Daily: last 7
- Weekly: last 4
- Monthly: last 12

Workflow target:

1. generate logical database export;
2. compress;
3. encrypt;
4. generate checksum;
5. upload outside operational database;
6. read/verify metadata;
7. record backup run status;
8. periodically restore-test.

A successful upload alone is not enough to mark a backup VERIFIED.

## 9. Restore Test Strategy

Restore drill minimum checks:

- schema applies successfully;
- row counts match expected backup manifest;
- membership records accessible;
- sales/journal/inventory reference integrity is intact;
- auth-related application access configuration can be reconstructed safely;
- application can read the restored environment;
- result and duration recorded.

Production restore must never overwrite the live environment as a test.

## 10. Files and Images

Rules:

- no large binary files in PostgreSQL;
- no base64 image blobs in transaction JSON;
- compress images before upload;
- use object storage references + hash + MIME type + file size;
- separate retention classes for POD, identity documents and ordinary attachments;
- do not automatically keep redundant generated PDFs.

POS receipt:

- authoritative transaction/receipt data is stored;
- HTML/print/PDF output is generated when requested;
- do not save one PDF file for every POS sale by default.

## 11. Reporting Efficiency

Introduce summary/read models for high-use dashboards, for example:

- daily sales summary;
- payment-channel summary;
- daily stock-movement summary;
- accounting trial/read models;
- member/loan portfolio summaries where authorized.

Historical dashboards should normally query summaries, while detailed drill-down retrieves specific authoritative records.

## 12. Development vs Production

### Development

- synthetic/demo data;
- experimental integrations;
- may be reset;
- current Supabase Development project;
- current Vercel deployment remains available while Cloudflare pilot is tested later.

### Future Production

Prerequisites before creation/use:

- architecture baseline approved;
- critical transaction engines tested;
- backup mechanism proven;
- restore drill proven;
- security review passed;
- production secrets procedure documented;
- real-data policy approved;
- owner explicitly authorizes Production environment.

## 13. Cloudflare Pilot Test Matrix

Before Cloudflare can replace Vercel as production candidate, verify:

1. application build succeeds;
2. login succeeds;
3. logout/session expiry succeeds;
4. server-side access context works;
5. protected routes return correct access behavior;
6. Supabase SSR session refresh works;
7. Server Actions work;
8. RLS behavior is unchanged;
9. Manager Dashboard works;
10. POS open/close shift works;
11. POS catalog/cart works;
12. cash completion works;
13. receipt display works;
14. mobile layout works;
15. error/health route works;
16. no service key is exposed to browser;
17. rollback path to Vercel remains available.

## 14. SIMKOPDES Relationship

KDKMP must remain usable independently.

Integration priority:

1. official API adapter if an authorized/documented API exists;
2. controlled export/import (CSV/Excel/PDF) where API is unavailable;
3. never scrape/fake a government integration and never label a mock adapter as official.

## 15. Owner Authorization Checkpoints

The assistant/engineering process must stop and ask the owner before:

- buying any domain;
- enabling any paid provider plan;
- creating the future real-data Production Supabase project;
- destructive archive/pruning activation;
- production cutover/hostname switch;
- production R2 credentials/account setup where explicit user account consent is required;
- activating real QRIS/payment provider credentials.

## 16. Implementation Order

### ZC-1 — Architecture Baseline

Status target: document + ADR + parent tracker.

### ZC-2 — Capacity Monitor

Read-only first. No destructive operations.

Minimum measurements:

- current DB size;
- top tables by total size;
- member count;
- monthly transaction counts;
- backup/archive status placeholders;
- computed traffic-light state.

### ZC-3 — Backup Foundation

Development-only backup proof first.

### ZC-4 — Restore Drill

Prove the backup can be restored before calling it operational.

### ZC-5 — Cloudflare Pilot

Requires owner/account authorization when account setup or credential binding is needed.

### ZC-6 — Archive Foundation

Create manifests and verification workflow; no automatic pruning initially.

### ZC-7 — Production Readiness

Only after product/business/regulatory readiness.

## 17. Current Authorization Need

None for ZC-1 and the read-only design of ZC-2.

Cloudflare account authorization will be requested later, at ZC-5. Do not create or buy a domain now.
