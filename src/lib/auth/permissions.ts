import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { PermissionCode } from "./permission-codes";

export async function hasPermission(permission: PermissionCode) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("has_permission", {
    p_permission_code: permission,
  });

  if (error) {
    return false;
  }

  return data === true;
}

export async function requirePermission(permission: PermissionCode) {
  const allowed = await hasPermission(permission);

  if (!allowed) {
    redirect(`/forbidden?permission=${encodeURIComponent(permission)}`);
  }
}
