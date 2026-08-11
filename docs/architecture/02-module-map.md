# Module / Bounded Context Map

**Status:** DRAFT — Architecture Baseline v1

## 1. Identity & Access
- Authentication
- Session Management
- User Lifecycle
- Roles
- Permissions
- User-specific permission overrides
- Data Scope
- MFA readiness
- Access Review

## 2. Organization
- Platform hierarchy
- Region hierarchy
- KDKMP
- Unit Usaha
- Organizational positions
- Assignments
- Feature/module activation

## 3. Cooperative Core
- Members
- Membership lifecycle/history
- Member capital
- Member savings related to cooperative membership
- General meetings / RAT
- Attendance
- Resolutions
- Voting (when applicable)
- SHU periods and allocations
- Governance terms and assignments

## 4. Human Resources
- Employees/staff
- Position assignment
- Work unit
- Employment status
- Task assignment
- Performance configuration

## 5. Commercial
- Product master
- Category
- UOM
- Pricing
- Promotion
- Customer
- POS
- Sales order
- Invoice / receipt
- Return / void controls

## 6. Procurement
- Purchase request
- Review and approval
- Purchase order
- Supplier
- Receiving
- Quality check
- Invoice matching
- Three-way matching

## 7. Inventory & Warehouse
- Warehouse
- Zone/location/bin
- Inventory balance
- Batch/lot/expiry
- Receipt
- Transfer
- Reservation
- Allocation
- Damage
- Expiry
- Loss
- Stock opname
- Adjustment approval
- Inventory costing policy

## 8. Supply Chain & Fulfillment
- Order fulfillment
- Picking
- Packing
- Delivery assignment
- POD
- Courier
- Fleet
- Distribution
- Hub/Torasera
- Offtaking

## 9. Finance & Accounting
- Chart of accounts
- Accounting event
- Journal
- General ledger
- Subledger
- Cash
- Bank
- Receivable
- Payable
- Budget
- Reconciliation
- Period close/lock
- Financial statements

## 10. Financial Services — Simpan Pinjam
- Financial Product Engine
- Savings products
- Term savings
- Goal/event savings
- Loan products
- Repayment schedule
- Teller/counter transaction
- Digital payment channel
- Loan origination
- Credit analysis
- Disbursement
- Collection
- Collateral
- KYC/PMPJ
- APU/PPT support
- Financial subledger
- Regulatory product validation

## 11. Governance & Approval
- Approval policy
- Approval matrix
- Workflow versioning
- Delegation/substitution
- Conflict of interest control
- Strategic approval
- Governance decision records

## 12. Risk & Internal Control
- Risk register
- Risk scoring
- Mitigation
- Control library
- Control checklist
- Control testing
- Follow-up actions

## 13. Audit & Compliance
- Append-only audit trail
- Findings
- Recommendations
- Follow-up
- Compliance obligations
- Regulatory library
- Authorization/permit register
- Regulatory status checks

## 14. Regulated Business
- LPG
- Pupuk
- Klinik
- Apotek
- Other regulated goods/services

Each regulated module must support legal basis, permit/authorization, effective dates, expiry, issuing authority, and transaction blocking when authorization is not active.

## 15. Document Management
- Upload
- Preview
- Download
- Version
- Classification
- Approval
- Expiry
- Ownership
- Link to business records

## 16. Integration
- Payment Adapter
- SIMKOPDES Adapter
- Supplier Adapter
- Logistics Adapter
- Government Adapter
- Outbox/inbox
- Retry
- Idempotency
- Reconciliation

## 17. Reporting & Analytics
- Operational reporting
- Finance reporting
- KPI
- Target vs actual
- Executive dashboards
- Drill-down/data lineage
- Export

## 18. AI Assistant
- Permission-aware data tools
- Data-grounded answers
- No unrestricted database access
- No autonomous critical financial approval
- Explainable source metrics where feasible

## Navigation Principle

The UI must not expose all bounded contexts as a flat 30–40 item sidebar. Navigation is task/domain based and filtered by permission and module activation.
