import { NextRequest, NextResponse } from "next/server";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

const RUN_KEY = "QW22sU-sw86BF4erE3r_rWTreuZPEbzIMdXv9Hn9ALwlC33GIUpE79uk6G_XiyWc";
const DEVELOPMENT_PROJECT_REF = "qdxybbcksjivcidsupbd";
const DEVELOPMENT_ORG_CODE = "DEMO-KDKMP-DEV";
const OUTSIDE_SCOPE_ORG_ID = "11111111-1111-4111-8111-111111111111";
const ACTORS = [
  { email: "nofilanirahmawan+uat-sup@gmail.com", role: "SUPERVISOR" },
  { email: "nofilanirahmawan+uat-teller@gmail.com", role: "TELLER" },
] as const;

type RpcResult = { data: unknown; error: { message: string } | null };
type GenericRpc = (fn: string, args?: Record<string, unknown>) => Promise<RpcResult>;

function noStoreJson(body: unknown, status = 200) {
  return NextResponse.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}

function tokenHashFromActionLink(actionLink: string | null | undefined) {
  if (!actionLink) return null;
  const parsed = new URL(actionLink);
  return parsed.searchParams.get("token") ?? parsed.searchParams.get("token_hash");
}

function rpcOf(client: unknown): GenericRpc {
  const rpc = (client as { rpc: { bind: (value: unknown) => unknown } }).rpc;
  return rpc.bind(client) as GenericRpc;
}

export async function GET(request: NextRequest) {
  if (request.nextUrl.searchParams.get("key") !== RUN_KEY) {
    return noStoreJson({ error: "not-found" }, 404);
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!supabaseUrl || !publishableKey || !supabaseUrl.includes(DEVELOPMENT_PROJECT_REF)) {
    return noStoreJson({ error: "development-target-required" }, 500);
  }

  const admin = createAdminClient();
  const { data: organization, error: organizationError } = await admin
    .from("organizations")
    .select("id,code")
    .eq("code", DEVELOPMENT_ORG_CODE)
    .maybeSingle();
  if (organizationError || !organization) {
    return noStoreJson({ error: "development-organization-not-found" }, 500);
  }

  const { data: period, error: periodError } = await admin
    .from("accounting_periods")
    .select("id,status")
    .eq("organization_id", organization.id)
    .eq("start_date", "2026-08-01")
    .eq("end_date", "2026-08-31")
    .maybeSingle();
  if (periodError || !period) return noStoreJson({ error: "uat-period-not-found" }, 500);

  const { data: usersPage, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
  if (usersError) return noStoreJson({ error: "auth-user-lookup-failed" }, 500);

  const results: Array<Record<string, unknown>> = [];

  for (const actor of ACTORS) {
    const authUser = usersPage.users.find((user) => user.email?.toLowerCase() === actor.email);
    if (!authUser) return noStoreJson({ error: "actor-auth-user-not-found", email: actor.email }, 404);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id,organization_id,status")
      .eq("auth_user_id", authUser.id)
      .maybeSingle();
    if (profileError || !profile || profile.organization_id !== organization.id || profile.status !== "ACTIVE") {
      return noStoreJson({ error: "actor-profile-invalid", email: actor.email }, 403);
    }

    const now = new Date().toISOString();
    const { data: roleAssignments, error: roleError } = await admin
      .from("user_roles")
      .select("role_id")
      .eq("profile_id", profile.id)
      .lte("valid_from", now)
      .or(`valid_until.is.null,valid_until.gt.${now}`);
    if (roleError || !roleAssignments || roleAssignments.length !== 1) {
      return noStoreJson({ error: "actor-role-assignment-invalid", email: actor.email }, 403);
    }

    const { data: role, error: roleLookupError } = await admin
      .from("roles")
      .select("code")
      .eq("id", roleAssignments[0].role_id)
      .maybeSingle();
    if (roleLookupError || role?.code !== actor.role) {
      return noStoreJson({ error: "actor-role-invalid", email: actor.email, role: role?.code ?? null }, 403);
    }

    const { data: scopeAssignments, error: scopeAssignmentError } = await admin
      .from("user_scope_assignments")
      .select("data_scope_id")
      .eq("profile_id", profile.id)
      .lte("valid_from", now)
      .or(`valid_until.is.null,valid_until.gt.${now}`);
    if (scopeAssignmentError || !scopeAssignments || scopeAssignments.length !== 1) {
      return noStoreJson({ error: "actor-scope-assignment-invalid", email: actor.email }, 403);
    }

    const { data: scope, error: scopeError } = await admin
      .from("data_scopes")
      .select("id,organization_id,organization_node_id,scope_type,name")
      .eq("id", scopeAssignments[0].data_scope_id)
      .maybeSingle();
    if (scopeError || !scope || scope.organization_id !== organization.id || !scope.organization_node_id) {
      return noStoreJson({ error: "actor-scope-invalid", email: actor.email }, 403);
    }

    const { data: generated, error: generateError } = await admin.auth.admin.generateLink({
      type: "recovery",
      email: actor.email,
    });
    if (generateError) return noStoreJson({ error: "recovery-link-failed", email: actor.email }, 500);

    const tokenHash = tokenHashFromActionLink(generated.properties?.action_link);
    if (!tokenHash) return noStoreJson({ error: "recovery-token-missing", email: actor.email }, 500);

    const client = createSupabaseClient(supabaseUrl, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    });
    const { data: verified, error: verifyError } = await client.auth.verifyOtp({ token_hash: tokenHash, type: "recovery" });
    if (verifyError || !verified.session || !verified.user || verified.user.email?.toLowerCase() !== actor.email) {
      return noStoreJson({ error: "actor-session-verification-failed", email: actor.email }, 500);
    }

    const rpc = rpcOf(client);
    const accessContext = await rpc("get_my_access_context");
    const ownScope = await rpc("has_data_scope", {
      p_organization_id: organization.id,
      p_organization_node_id: scope.organization_node_id,
      p_organization_unit_id: null,
      p_owner_auth_user_id: null,
      p_assigned_profile_id: null,
    });
    const outsideScope = await rpc("has_data_scope", {
      p_organization_id: OUTSIDE_SCOPE_ORG_ID,
      p_organization_node_id: null,
      p_organization_unit_id: null,
      p_owner_auth_user_id: null,
      p_assigned_profile_id: null,
    });

    if (accessContext.error || ownScope.error || outsideScope.error || ownScope.data !== true || outsideScope.data !== false) {
      await client.auth.signOut();
      return noStoreJson({
        error: "actor-scope-smoke-failed",
        email: actor.email,
        access_context_error: accessContext.error?.message ?? null,
        own_scope: ownScope.data,
        outside_scope: outsideScope.data,
      }, 500);
    }

    let negativeWrite: Record<string, unknown>;
    if (actor.role === "SUPERVISOR") {
      const denied = await rpc("create_manual_journal_draft", {
        p_accounting_period_id: period.id,
        p_entry_date: "2026-08-19",
        p_description: "Release-1 Gate 1 negative write — SUPERVISOR must not create Accounting draft",
        p_lines: [],
        p_idempotency_key: "uat-g1-supervisor-negative-accounting-draft",
        p_source_reference: "UAT-G1-NEGATIVE",
      });
      const deniedCorrectly = Boolean(denied.error?.message.includes("ACCOUNTING_DRAFT_CREATE_DENIED"));
      if (!deniedCorrectly) {
        await client.auth.signOut();
        return noStoreJson({ error: "supervisor-negative-write-failed", detail: denied.error?.message ?? null }, 500);
      }
      negativeWrite = { action: "create_manual_journal_draft", denied: true, expected: "ACCOUNTING_DRAFT_CREATE_DENIED" };
    } else {
      const denied = await rpc("get_accounting_dashboard_snapshot");
      const deniedCorrectly = Boolean(denied.error?.message.includes("ACCOUNTING_VIEW_DENIED"));
      if (!deniedCorrectly) {
        await client.auth.signOut();
        return noStoreJson({ error: "teller-workspace-isolation-failed", detail: denied.error?.message ?? null }, 500);
      }
      negativeWrite = { action: "get_accounting_dashboard_snapshot", denied: true, expected: "ACCOUNTING_VIEW_DENIED" };
    }

    await client.auth.signOut();
    results.push({
      email: actor.email,
      role: actor.role,
      session: "verified",
      scope_type: scope.scope_type,
      scope_name: scope.name,
      own_scope_allowed: true,
      outside_scope_allowed: false,
      negative_write: negativeWrite,
    });
  }

  return noStoreJson({ status: "completed", environment: "development", actors: results });
}
