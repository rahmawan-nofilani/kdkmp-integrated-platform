import { createHash, timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const EXPECTED_TOKEN_SHA256 = "57e0855326000a77d1bf61d49d34519012feaff71712b0e79982362443e4adca";
const DEVELOPMENT_PROJECT_REF = "qdxybbcksjivcidsupbd";

const UAT_IDENTITIES = [
  { email: "nofilanirahmawan+uat-board@gmail.com", fullName: "UAT BOARD" },
  { email: "nofilanirahmawan+uat-sup@gmail.com", fullName: "UAT SUPERVISOR" },
  { email: "nofilanirahmawan+uat-teller@gmail.com", fullName: "UAT TELLER" },
  { email: "nofilanirahmawan+uat-fin@gmail.com", fullName: "UAT FINANCE" },
] as const;

function isAuthorized(request: NextRequest) {
  const supplied = request.nextUrl.searchParams.get("token") ?? "";
  if (!supplied) return false;

  const suppliedHash = createHash("sha256").update(supplied).digest();
  const expectedHash = Buffer.from(EXPECTED_TOKEN_SHA256, "hex");
  return suppliedHash.length === expectedHash.length && timingSafeEqual(suppliedHash, expectedHash);
}

export async function GET(request: NextRequest) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
  if (!supabaseUrl.includes(DEVELOPMENT_PROJECT_REF)) {
    return NextResponse.json({ error: "DEVELOPMENT_ONLY" }, { status: 403 });
  }

  if (!isAuthorized(request)) {
    return NextResponse.json({ error: "NOT_FOUND" }, { status: 404 });
  }

  const admin = createAdminClient();
  const { data: listed, error: listError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (listError) {
    return NextResponse.json({ error: "AUTH_LIST_FAILED", detail: listError.message }, { status: 500 });
  }

  const existingByEmail = new Map(
    listed.users
      .filter((user) => user.email)
      .map((user) => [user.email!.toLowerCase(), user]),
  );

  const results: Array<{ email: string; userId: string; action: string }> = [];

  for (const spec of UAT_IDENTITIES) {
    const existing = existingByEmail.get(spec.email.toLowerCase());
    if (existing) {
      if (!existing.email_confirmed_at) {
        const { error: confirmError } = await admin.auth.admin.updateUserById(existing.id, {
          email_confirm: true,
          user_metadata: {
            ...(existing.user_metadata ?? {}),
            full_name: spec.fullName,
          },
        });
        if (confirmError) {
          return NextResponse.json(
            { error: "AUTH_CONFIRM_FAILED", email: spec.email, detail: confirmError.message },
            { status: 500 },
          );
        }
        results.push({ email: spec.email, userId: existing.id, action: "confirmed-existing" });
      } else {
        results.push({ email: spec.email, userId: existing.id, action: "already-confirmed" });
      }
      continue;
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email: spec.email,
      email_confirm: true,
      user_metadata: { full_name: spec.fullName },
    });
    if (createError || !created.user) {
      return NextResponse.json(
        { error: "AUTH_CREATE_FAILED", email: spec.email, detail: createError?.message ?? "missing user" },
        { status: 500 },
      );
    }

    results.push({ email: spec.email, userId: created.user.id, action: "created-confirmed" });
  }

  return NextResponse.json(
    { status: "ok", environment: "DEVELOPMENT", results },
    {
      headers: {
        "Cache-Control": "no-store",
        "X-Robots-Tag": "noindex, nofollow",
      },
    },
  );
}
