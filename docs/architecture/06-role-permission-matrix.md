# Role & Permission Matrix

Status: **DRAFT ARCHITECTURE BASELINE**

## Access formula

Access is evaluated as:

`IDENTITY + ROLE + PERMISSION + DATA SCOPE + WORKFLOW STATE + SEGREGATION OF DUTIES + REGULATORY STATUS`

Roles are not sufficient by themselves.

## Primary roles

- MANAGER
- ADMIN
- MEMBER
- COURIER
- SUPERVISOR/PENGAWAS
- BOARD/PENGURUS

## Operational roles

- CASHIER
- WAREHOUSE_OPERATOR
- PROCUREMENT_OFFICER
- FINANCE_OFFICER
- TELLER
- LOAN_OFFICER
- COMPLIANCE_OFFICER
- AUDITOR

A user may hold multiple roles only when allowed by segregation-of-duties policy.

## Permission namespace

### Identity & User
- USER_VIEW
- USER_CREATE
- USER_UPDATE
- USER_SUSPEND
- USER_ARCHIVE
- ROLE_VIEW
- ROLE_ASSIGN
- PERMISSION_VIEW
- PERMISSION_GRANT
- SCOPE_ASSIGN

### Member
- MEMBER_VIEW
- MEMBER_CREATE
- MEMBER_UPDATE
- MEMBER_STATUS_CHANGE
- MEMBER_DOCUMENT_VIEW
- MEMBER_DOCUMENT_UPDATE

### Product & Inventory
- PRODUCT_VIEW
- PRODUCT_CREATE
- PRODUCT_UPDATE
- PRODUCT_PRICE_CHANGE
- INVENTORY_VIEW
- INVENTORY_RECEIVE
- INVENTORY_TRANSFER
- INVENTORY_ADJUST_REQUEST
- INVENTORY_ADJUST_APPROVE
- STOCK_OPNAME_CREATE
- STOCK_OPNAME_APPROVE

### Procurement
- PURCHASE_REQUEST_CREATE
- PURCHASE_REQUEST_SUBMIT
- PURCHASE_APPROVE
- PURCHASE_ORDER_CREATE
- RECEIVING_CREATE
- RECEIVING_QC
- SUPPLIER_INVOICE_RECORD
- SUPPLIER_PAYMENT_CREATE
- SUPPLIER_PAYMENT_APPROVE

### Sales/POS
- SALES_CREATE
- SALES_DISCOUNT
- SALES_VOID_REQUEST
- SALES_VOID_APPROVE
- POS_OPEN_SHIFT
- POS_CLOSE_SHIFT
- CASH_RECONCILIATION

### Finance & Accounting
- JOURNAL_VIEW
- JOURNAL_CREATE
- JOURNAL_POST
- JOURNAL_REVERSE
- PAYMENT_CREATE
- PAYMENT_APPROVE
- BANK_RECONCILE
- REPORT_FINANCE_VIEW
- REPORT_FINANCE_EXPORT

### Simpan Pinjam
- SAVINGS_PRODUCT_VIEW
- SAVINGS_PRODUCT_CREATE
- SAVINGS_PRODUCT_UPDATE
- SAVINGS_PRODUCT_SUBMIT
- SAVINGS_PRODUCT_APPROVE
- SAVINGS_ACCOUNT_OPEN
- SAVINGS_DEPOSIT
- SAVINGS_WITHDRAW_REQUEST
- SAVINGS_WITHDRAW_APPROVE
- LOAN_PRODUCT_VIEW
- LOAN_PRODUCT_CREATE
- LOAN_PRODUCT_UPDATE
- LOAN_APPLICATION_CREATE
- LOAN_ANALYZE
- LOAN_REVIEW
- LOAN_APPROVE
- LOAN_DISBURSE
- LOAN_REPAYMENT_POST
- LOAN_COLLECTION_MANAGE
- KYC_REVIEW
- COMPLIANCE_REVIEW

### Delivery
- DELIVERY_VIEW
- DELIVERY_ASSIGN
- DELIVERY_ACCEPT
- DELIVERY_STATUS_UPDATE
- DELIVERY_POD_UPLOAD

### Governance & Audit
- APPROVAL_VIEW
- APPROVAL_DECIDE
- RISK_VIEW
- RISK_MANAGE
- CONTROL_VIEW
- CONTROL_TEST
- AUDIT_VIEW
- AUDIT_FINDING_CREATE
- AUDIT_FOLLOWUP_REVIEW

## Default role policy (summary)

| Capability | Manager | Admin | Member | Courier | Pengawas | Pengurus |
|---|---:|---:|---:|---:|---:|---:|
| Create operational user | Yes | No | No | No | No | No |
| Assign ordinary operational role | Policy | No | No | No | No | No |
| Grant privileged permission | No/self-escalation blocked | No | No | No | No | Governance policy |
| View own member data | Yes if member | N/A | Yes | No | Audit scope | Governance scope |
| Create operational transaction | Yes by permission | Yes by permission | Limited self-service | Delivery only | No | Normally no |
| Strategic approval | Policy | No | No | No | No | Policy |
| Audit/review | View | Limited | Own history | Own delivery history | Yes | View |
| Delete historical transaction | No | No | No | No | No | No |

## Segregation-of-duties examples

The following combinations may be blocked within the same transaction:

- creator + final approver
- final approver + payer
- loan analyst + final loan approver
- loan final approver + disbursement officer
- stock counter + final stock-adjustment approver
- supplier invoice recorder + final supplier-payment approver

Exact SoD combinations remain configurable.

## Privilege delegation rule

A manager cannot grant a permission outside their delegated grantable-permission set and cannot elevate their own account beyond approved authority.

Privileged permissions require a higher-level approval or platform/tenant governance process.
