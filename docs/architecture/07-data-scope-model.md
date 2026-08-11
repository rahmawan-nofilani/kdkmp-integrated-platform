# Data Scope Model

Status: **DRAFT ARCHITECTURE BASELINE**

## Purpose

Data Scope controls *which records* a user may access after role and permission checks pass.

## Scope hierarchy

```text
PLATFORM
└── PROVINCE
    └── REGENCY/CITY
        └── DISTRICT
            └── VILLAGE/URBAN VILLAGE
                └── KDKMP
                    └── BUSINESS UNIT
```

## Scope types

- PLATFORM_SCOPE
- REGION_SCOPE
- COOPERATIVE_SCOPE
- UNIT_SCOPE
- OWN_DATA_ONLY
- ASSIGNED_RECORDS_ONLY

## Examples

### KDKMP Manager
`COOPERATIVE_SCOPE = KDKMP X`

May access authorized data across units under KDKMP X.

### Teller
`UNIT_SCOPE = SIMPAN_PINJAM`

May access only authorized financial-service data for the assigned unit.

### Courier
`ASSIGNED_RECORDS_ONLY = DELIVERY_ASSIGNMENTS`

May access only deliveries assigned to that courier.

### Member
`OWN_DATA_ONLY`

May access only their own membership, savings, loan, purchase, order, benefit, and SHU data subject to specific permissions.

## Technical model

Recommended entities:
- data_scopes
- user_scope_assignments
- organization_nodes
- organization_units

Avoid duplicating `tenant_id + cooperative_id + region_id + unit_id` in every table when a canonical organization node can provide hierarchy. Denormalized identifiers may be added only when justified for performance and protected from inconsistency.

## Backend enforcement

Menu hiding is never sufficient. Scope is checked server-side and/or through database policies.

A valid role with an invalid scope must still return `403 Forbidden` or no accessible rows, depending on endpoint semantics.

## Cross-tenant protection

A user from one cooperative must never access another cooperative's records unless explicitly assigned a higher regional/platform scope through approved governance.
