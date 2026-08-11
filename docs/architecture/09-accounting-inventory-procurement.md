# Accounting, Inventory & Procurement Architecture

Status: **DRAFT ARCHITECTURE BASELINE**

## Accounting principles

- Financial statements are generated from transaction postings, never manually hardcoded.
- Posted journals are immutable.
- Corrections use reversal and correcting entries.
- Subledgers reconcile to the general ledger.
- Accounting periods support open, soft-close, hard-close, and locked states.

## Core accounting entities

- chart_of_accounts
- accounting_periods
- journals
- journal_lines
- journal_sources
- journal_batches
- receivables
- payables
- cash_accounts
- bank_accounts
- reconciliations
- budgets
- budget_lines

## Posting examples

### Cash sale
- Dr Cash
- Cr Revenue
- Dr Cost of Goods Sold
- Cr Inventory

### Credit sale
- Dr Receivable
- Cr Revenue
- Dr Cost of Goods Sold
- Cr Inventory

### Goods received before supplier invoice
- Dr Inventory
- Cr GRNI / interim liability

### Supplier invoice
- clear GRNI as applicable
- recognize payable

### Supplier payment
- Dr Payable
- Cr Cash/Bank

Exact account codes remain configurable.

## Inventory principles

Inventory is movement-based, not direct-balance editing.

### Stock states
- ON_HAND
- AVAILABLE
- RESERVED
- ALLOCATED
- QUARANTINE
- DAMAGED
- EXPIRED
- IN_TRANSIT

### Movement types
- RECEIPT
- SALE
- TRANSFER
- RETURN
- ADJUSTMENT
- DAMAGE
- EXPIRED
- LOSS

### Warehouse hierarchy
`WAREHOUSE -> ZONE -> LOCATION -> BIN`

### Product/UOM
Support:
- SKU
- barcode
- base UOM
- alternate UOM
- UOM conversion
- batch/lot
- expiry
- reorder point
- min/max stock

### Costing
Inventory valuation method must be configured before transactional go-live. Candidate methods include weighted average, FIFO, or other approved method. Final choice is a policy decision.

## Reservation model

`ON_HAND - RESERVED - QUARANTINE - other unavailable quantity = AVAILABLE`

Sales orders reserve inventory before shipment. Physical stock decreases when the appropriate fulfillment movement occurs.

## Procurement controls

Canonical flow:
`REQUEST -> APPROVAL -> PO -> RECEIVING -> QC -> SUPPLIER INVOICE -> THREE WAY MATCH -> PAYMENT`

Three-way matching compares:
- PO
- accepted receiving
- supplier invoice

Tolerance policy for quantity/price differences is configurable and versioned.

## Segregation of duties

Recommended separation:
- requester
- approver
- receiver/QC
- invoice recorder
- payment maker
- payment approver

No single user should control the entire procure-to-pay chain.
