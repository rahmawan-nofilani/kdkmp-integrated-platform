# Archive Foundation — Zero-Cost DEVELOPMENT

Status: **POLICY READY / ARCHIVE EXECUTION NOT ACTIVATED**.

This document defines the ZC-4 archive foundation for the KDKMP Integrated Management Platform. It is intentionally metadata-first and non-destructive. It does not move, prune, delete, purge, or detach operational rows from the hot Supabase database.

## 1. Purpose

The archive layer exists to control long-term database growth while preserving accounting integrity, inventory traceability, auditability, and recoverability.

Archive and backup are different controls:

- **Backup** protects recoverability of the operational database.
- **Archive** preserves closed historical detail outside the hot operational working set while keeping verifiable lineage back to the authoritative source.

An archive package is never considered trustworthy merely because a file was written. It must pass identity, checksum, read-back, and recovery gates.

## 2. Safety boundary for ZC-4A

ZC-4A is policy and contract only.

Explicitly not activated in this phase:

- hot-data deletion;
- table partition detach/drop;
- archive-driven `DELETE` statements;
- object purge or retention cleanup;
- database vacuum strategies intended to reclaim space from archived rows;
- automatic legal-retention enforcement;
- Cloudflare R2 or any paid storage;
- production data onboarding;
- automatic archive scheduling.

Any later destructive pruning requires a separate owner authorization checkpoint, a dedicated PR, a verified archive copy, read-back proof, reconciliation proof, and a rollback/recovery procedure.

## 3. Capacity trigger

The existing Zero-Cost Mode thresholds remain the operational trigger:

- **NORMAL:** database < 300 MB;
- **WARNING:** 300–350 MB;
- **ARCHIVE_REQUIRED:** 350–400 MB;
- **CRITICAL:** 400–450 MB;
- emergency action before 450 MB;
- never intentionally operate near the 500 MB Supabase Free ceiling.

The threshold determines when archive preparation becomes urgent. It does **not** authorize deletion.

## 4. Hot-data policy

The hot operational database keeps data that is required for current business operation, current balances, current inventory, governance, exception handling, or a recent reporting window.

Hot data includes at minimum:

- active members, users, roles, permissions, organization hierarchy, and current master data;
- current product and financial-product configurations, including active versions;
- current inventory balances, open batches/lots, and open stock-control exceptions;
- open procurement, receiving, order, delivery, payment, receivable, payable, and approval workflows;
- current cash/bank positions and unreconciled transactions;
- open accounting periods and journal detail required for current financial reporting;
- active assets and depreciation state;
- unresolved audit findings, risks, controls, investigations, disputes, and compliance exceptions;
- recent POS/sales detail required for daily operations and approved reporting windows;
- archive manifests, archive verification metadata, and immutable lineage references.

A record being old is not enough to make it archive-eligible.

## 5. Cold-data eligibility policy

Historical detail can become **archive-eligible** only when all applicable conditions are true:

1. the business transaction/workflow is terminal and cannot legitimately continue in normal operation;
2. the relevant accounting period is closed or the transaction has been included in a reconciled closed period;
3. inventory effects are fully posted and no unresolved stock discrepancy depends on the detail;
4. payment, cash, bank, AR/AP, and settlement state is reconciled when applicable;
5. approvals are final and all required evidence references are present;
6. audit, risk, legal, dispute, fraud, investigation, or regulatory hold flags are absent;
7. no active return, refund, void, chargeback, correction, or adjustment workflow references the transaction;
8. source row counts for the archive scope are frozen and reproducible;
9. schema/application version metadata is known;
10. the archive package is created, checksummed, read back, and verified;
11. recovery/read-back from the archive package is proven according to the archive recovery contract;
12. any future destructive pruning has separate explicit owner approval.

If any gate is unknown, the data remains hot.

## 6. Initial archive scope classes

These classes describe logical archive candidates. They do not activate archival automatically.

### 6.1 Transaction history

Examples:

- closed POS sales and sale items;
- closed orders and order items;
- completed deliveries and delivery items;
- closed purchase requests/orders/items and completed receivings;
- closed payment events and settlement detail.

### 6.2 Accounting history

Examples:

- journal and journal-line detail from closed reconciled periods;
- supporting cash/bank transaction detail already represented in closed statements;
- historical AR/AP detail only after balances are fully settled and reconciled.

Accounting summary balances, period close evidence, and audit lineage must remain queryable in the hot layer even if eligible detail is archived later.

### 6.3 Inventory movement history

Old inventory movements may become eligible only after:

- stock position has been reconciled;
- stock opname differences are resolved;
- batch/lot/expiry traceability is no longer operationally active;
- no recall, dispute, or regulated-goods investigation requires the detail to remain hot.

Current inventory balances and active traceability records remain hot.

### 6.4 Audit and governance records

Audit logs, approvals, compliance records, risk/control evidence, and documents are **conservative-retention classes**. They are not first-wave pruning candidates. Their legal and governance retention periods remain DRAFT / SUBJECT TO FINAL REGULATION and approved cooperative policy.

## 7. Archive unit

An archive package must have a deterministic source boundary.

Preferred archive unit:

`tenant/cooperative + archive class + closed source period`

Examples:

- one cooperative + POS_TRANSACTION + calendar month;
- one cooperative + ACCOUNTING_DETAIL + closed accounting period;
- one cooperative + INVENTORY_MOVEMENT + closed month.

Cross-tenant packages are prohibited. Multi-KDKMP deployments must preserve tenant isolation in archive generation and recovery.

## 8. Archive state machine

Planned logical states for a future registry:

`REQUESTED -> SNAPSHOTTED -> PACKAGED -> WRITTEN -> READBACK_VERIFIED -> RECOVERY_VERIFIED -> ELIGIBLE_FOR_PRUNE`

Failure terminal states:

`FAILED` or `CANCELLED`.

Important rules:

- `WRITTEN` is not sufficient for trust;
- `READBACK_VERIFIED` requires checksum and size equality from the destination copy;
- `RECOVERY_VERIFIED` requires reconstruction/read-back validation on an isolated trusted environment;
- `ELIGIBLE_FOR_PRUNE` is only a technical eligibility state, not authorization to delete;
- a separate owner-approved destructive workflow is required before any pruning occurs.

## 9. Archive manifest contract

Every archive package must carry a machine-readable manifest. Minimum required fields:

```json
{
  "archive_run_number": "ARC-...",
  "archive_format_version": 1,
  "environment": "DEVELOPMENT",
  "tenant_id": "...",
  "cooperative_id": "...",
  "archive_class": "POS_TRANSACTION",
  "source_period": {
    "from": "YYYY-MM-DDTHH:MM:SSZ",
    "to": "YYYY-MM-DDTHH:MM:SSZ",
    "timezone": "Asia/Jakarta"
  },
  "source_schema_version": "...",
  "application_commit_sha": "...",
  "tables": [
    {
      "name": "sales",
      "row_count": 0,
      "content_sha256": "..."
    }
  ],
  "package": {
    "encrypted": true,
    "size_bytes": 0,
    "sha256": "..."
  },
  "reconciliation": {
    "status": "PASSED",
    "evidence": []
  },
  "created_at": "...",
  "readback_verified_at": null,
  "recovery_verified_at": null
}
```

The exact schema will be versioned before implementation. Future readers must reject unknown incompatible manifest versions rather than silently interpreting them.

## 10. Integrity requirements

For each archive package:

- source query boundary must be deterministic and recorded;
- source table row counts must be recorded;
- logical content checksums must be recorded where technically practical;
- encrypted package SHA-256 and byte size must be recorded;
- only encrypted payloads may leave the trusted runner/workspace;
- the destination copy must be read back independently;
- destination SHA-256 and byte size must equal the source package;
- manifest identity must match the archive registry record;
- recovery validation must prove that archived records can be reconstructed/read for audit and reporting;
- any mismatch fails closed.

## 11. Reconciliation gate

Before an archive class can become recovery-verified, applicable control totals must reconcile.

Examples:

- POS: transaction count, gross sales, discount, tax if applicable, payment totals, void/refund totals;
- Accounting: journal count, debit total, credit total, period balance equality;
- Inventory: movement count, inbound/outbound quantities, adjustment totals, closing quantity lineage;
- Procurement: PO/receiving/invoice/payment control totals when applicable.

The archive package must not become a new source of truth that disagrees with the authoritative closed-period totals.

## 12. Query/read-back contract

The future archive reader must support controlled retrieval without restoring the whole operational database.

Minimum expected capabilities:

- locate archive packages by cooperative, archive class, and source period;
- verify package integrity before reading;
- reconstruct selected records into an isolated temporary environment or safe read model;
- expose provenance: archive run, source period, source schema version, checksum, and verification status;
- never bypass tenant/data-scope authorization when archived data is surfaced to an application user.

Archive access is an audited operation.

## 13. Legal and regulatory retention

No numeric legal retention period is hardcoded in ZC-4A.

Final retention must be mapped later per data category against applicable cooperative, accounting, tax, consumer, employment, health, pharmacy, regulated-goods, privacy, and other requirements. Until legal/regulatory review is complete, destructive pruning based on age alone is prohibited.

## 14. Storage boundary

No durable archive destination is activated by this document.

Current rules:

- Cloudflare R2 remains **NOT AUTHORIZED / NOT ACTIVATED**;
- paid cloud storage is **NOT AUTHORIZED**;
- GitHub Artifact is a short-retention backup transport, not a durable archive store;
- any future durable archive destination must pass the same zero-cost, encrypted-only, checksum, read-back, recovery, and owner-authorization gates defined for durable off-site backups.

## 15. Planned ZC-4B — archive registry schema

The next implementation phase may add non-destructive metadata tables only, after migration generation and verification are available.

Planned registry concepts:

- `system_archive_runs` — archive identity, source boundary, class, status, manifest, checksum, size, destination metadata;
- `system_archive_recovery_tests` — read-back/reconstruction tests and integrity evidence;
- optional `system_archive_holds` — explicit legal/audit/dispute holds that block pruning eligibility.

Security requirements:

- RLS enabled for every `public` table;
- explicit grants only;
- application users read archive status only through existing permission controls;
- no insert/update/delete grants to ordinary authenticated users;
- terminal verification records become immutable;
- no `SECURITY DEFINER` function exposed through `public` merely to bypass RLS;
- database advisors and migration verification must pass before merge.

## 16. Definition of done for ZC-4A

ZC-4A is complete when:

- hot/cold eligibility is documented;
- archive scope and tenant boundary are explicit;
- manifest and integrity contracts are defined;
- reconciliation and recovery gates are defined;
- destructive pruning remains technically and procedurally disabled;
- R2/paid storage remains disabled;
- ZC-4B schema work is separated behind a verified migration workflow.
