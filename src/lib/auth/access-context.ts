import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export async function requireAccessContext() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();
  const subject = data?.claims?.sub;

  if (error || !subject) {
    redirect("/login");
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("id,full_name,status,organization_id")
    .eq("auth_user_id", subject)
    .maybeSingle();

  if (!profile || profile.status !== "ACTIVE") {
    redirect("/access-pending");
  }

  const { data: assignments } = await supabase
    .from("user_roles")
    .select("role_id,valid_from,valid_until")
    .eq("profile_id", profile.id);

  const now = Date.now();
  const activeAssignments = (assignments ?? []).filter((assignment) => {
    const validFrom = Date.parse(assignment.valid_from);
    const validUntil = assignment.valid_until ? Date.parse(assignment.valid_until) : null;
    return validFrom <= now && (validUntil === null || validUntil > now);
  });

  if (activeAssignments.length === 0) {
    redirect("/access-pending");
  }

  const roleIds = [...new Set(activeAssignments.map((assignment) => assignment.role_id))];
  const { data: roles } = await supabase
    .from("roles")
    .select("id,code,name,is_privileged")
    .in("id", roleIds);

  if (!roles || roles.length === 0) {
    redirect("/access-pending");
  }

  const claims = data.claims as Record<string, unknown>;
  const email = typeof claims.email === "string" ? claims.email : "Akun KDKMP";

  return {
    supabase,
    subject,
    email,
    profile,
    roles,
  };
}
