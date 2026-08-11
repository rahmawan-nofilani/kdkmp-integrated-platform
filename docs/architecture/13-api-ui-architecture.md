# API & UI Architecture

Status: **DRAFT ARCHITECTURE BASELINE**

## API principles

Initial application uses Next.js server-side/application APIs with a modular service layer. External/public APIs are versioned.

Suggested namespace:

- `/api/v1/auth`
- `/api/v1/users`
- `/api/v1/roles`
- `/api/v1/permissions`
- `/api/v1/organizations`
- `/api/v1/members`
- `/api/v1/products`
- `/api/v1/inventory`
- `/api/v1/purchases`
- `/api/v1/sales`
- `/api/v1/payments`
- `/api/v1/accounting`
- `/api/v1/savings`
- `/api/v1/loans`
- `/api/v1/approvals`
- `/api/v1/risks`
- `/api/v1/audits`
- `/api/v1/documents`
- `/api/v1/reports`
- `/api/v1/integrations`

## API controls

Every sensitive endpoint validates:
- authenticated identity
- permission
- data scope
- workflow state
- segregation-of-duties policy
- regulatory/feature status where applicable

Common platform requirements:
- request/correlation ID
- standard error envelope
- pagination
- filtering
- sorting
- idempotency for retry-sensitive writes
- audit hooks
- input validation

Example unauthorized behavior:

`POST /api/v1/users` without USER_CREATE -> `403 Forbidden`.

## Integration architecture

External systems use adapters:
- SIMKOPDESAdapter
- PaymentAdapter
- QRIS/PJP adapter
- SupplierAdapter
- LogisticsAdapter
- GovernmentAdapter

If an official API is unavailable, use a clearly marked mock adapter with `REPLACE WITH OFFICIAL API` documentation.

Integration reliability uses:
- transactional outbox
- inbox/deduplication
- retry
- idempotency
- reconciliation
- dead-letter handling

## UI information architecture

The interface is task-centric, not a 40-item flat sidebar.

### Desktop navigation

- Beranda
- Operasional
  - Penjualan
  - Pengadaan
  - Persediaan
  - Distribusi
- Anggota
- Simpan Pinjam
- Keuangan
- Tata Kelola
  - Approval
  - Risiko
  - Kontrol
  - Audit
- Dokumen
- Administrasi
  - Organisasi
  - User
  - Role & Permission
  - Unit Usaha
  - Master Data
  - Integrasi

Menus are permission-aware but backend authorization remains authoritative.

## Manager dashboard

### Business Health
- Revenue
- Gross Margin
- Net Profit
- Cash
- Receivable
- Payable

### Operational Health
- inventory alerts
- stock accuracy
- orders
- procurement
- deliveries

### Financial Services Health
- total savings
- outstanding loans
- due installments
- overdue loans
- liquidity indicators
- pending approvals
- KYC/compliance alerts

### Action Center
- approvals waiting
- critical stock
- overdue tasks
- expiring documents/authorization
- incidents and audit follow-ups

## Mobile/PWA

Mobile uses:
- bottom navigation
- drawers
- responsive cards
- mobile-friendly tables
- camera/file upload
- GPS for delivery/POD when authorized
- offline/sync status where supported

Target responsive widths include 320, 375, 390, 430, 768, 1024, 1280, 1440, and 1920 px.

## Design system

Visual direction:
`Government Enterprise + Cooperative + Modern SaaS + Financial-grade UI`

Required primitives:
- typography tokens
- spacing tokens
- colors/status tokens
- buttons
- inputs
- cards
- tables
- modal/dialog
- drawer/sheet
- badges
- toast
- charts
- skeleton/loading
- empty/error states

No generic demo-template look and no mobile-only fixed-width application shell.
