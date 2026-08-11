# Database Domain Model

Status: **DRAFT ARCHITECTURE BASELINE**

Database: PostgreSQL via Supabase.

## Design principles

- relational model for authoritative transactions;
- UUID primary keys where appropriate;
- explicit foreign keys;
- append-only movement/audit records;
- no destructive cascade for historical financial/business transactions;
- timestamps and actor/source metadata on critical records;
- tenant/organization scope enforced consistently;
- RLS applied to exposed schemas as defense in depth;
- regulatory details remain configurable and versioned.

## Phase 1 core

### Organization
- organizations
- organization_nodes
- organization_units
- organization_assignments
- feature_modules
- regulatory_authorizations

### Identity & access
- profiles
- roles
- permissions
- role_permissions
- user_roles
- user_permissions
- data_scopes
- user_scope_assignments
- grantable_permissions
- segregation_of_duties_policies

### Governance foundation
- approval_policies
- approval_policy_versions
- approval_instances
- approval_steps
- approval_decisions

### Audit
- audit_logs
- security_events

## Cooperative Core
- members
- member_status_history
- member_documents
- member_capital_accounts
- member_capital_transactions
- general_meetings
- meeting_attendance
- meeting_resolutions
- voting_sessions
- voting_records
- governance_positions
- governance_terms
- governance_assignments
- shu_periods
- shu_policy_versions
- shu_allocations

## Commercial & master data
- products
- categories
- units_of_measure
- product_uoms
- product_prices
- customers
- suppliers
- supplier_products

## Inventory & warehouse
- warehouses
- warehouse_zones
- warehouse_locations
- inventory_balances
- inventory_lots
- inventory_movements
- stock_reservations
- stock_opnames
- stock_opname_lines
- stock_adjustments

## Procurement
- purchase_requests
- purchase_request_items
- purchase_orders
- purchase_order_items
- receivings
- receiving_items
- supplier_invoices
- supplier_invoice_items
- three_way_matches

## Sales / POS
- pos_shifts
- sales
- sale_items
- sales_orders
- sales_order_items
- receipts
- sales_returns

## Accounting
- chart_of_accounts
- accounting_periods
- journal_batches
- journals
- journal_lines
- receivables
- payables
- cash_accounts
- bank_accounts
- reconciliations
- budgets
- budget_lines

## Financial Services / Simpan Pinjam

### Product configuration
- financial_products
- financial_product_versions
- product_eligibility_rules
- product_rate_rules
- product_tenor_rules
- product_repayment_rules
- product_channel_rules
- product_accounting_mappings
- product_regulatory_mappings

### Savings
- savings_accounts
- savings_transactions
- term_savings_maturities
- savings_goals
- savings_withdrawal_requests

### Loans
- loan_applications
- loan_assessments
- loan_accounts
- loan_schedules
- loan_installments
- loan_payments
- loan_allocations
- loan_collateral
- collection_cases
- restructuring_cases

### KYC/Compliance
- kyc_profiles
- kyc_reviews
- compliance_alerts
- compliance_cases

## Delivery & fleet
- deliveries
- delivery_items
- delivery_assignments
- proof_of_delivery
- vehicles
- vehicle_maintenance
- routes

## Risk, controls, audit findings
- risks
- risk_assessments
- controls
- control_tests
- audit_findings
- corrective_actions
- incidents

## Document management
- documents
- document_versions
- document_links
- document_approvals

## Integration
- integration_endpoints
- integration_credentials_metadata
- integration_outbox
- integration_inbox
- integration_attempts
- integration_dead_letters

Secrets are never stored in normal application tables; they use secure environment/secret storage.

## Sync/offline
- devices
- sync_queue
- sync_conflicts
- idempotency_keys

## Analytics
Operational transactions remain in the primary database. Large-scale executive analytics may later use dedicated read models or analytical storage.
