# System Architecture Baseline

**Status:** DRAFT — Architecture Baseline v1

## 1. Architectural Goal

KDKMP Digital Operating System is designed as a modular enterprise application, not as a collection of disconnected menus.

## 2. Initial Architecture

```text
Users (Desktop / Mobile / PWA)
            |
            v
      Next.js Application
            |
            +--------------------+
            |                    |
            v                    v
     Server/API Layer       UI/Application Layer
            |
            v
       Supabase Platform
   +--------+---------+
   |        |         |
Postgres   Auth     Storage
   |
   v
Business Transactions
   |
   +--> Inventory / Sales / Procurement
   +--> Accounting Events
   +--> Approval / Workflow
   +--> Audit Events
   +--> Reporting Read Models
   +--> Integration Outbox (future)
```

## 3. Architecture Style

Initial implementation uses a **Modular Monolith**.

Reason:

- simpler to operate for early KDKMP deployment;
- fewer infrastructure components;
- easier transaction consistency;
- lower operational complexity;
- bounded contexts can later be extracted into dedicated services when justified.

## 4. Core Bounded Contexts

1. Identity & Access
2. Organization
3. Cooperative Core
4. Human Resources
5. Commercial
6. Procurement
7. Inventory & Warehouse
8. Supply Chain & Fulfillment
9. Finance & Accounting
10. Financial Services / Simpan Pinjam
11. Governance & Approval
12. Risk & Internal Control
13. Audit & Compliance
14. Regulated Business
15. Document Management
16. Integration
17. Reporting & Analytics
18. AI Assistant

## 5. Core Access Formula

Every protected action is evaluated using:

```text
Identity
+ Role
+ Permission
+ Data Scope
+ Workflow State
+ Segregation-of-Duties Policy
+ Regulatory/Authorization State
= ALLOW or DENY
```

UI visibility is convenience only. Authorization must be enforced server-side and, where applicable, at database/RLS level.

## 6. Transaction Principle

A business transaction is the authoritative source. Downstream consequences are generated from the transaction, not manually re-entered.

Example:

```text
POS SALE COMPLETED
    |
    +--> payment record
    +--> inventory movement
    +--> accounting event
    +--> member/customer history
    +--> KPI/reporting event
    +--> audit log
```

## 7. Integration Principle

External integrations must use adapters.

Examples:

- PaymentAdapter
- QRIS/PJP Adapter
- SIMKOPDESAdapter
- LogisticsAdapter
- GovernmentAdapter

If an official API is not available, integration remains disabled or uses explicitly labeled mock/sandbox behavior. Mock behavior must never be presented as an official live integration.

## 8. Offline Principle

Offline capability is selective, not universal. Every transaction type must declare whether it supports offline operation and its conflict policy.

Sensitive actions such as privilege changes, certain approvals, regulated authorization changes, and external settlement should default to online-only unless explicitly designed otherwise.

## 9. Data Principle

Operational data is stored in PostgreSQL. Master data is reused across modules. Financial and inventory balances are derived from controlled ledgers/movements rather than casual direct edits.

## 10. Evolution Path

When scale requires it, selected concerns may be extracted into dedicated services/workers, for example:

- notification worker;
- integration worker;
- analytics pipeline;
- AI orchestration service;
- high-volume financial processing service.

Extraction must be justified by load, isolation, compliance, or operational needs, not by architectural fashion.
