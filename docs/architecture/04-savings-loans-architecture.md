# Simpan Pinjam / Financial Services Architecture

**Status:** DRAFT — Architecture Baseline v1  
**Important:** Financial products and controls are configurable, versioned, auditable, and subject to applicable regulation and KDKMP authorization.

## 1. Domain Purpose

The Simpan Pinjam domain supports authorized cooperative financial-service activities without treating KDKMP as a bank by default.

The application must distinguish:

- cooperative/member capital and membership-related savings;
- unit usaha simpan pinjam products and transactions;
- payment-channel integration;
- accounting subledgers;
- regulatory/compliance obligations.

## 2. Main Modules

- Financial Product Engine
- Savings Accounts
- Term Savings
- Goal/Event Savings
- Loan Origination
- Repayment Schedule
- Teller Transactions
- Digital Payment Channels
- Loan Disbursement
- Collection
- Collateral
- KYC / PMPJ support
- APU/PPT support
- Regulatory Compliance
- Savings Subledger
- Loan Subledger
- Reconciliation

## 3. Financial Product Engine

Products must not be hardcoded. Authorized users create product versions through configuration and approval.

### Savings templates

- Flexible Savings
- Term Savings
- Periodic Savings
- Goal Savings
- Event Savings
- Education Savings
- Qurban Savings
- Lebaran Savings
- Business Capital Goal Savings
- Seasonal Savings

Marketing names are separated from legal/regulatory product classification.

Example:

```text
Marketing Name: Simpanan Kurban 2027
Product Family: Goal/Event Savings
Legal Classification: configured according to applicable cooperative regulation
```

### Loan templates

- Monthly Installment Loan
- Weekly Installment Loan
- Biweekly Installment Loan
- Seasonal Loan
- Bullet / At-Maturity Loan
- Balloon Loan
- Working Capital Loan
- Productive Loan
- Education Loan
- Emergency Loan
- Agricultural/Harvest-cycle Loan

Availability of a template does not mean it is automatically legally permitted or approved for a KDKMP.

## 4. Product Configuration

Every product version may configure:

- product code
- product name
- product family
- legal/regulatory classification
- eligibility
- member-only rule
- minimum/maximum amount
- minimum/maximum balance
- minimum opening deposit
- tenor
- repayment frequency
- repayment method
- grace period
- due-date rule
- interest/service rate policy
- calculation method
- fees/charges
- early repayment rules
- withdrawal rules
- maturity rules
- collateral rules
- required documents
- approval requirements
- available channels
- accounting mapping
- risk policy
- regulatory basis
- effective date

## 5. Repayment Methods

Engine capability may support:

- INSTALLMENT
- AMORTIZING
- BULLET / AT_MATURITY
- BALLOON
- CUSTOM_APPROVED_SCHEDULE

Possible frequencies:

- DAILY
- WEEKLY
- BIWEEKLY
- MONTHLY
- QUARTERLY
- SEASONAL
- AT_MATURITY
- CUSTOM

Only configurations allowed by approved policy/regulation can be activated.

## 6. Product Lifecycle

```text
DRAFT
 -> UNDER_REVIEW
 -> COMPLIANCE_CHECK
 -> APPROVED
 -> ACTIVE
 -> SUSPENDED
 -> RETIRED
 -> ARCHIVED
```

RETIRED means no new account/contract is opened under that version while existing contracts continue under their original terms.

## 7. Product Versioning

Existing accounts/loans must preserve a snapshot of the approved product version used at origination/opening.

A new product configuration must never retroactively change historical contracts.

## 8. Savings Transaction Principle

Balances are ledger-derived.

Do not implement direct casual balance editing such as:

```text
balance = new_value
```

Instead:

```text
Opening / Deposit / Withdrawal / Adjustment / Reversal
 -> Savings Ledger
 -> Current Balance
 -> Accounting Event
 -> Audit Trail
```

Any exceptional adjustment requires controlled reason, evidence, permission, and approval where applicable.

## 9. Office/Teller Deposit

```text
Member
 -> Teller
 -> Select Savings Account
 -> Enter Deposit
 -> Validate
 -> Receive Funds
 -> Post Savings Transaction
 -> Accounting Event
 -> Receipt
 -> Audit
```

## 10. QRIS / Digital Payment Deposit

QRIS is implemented through an authorized payment-service/provider adapter, not by pretending the KDKMP application itself is a payment system provider.

```text
Member initiates deposit
 -> Payment Service
 -> QRIS/PJP Adapter
 -> External Payment Confirmation
 -> Reconciliation/Validation
 -> Savings Posting
 -> Accounting
 -> Receipt
```

A screenshot alone does not constitute final payment confirmation for automated balance posting.

Payment status model may include:

- CREATED
- PENDING
- PAID
- SETTLED
- FAILED
- EXPIRED
- REFUNDED

## 11. Withdrawal

```text
Request
 -> Balance/Product Validation
 -> Limit/Policy Check
 -> Risk/Compliance Check when required
 -> Approval when required
 -> Payment
 -> Savings Ledger
 -> Accounting
 -> Audit
```

## 12. Loan Origination

```text
Application
 -> Member/KYC Validation
 -> Eligibility
 -> Credit Analysis
 -> Risk Assessment
 -> Required Documents
 -> Review
 -> Approval
 -> Agreement
 -> Disbursement
 -> Repayment Schedule
 -> Monitoring
 -> Settlement/Closure
```

A prohibited state jump such as DRAFT directly to DISBURSED must be rejected by backend workflow rules.

## 13. Segregation of Duties

The system must support separation between:

- application/origination
- review/analysis
- approval
- disbursement
- collection
- audit/compliance review

A configurable SoD policy can block conflicting combinations.

## 14. Accounting & Subledger

Financial services require dedicated subledgers:

- Savings Subledger
- Loan Subledger
- General Ledger

Reconciliation principle:

```text
Total member savings liability in subledger
=
Corresponding general-ledger liability balance
```

Differences must generate reconciliation exceptions.

## 15. Regulatory & Authorization Guard

The domain uses a regulatory policy and authorization registry with fields such as:

- legal basis
- regulation number/title
- issuing authority
- applicable entity/activity
- permit/authorization number
- operating scope
- effective date
- expiry date
- status
- evidence/document
- system control

Possible authorization states:

- ACTIVE
- PENDING
- SUSPENDED
- EXPIRED
- NOT_AUTHORIZED

If required authorization is not ACTIVE, affected financial transactions are blocked.

## 16. Data Classification

Member financial data is classified at least CONFIDENTIAL/RESTRICTED according to the final data-governance policy.

Examples:

- identity data
- balances
- loans
- repayment history
- arrears
- income/source-of-funds data
- KYC documents

Access is permission- and scope-controlled and auditable.

## 17. Management Dashboard Metrics

Possible transaction-derived metrics include:

- total savings
- savings by product
- outstanding loans
- loans due soon
- overdue amounts
- collection performance
- liquidity indicators
- product performance
- approval backlog
- reconciliation exceptions
- KYC/compliance review queue

Metrics must not be presented as official regulatory ratios unless their formula and legal basis are verified and versioned.
