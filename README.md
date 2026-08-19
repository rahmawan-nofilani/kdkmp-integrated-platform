# KDKMP Integrated Management Platform

**Working name:** KDKMP Digital Operating System  
**Current checkpoint:** Release-1 DEVELOPMENT RC1 accepted; Production Readiness Phase 0  
**Repository status:** Private DEVELOPMENT repository; production cutover is not authorized  

## What is this project?

KDKMP Integrated Management Platform is a digital operating system for Koperasi Desa/Kelurahan Merah Putih.

The target ecosystem includes:

- Cooperative Core / Membership
- User, Role, Permission & Data Scope
- Retail POS
- Procurement
- Inventory & Warehouse
- Supply Chain & Distribution
- Finance & Accounting
- Simpan Pinjam / Financial Services
- Governance & Approval
- Risk, Internal Control & Audit
- Regulated Business Modules
- Document Management
- Reporting & Analytics
- External Integrations
- AI Assistant

This project is **not** intended to be a static dashboard, a fake demo, or a single giant HTML file.

## Current status

Release-1 DEVELOPMENT UAT has completed and the accepted candidate is frozen on `release/release1-development-rc1`.

Accepted DEVELOPMENT scope includes:

- identity, organization hierarchy, RBAC, permission resolution, and data scope;
- cooperative membership and membership finance foundations;
- inventory, procurement, receiving/match controls, logistics and distribution foundations;
- operational POS CASH shift/cart/sale/receipt with stock/accounting/cash effects;
- controlled full CASH reversal and partial return/refund;
- Accounting maker/checker/BOARD posting, reversal, reconciliation and period controls;
- audit/control evidence and responsive/accessibility Chromium smoke;
- provider-neutral non-cash confirmation/reconciliation foundations kept fail-closed until authorization.

Intentionally not activated:

- monetary Savings/Loan operation pending regulatory/product validation (Issue #182);
- real QRIS/BANK_TRANSFER E2E pending provider credential/commercial authorization (Issue #51);
- true production infrastructure, production data onboarding, custom production domain, and production cutover.

The current authoritative checkpoint is recorded in:

- `docs/current-project-status.md`
- `docs/operations/release1-production-readiness.md`
- `docs/operations/release1-uat-readiness.md` (completed UAT plan/evidence reference)
- `docs/operations/zc5k-final-zero-cost-readiness-handoff.md`

## Infrastructure decision

- Vercel DEVELOPMENT remains intact.
- Supabase DEVELOPMENT remains the current hot database/auth environment.
- Future STAGING/PRODUCTION must be isolated environments and may not silently reuse DEVELOPMENT resources.
- The Cloudflare DEVELOPMENT pilot is functional.
- Cloudflare Workers Free is **not approved** as the current full-stack SSR production runtime because the measured CPU gate did not pass.
- No production cutover, production data onboarding, paid Cloudflare service, R2 activation, or custom-domain change is authorized by the current checkpoint.

## Start here

- `docs/current-project-status.md`
- `docs/operations/release1-production-readiness.md`
- `docs/architecture/00-project-charter.md`
- `docs/architecture/01-system-architecture.md`
- `docs/architecture/02-module-map.md`
- `docs/architecture/03-organization-access-model.md`
- `docs/architecture/04-savings-loans-architecture.md`
- `docs/operations/zc5k-final-zero-cost-readiness-handoff.md`
- `docs/decisions/ADR-001-foundation-stack.md`

## Technology baseline

- Next.js + TypeScript
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- Vercel DEVELOPMENT
- Cloudflare DEVELOPMENT compatibility pilot
- GitHub Actions
- Modular Monolith architecture

## Environment policy

- DEVELOPMENT: demo/test data only
- STAGING/UAT: testing and acceptance on isolated resources
- PRODUCTION: official operational data only after security, readiness, and explicit owner approval

Application classification uses `KDKMP_APP_ENV`. Future STAGING/PRODUCTION must also pin `KDKMP_EXPECTED_SUPABASE_REF` so the application fails closed rather than silently using the wrong Supabase project.

## Security rules

Never commit:

- passwords
- database passwords
- service-role/secret keys
- private API keys
- real NIK/member financial data during development or staging

## Development principle

Every material feature must be considered across:

1. Business Rule
2. Data Model
3. Backend/Server Validation
4. Permission & Scope
5. Audit
6. UI/UX
7. Testing

All repository changes must follow branch → PR → CI/build proof → merge. Database migrations must also pass Database Migration CI before controlled environment application.

## Important

Financial-services, regulated-business, accounting, and government-integration behavior must be driven by verified authorization, policy, and applicable regulation. Draft or unverified rules must be labeled accordingly.
