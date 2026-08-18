import { NextResponse } from "next/server";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  XENDIT_PROVIDER_CODE,
  XenditWebhookError,
  moneyToMinorUnits,
  parseXenditWebhook,
  verifyXenditCallbackToken,
} from "@/lib/payments/xendit";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const RETRYABLE_ATTEMPT_STATES = ["CREATED", "PENDING", "SETTLEMENT_PENDING", "SETTLED", "REFUNDED"];

function reply(status: number, code: string) {
  return NextResponse.json(
    { received: status >= 200 && status < 300, code },
    {
      status,
      headers: {
        "Cache-Control": "no-store",
        "X-Robots-Tag": "noindex, nofollow",
      },
    },
  );
}

export async function POST(request: Request) {
  const expectedToken = process.env.XENDIT_WEBHOOK_TOKEN;
  const expectedBusinessId = process.env.XENDIT_BUSINESS_ID;
  if (!expectedToken || !expectedBusinessId || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
    return reply(503, "PROVIDER_WEBHOOK_NOT_CONFIGURED");
  }

  if (!verifyXenditCallbackToken(request.headers.get("x-callback-token"), expectedToken)) {
    return reply(401, "PROVIDER_WEBHOOK_UNAUTHORIZED");
  }

  let parsed;
  try {
    parsed = parseXenditWebhook(await request.text());
  } catch (error) {
    if (error instanceof XenditWebhookError) return reply(400, error.code);
    return reply(400, "PROVIDER_WEBHOOK_INVALID");
  }

  if (parsed.kind === "ignored") return reply(202, "PROVIDER_EVENT_IGNORED");
  const capture = parsed.capture;

  if (capture.businessId !== expectedBusinessId) {
    return reply(401, "PROVIDER_BUSINESS_MISMATCH");
  }

  let db;
  try {
    db = createAdminClient();
  } catch {
    return reply(503, "PROVIDER_BACKEND_NOT_CONFIGURED");
  }

  const { data: attempts, error: attemptError } = await db
    .from("payment_attempts")
    .select("id,provider_config_id,channel,amount,currency,status,merchant_reference")
    .eq("merchant_reference", capture.merchantReference)
    .in("status", RETRYABLE_ATTEMPT_STATES)
    .limit(2);

  if (attemptError) return reply(503, "PROVIDER_ATTEMPT_LOOKUP_FAILED");
  if (!attempts || attempts.length === 0) return reply(409, "PROVIDER_ATTEMPT_NOT_READY");
  if (attempts.length !== 1) return reply(409, "PROVIDER_ATTEMPT_REFERENCE_AMBIGUOUS");

  const attempt = attempts[0];
  if (!attempt.provider_config_id) return reply(409, "PROVIDER_ATTEMPT_NOT_BOUND");
  if (attempt.channel !== capture.internalChannel || attempt.currency !== capture.currency) {
    return reply(409, "PROVIDER_ATTEMPT_CHANNEL_MISMATCH");
  }

  try {
    if (moneyToMinorUnits(attempt.amount) !== capture.amountMinorUnits) {
      return reply(409, "PROVIDER_ATTEMPT_AMOUNT_MISMATCH");
    }
  } catch {
    return reply(409, "PROVIDER_ATTEMPT_AMOUNT_INVALID");
  }

  const { data: provider, error: providerError } = await db
    .from("payment_provider_configs")
    .select("id,code,provider_type,supported_channels,config_status,status")
    .eq("id", attempt.provider_config_id)
    .maybeSingle();

  if (providerError) return reply(503, "PROVIDER_CONFIG_LOOKUP_FAILED");
  if (!provider || provider.code !== XENDIT_PROVIDER_CODE || provider.provider_type !== "PJP") {
    return reply(409, "PROVIDER_CONFIG_IDENTITY_MISMATCH");
  }

  const { data: existing, error: existingError } = await db
    .from("pos_provider_confirmation_commands")
    .select("payment_attempt_id,event_type,event_status,provider_reference,merchant_reference,amount,currency,payload_hash")
    .eq("provider_config_id", provider.id)
    .eq("external_event_id", capture.externalEventId)
    .maybeSingle();

  if (existingError) return reply(503, "PROVIDER_IDEMPOTENCY_LOOKUP_FAILED");
  if (existing) {
    let sameAmount = false;
    try {
      sameAmount = moneyToMinorUnits(existing.amount) === capture.amountMinorUnits;
    } catch {
      sameAmount = false;
    }
    const sameEvent =
      existing.payment_attempt_id === attempt.id &&
      existing.event_type === capture.eventType &&
      existing.event_status === "PAID" &&
      existing.provider_reference === capture.providerReference &&
      existing.merchant_reference === capture.merchantReference &&
      sameAmount &&
      existing.currency === capture.currency &&
      existing.payload_hash === capture.payloadHash;

    return sameEvent
      ? reply(200, "PROVIDER_EVENT_ALREADY_CONFIRMED")
      : reply(409, "PROVIDER_EVENT_IDEMPOTENCY_CONFLICT");
  }

  if (provider.status !== "ACTIVE" || provider.config_status !== "VALIDATED") {
    return reply(503, "PROVIDER_CONFIG_NOT_ACTIVE");
  }
  if (!Array.isArray(provider.supported_channels) || !provider.supported_channels.includes(capture.internalChannel)) {
    return reply(409, "PROVIDER_CHANNEL_NOT_ENABLED");
  }

  const { error: confirmationError } = await db.rpc("confirm_pos_provider_payment", {
    p_provider_config_id: provider.id,
    p_payment_attempt_id: attempt.id,
    p_external_event_id: capture.externalEventId,
    p_event_type: capture.eventType,
    p_provider_reference: capture.providerReference,
    p_merchant_reference: capture.merchantReference,
    p_amount: capture.amount,
    p_currency: capture.currency,
    p_payload_hash: capture.payloadHash,
    p_sanitized_metadata: capture.sanitizedMetadata,
  });

  if (confirmationError) {
    console.error("Xendit provider confirmation rejected", {
      code: confirmationError.code,
      message: confirmationError.message,
    });
    return reply(503, "PROVIDER_CONFIRMATION_REJECTED");
  }

  return reply(200, "PROVIDER_PAYMENT_CONFIRMED");
}
