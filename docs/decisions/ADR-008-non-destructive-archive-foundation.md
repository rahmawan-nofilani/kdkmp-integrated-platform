# ADR-008 — Non-Destructive Archive Foundation

**Status:** Accepted for DEVELOPMENT foundation  
**Date:** 2026-08-13

## Context

The KDKMP Integrated Management Platform must remain viable in Zero-Cost Mode while preserving accounting integrity, inventory traceability, auditability, tenant isolation, and recovery capability.

Supabase Free is the current hot operational database layer. Database growth therefore needs an archive strategy before capacity pressure becomes operationally critical. However, the project owner has explicitly prohibited destructive pruning/delete at this stage and has also prohibited activating Cloudflare R2 or paid Cloudflare storage.

The archive design must therefore be safe before it becomes space-reclaiming.

## Decision

Adopt a **non-destructive, verification-first archive architecture**.

In the current DEVELOPMENT phase:

- archive policy is defined before archive execution;
- no hot operational row is deleted, pruned, detached, or purged;
- no archive package becomes trusted until checksum and independent read-back verification pass;
- no archive package becomes technically eligible for future pruning until recovery/reconstruction verification also passes;
- technical eligibility never equals authorization to delete;
- destructive pruning requires a separate owner-approved workflow and PR;
- legal/regulatory retention periods remain DRAFT / SUBJECT TO FINAL REGULATION;
- Cloudflare R2 remains NOT AUTHORIZED / NOT ACTIVATED;
- paid object storage remains NOT AUTHORIZED.

Archive and backup remain separate controls. A valid backup does not replace an archive, and an archive does not replace disaster-recovery backup coverage.

## Archive boundary

Archive packages must be deterministic and tenant-safe.

Preferred boundary:

`tenant/cooperative + archive class + closed source period`

Cross-tenant archive packages are prohibited.

## Verification order

The future archive pipeline must fail closed in this order:

1. confirm business closure and reconciliation eligibility;
2. freeze deterministic source boundary;
3. record source row counts and source schema/application version;
4. package archive data;
5. encrypt the package;
6. calculate package checksum and byte size;
7. write to an approved external destination;
8. independently read the destination copy back;
9. verify checksum, size, and manifest identity;
10. prove controlled reconstruction/read-back in an isolated environment;
11. mark the archive as recovery-verified;
12. only then may a separate process consider technical pruning eligibility.

No later step may compensate for a failed earlier gate.

## Safety invariant

The system must always be able to answer:

- what data period was archived;
- from which cooperative/tenant;
- from which schema/application version;
- how many rows were included per source table;
- what the encrypted package checksum and size were;
- where the package was stored;
- whether destination read-back passed;
- whether reconstruction/recovery passed;
- whether a legal/audit/dispute hold exists;
- whether destructive pruning has ever been separately authorized.

If these facts cannot be proven, the archive cannot be used as justification to remove hot data.

## Consequences

Positive:

- capacity management can mature without risking data loss;
- archive integrity is testable independently of storage-provider acknowledgements;
- tenant isolation remains explicit;
- future pruning can be gated by evidence rather than age alone;
- the design remains provider-neutral and compatible with Zero-Cost Mode.

Trade-offs:

- hot database size does not shrink during ZC-4A;
- archive engineering requires manifest, reconciliation, read-back, and recovery-test metadata;
- legal retention mapping is still required before any production pruning policy can be approved.

## Follow-up

ZC-4B may introduce archive registry metadata tables only after the repository migration-generation path is verified. Any schema change must use RLS, explicit grants, least privilege, migration verification, database advisors, branch → PR → Application CI → merge, and must remain non-destructive.
