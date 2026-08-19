import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const RUN_KEY = "D6cq2n-XQFZUpW2TR9nMeJWCePLyLb7vQCvLQXr45rFsMHa1SWn-z7yl5wIPoBV1";
const DEVELOPMENT_PROJECT_REF = "qdxybbcksjivcidsupbd";
const DEVELOPMENT_ORG_CODE = "DEMO-KDKMP-DEV";
const MANAGER_EMAIL = "nofilanirahmawan@gmail.com";

function tokenHashFromActionLink(actionLink: string | null | undefined) {
  if (!actionLink) return null;
  const parsed = new URL(actionLink);
  return parsed.searchParams.get("token") ?? parsed.searchParams.get("token_hash");
}

export async function GET(request: NextRequest) {
  if (request.nextUrl.searchParams.get("key") !== RUN_KEY) {
    return NextResponse.json({ error: "not-found" }, { status: 404, headers: { "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow" } });
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!supabaseUrl || !publishableKey || !supabaseUrl.includes(DEVELOPMENT_PROJECT_REF)) {
    return NextResponse.json({ error: "development-target-required" }, { status: 500 });
  }

  const admin = createAdminClient();
  const { data: organization, error: organizationError } = await admin
    .from("organizations")
    .select("id,code")
    .eq("code", DEVELOPMENT_ORG_CODE)
    .maybeSingle();
  if (organizationError || !organization) {
    return NextResponse.json({ error: "development-org-not-found" }, { status: 500 });
  }

  const { data: usersPage, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersError) return NextResponse.json({ error: "manager-auth-lookup-failed" }, { status: 500 });
  const authUser = usersPage.users.find((user) => user.email?.toLowerCase() === MANAGER_EMAIL);
  if (!authUser) return NextResponse.json({ error: "manager-not-found" }, { status: 404 });

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id,organization_id,status")
    .eq("auth_user_id", authUser.id)
    .maybeSingle();
  if (profileError || !profile || profile.organization_id !== organization.id || profile.status !== "ACTIVE") {
    return NextResponse.json({ error: "manager-profile-invalid" }, { status: 403 });
  }

  const now = new Date().toISOString();
  const { data: assignments, error: assignmentError } = await admin
    .from("user_roles")
    .select("role_id")
    .eq("profile_id", profile.id)
    .lte("valid_from", now)
    .or(`valid_until.is.null,valid_until.gt.${now}`);
  if (assignmentError || !assignments || assignments.length !== 1) {
    return NextResponse.json({ error: "manager-role-assignment-invalid" }, { status: 403 });
  }
  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("code")
    .eq("id", assignments[0].role_id)
    .maybeSingle();
  if (roleError || role?.code !== "MANAGER") {
    return NextResponse.json({ error: "manager-role-invalid" }, { status: 403 });
  }

  const { data: generated, error: generateError } = await admin.auth.admin.generateLink({
    type: "recovery",
    email: MANAGER_EMAIL,
  });
  if (generateError) return NextResponse.json({ error: "recovery-generation-failed" }, { status: 500 });
  const tokenHash = tokenHashFromActionLink(generated.properties?.action_link);
  if (!tokenHash) return NextResponse.json({ error: "recovery-token-missing" }, { status: 500 });

  const redirectUrl = new URL("/dashboard", request.url);
  const response = NextResponse.redirect(redirectUrl);
  response.headers.set("Cache-Control", "no-store");
  response.headers.set("X-Robots-Tag", "noindex, nofollow");

  const supabase = createServerClient(supabaseUrl, publishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  const { data: verified, error: verifyError } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type: "recovery",
  });
  if (verifyError || !verified.user || verified.user.email?.toLowerCase() !== MANAGER_EMAIL || !verified.session) {
    return NextResponse.json({ error: "manager-session-verification-failed" }, { status: 500 });
  }

  return response;
}
