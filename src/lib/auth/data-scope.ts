import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type DataScopeTarget = {
  organizationId?: string;
  organizationNodeId?: string;
  organizationUnitId?: string;
  ownerAuthUserId?: string;
  assignedProfileId?: string;
};

export async function hasDataScope(target: DataScopeTarget) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("has_data_scope", {
    p_organization_id: target.organizationId,
    p_organization_node_id: target.organizationNodeId,
    p_organization_unit_id: target.organizationUnitId,
    p_owner_auth_user_id: target.ownerAuthUserId,
    p_assigned_profile_id: target.assignedProfileId,
  });

  if (error) {
    return false;
  }

  return data === true;
}

export async function requireDataScope(target: DataScopeTarget) {
  const allowed = await hasDataScope(target);

  if (!allowed) {
    redirect("/forbidden?reason=data-scope");
  }
}
