import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabaseUrlConfigured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const supabaseKeyConfigured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);

  return NextResponse.json(
    {
      status: "ok",
      application: "KDKMP Integrated Management Platform",
      environment: "development",
      supabase: {
        urlConfigured: supabaseUrlConfigured,
        publishableKeyConfigured: supabaseKeyConfigured,
        ready: supabaseUrlConfigured && supabaseKeyConfigured,
      },
      timestamp: new Date().toISOString(),
    },
    {
      headers: {
        "Cache-Control": "no-store",
        "X-Robots-Tag": "noindex, nofollow",
      },
    },
  );
}
