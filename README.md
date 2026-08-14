# KDKMP Integrated Management Platform

**Working name:** KDKMP Digital Operating System  
**Current checkpoint:** ZC-5K — Zero-Cost readiness and operating handoff  
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

The project has progressed beyond the original Phase 0 architecture baseline. The repository now contains implemented DEVELOPMENT foundations for:

- identity, organization hierarchy, RBAC, permission resolution, and data scope;
- cooperative membership and membership finance;
- configurable financial products, accounting controls, approval/SoD, savings, loans, KYC, teller, and payment orchestration;
- inventory, procurement, commercial/POS, logistics, distribution, shifts, cash completion, journals, stock movement, and receipts;
- zero-cost capacity monitoring, verified backup/restore controls, non-destructive archive foundations, and a Cloudflare compatibility pilot.

The current authoritative checkpoint is recorded in:

- `docs/current-project-status.md`
- `docs/operations/zc5k-final-zero-cost-readiness-handoff.md`

## Infrastructure decision

- Vercel DEVELOPMENT remains intact.
- Supabase DEVELOPMENT remains the hot database/auth environment.
- The Cloudflare DEVELOPMENT pilot is functional.
- Cloudflare Workers Free is **not approved** as the current full-stack SSR production runtime because the measured CPU gate did not pass.
- No production cutover, production data onboarding, paid Cloudflare service, R2 activation, or custom-domain change is authorized by the current checkpoint.

## Start here

- `docs/current-project-status.md`
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
- Staging/UAT: testing and acceptance
- Production: official operational data only after security, readiness, and explicit owner approval

## Security rules

Never commit:

- passwords
- database passwords
- service-role/secret keys
- private API keys
- real NIK/member financial data during development

## Development principle

Every material feature must be considered across:

1. Business Rule
2. Data Model
3. Backend/Server Validation
4. Permission & Scope
5. Audit
6. UI/UX
7. Testing

All repository changes must follow branch → PR → CI → merge. Database migrations must also pass Database Migration CI before controlled environment application.

## Important

Financial-services, regulated-business, accounting, and government-integration behavior must be driven by verified authorization, policy, and applicable regulation. Draft or unverified rules must be labeled accordingly.
