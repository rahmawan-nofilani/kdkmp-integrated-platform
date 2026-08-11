import { hasPermission, requirePermission } from "@/lib/auth/permissions";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AccessManagementPage() {
  await requirePermission("USER_VIEW");

  const supabase = await createClient();
  const now = new Date().toISOString();

  const [rolesResult, permissionsResult, scopeAssignmentsResult, capabilities] = await Promise.all([
    supabase.from("roles").select("id,code,name,status").order("name"),
    supabase.from("permissions").select("id,code,domain,is_privileged").order("domain").order("code"),
    supabase
      .from("user_scope_assignments")
      .select("id,valid_from,valid_until,data_scopes(id,name,scope_type,organization_id,organization_node_id,organization_unit_id)")
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
  const activeScopes = scopeAssignmentsResult.data ?? [];

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Identity & Access</p>
          <h1>User & Akses</h1>
          <p>
            Halaman ini diproteksi oleh permission engine dan menampilkan data scope
            aktif milik user yang sedang login. Provisioning user ditambahkan setelah
            bootstrap Manager pertama.
          </p>
        </div>
      </section>

      <section className="metric-grid" aria-label="Kesiapan pengelolaan akses">
        <article className="metric-card">
          <div className="metric-label">Role</div>
          <div className="metric-value">{rolesResult.data?.length ?? 0}</div>
          <div className="metric-note">Role aktif/inaktif yang terdaftar di katalog.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Permission</div>
          <div className="metric-value">{permissionsResult.data?.length ?? 0}</div>
          <div className="metric-note">Permission granular yang dikenal sistem.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Data Scope Aktif</div>
          <div className="metric-value">{activeScopes.length}</div>
          <div className="metric-note">Scope aktif yang dapat digunakan untuk membatasi data.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Buat User</div>
          <div className="metric-value" style={{ fontSize: 22 }}>{canCreateUser ? "ALLOW" : "DENY"}</div>
          <div className="metric-note">Hasil langsung dari permission engine.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Kewenangan Administrasi Saat Ini</h3>
          <p className="panel-subtitle">Dihitung dari role + override user yang masih berlaku.</p>
          <div className="check-list">
            <div className="check-item"><span>Create operational user</span><span className={`check-state ${canCreateUser ? "" : "pending"}`}>{canCreateUser ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Assign role</span><span className={`check-state ${canAssignRole ? "" : "pending"}`}>{canAssignRole ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Grant direct permission</span><span className={`check-state ${canGrantPermission ? "" : "pending"}`}>{canGrantPermission ? "ALLOW" : "DENY"}</span></div>
            <div className="check-item"><span>Assign data scope</span><span className={`check-state ${canAssignScope ? "" : "pending"}`}>{canAssignScope ? "ALLOW" : "DENY"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Scope yang Sedang Berlaku</h3>
          <p className="panel-subtitle">Permission menentukan tindakan; scope menentukan batas datanya.</p>
          {activeScopes.length === 0 ? (
            <div className="empty-state">
              Belum ada data scope aktif. User tanpa scope tidak boleh diasumsikan memiliki akses ke seluruh data organisasi.
            </div>
          ) : (
            <div className="check-list">
              {activeScopes.map((assignment) => (
                <div className="check-item" key={assignment.id}>
                  <span>{assignment.data_scopes?.name ?? "Scope"}</span>
                  <span className="check-state">{assignment.data_scopes?.scope_type ?? "ACTIVE"}</span>
                </div>
              ))}
            </div>
          )}
        </article>
      </section>
    </>
  );
}
