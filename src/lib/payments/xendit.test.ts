import assert from "node:assert/strict";
import test from "node:test";
import {
  XenditWebhookError,
  parseXenditWebhook,
  verifyXenditCallbackToken,
} from "./xendit";

function capturePayload(overrides: Record<string, unknown> = {}) {
  return {
    event: "payment.capture",
    api_version: "v3",
    business_id: "business-kdkmp-dev",
    created: "2026-08-18T06:00:00.000Z",
    data: {
      type: "PAY",
      status: "SUCCEEDED",
      country: "ID",
      currency: "IDR",
      business_id: "business-kdkmp-dev",
      payment_id: "py-1402feb0-bb79-47ae-9d1e-e69394d3949c",
      payment_request_id: "pr-1102feb0-bb79-47ae-9d1e-e69394d3949c",
      reference_id: "POS-PAY-6dc650e0-f050-4af0-b44a-48d7aad0bf0a",
      channel_code: "QRIS",
      request_amount: 125000,
      captures: [
        {
          capture_id: "cptr-1502feb0-bb79-47ae-9d1e-e69394d3949c",
          capture_amount: 125000,
          capture_timestamp: "2026-08-18T06:00:01.000Z",
        },
      ],
      created: "2026-08-18T05:59:59.000Z",
      updated: "2026-08-18T06:00:01.000Z",
      ...overrides,
    },
  };
}

test("accepts a successful QRIS capture and emits sanitized provider evidence", () => {
  const raw = JSON.stringify(capturePayload());
  const result = parseXenditWebhook(raw);
  if (result.kind !== "capture") assert.fail("expected capture result");

  assert.equal(result.capture.internalChannel, "QRIS");
  assert.equal(result.capture.channelCode, "QRIS");
  assert.equal(result.capture.amountMinorUnits, 12_500_000);
  assert.equal(result.capture.currency, "IDR");
  assert.equal(
    result.capture.externalEventId,
    "xendit:payment.capture:py-1402feb0-bb79-47ae-9d1e-e69394d3949c",
  );
  assert.deepEqual(result.capture.sanitizedMetadata.capture_ids, [
    "cptr-1502feb0-bb79-47ae-9d1e-e69394d3949c",
  ]);
  assert.match(result.capture.payloadHash, /^[0-9a-f]{64}$/);
  assert.equal("payment_details" in result.capture.sanitizedMetadata, false);
});

test("maps BRI virtual account to internal BANK_TRANSFER", () => {
  const raw = JSON.stringify(capturePayload({ channel_code: "BRI_VIRTUAL_ACCOUNT" }));
  const result = parseXenditWebhook(raw);
  if (result.kind !== "capture") assert.fail("expected capture result");
  assert.equal(result.capture.internalChannel, "BANK_TRANSFER");
  assert.equal(result.capture.channelCode, "BRI_VIRTUAL_ACCOUNT");
});

test("ignores non-capture webhook events without finalizing payment", () => {
  const result = parseXenditWebhook(JSON.stringify({ event: "payment.failure" }));
  assert.deepEqual(result, { kind: "ignored", event: "payment.failure" });
});

test("rejects capture amount mismatch", () => {
  const raw = JSON.stringify(
    capturePayload({
      captures: [
        {
          capture_id: "cptr-1502feb0-bb79-47ae-9d1e-e69394d3949c",
          capture_amount: 124999,
        },
      ],
    }),
  );

  assert.throws(
    () => parseXenditWebhook(raw),
    (error: unknown) => error instanceof XenditWebhookError && error.code === "XENDIT_CAPTURE_AMOUNT_MISMATCH",
  );
});

test("rejects unsupported payment channels", () => {
  const raw = JSON.stringify(capturePayload({ channel_code: "OVO" }));
  assert.throws(
    () => parseXenditWebhook(raw),
    (error: unknown) => error instanceof XenditWebhookError && error.code === "XENDIT_CHANNEL_UNSUPPORTED",
  );
});

test("rejects reusable/static payment code confirmations for POS", () => {
  const raw = JSON.stringify(capturePayload({ type: "REUSABLE_PAYMENT_CODE" }));
  assert.throws(
    () => parseXenditWebhook(raw),
    (error: unknown) => error instanceof XenditWebhookError && error.code === "XENDIT_PAYMENT_TYPE_UNSUPPORTED",
  );
});

test("rejects disagreement between top-level and payment business id", () => {
  const raw = JSON.stringify(capturePayload({ business_id: "other-business" }));
  assert.throws(
    () => parseXenditWebhook(raw),
    (error: unknown) => error instanceof XenditWebhookError && error.code === "XENDIT_BUSINESS_MISMATCH",
  );
});

test("callback token comparison is fail-closed", () => {
  assert.equal(verifyXenditCallbackToken("token-1", "token-1"), true);
  assert.equal(verifyXenditCallbackToken("token-1", "token-2"), false);
  assert.equal(verifyXenditCallbackToken(null, "token-1"), false);
  assert.equal(verifyXenditCallbackToken("token-1", undefined), false);
});
