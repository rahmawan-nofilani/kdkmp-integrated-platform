import { hasPermission, requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import {
  archiveOperationalUserAction,
  assignOperationalRoleAction,
  assignOperationalScopeAction,
  bootstrapFirstBoardUatAction,
  inviteOperationalUserAction,
  suspendOperationalUserAction,
  updateOperationalUserAction,
} from "./actions";

export const dynamic = "force-dynamic";

const allowedRoleCodes = new Set(["CASHIER", "TELLER", "FINANCE_OFFICER", "SUPERVISOR"]);

const successMessages: Record<string, string> = {
  "user-invited": "Undangan user berhasil dikirim dan profile operasional diprovision secara terkontrol.",
  "user-updated": "Data user berhasil diperbarui.",
  "user-suspended": "User berhasil disuspend. Role dan scope aktif ditutup.",
  "user-archived": "User nonaktif berhasil diarsipkan tanpa menghapus histori.",
  "role-assigned": "Role operasional berhasil diperbarui.",
  "scope-assigned": "Data scope berhasil diperbarui di dalam scope Manager.",
  "first-board-created": "First BOARD DEVELOPMENT/UAT berhasil dibuat melalui bootstrap satu-kali.",
};

const errorMessages: Record<string, string> = {
  "actor-scope": "Manager tidak memiliki organisasi aktif untuk administrasi akses.",
  "invalid-invite": "Data undangan belum lengkap atau role tidak diizinkan.",
  "invalid-update": "Data pembaruan user belum lengkap.",
  "invalid-suspend": "Alasan suspend wajib diisi.",
  "invalid-archive": "Alasan archive wajib diisi.",
  "invalid-role": "Role yang dipilih tidak dapat diberikan oleh Manager.",
  "invalid-scope": "Scope atau alasan belum lengkap.",
  "invalid-board-bootstrap": "Data first BOARD bootstrap belum lengkap.",
  "invite-failed": "Undangan Auth gagal dikirim. Tidak ada akses baru yang diaktifkan.",
  "command-failed": "Perintah administrasi akses ditolak atau gagal. Detail teknis tidak ditampilkan.",
  "self-admin-denied": "Manager tidak boleh mengadministrasikan dirinya sendiri.",
  "protected-role-denied": "Akun yang pernah memegang MANAGER/BOARD dilindungi dari command administrasi umum.",
  "role-not-assignable": "Manager hanya boleh memberi CASHIER, TELLER, FINANCE_OFFICER, atau SUPERVISOR.",
  "scope-escalation-denied": "Scope target berada di luar scope efektif Manager.",
  "cross-organization-denied": "Administrasi lintas organisasi ditolak.",
  "suspend-before-archive-required": "User ACTIVE harus disuspend lebih dulu sebelum diarsipkan.",
  "target-not-active": "Operasi tersebut hanya berlaku untuk user ACTIVE.",
  "archived-immutable": "User yang sudah ARCHIVED tidak dapat diubah melalui command operasional.",
  "first-board-bootstrap-already-used": "Bootstrap first BOARD sudah pernah digunakan dan tidak dapat diulang untuk user lain.",
  "active-board-already-exists": "BOARD aktif sudah tersedia; bootstrap khusus tidak diperlukan.",
  "uat-development-only": "Bootstrap first BOARD hanya diizinkan pada organisasi DEVELOPMENT.",
  "idempotency-conflict": "Idempotency key bertabrakan dengan request berbeda.",
};

export default async function AccessManagementPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  await requirePermission("USER_VIEW");
  const { profile: currentProfile, supabase } = await requireAccessContext();
  const params = await searchParams;
  const now = new Date().toISOString();
  const organizationId = currentProfile.organization_id;

  const [
    rolesResult,
    permissionsResult,
    profilesResult,
    userRolesResult,
    scopeAssignmentsResult,
    capabilities,
  ] = await Promise.all([
    supabase.from("roles").select("id,code,name,status").order("name"),
    supabase.from("permissions").select("id,code,domain,is_privileged").order("domain").order("code"),
    organizationId
      ? supabase
          .from("profiles")
          .select("id,full_name,phone,status,created_at,updated_at")
          .eq("organization_id", organizationId)
          .order("created_at")
      : Promise.resolve({ data: [], error: null }),
    supabase
      .from("user_roles")
      .select("id,profile_id,valid_from,valid_until,roles(id,code,name,status)")
      .lte("valid_from", now)
      .or(`valid_until.is.null,valid_until.gt.${now}`),
    supabase
      .from("user_scope_assignments")
      .select("id,profile_id,valid_from,valid_until,data_scopes(id,name,scope_type,organization_id,organization_node_id,organization_unit_id)")
      .lte("valid_from", now)
      .or(`valid_until.is.null,valid_until.gt.${now}`),
    Promise.all([
      hasPermission("USER_CREATE"),
      hasPermission("USER_UPDATE"),
      hasPermission("USER_SUSPEND"),
      hasPermission("USER_ARCHIVE"),
      hasPermission("ROLE_ASSIGN"),
      hasPermission("PERMISSION_GRANT"),
      hasPermission("SCOPE_ASSIGN"),
    ]),
  ]);

  const [canCreateUser, canUpdateUser, canSuspendUser, canArchiveUser, canAssignRole, canGrantPermission, canAssignScope] = capabilities;
  const profiles = profilesResult.data ?? [];
  const activeRoles = userRolesResult.data ?? [];
  const activeScopes = scopeAssignmentsResult.data ?? [];
  const activeUserCount = profiles.filter((profile) => profile.status === "ACTIVE").length;
  const pendingUserCount = profiles.filter((profile) => profile.status === "PENDING").length;
  const allowedRoles = (rolesResult.data ?? []).filter((role) => role.status === "ACTIVE" && allowedRoleCodes.has(role.code));
  const managerScopes = activeScopes
    .filter((assignment) => assignment.profile_id === currentProfile.id)
    .map((assignment) => assignment.data_scopes)
    .filter(Boolean);
  const activeBoardCount = profiles.filter((profile) =>
    profile.status === "ACTIVE" && activeRoles.some((assignment) => assignment.profile_id === profile.id && assignment.roles?.code === "BOARD"),
  ).length;
  const canProvision = canCreateUser && canAssignRole && canAssignScope && managerScopes.length > 0 && allowedRoles.length > 0;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Identity & Access</p>
          <h1>User & Akses</h1>
          <p>
            Manager dapat mengundang dan mengelola user operasional hanya di organisasi/scope sendiri. Role MANAGER dan BOARD tidak tersedia pada command umum; first BOARD DEVELOPMENT/UAT memakai bootstrap satu-kali yang terpisah.
          </p>
        </div>
        <span className="status-pill">CONTROLLED ACCESS</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success && successMessages[params.success] ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>{successMessages[params.success]}</div> : null}

      <section className="metric-grid" aria-label="Kesiapan pengelolaan akses">
        <article className="metric-card"><div className="metric-label">User Aktif</div><div className="metric-value">{activeUserCount}</div><div className="metric-note">Profile ACTIVE pada organisasi yang boleh Anda lihat.</div></article>
        <article className="metric-card"><div className="metric-label">User Pending</div><div className="metric-value">{pendingUserCount}</div><div className="metric-note">Belum memiliki akses operasional aktif.</div></article>
        <article className="metric-card"><div className="metric-label">BOARD Aktif</div><div className="metric-value">{activeBoardCount}</div><div className="metric-note">First BOARD bootstrap hanya tersedia bila angka ini masih 0.</div></article>
        <article className="metric-card"><div className="metric-label">Permission Catalog</div><div className="metric-value">{permissionsResult.data?.length ?? 0}</div><div className="metric-note">Direct permission grant tetap tidak diaktifkan.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Kewenangan Administrasi</h3>
          <p className="panel-subtitle">Dihitung dari compact access context session saat ini.</p>
          <div className="check-list">
            <div className="check-item"><span>Create operational user</span><span className={`check-state ${canCreateUser ? "" : "pending"}`}>{canCreateUser ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Update / suspend / archive</span><span className={`check-state ${canUpdateUser && canSuspendUser && canArchiveUser ? "" : "pending"}`}>{canUpdateUser && canSuspendUser && canArchiveUser ? "ALLOW" : "PARTIAL / DENY"}</span></div>
            <div className="check-item"><span>Assign operational role</span><span className={`check-state ${canAssignRole ? "" : "pending"}`}>{canAssignRole ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Assign own data scope</span><span className={`check-state ${canAssignScope ? "" : "pending"}`}>{canAssignScope ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Grant direct permission</span><span className={`check-state ${canGrantPermission ? "pending" : ""}`}>{canGrantPermission ? "UNEXPECTED" : "BLOCKED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Allowed Role Boundary</h3>
          <p className="panel-subtitle">Role yang dapat diberikan Manager melalui command umum.</p>
          <div className="check-list">
            {allowedRoles.map((role) => <div className="check-item" key={role.id}><span>{role.name}</span><span className="check-state">{role.code}</span></div>)}
            <div className="check-item"><span>MANAGER / BOARD</span><span className="check-state pending">PROTECTED</span></div>
          </div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Undang User Operasional</h3>
          <p className="panel-subtitle">Auth invite dijalankan hanya dari trusted server. User langsung diprovision ke satu role operasional dan satu scope yang berada di bawah Manager.</p>
          {canProvision ? (
            <form action={inviteOperationalUserAction} className="form-stack">
              <input type="hidden" name="idempotency_key" value={`access-invite-${crypto.randomUUID()}`} />
              <div className="field"><label htmlFor="invite-email">Email</label><input id="invite-email" name="email" type="email" required autoComplete="off" /></div>
              <div className="field"><label htmlFor="invite-name">Nama lengkap</label><input id="invite-name" name="full_name" required maxLength={160} /></div>
              <div className="field"><label htmlFor="invite-phone">Telepon</label><input id="invite-phone" name="phone" maxLength={40} /></div>
              <div className="field"><label htmlFor="invite-role">Role operasional</label><select id="invite-role" name="role_code" required defaultValue=""><option value="" disabled>Pilih role</option>{allowedRoles.map((role) => <option key={role.id} value={role.code}>{role.name} · {role.code}</option>)}</select></div>
              <div className="field"><label htmlFor="invite-scope">Data scope</label><select id="invite-scope" name="data_scope_id" required defaultValue=""><option value="" disabled>Pilih scope</option>{managerScopes.map((scope) => <option key={scope!.id} value={scope!.id}>{scope!.name} · {scope!.scope_type}</option>)}</select></div>
              <div className="field"><label htmlFor="invite-reason">Alasan / catatan onboarding</label><input id="invite-reason" name="reason" required maxLength={500} /></div>
              <button className="primary-button" type="submit">Kirim Undangan &amp; Provision</button>
            </form>
          ) : <div className="empty-state">Permission provisioning atau scope Manager belum lengkap.</div>}
        </article>

        <article className="panel">
          <h3>First BOARD · DEVELOPMENT/UAT</h3>
          <p className="panel-subtitle">Jalur khusus satu-kali. Setelah BOARD pertama tercatat, form ini tidak lagi menjadi jalur governance normal.</p>
          {activeBoardCount === 0 && canCreateUser && canAssignRole && canAssignScope && managerScopes.length ? (
            <form action={bootstrapFirstBoardUatAction} className="form-stack">
              <input type="hidden" name="idempotency_key" value={`access-board-${crypto.randomUUID()}`} />
              <div className="field"><label htmlFor="board-email">Email BOARD UAT</label><input id="board-email" name="email" type="email" required autoComplete="off" /></div>
              <div className="field"><label htmlFor="board-name">Nama lengkap</label><input id="board-name" name="full_name" required maxLength={160} /></div>
              <div className="field"><label htmlFor="board-phone">Telepon</label><input id="board-phone" name="phone" maxLength={40} /></div>
              <div className="field"><label htmlFor="board-scope">Data scope</label><select id="board-scope" name="data_scope_id" required defaultValue=""><option value="" disabled>Pilih scope</option>{managerScopes.map((scope) => <option key={scope!.id} value={scope!.id}>{scope!.name} · {scope!.scope_type}</option>)}</select></div>
              <div className="field"><label htmlFor="board-reason">Alasan bootstrap</label><input id="board-reason" name="reason" required maxLength={500} defaultValue="Release-1 DEVELOPMENT UAT first BOARD bootstrap" /></div>
              <button className="primary-button" type="submit">Bootstrap First BOARD UAT</button>
            </form>
          ) : <div className="empty-state">Bootstrap tidak tersedia: BOARD aktif sudah ada atau permission/scope belum memenuhi gate.</div>}
        </article>
      </section>

      <section className="panel section-panel">
        <h3>User dalam Scope Organisasi</h3>
        <p className="panel-subtitle">Email/password Auth tidak ditampilkan. Akun MANAGER/BOARD dilindungi dari kontrol operasional umum.</p>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>User</th><th>Status</th><th>Role Aktif</th><th>Data Scope</th><th>Kontrol</th></tr></thead>
            <tbody>
              {profiles.map((profile) => {
                const profileRoles = activeRoles.filter((assignment) => assignment.profile_id === profile.id);
                const profileScopes = activeScopes.filter((assignment) => assignment.profile_id === profile.id);
                const roleCodes = profileRoles.map((assignment) => assignment.roles?.code).filter(Boolean);
                const protectedUser = roleCodes.includes("MANAGER") || roleCodes.includes("BOARD");
                const isSelf = profile.id === currentProfile.id;
                const manageable = !protectedUser && !isSelf;
                return (
                  <tr key={profile.id}>
                    <td><strong>{profile.full_name?.trim() || "Pengguna KDKMP"}</strong><small className="item-subtext">ID {profile.id.slice(0, 8)}… · {profile.phone || "tanpa telepon"}</small></td>
                    <td><span className={`table-badge ${profile.status === "ACTIVE" ? "success" : "warning"}`}>{profile.status}</span></td>
                    <td>{profileRoles.map((assignment) => assignment.roles?.name ?? assignment.roles?.code).filter(Boolean).join(", ") || "—"}</td>
                    <td>{profileScopes.map((assignment) => assignment.data_scopes?.name ?? assignment.data_scopes?.scope_type).filter(Boolean).join(", ") || "—"}</td>
                    <td>
                      {!manageable ? <span className="check-state pending">{isSelf ? "SELF PROTECTED" : "GOVERNANCE PROTECTED"}</span> : (
                        <details>
                          <summary className="text-link" style={{ cursor: "pointer" }}>Kelola</summary>
                          <div className="form-stack" style={{ marginTop: 12, minWidth: 280 }}>
                            {canUpdateUser && profile.status !== "ARCHIVED" ? <form action={updateOperationalUserAction} className="form-stack"><input type="hidden" name="profile_id" value={profile.id} /><input type="hidden" name="idempotency_key" value={`access-update-${profile.id}-${crypto.randomUUID()}`} /><input name="full_name" required maxLength={160} defaultValue={profile.full_name ?? ""} placeholder="Nama lengkap" /><input name="phone" maxLength={40} defaultValue={profile.phone ?? ""} placeholder="Telepon" /><input name="reason" required maxLength={500} placeholder="Alasan perubahan" /><button className="secondary-button" type="submit">Update User</button></form> : null}
                            {canAssignRole && profile.status === "ACTIVE" ? <form action={assignOperationalRoleAction} className="form-stack"><input type="hidden" name="profile_id" value={profile.id} /><input type="hidden" name="idempotency_key" value={`access-role-${profile.id}-${crypto.randomUUID()}`} /><select name="role_code" required defaultValue=""><option value="" disabled>Pilih role baru</option>{allowedRoles.map((role) => <option key={role.id} value={role.code}>{role.name}</option>)}</select><input name="reason" required maxLength={500} placeholder="Alasan perubahan role" /><button className="secondary-button" type="submit">Assign Role</button></form> : null}
                            {canAssignScope && profile.status === "ACTIVE" && managerScopes.length ? <form action={assignOperationalScopeAction} className="form-stack"><input type="hidden" name="profile_id" value={profile.id} /><input type="hidden" name="idempotency_key" value={`access-scope-${profile.id}-${crypto.randomUUID()}`} /><select name="data_scope_id" required defaultValue=""><option value="" disabled>Pilih scope baru</option>{managerScopes.map((scope) => <option key={scope!.id} value={scope!.id}>{scope!.name}</option>)}</select><input name="reason" required maxLength={500} placeholder="Alasan perubahan scope" /><button className="secondary-button" type="submit">Assign Scope</button></form> : null}
                            {canSuspendUser && profile.status === "ACTIVE" ? <form action={suspendOperationalUserAction} className="form-stack"><input type="hidden" name="profile_id" value={profile.id} /><input type="hidden" name="idempotency_key" value={`access-suspend-${profile.id}-${crypto.randomUUID()}`} /><input name="reason" required maxLength={500} placeholder="Alasan suspend" /><button className="secondary-button" type="submit">Suspend User</button></form> : null}
                            {canArchiveUser && profile.status !== "ACTIVE" && profile.status !== "ARCHIVED" ? <form action={archiveOperationalUserAction} className="form-stack"><input type="hidden" name="profile_id" value={profile.id} /><input type="hidden" name="idempotency_key" value={`access-archive-${profile.id}-${crypto.randomUUID()}`} /><input name="reason" required maxLength={500} placeholder="Alasan archive" /><button className="secondary-button" type="submit">Archive User</button></form> : null}
                          </div>
                        </details>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    </>
  );
}
