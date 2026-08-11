# Cooperative Core Architecture

Status: **DRAFT ARCHITECTURE BASELINE**

## Purpose

Cooperative Core is the domain that makes KDKMP a cooperative operating system rather than a generic retail ERP. It owns membership, member rights, cooperative capital, governance records, RAT-related records, and SHU-related data.

## Core principles

1. Membership data is authoritative and created once.
2. Membership status changes are historical events, not destructive edits.
3. Cooperative capital/membership savings are separated from commercial savings products in the Simpan Pinjam unit.
4. Governance positions are separated from application roles.
5. RAT, resolutions, voting, and SHU data must be versioned, traceable, and auditable.
6. Historical cooperative records are never hard deleted through normal UI flows.

## Domain model

### Member
Suggested entities:
- members
- member_status_history
- member_addresses
- member_contacts
- member_documents
- member_beneficiaries

Suggested membership lifecycle:

`APPLICANT -> UNDER_REVIEW -> ACTIVE -> SUSPENDED -> INACTIVE -> RESIGNED/TERMINATED -> ARCHIVED`

Exact legal transitions are **PENDING LEGAL VALIDATION**.

### Cooperative capital and membership-related savings

This area is intentionally separate from the financial-services savings product engine.

Suggested entities:
- member_capital_accounts
- member_capital_transactions
- membership_savings_types
- membership_savings_transactions

Examples may include mandatory/initial/member-capital-related contributions, but exact terminology, treatment, and accounting rules are **PENDING AD/ART AND REGULATORY VALIDATION**.

### Governance

Suggested entities:
- governance_bodies
- governance_positions
- governance_terms
- governance_assignments
- governance_decisions

A person may hold a governance position without that position being identical to a system role.

### RAT / General Meeting

Suggested entities:
- general_meetings
- meeting_agendas
- meeting_attendance
- meeting_documents
- meeting_resolutions
- voting_sessions
- voting_options
- voting_records

Meeting records must preserve version history and evidence.

### SHU

Suggested entities:
- shu_periods
- shu_policies
- shu_policy_versions
- shu_calculations
- shu_allocations
- shu_member_entitlements
- shu_distributions

The system must never hardcode an SHU formula as a universal rule. Formula, weights, period, eligibility, and allocation method must be configurable and versioned. Official formulas are **PENDING ORGANIZATIONAL/REGULATORY VALIDATION**.

## Important separation: Cooperative Core vs Simpan Pinjam

A member can have both:

- cooperative membership/capital records; and
- commercial financial-service accounts from the Simpan Pinjam unit.

These are related by member identity but must not be merged into one balance.

Example:

```text
MEMBER
├── Cooperative Core
│   ├── Membership status
│   ├── Member capital
│   └── SHU entitlement
└── Financial Services
    ├── Savings account
    ├── Term savings account
    └── Loan account
```

## Audit requirements

Every critical change records at minimum:
- actor
- action
- timestamp
- source/device/session where available
- before state
- after state
- reason
- evidence/document reference where relevant

## Phase dependency

Cooperative Core is designed in Phase 0 and implemented incrementally beginning in Phase 2 after Identity, Organization, RBAC, Scope, and Audit foundations are stable.
