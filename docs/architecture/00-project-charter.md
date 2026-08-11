# KDKMP Integrated Management Platform — Project Charter

**Status:** DRAFT — Architecture Baseline v1  
**Project:** KDKMP Integrated Management Platform  
**Working Name:** KDKMP Digital Operating System  
**Phase:** 0 — Architecture  

## 1. Purpose

Membangun platform digital terpadu untuk mendukung operasional, tata kelola, transaksi, pengawasan, pelaporan, dan pengambilan keputusan Koperasi Desa/Kelurahan Merah Putih (KDKMP).

Sistem tidak diposisikan sebagai website koperasi atau dashboard statis, melainkan sebagai digital operating system yang secara bertahap dapat berkembang menjadi Cooperative ERP + POS + WMS + SCM + CRM + Accounting + Financial Services + Governance + Audit + Analytics + AI.

## 2. Primary Users

- Manager
- Pengurus
- Pengawas
- Admin
- Anggota
- Kurir
- Kasir
- Petugas Gudang
- Procurement Officer
- Finance Officer
- Teller
- Loan Officer
- Compliance Officer

## 3. Core Principles

1. **One Data** — data master tidak dimasukkan berulang.
2. **One Transaction** — satu transaksi menghasilkan dampak otomatis ke domain terkait.
3. **Traceable** — transaksi dapat ditelusuri dari sumber sampai jurnal, pembayaran, dan audit.
4. **Segregation of Duties** — pembuat, penyetuju, pembayar, dan auditor dipisahkan sesuai kebijakan.
5. **Never Trust Frontend** — backend/database tetap memvalidasi akses.
6. **No Unsafe Hard Delete** — transaksi historis tidak dihapus tanpa mekanisme koreksi yang sah.
7. **Configuration over Hardcode** — workflow, produk, approval, parameter, dan regulasi dikonfigurasi.
8. **Audit by Design** — aktivitas penting menghasilkan audit trail.
9. **Regulatory by Design** — regulasi diterjemahkan menjadi kontrol sistem, bukan hanya dokumen referensi.
10. **Human Control over AI** — AI membantu analisis, tidak mengambil alih keputusan kritis tanpa kontrol manusia.

## 4. Business Scope

Platform dirancang untuk mencakup:

- Kelembagaan dan organisasi
- Keanggotaan dan cooperative core
- User, role, permission, data scope
- SDM dan assignment
- Gerai dan POS
- Product master dan pricing
- Procurement dan supplier
- Warehouse dan inventory
- Penjualan dan pembelian
- Distribusi, delivery, kurir, fleet
- Finance dan accounting
- Unit Simpan Pinjam dan financial product engine
- Offtaking dan kemitraan
- LPG, pupuk, klinik, apotek sebagai regulated business modules
- Asset management
- KPI dan target
- Risk, internal control, pengawasan, audit
- Document management
- Approval dan workflow
- Notification
- Reporting
- External integration
- Analytics dan AI Assistant

## 5. Technology Baseline

Initial implementation baseline:

- Application: Next.js + TypeScript
- Database: PostgreSQL via Supabase
- Authentication: Supabase Auth
- Storage: Supabase Storage
- Hosting / Delivery: Vercel
- Source Control: GitHub
- Architecture Style: Modular Monolith with clear bounded contexts

Architecture must remain evolvable toward dedicated backend services/workers when scale or integration complexity requires it.

## 6. Environment Strategy

- **Development** — development and demo data only.
- **Staging/UAT** — user acceptance testing, no production personal/financial data.
- **Production** — official operational data, created only after security, testing, backup, and governance readiness.

## 7. Non-Negotiable Controls

- No hardcoded production passwords.
- No fake government API presented as real integration.
- No RBAC implemented only by hiding UI.
- No manual KPI presented as transaction-derived KPI.
- No financial reports derived from hardcoded values.
- No audit trail deletion through normal application operations.
- No activation of regulated business/product without authorization/compliance state.
- No financial product changes that retroactively alter existing contracts/accounts.

## 8. Project Governance

Architecture Baseline must be approved before Phase 1 implementation.

Material architecture changes after baseline approval must be documented using Architecture Decision Records (ADR).

## 9. Current Status

Phase 0 is active. Production coding and production database use are not yet authorized.
