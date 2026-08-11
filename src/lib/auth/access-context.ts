import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type AccessRole = {
  id: string;
  code: string;
  name: string;
  is_privileged: boolean;
};

export type AccessScope = {
  id: string;
  name: string;
  scope_type: string;
  organization_id: string | null;
  organization_node_id: string | null;
  organization_unit_id: string | null;
};

type AccessContextRow = {
  profile_id: string;
  full_name: string | null;
  profile_status: string;
  organization_id: string | null;
  roles: unknown;
  permission_codes: string[];
  scopes: unknown;
};

type RpcResult = {
  data: AccessContextRow[] | null;
  error: { message: string } | null;
};

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export const requireAccessContext = cache(async function requireAccessContext() {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
  const subject = claimsData?.claims?.sub;

  if (claimsError || !subject) {
    redirect("/login");
  }

  // The generated database type is refreshed on schema milestones. Keep this
  // narrow cast local so the rest of the application remains fully typed.
  const rpc = supabase.rpc as unknown as (
    fn: "get_my_access_context",
  ) => Promise<RpcResult>;
  const { data, error } = await rpc("get_my_access_context");
  const context = data?.[0];

  if (error || !context || context.profile_status !== "ACTIVE") {
    redirect("/access-pending");
  }

  const roles = asArray<AccessRole>(context.roles);

  if (roles.length === 0) {
    redirect("/access-pending");
  }

  const claims = claimsData.claims as Record<string, unknown>;
  const email = typeof claims.email === "string" ? claims.email : "Akun KDKMP";

  return {
    supabase,
    subject,
    email,
    profile: {
      id: context.profile_id,
      full_name: context.full_name,
      status: context.profile_status,
      organization_id: context.organization_id,
    },
    roles,
    permissionCodes: context.permission_codes ?? [],
    scopes: asArray<AccessScope>(context.scopes),
  };
});
