import { hasPermission, requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";

export const dynamic = "force-dynamic";

export default async function AccessManagementPage() {
  await requirePermission("USER_VIEW");
  const { profile: currentProfile, supabase } = await requireAccessContext();

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
      hasPermission("ROLE_ASSIGN"),
      hasPermission("PERMISSION_GRANT"),
      hasPermission("SCOPE_ASSIGN"),
    ]),
  ]);

  const [canCreateUser, canAssignRole, canGrantPermission, canAssignScope] = capabilities;
  const profiles = profilesResult.data ?? [];
  const activeRoles = userRolesResult.data ?? [];
  const activeScopes = scopeAssignmentsResult.data ?? [];
  const activeUserCount = profiles.filter((profile) => profile.status === "ACTIVE").length;
  const pendingUserCount = profiles.filter((profile) => profile.status === "PENDING").length;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Identity & Access</p>
          <h1>User & Akses</h1>
          <p>
            Daftar user, role, dan scope di bawah dibatasi oleh permission `USER_VIEW`
            dan organisasi user yang sedang login. Pembuatan user dari aplikasi belum
            diaktifkan sampai channel email/SMTP DEVELOPMENT disiapkan dengan benar.
          </p>
        </div>
      </section>

      <section className="metric-grid" aria-label="Kesiapan pengelolaan akses">
        <article className="metric-card">
          <div className="metric-label">User Aktif</div>
          <div className="metric-value">{activeUserCount}</div>
          <div className="metric-note">Profile ACTIVE pada organisasi yang boleh Anda lihat.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">User Pending</div>
          <div className="metric-value">{pendingUserCount}</div>
          <div className="metric-note">Belum boleh mengakses aplikasi sampai provisioning selesai.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Role Catalog</div>
          <div className="metric-value">{rolesResult.data?.length ?? 0}</div>
          <div className="metric-note">Role dasar pada Identity & Access.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Permission Catalog</div>
          <div className="metric-value">{permissionsResult.data?.length ?? 0}</div>
          <div className="metric-note">Permission granular yang dikenal policy engine.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Kewenangan Administrasi Saat Ini</h3>
          <p className="panel-subtitle">Dihitung dari compact access context yang sama dengan session saat ini.</p>
          <div className="check-list">
            <div className="check-item"><span>Create operational user</span><span className={`check-state ${canCreateUser ? "" : "pending"}`}>{canCreateUser ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Assign role</span><span className={`check-state ${canAssignRole ? "" : "pending"}`}>{canAssignRole ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Grant direct permission</span><span className={`check-state ${canGrantPermission ? "" : "pending"}`}>{canGrantPermission ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Assign data scope</span><span className={`check-state ${canAssignScope ? "" : "pending"}`}>{canAssignScope ? "ALLOW" : "DENY"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>User Provisioning</h3>
          <p className="panel-subtitle">Permission tersedia, tetapi channel onboarding belum dibuka.</p>
          <div className="empty-state">
            Tombol “Tambah User” sengaja belum diaktifkan. Kita tidak akan menghasilkan
            password sementara atau menyimpan secret di aplikasi. Setelah Custom SMTP
            DEVELOPMENT siap, Manager dapat membuat user dari sini dan user akan membuat
            passwordnya sendiri melalui alur undangan terkontrol.
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <h3>User dalam Scope Organisasi</h3>
        <p className="panel-subtitle">Tidak ada email/password yang ditampilkan dari tabel Auth.</p>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead>
              <tr><th>User</th><th>Status</th><th>Role Aktif</th><th>Data Scope</th><th>Dibuat</th></tr>
            </thead>
            <tbody>
              {profiles.map((profile) => {
                const profileRoles = activeRoles.filter((assignment) => assignment.profile_id === profile.id);
                const profileScopes = activeScopes.filter((assignment) => assignment.profile_id === profile.id);
                return (
                  <tr key={profile.id}>
                    <td>
                      <strong>{profile.full_name?.trim() || "Pengguna KDKMP"}</strong>
                      <small className="item-subtext">ID {profile.id.slice(0, 8)}…</small>
                    </td>
                    <td><span className={`table-badge ${profile.status === "ACTIVE" ? "success" : "warning"}`}>{profile.status}</span></td>
                    <td>{profileRoles.map((assignment) => assignment.roles?.name ?? assignment.roles?.code).filter(Boolean).join(", ") || "—"}</td>
                    <td>{profileScopes.map((assignment) => assignment.data_scopes?.name ?? assignment.data_scopes?.scope_type).filter(Boolean).join(", ") || "—"}</td>
                    <td>{new Date(profile.created_at).toLocaleDateString("id-ID")}</td>
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
