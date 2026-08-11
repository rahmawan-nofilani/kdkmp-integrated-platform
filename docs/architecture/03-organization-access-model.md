# Organization & Access Model

**Status:** DRAFT — Architecture Baseline v1

## 1. Organization Hierarchy

```text
PLATFORM
  -> PROVINCE
    -> REGENCY / CITY
      -> DISTRICT
        -> VILLAGE / URBAN VILLAGE
          -> KDKMP
            -> BUSINESS UNIT
```

The application must support multiple KDKMP organizations.

## 2. Organization Node Principle

Business data should be attached to an authoritative organization/unit structure. Do not duplicate multiple unrelated location identifiers in every table if they can conflict.

Core concepts:

- tenant/platform boundary
- organization node
- KDKMP
- business unit
- operating location

## 3. Initial Business Units

A KDKMP may activate one or more units:

- Office / Administration
- Retail / Gerai
- Warehouse
- Simpan Pinjam
- Distribution
- Offtaking
- LPG
- Pupuk
- Clinic
- Pharmacy
- Other approved unit

Module enabled does not automatically mean legally authorized.

## 4. Position vs System Role

Organizational position and application role are separate concepts.

Example:

```text
Person: Budi
Position: Manager KDKMP
System Role: ROLE_MANAGER
Scope: KDKMP A + all authorized units
```

Another example:

```text
Person: Siti
Position: Petugas Gerai
System Roles:
- ROLE_CASHIER
- ROLE_INVENTORY_VIEWER
Scope: KDKMP A / Gerai 01
```

## 5. Core Organizational Positions

Examples, configurable by organization:

- Ketua Pengurus
- Sekretaris
- Bendahara
- Pengawas
- Manager
- Admin
- Kasir
- Petugas Gudang
- Procurement Officer
- Finance Officer
- Teller
- Loan Officer
- Compliance Officer
- Courier

## 6. System Roles

Initial role families:

- MANAGER
- ADMIN
- MEMBER
- COURIER
- BOARD / PENGURUS
- SUPERVISOR / PENGAWAS
- CASHIER
- WAREHOUSE_OPERATOR
- PROCUREMENT_OFFICER
- FINANCE_OFFICER
- TELLER
- LOAN_OFFICER
- COMPLIANCE_OFFICER

Roles are bundles of permissions. Roles alone must not determine access.

## 7. Permission Model

Permissions use action-oriented codes such as:

- USER_VIEW
- USER_CREATE
- USER_UPDATE
- USER_SUSPEND
- ROLE_VIEW
- PERMISSION_ASSIGN
- MEMBER_VIEW
- MEMBER_CREATE
- PRODUCT_VIEW
- PRODUCT_CREATE
- INVENTORY_VIEW
- INVENTORY_RECEIVE
- INVENTORY_ADJUST
- PURCHASE_CREATE
- PURCHASE_SUBMIT
- PURCHASE_APPROVE
- PAYMENT_CREATE
- PAYMENT_APPROVE
- SAVINGS_VIEW
- SAVINGS_DEPOSIT
- SAVINGS_WITHDRAW
- LOAN_CREATE
- LOAN_REVIEW
- LOAN_APPROVE
- LOAN_DISBURSE
- AUDIT_VIEW
- REPORT_VIEW

Permissions must be stored/configured, not implemented only as role-name if-statements.

## 8. Data Scope

Examples:

- PLATFORM scope
- REGIONAL scope
- KDKMP scope
- UNIT scope
- OWN_DATA_ONLY
- ASSIGNED_DELIVERIES_ONLY

A member must default to OWN_DATA_ONLY for member-facing financial and membership data.

## 9. Access Decision

```text
Authenticated Identity
+ Active User Status
+ Role
+ Permission
+ Data Scope
+ Feature/Unit Activation
+ Workflow State
+ Segregation-of-Duties Rule
+ Regulatory Authorization
= ALLOW / DENY
```

## 10. User Lifecycle

```text
PENDING
 -> ACTIVE
 -> SUSPENDED
 -> INACTIVE
 -> ARCHIVED
```

Users with historical transactions must not be permanently deleted through normal business UI.

## 11. Provisioning / Bootstrap

The initial Manager cannot be created by a Manager who does not yet exist. Therefore the architecture includes a controlled platform/tenant provisioning function that creates or assigns the initial authorized KDKMP administrator/Manager.

This provisioning authority is not an ordinary KDKMP operational role.

## 12. Grantable Permission Control

A Manager cannot freely grant any permission in the platform. Permissions that a user can assign must be constrained by a grantable-permission policy.

A user must not be able to elevate themselves or another user beyond the authority delegated to them.

## 13. Segregation of Duties

Examples of conflict rules:

- transaction creator should not automatically be final approver;
- loan originator should not automatically be final disbursement approver;
- payment creator and payment approver may require separation;
- auditor/supervisor must not modify audited business transactions;
- audit records cannot be removed through normal application operations.
