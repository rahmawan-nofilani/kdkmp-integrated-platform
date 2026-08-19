import { NextResponse } from "next/server";
import { getEnvironmentTargetGuard } from "@/lib/environment";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabaseUrlConfigured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const supabaseKeyConfigured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);

  let environment: "development" | "staging" | "production";
  let expectedTargetConfigured = false;
  let targetMatches = false;

  try {
    const targetGuard = getEnvironmentTargetGuard();
    environment = targetGuard.environment;
    expectedTargetConfigured = targetGuard.expectedTargetConfigured;
    targetMatches = targetGuard.targetMatches;
  } catch {
    return NextResponse.json(
      {
        status: "misconfigured",
        application: "KDKMP Integrated Management Platform",
        environment: "invalid",
        supabase: {
          urlConfigured: supabaseUrlConfigured,
          publishableKeyConfigured: supabaseKeyConfigured,
          expectedTargetConfigured: false,
          targetMatches: false,
          ready: false,
        },
        timestamp: new Date().toISOString(),
      },
      {
        status: 503,
        headers: {
          "Cache-Control": "no-store",
          "X-Robots-Tag": "noindex, nofollow",
        },
      },
    );
  }

  const ready =
    supabaseUrlConfigured &&
    supabaseKeyConfigured &&
    targetMatches &&
    (environment === "development" || expectedTargetConfigured);

  return NextResponse.json(
    {
      status: ready ? "ok" : "misconfigured",
      application: "KDKMP Integrated Management Platform",
      environment,
      supabase: {
        urlConfigured: supabaseUrlConfigured,
        publishableKeyConfigured: supabaseKeyConfigured,
        expectedTargetConfigured,
        targetMatches,
        ready,
      },
      timestamp: new Date().toISOString(),
    },
    {
      status: ready ? 200 : 503,
      headers: {
        "Cache-Control": "no-store",
        "X-Robots-Tag": "noindex, nofollow",
      },
    },
  );
}
