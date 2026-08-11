# KDKMP Integrated Management Platform

**Working name:** KDKMP Digital Operating System  
**Current phase:** PHASE 0 — Architecture Baseline  
**Repository status:** Private development repository  

## What is this project?

KDKMP Integrated Management Platform is being designed as a digital operating system for Koperasi Desa/Kelurahan Merah Putih.

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

We are intentionally **not coding production features yet**.

Phase 0 is documenting and approving the architecture before database schemas and application features are implemented.

Start here:

- `docs/architecture/00-project-charter.md`
- `docs/architecture/01-system-architecture.md`
- `docs/architecture/02-module-map.md`
- `docs/architecture/03-organization-access-model.md`
- `docs/architecture/04-savings-loans-architecture.md`
- `docs/decisions/ADR-001-foundation-stack.md`

## Initial technology baseline

- Next.js + TypeScript
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- Vercel
- GitHub
- Modular Monolith architecture

## Environment policy

- Development: demo/test data only
- Staging/UAT: testing and acceptance
- Production: official operational data only after security and readiness approval

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

## Important

Financial-services, regulated-business, accounting, and government-integration behavior must be driven by verified authorization, policy, and applicable regulation. Draft or unverified rules must be labeled accordingly.
