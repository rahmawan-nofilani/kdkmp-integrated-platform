import { redirect } from "next/navigation";
import { requireAccessContext } from "./access-context";
import type { PermissionCode } from "./permission-codes";

export async function hasPermission(permission: PermissionCode) {
  const { permissionCodes } = await requireAccessContext();
  return permissionCodes.includes(permission);
}

export async function requirePermission(permission: PermissionCode) {
  const allowed = await hasPermission(permission);

  if (!allowed) {
    redirect(`/forbidden?permission=${encodeURIComponent(permission)}`);
  }
}
