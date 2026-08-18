import { createHash, timingSafeEqual } from "node:crypto";

export const XENDIT_PROVIDER_CODE = "XENDIT-PAYMENTS-V3" as const;
export const XENDIT_WEBHOOK_EVENT = "payment.capture" as const;
export const XENDIT_WEBHOOK_API_VERSION = "v3" as const;
export const XENDIT_HTTP_API_VERSION = "2024-11-11" as const;
export const XENDIT_MAX_WEBHOOK_BYTES = 512 * 1024;

export type XenditInternalChannel = "QRIS" | "BANK_TRANSFER";
export type XenditSupportedChannelCode = "QRIS" | "BRI_VIRTUAL_ACCOUNT";

type JsonObject = Record<string, unknown>;

export type TrustedXenditCapture = {
  businessId: string;
  externalEventId: string;
  eventType: "XENDIT_PAYMENT_CAPTURE";
  providerReference: string;
  merchantReference: string;
  paymentRequestId: string;
  channelCode: XenditSupportedChannelCode;
  internalChannel: XenditInternalChannel;
  amount: number;
  amountMinorUnits: number;
  currency: "IDR";
  payloadHash: string;
  sanitizedMetadata: {
    provider: "XENDIT";
    api_version: "v3";
    event: "payment.capture";
    payment_id: string;
    payment_request_id: string;
    channel_code: XenditSupportedChannelCode;
    capture_ids: string[];
    provider_created_at: string | null;
    provider_updated_at: string | null;
  };
};

export type XenditWebhookParseResult =
  | { kind: "ignored"; event: string }
  | { kind: "capture"; capture: TrustedXenditCapture };

export class XenditWebhookError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "XenditWebhookError";
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(source: JsonObject, key: string, maxLength = 255) {
  const value = source[key];
  if (typeof value !== "string") {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", `${key} must be a string`);
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > maxLength) {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", `${key} is invalid`);
  }
  return normalized;
}

function optionalTimestamp(source: JsonObject, key: string) {
  const value = source[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", `${key} must be an ISO timestamp`);
  }
  return value;
}

export function moneyToMinorUnits(value: unknown) {
  const numeric = typeof value === "number" ? value : typeof value === "string" ? Number(value) : Number.NaN;
  if (!Number.isFinite(numeric) || numeric <= 0 || numeric > 999_999_999_999) {
    throw new XenditWebhookError("XENDIT_AMOUNT_INVALID", "amount is outside the accepted range");
  }

  const scaled = numeric * 100;
  const rounded = Math.round(scaled);
  if (!Number.isSafeInteger(rounded) || Math.abs(scaled - rounded) > 0.000001) {
    throw new XenditWebhookError("XENDIT_AMOUNT_INVALID", "amount supports at most two decimal places");
  }
  return rounded;
}

export function verifyXenditCallbackToken(receivedToken: string | null, expectedToken: string | undefined) {
  if (!receivedToken || !expectedToken) return false;
  const receivedDigest = createHash("sha256").update(receivedToken, "utf8").digest();
  const expectedDigest = createHash("sha256").update(expectedToken, "utf8").digest();
  return timingSafeEqual(receivedDigest, expectedDigest);
}

function mapChannel(channelCode: string): {
  channelCode: XenditSupportedChannelCode;
  internalChannel: XenditInternalChannel;
} {
  if (channelCode === "QRIS") return { channelCode, internalChannel: "QRIS" };
  if (channelCode === "BRI_VIRTUAL_ACCOUNT") {
    return { channelCode, internalChannel: "BANK_TRANSFER" };
  }
  throw new XenditWebhookError("XENDIT_CHANNEL_UNSUPPORTED", `unsupported channel ${channelCode}`);
}

export function parseXenditWebhook(rawBody: string): XenditWebhookParseResult {
  if (Buffer.byteLength(rawBody, "utf8") > XENDIT_MAX_WEBHOOK_BYTES) {
    throw new XenditWebhookError("XENDIT_WEBHOOK_TOO_LARGE", "webhook body exceeds the maximum size");
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", "webhook body is not valid JSON");
  }
  if (!isObject(payload)) {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", "webhook payload must be an object");
  }

  const event = requiredString(payload, "event", 100);
  if (event !== XENDIT_WEBHOOK_EVENT) return { kind: "ignored", event };

  if (payload.api_version !== XENDIT_WEBHOOK_API_VERSION) {
    throw new XenditWebhookError("XENDIT_API_VERSION_UNSUPPORTED", "payment webhook must use api_version v3");
  }

  const businessId = requiredString(payload, "business_id", 100);
  if (!isObject(payload.data)) {
    throw new XenditWebhookError("XENDIT_PAYLOAD_INVALID", "payment webhook data must be an object");
  }
  const data = payload.data;

  if (data.status !== "SUCCEEDED") {
    throw new XenditWebhookError("XENDIT_PAYMENT_NOT_SUCCEEDED", "payment.capture must be SUCCEEDED");
  }
  if (data.country !== "ID" || data.currency !== "IDR") {
    throw new XenditWebhookError("XENDIT_MARKET_UNSUPPORTED", "only ID/IDR provider payments are accepted");
  }

  const paymentId = requiredString(data, "payment_id", 100);
  const paymentRequestId = requiredString(data, "payment_request_id", 100);
  const merchantReference = requiredString(data, "reference_id", 255);
  const mappedChannel = mapChannel(requiredString(data, "channel_code", 100));
  const amountMinorUnits = moneyToMinorUnits(data.request_amount);

  if (!Array.isArray(data.captures) || data.captures.length === 0 || data.captures.length > 10) {
    throw new XenditWebhookError("XENDIT_CAPTURE_INVALID", "payment.capture must contain capture evidence");
  }

  const captureIds: string[] = [];
  let capturedMinorUnits = 0;
  for (const item of data.captures) {
    if (!isObject(item)) {
      throw new XenditWebhookError("XENDIT_CAPTURE_INVALID", "capture item must be an object");
    }
    captureIds.push(requiredString(item, "capture_id", 100));
    capturedMinorUnits += moneyToMinorUnits(item.capture_amount);
  }
  if (new Set(captureIds).size !== captureIds.length) {
    throw new XenditWebhookError("XENDIT_CAPTURE_INVALID", "capture ids must be unique");
  }
  if (capturedMinorUnits !== amountMinorUnits) {
    throw new XenditWebhookError("XENDIT_CAPTURE_AMOUNT_MISMATCH", "captured amount does not match request amount");
  }

  const rawAmount = typeof data.request_amount === "number" ? data.request_amount : Number(data.request_amount);
  const payloadHash = createHash("sha256").update(rawBody, "utf8").digest("hex");

  return {
    kind: "capture",
    capture: {
      businessId,
      externalEventId: `xendit:payment.capture:${paymentId}`,
      eventType: "XENDIT_PAYMENT_CAPTURE",
      providerReference: paymentId,
      merchantReference,
      paymentRequestId,
      channelCode: mappedChannel.channelCode,
      internalChannel: mappedChannel.internalChannel,
      amount: rawAmount,
      amountMinorUnits,
      currency: "IDR",
      payloadHash,
      sanitizedMetadata: {
        provider: "XENDIT",
        api_version: "v3",
        event: "payment.capture",
        payment_id: paymentId,
        payment_request_id: paymentRequestId,
        channel_code: mappedChannel.channelCode,
        capture_ids: captureIds,
        provider_created_at: optionalTimestamp(data, "created") ?? optionalTimestamp(payload, "created"),
        provider_updated_at: optionalTimestamp(data, "updated"),
      },
    },
  };
}
