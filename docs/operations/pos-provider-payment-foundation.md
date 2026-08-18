# POS Trusted Provider Payment Foundation

Environment target: DEVELOPMENT. Production activation is not authorized.

## Purpose

This foundation separates three states that must never be conflated:

1. the cashier starts a QRIS/BANK_TRANSFER payment intent;
2. a trusted backend adapter verifies an authoritative provider event and confirms that the customer paid;
3. a provider/bank settlement file or API result is reconciled before the cooperative records the provider receivable as settled to bank.

A screenshot, uploaded image, cashier statement, customer message, or manually typed transaction reference is never authoritative payment confirmation.

## Existing cashier boundary

`start_pos_payment(...)` remains the cashier-facing initiation command. QRIS/BANK_TRANSFER can only start when an organization-scoped provider configuration is `ACTIVE`, `VALIDATED`, and supports the requested channel.

The current DEMO QRIS and BANK_TRANSFER provider records remain placeholders and must not be activated merely to make the buttons usable.

## Trusted confirmation contract

A provider adapter must perform provider-specific signature/authentication validation before calling:

`confirm_pos_provider_payment(...)`

The RPC is executable only by `service_role`. It requires exact agreement across:

- provider configuration;
- internal payment attempt;
- merchant reference;
- provider reference;
- amount;
- currency;
- trusted external event id;
- SHA-256 payload hash.

Only a verified `PAID` event can complete this foundation path.

When accepted, the database transaction atomically creates/updates:

- immutable/sanitized `payment_external_events` evidence;
- payment intent/attempt -> `SETTLEMENT_PENDING`;
- POS `SALE_ISSUE` inventory movement;
- posted sale journal using provider clearing rather than cash/bank;
- payment allocation to the sale;
- authoritative non-cash POS receipt;
- sale -> `COMPLETED`;
- audit evidence.

No POS cash movement is created for QRIS/BANK_TRANSFER.

## Settlement reconciliation contract

Provider settlement ingestion calls:

`reconcile_pos_provider_settlement(...)`

This RPC is also service-role only. Each settlement item must provide provider reference, gross amount, fee amount, and net amount. `gross - fee = net` is mandatory.

Every settlement item must match a `SETTLEMENT_PENDING` internal payment by provider, provider reference, amount, and currency. Any mismatch makes the batch `EXCEPTION`; the settlement journal is not posted and the internal payment remains pending.

When every item matches, the settlement journal posts:

- debit bank for net settlement;
- debit payment-provider fee expense when applicable;
- credit QRIS and/or BANK_TRANSFER clearing for gross settled value.

Only after this journal succeeds do the payment attempt and intent move to `SETTLED` and the batch become `RECONCILED`.

## Required accounting mappings

The provider-confirmed sale event `POS_PROVIDER_SALE_POST` requires:

- `qris_clearing_account_code`;
- `bank_transfer_clearing_account_code`;
- `sales_revenue_account_code`;
- `inventory_account_code`;
- `cogs_account_code`;
- `tax_payable_account_code` when tax is non-zero.

The settlement event `POS_PROVIDER_SETTLEMENT_POST` requires:

- `bank_account_code`;
- `qris_clearing_account_code`;
- `bank_transfer_clearing_account_code`;
- `payment_fee_account_code` when provider fees are non-zero.

These mappings are intentionally not created as real operational mappings by the foundation migration. They depend on the approved cooperative chart of accounts and provider commercial terms.

## Provider activation boundary

Real QRIS/BANK_TRANSFER activation requires a separate explicit decision because it may introduce credentials, contractual terms, MDR/fees, callback endpoints, IP allowlists, signing keys, or paid provider services.

Before activation, require all of the following:

- selected authorized provider/bank;
- confirmed zero-cost vs paid commercial terms;
- sandbox/DEVELOPMENT credentials stored outside public database/source control;
- provider-specific signature verification adapter;
- callback/retry/idempotency rules documented from official provider specifications;
- approved provider clearing/bank/fee accounting mappings;
- successful sandbox end-to-end test and settlement reconciliation;
- explicit production authorization before any production credential or endpoint is configured.

Until those conditions are met, QRIS and Transfer remain disabled in the cashier UI even though the provider-neutral database foundation exists.
