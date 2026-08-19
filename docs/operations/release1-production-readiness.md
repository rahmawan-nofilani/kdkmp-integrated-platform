# Release 1 — Production Readiness & Cutover Gates

Date: 2026-08-19  
Repository: `rahmawan-nofilani/kdkmp-integrated-platform`  
Current accepted candidate: `release/release1-development-rc1`  
Production cutover: **NOT AUTHORIZED**

## Purpose

This document defines the controlled path from the completed DEVELOPMENT UAT/RC1 milestone toward staging and, later, production. It deliberately separates engineering readiness from authorization to create infrastructure, activate regulated/provider functions, onboard real data, or cut over production.

## Current baseline

- Release-1 DEVELOPMENT UAT Issue #129: COMPLETE.
- DEVELOPMENT RC1 Issue #183: COMPLETE.
- Frozen RC1 pointer: `release/release1-development-rc1`.
- Vercel currently has only the `kdkmp-development` project for this application.
- Integrated-platform Supabase DEVELOPMENT: `qdxybbcksjivcidsupbd`, region `ap-south-1` (Mumbai).
- Issue #19 remains open for staging/region evaluation; Singapore (`ap-southeast-1`) is the candidate region to evaluate for Indonesian users.
- Cloudflare Workers Free remains NO-GO as the full-stack SSR production runtime under the measured CPU gate.
- Savings/Loan monetary activation is deferred to Issue #182.
- Real QRIS/BANK_TRANSFER provider E2E remains tracked by Issue #51.

A separate Supabase project used by another KDKMP workstream/repository must not be treated as the production database for this integrated platform unless explicitly reclassified through a future architecture decision.

## Environment contract

Application environment is controlled by `KDKMP_APP_ENV`:

- `development`
- `staging`
- `production`

The existing runtime safely defaults to `development` for backward compatibility. Staging and production must set the value explicitly.

`KDKMP_EXPECTED_SUPABASE_REF` is mandatory for staging/production. `/api/health` must return HTTP 503 when a non-development environment has no expected Supabase project pin or when the configured Supabase URL does not match that pin.

Do not infer application environment from Vercel's target label alone. The current DEVELOPMENT site can be represented internally by Vercel as a production-target deployment while remaining a KDKMP DEVELOPMENT environment.

## Proposed environment separation

These are naming conventions only; they do not authorize resource creation.

| Layer | DEVELOPMENT | STAGING candidate | PRODUCTION candidate |
| --- | --- | --- | --- |
| Git pointer | `main` / RC branch | frozen staging candidate | frozen production candidate |
| Vercel | `kdkmp-development` | `kdkmp-staging` | `kdkmp-production` |
| Supabase | current DEVELOPMENT project | dedicated isolated project | dedicated isolated project |
| App env | `development` | `staging` | `production` |
| Data | synthetic/demo/UAT | synthetic or sanitized fixtures only | official operational data only |
| Provider | inactive/fail-closed | sandbox/test credentials only after authorization | production credentials only after separate authorization |

Development, staging, and production must never share a service-role key, provider secret, callback token, or database project.

## Gate P0 — repository/environment readiness

Required before creating staging:

1. explicit environment classification exists and is not hardcoded;
2. health endpoint validates the expected Supabase target;
3. `.env.example` documents browser-safe versus server-only values without real secrets;
4. RC1 remains frozen and normal feature work does not move the RC pointer;
5. no temporary UAT/internal runner routes remain live;
6. DEVELOPMENT provider and regulatory flows remain fail-closed;
7. current status documentation reflects completed DEVELOPMENT UAT.

Any regression that can cause production to point at DEVELOPMENT data is a release blocker.

## Gate P1 — staging architecture decision

Resolve Issue #19 before production data volume grows.

Required evidence:

- documented choice of staging Supabase region;
- migration replay on a fresh isolated database;
- backup integrity and restore rehearsal;
- latency comparison for the primary Indonesian user path;
- database extension/function/RLS/grant parity;
- Auth configuration and redirect inventory;
- Storage bucket/policy inventory if used;
- rollback and abandonment procedure;
- cost confirmation before creating any resource that can incur cost.

No existing project may be repurposed as staging merely because it already exists.

## Gate P2 — staging infrastructure

Requires explicit owner authorization at execution time.

Minimum staging layout:

- dedicated Supabase project, preferably in the region approved by Gate P1;
- dedicated Vercel project;
- `KDKMP_APP_ENV=staging`;
- `KDKMP_EXPECTED_SUPABASE_REF=<staging-ref>`;
- isolated server-only secrets;
- no production/customer/member financial data;
- Vercel auto-deployment policy chosen deliberately under the Zero-Cost constraints.

After creation, staging must start from migration replay and controlled seed data, not a blind copy of DEVELOPMENT state.

## Gate P3 — staging verification

Execute an abbreviated but authoritative replay of the Release-1 gates:

- auth/RBAC/scope;
- POS CASH and idempotency;
- void/partial return;
- Accounting maker/checker/BOARD, reversal and period control;
- Procurement/Inventory receiving and match controls;
- Audit/reconciliation;
- Chromium desktop/mobile/accessibility smoke;
- health/environment target guard;
- backup and restore drill;
- runtime error scan and security advisor review.

Provider and regulated-product cases remain blocked/deferred unless separately authorized.

P0/P1 application defects must be zero before a production proposal.

## Gate P4 — production infrastructure plan

Planning may happen before authorization; resource creation may not.

Define before creation:

- production Supabase region/project naming;
- production Vercel project/domain plan;
- DNS/certificate ownership;
- secret owners and rotation procedure;
- backup frequency, retention and restore objectives;
- capacity thresholds and escalation;
- audit retention and privacy controls;
- Auth email/redirect configuration;
- production bootstrap user/BOARD governance path;
- observability and incident-response contacts;
- maintenance window and rollback decision authority.

Cloudflare Workers Free is not an approved fallback production SSR runtime unless a future re-evaluation passes its CPU/security gates.

## Gate P5 — real data readiness

Separate explicit authorization required.

Before any official member or financial data enters production:

- data classification and minimum-required fields approved;
- real NIK/member/financial data prohibited from DEVELOPMENT/STAGING;
- import validation and duplicate prevention established;
- migration/import audit references retained;
- rollback/quarantine strategy documented;
- access roles/scopes reviewed for the target cooperative;
- backup completed before material onboarding/import operations.

Do not copy UAT/demo identities, historical test journals, synthetic POS sales, or test provider events into production.

## Gate P6 — provider/regulatory activation

This is independent of core production hosting readiness.

Savings/Loans:
- Issue #182 regulatory/product gate must be resolved before monetary activation.

QRIS/BANK_TRANSFER:
- Issue #51 must have authorized credentials/test mode, trusted backend confirmation, provider configuration, commercial/MDR terms, accounting clearing/bank/fee mappings, settlement reconciliation, and positive/negative E2E evidence.

A production web application can remain fail-closed for these modules until those gates pass. Do not create fake success states to satisfy a release checklist.

## Gate P7 — production cutover rehearsal

Before owner approval:

1. freeze a production candidate SHA;
2. verify repository/build/database checks;
3. create a timestamped pre-cutover backup and prove readability;
4. rehearse migration on an isolated target;
5. record expected migration counts/checksums;
6. define DNS/alias switch sequence;
7. define health/RBAC/POS/Accounting smoke immediately after cutover;
8. define rollback threshold and rollback operator;
9. define no-go conditions;
10. confirm provider/regulatory modules remain in their approved state.

## Gate P8 — owner authorization

Production cutover requires a fresh explicit owner authorization after P0-P7 evidence is reviewed. A general instruction to continue planning or development does not by itself authorize:

- paid infrastructure;
- creation of true production resources;
- custom-domain purchase/assignment;
- production secret/provider activation;
- real-data onboarding;
- production DNS/alias cutover.

## Immediate next executable work

Without creating infrastructure, the project can now:

1. complete Phase 0 repository/environment hardening;
2. inventory migration/backup/security requirements;
3. evaluate Issue #19 and prepare a zero-cost staging architecture decision;
4. prepare the staging creation checklist and cost boundary;
5. keep Issues #51 and #182 separate from core hosting readiness.

Only after those planning gates are complete should staging resource creation be proposed.
