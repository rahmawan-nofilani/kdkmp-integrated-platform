# POS Xendit adapter foundation

Status: repository-only, fail-closed, not activated.

This slice binds the existing provider-neutral POS confirmation engine to the Xendit Payments API v3 webhook contract without adding provider credentials, activating a provider configuration, enabling QRIS/BANK_TRANSFER in the cashier UI, or changing production.

## Why Xendit is the first adapter target

The provider-neutral core remains authoritative. Xendit is only the first concrete adapter because its current public documentation exposes Payments API v3, a server-side payment webhook with `x-callback-token`, test-mode payment simulation, QRIS, BRI Virtual Account, and explicit onboarding requirements for Indonesian cooperatives.

Official references checked for this implementation:

- https://docs.xendit.co/apidocs/payment-webhook-notification
- https://docs.xendit.co/apidocs/create-payment-request
- https://docs.xendit.co/apidocs/simulate-payment-test-mode
- https://docs.xendit.co/docs/qris
- https://docs.xendit.co/docs/bri-virtual-account

Commercial pricing and MDR are intentionally not encoded in application logic or database migrations. Merchant classification and final fees must be confirmed during onboarding before activation.

## Implemented boundary

Webhook route:

`POST /api/payments/xendit/webhook`

The route is Node-runtime/server-only and remains unavailable until all of these server environment values exist:

- `SUPABASE_SERVICE_ROLE_KEY`
- `XENDIT_WEBHOOK_TOKEN`
- `XENDIT_BUSINESS_ID`

`NEXT_PUBLIC_SUPABASE_URL` remains the Supabase project URL already used by the application. No provider secret is exposed through a `NEXT_PUBLIC_*` variable.

The route does not require `XENDIT_SECRET_KEY` yet because this slice does not create a Xendit Payment Request. Provider payment initiation is the next credential-bound step.

## Accepted confirmation event

Only a Xendit Payments API v3 `payment.capture` event is eligible to reach the authoritative database confirmation RPC. It must satisfy all of the following:

1. `x-callback-token` matches the configured server-side webhook token using a constant-time digest comparison.
2. `api_version` is `v3`.
3. event status is `SUCCEEDED`.
4. country/currency are `ID` / `IDR`.
5. channel is currently allowlisted as either `QRIS` or `BRI_VIRTUAL_ACCOUNT`.
6. capture evidence exists and summed capture amount equals `request_amount` exactly.
7. webhook `business_id` equals the configured Xendit business id.
8. `reference_id` resolves to exactly one internal payment attempt.
9. internal attempt channel, amount, and currency match the provider event.
10. the attempt is bound to an internal provider config whose code is exactly `XENDIT-PAYMENTS-V3` and provider type is `PJP`.
11. for a new event, that config must be `ACTIVE`, `VALIDATED`, and enable the internal channel.
12. only then may the service-role client call `confirm_pos_provider_payment(...)`.

The webhook payload never supplies the authoritative internal `payment_attempt_id` or `provider_config_id`; both are resolved from KDKMP data using the merchant reference.

## Idempotency and evidence

The stable external event key is:

`xendit:payment.capture:<payment_id>`

The raw request body is SHA-256 hashed. Only sanitized provider metadata is sent to the provider-neutral command engine: payment id, payment-request id, channel code, capture ids, and provider timestamps. Raw payment details, payer information, callback token, and credentials are not persisted by the adapter.

Before invoking the confirmation RPC, the route checks `pos_provider_confirmation_commands`. An exact replay is acknowledged as already confirmed; the same event id with changed payment evidence is rejected as an idempotency conflict.

Non-capture webhook events are acknowledged as ignored and cannot finalize a payment.

## Provider code contract

Future DEVELOPMENT activation must create or promote a scoped provider configuration using:

`XENDIT-PAYMENTS-V3`

`payment_provider_configs` already scopes `code` uniqueness by organization node, so each node can have its own Xendit configuration without making the adapter trust a provider id supplied over the network.

No such active config is created by this slice.

## Still intentionally blocked

The following are outside this repository-only slice and must remain blocked until provider onboarding / credential / commercial approval:

- Xendit account activation and legal onboarding;
- test or live secret API key;
- webhook token and business id provisioning;
- Xendit Payment Request creation for QRIS or BRI VA;
- Vercel environment secret changes;
- provider configuration activation;
- provider-specific settlement report ingestion;
- approved clearing/bank/fee account mapping;
- final MDR / VA fee policy and merchant category confirmation;
- enabling QRIS or BANK_TRANSFER controls in the cashier UI;
- any production deployment or production provider credential.

The existing provider-neutral settlement engine remains the authoritative reconciliation target once a provider-specific settlement adapter is approved.

## Test coverage

`POS Xendit Adapter CI` performs application typecheck and focused runtime tests for:

- successful QRIS capture parsing;
- BRI Virtual Account -> internal BANK_TRANSFER mapping;
- non-capture events being ignored;
- capture/request amount mismatch rejection;
- unsupported channel rejection;
- fail-closed callback-token comparison.
