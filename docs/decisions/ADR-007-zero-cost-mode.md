# ADR-007 — Zero-Cost Mode as an Architecture Requirement

**Status:** Accepted with ADR-008 archive clarification  
**Date:** 2026-08-12  
**Amended:** 2026-08-13

## Context

KDKMP is intended to remain usable as an operational fallback/supplement if SIMKOPDES does not meet local operational needs. The project owner also requires a practical path to run the application with zero recurring infrastructure cost at the initial scale, without weakening security, accounting integrity, inventory traceability, auditability, or regulated-service gates.

Initial planning assumptions:

- approximately 2,000 active cooperative members;
- approximately 100 POS transactions per day;
- design capacity of 5,000 members and 300 POS transactions per day;
- development remains demo/test data only;
- real production data is not onboarded until production readiness is explicitly approved.

## Decision

Zero-Cost Mode is a first-class non-functional requirement.

The target architecture is:

- GitHub: private source control, CI and architecture documentation;
- Supabase Free: operational PostgreSQL + Auth for the initial hot-data layer;
- Cloudflare Workers/Pages: zero-cost production hosting candidate after a parallel compatibility pilot;
- Cloudflare R2: **NOT AUTHORIZED / NOT ACTIVATED** in the current implementation. It may only be reconsidered after explicit owner authorization and a fresh verification that activation cannot create an unwanted paid/billing commitment;
- Vercel: keep as development/preview during the migration/pilot period;
- adapter-based SIMKOPDES integration only through an official API when available, otherwise controlled export/import.

No provider is allowed to auto-upgrade to a paid plan as an application requirement. Any paid-plan activation, R2 activation, or domain purchase requires explicit owner authorization.

## Capacity Policy

Operational targets:

- database NORMAL: < 300 MB;
- WARNING: 300–350 MB;
- ARCHIVE REQUIRED: 350–400 MB;
- CRITICAL: 400–450 MB;
- emergency capacity action before 450 MB;
- never intentionally operate near the Supabase Free 500 MB ceiling;
- Supabase egress target: < 3.5 GB/month;
- Cloudflare dynamic request target: < 50,000/day;
- no active R2 storage target while R2 remains disabled.

These are internal engineering thresholds, not provider guarantees. Provider limits must be re-verified before production cutover.

## Hot / Cold Data Strategy

The operational database is not a permanent archive for every historical detail.

Hot database keeps:

- current members and organization master data;
- current account/subledger states;
- current inventory positions and open operational documents;
- recent transaction history required for day-to-day operations;
- recent audit/reporting windows;
- archive manifests and integrity metadata.

Cold archive keeps eligible closed historical detail only after:

1. business period/workflow is closed;
2. required reconciliation passes;
3. archive package is created;
4. row counts and schema/version metadata are recorded;
5. checksums are generated;
6. object is uploaded outside the hot database to an approved destination;
7. read-back verification passes;
8. restoreability/reconstruction is proven according to the archive recovery policy.

No destructive pruning is enabled during development. Final retention periods remain DRAFT / SUBJECT TO FINAL REGULATION and approved cooperative policy. ADR-008 adds the non-destructive archive verification and authorization gates.

## Backup Strategy

Archive and backup are different controls.

- Archive = long-term historical retention.
- Backup = disaster recovery copy of operational data.

Planned zero-cost backup retention target:

- daily: 7 generations;
- weekly: 4 generations;
- monthly: 12 generations.

Retention remains subject to measured backup size and available zero-cost capacity. A backup is not considered valid until restore-tested.

## File and Receipt Rules

- Do not store large photos, PDFs or base64 files in PostgreSQL.
- Store only object metadata/reference/hash in PostgreSQL.
- Compress operational images before upload.
- Do not persist a PDF copy for every POS receipt; generate print/PDF output on demand from authoritative transaction records.
- Large files and POD evidence require explicit retention classes.

## Reporting Rules

Dashboards and historical reports should use read models/summaries where appropriate rather than repeatedly scanning full transaction history. This reduces latency, database load and egress while preserving authoritative source transactions.

## Environment Separation

Development and future Production must be separate environments.

Development:

- DEMO/synthetic data only;
- may be reset;
- integration experiments allowed behind feature flags.

Production:

- official operational data;
- cannot be reset casually;
- destructive maintenance requires approval, backup and audit controls.

The future Production Supabase project must not be created until schema/security/backup readiness is approved.

## Cloudflare Pilot Rule

Do not replace Vercel abruptly.

The Cloudflare hosting pilot must run in parallel and pass a compatibility matrix covering at minimum:

- login/session refresh;
- protected routes;
- SSR;
- Server Actions;
- Supabase Auth and RLS;
- Manager dashboard;
- POS shift/cart/cash payment path;
- responsive/mobile operation;
- error handling and health checks.

Only after the matrix passes can Cloudflare become the production-hosting candidate. The hosting pilot does not authorize R2 or any paid Cloudflare product.

## Domain Decision

A custom domain is optional for the pilot and initial zero-cost operation.

Use the provider-supplied free hostname during development/pilot. A custom domain should be considered when the application becomes operationally important and branded access is justified. Buying or attaching a paid/custom domain requires explicit owner approval.

## Authorization Boundary

Explicit owner authorization is required before:

- purchasing a domain;
- enabling any paid provider plan;
- activating Cloudflare R2 or any storage path that requires billing/payment commitment;
- creating the future real-data Production Supabase project;
- creating/using production secrets that require owner account consent;
- activating destructive archive/pruning automation;
- changing the production hostname/cutover;
- activating a real payment/QRIS provider.

## Consequences

Positive:

- recurring infrastructure cost can remain zero at the initial operating scale if usage stays within verified free-tier limits;
- storage growth is managed deliberately rather than waiting for a hard quota failure;
- provider migration is planned and reversible;
- historical/audit data remains traceable through archive manifests and integrity verification.

Trade-offs:

- monitoring, backup, archive and restore engineering become mandatory features;
- free-tier constraints must be monitored continuously;
- business-critical production may eventually justify paid infrastructure even if Zero-Cost Mode remains available;
- the system must avoid wasteful queries, large persistent files and unnecessary historical duplication.
