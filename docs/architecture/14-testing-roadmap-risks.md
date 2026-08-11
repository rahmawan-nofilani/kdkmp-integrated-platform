# Testing Strategy, Roadmap & Critical Risks

Status: **DRAFT ARCHITECTURE BASELINE**

## Testing layers

### Unit tests
Validate isolated business rules such as:
- permission evaluation
- loan schedule calculations
- inventory reservation rules
- accounting posting rules
- workflow transitions

### Integration tests
Validate interactions between:
- auth and authorization
- sales and inventory
- procurement and inventory
- transaction engine and accounting
- savings/loan subledger and general ledger
- payment adapter and reconciliation

### Security tests
Mandatory scenarios include:
- Member attempts to access another member's data -> denied
- Courier attempts to change product price -> 403
- Admin attempts to create privileged user -> 403
- Pengawas attempts to mutate transaction -> 403
- User attempts cross-KDKMP access -> denied
- Suspended user session attempts sensitive action -> denied

### Workflow tests
Examples:
- PO cannot transition DRAFT -> PAID
- loan cannot disburse before APPROVED
- posted journal cannot be edited
- stock adjustment cannot post before approval when policy requires it
- savings QRIS deposit cannot post before payment confirmation

### Responsive tests
Target widths:
320, 375, 390, 430, 768, 1024, 1280, 1440, 1920 px.

## Phase roadmap

### Phase 0 — Architecture
Deliverables:
- architecture baseline
- workflows
- domain model
- ERD
- security
- API/UI architecture
- testing strategy

### Phase 1 — Foundation
- authentication
- organization hierarchy
- units
- user management
- RBAC
- permissions
- data scopes
- approval foundation
- audit foundation
- dashboard shell

Acceptance highlights:
- real login
- backend permission enforcement
- 403 for unauthorized actions
- Manager can create permitted operational users
- Admin cannot create privileged users
- member/role/data scopes validated
- audit events recorded
- mobile and desktop responsive

### Phase 2 — Cooperative & Master Data
- member
- cooperative core
- product catalog
- supplier
- customer
- warehouse master

### Phase 3 — Procurement, Inventory, Sales & POS
- purchase request/PO through receiving
- inventory movements/reservations
- POS and sales
- stock opname
- cash shift closing

### Phase 4 — Accounting & Finance
- chart of accounts
- transaction posting
- AP/AR
- cash/bank
- reconciliation
- budget
- financial reporting

### Phase 5 — Simpan Pinjam
- configurable financial product engine
- savings
- term/goal/event savings
- loan origination
- monthly/weekly/seasonal/at-maturity schedules
- teller
- repayment/collection
- subledger
- compliance placeholders pending legal validation

### Phase 6 — Delivery, Fleet & Supply Chain
- order fulfillment
- courier
- POD
- fleet
- offtaking

### Phase 7 — Governance, Risk & Audit
- risk register
- controls
- control testing
- findings
- corrective actions
- incidents

### Phase 8 — Regulated Business
- LPG
- Pupuk
- Klinik
- Apotek
- authorization hard gates

### Phase 9 — Integrations
- payment adapters
- QRIS/PJP
- SIMKOPDES adapter
- supplier/logistics/government adapters

### Phase 10 — Analytics & AI
- KPI registry
- executive dashboard
- semantic/approved data tools
- AI assistant with permission-aware access

## Critical risks

1. **Regulatory uncertainty** — mitigated by configurable, versioned regulatory engine and hard-gate activation.
2. **Privilege escalation** — mitigated by grantable permission boundaries and SoD.
3. **Cross-tenant data leakage** — mitigated by canonical scope model, backend authorization, RLS, tests.
4. **Accounting inconsistency** — mitigated by posting engine, subledger reconciliation, immutable posted journals.
5. **Stock corruption** — mitigated by movement ledger, reservation model, approval-based adjustment.
6. **Offline duplicate transactions** — mitigated by idempotency keys, device/session identifiers, sync conflict rules.
7. **Payment false-positive** — mitigated by external confirmation and settlement reconciliation.
8. **Product-rule changes affecting old contracts** — mitigated by immutable product version snapshots.
9. **Premature complexity** — mitigated by modular monolith first; extract services only when justified.
10. **AI overreach/hallucination** — mitigated by approved tools, permission context, evidence-based answers, and human approval for writes.

## Phase 0 exit criteria

Phase 0 can be approved when:
- architecture domains are coherent;
- role/permission/scope model is defined;
- key workflows are state-driven;
- cooperative core and Simpan Pinjam are separated correctly;
- accounting/inventory/procurement dependencies are documented;
- conceptual ERD exists;
- security/audit/regulatory placeholders exist;
- API/UI/testing architecture exists;
- roadmap dependencies are internally consistent.
