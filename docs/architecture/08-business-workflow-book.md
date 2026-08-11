# Business Workflow Book

Status: **DRAFT ARCHITECTURE BASELINE**

This document defines the canonical state-driven flows. Exact regulatory steps may be extended later without changing the core architecture.

## 1. User lifecycle

`PENDING -> ACTIVE -> SUSPENDED -> INACTIVE -> ARCHIVED`

No permanent deletion when transaction history exists.

## 2. Procurement

`REQUEST -> REVIEW -> SUBMITTED -> APPROVAL -> PURCHASE_ORDER -> DELIVERY -> RECEIVING -> QUALITY_CHECK -> WAREHOUSE -> INVOICE -> THREE_WAY_MATCH -> PAYMENT -> COMPLETED`

Invalid shortcut example: `DRAFT -> PAID` is forbidden.

## 3. Inventory receiving

`EXPECTED -> RECEIVED -> QC_PENDING -> ACCEPTED/REJECTED -> PUTAWAY -> AVAILABLE`

## 4. Stock opname

`OPEN -> COUNTING -> REVIEW -> DIFFERENCE_IDENTIFIED -> REASON_AND_EVIDENCE -> APPROVAL -> ADJUSTMENT -> CLOSED`

Never execute direct `stock = physical_count` without an approved movement.

## 5. POS cash sale

`SHIFT_OPEN -> CART -> CUSTOMER/MEMBER -> PRICE/DISCOUNT_VALIDATION -> PAYMENT -> SALE_COMPLETE -> INVENTORY_MOVEMENT -> ACCOUNTING_EVENT -> RECEIPT -> AUDIT`

## 6. Sales order / B2B

`DRAFT -> CONFIRMED -> RESERVED -> PICKING -> PACKING -> SHIPPED -> INVOICED -> PAID/PARTIALLY_PAID -> COMPLETED`

## 7. Delivery

`ORDER_CREATED -> VERIFIED -> PICKING -> PACKING -> ASSIGNED -> ACCEPTED -> PICKED_UP -> ON_DELIVERY -> ARRIVED -> DELIVERED -> POD_VERIFIED -> COMPLETED`

POD can include GPS, photo, signature, and timestamp.

## 8. Savings deposit

### Teller/cash
`INITIATED -> MEMBER_VALIDATED -> CASH_RECEIVED -> TRANSACTION_POSTED -> SAVINGS_SUBLEDGER_UPDATED -> ACCOUNTING_POSTED -> RECEIPT -> AUDIT`

### QRIS/digital
`PAYMENT_CREATED -> PENDING -> EXTERNAL_CONFIRMATION -> PAID -> DEPOSIT_POSTED -> SUBLEDGER_UPDATED -> ACCOUNTING_POSTED -> SETTLEMENT_RECONCILIATION`

Screenshot upload alone never means PAID.

## 9. Savings withdrawal

`REQUESTED -> BALANCE_VALIDATION -> PRODUCT_RULE_VALIDATION -> RISK/COMPLIANCE_CHECK -> APPROVAL_IF_REQUIRED -> PAYMENT -> SUBLEDGER_POSTING -> ACCOUNTING -> AUDIT -> COMPLETED`

## 10. Loan origination

`APPLICATION -> MEMBER/KYC_VALIDATION -> ELIGIBILITY -> CREDIT_ANALYSIS -> RISK_ASSESSMENT -> DOCUMENT_REVIEW -> APPROVAL -> AGREEMENT -> DISBURSEMENT -> ACTIVE_LOAN`

## 11. Loan repayment

`DUE -> PAYMENT_INITIATED -> PAYMENT_CONFIRMED -> ALLOCATION -> LOAN_SUBLEDGER -> ACCOUNTING -> RECEIPT -> AUDIT`

## 12. Overdue / collection

`CURRENT -> DUE -> OVERDUE -> COLLECTION -> ACTION_PLAN -> RESTRUCTURING_IF_APPROVED -> SETTLED/CLOSED`

Exact classification terminology and thresholds are **PENDING REGULATORY VALIDATION**.

## 13. Journal lifecycle

`DRAFT -> VALIDATED -> POSTED -> REVERSED`

POSTED journals are immutable. Corrections use reversal and correcting entries.

## 14. Approval lifecycle

`DRAFT -> SUBMITTED -> UNDER_REVIEW -> APPROVED/REJECTED/CANCELLED -> COMPLETED`

Every submitted transaction stores policy version and workflow snapshot.

## 15. Risk and audit

`RISK -> CONTROL -> CONTROL_TEST -> FINDING -> ACTION_PLAN -> FOLLOW_UP -> VERIFIED -> CLOSED`

## 16. Incident

`REPORTED -> INVESTIGATION -> ROOT_CAUSE -> ACTION -> VERIFICATION -> CLOSED`

## 17. Document

`DRAFT -> REVIEW -> APPROVED -> ACTIVE -> SUPERSEDED/EXPIRED -> ARCHIVED`

## State-machine rule

Every transition is validated on the backend. UI visibility is convenience only; it is not the enforcement layer.
