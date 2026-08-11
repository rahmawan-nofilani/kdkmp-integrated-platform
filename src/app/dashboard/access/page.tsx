import { hasPermission, requirePermission } from "@/lib/auth/permissions";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AccessManagementPage() {
  await requirePermission("USER_VIEW");

  const supabase = await createClient();
  const [rolesResult, permissionsResult, capabilities] = await Promise.all([
    supabase.from("roles").select("id,code,name,status").order("name"),
    supabase.from("permissions").select("id,code,domain,is_privileged").order("domain").order("code"),
    Promise.all([
      hasPermission("USER_CREATE"),
      hasPermission("ROLE_ASSIGN"),
      hasPermission("PERMISSION_GRANT"),
      hasPermission("SCOPE_ASSIGN"),
    ]),
  ]);

  const [canCreateUser, canAssignRole, canGrantPermission, canAssignScope] = capabilities;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Identity & Access</p>
          <h1>User & Akses</h1>
          <p>
            Halaman ini sudah diproteksi oleh permission engine database. Fitur
            provisioning user akan ditambahkan setelah bootstrap Manager pertama.
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
          <div className="metric-label">Buat User</div>
          <div className="metric-value" style={{ fontSize: 22 }}>{canCreateUser ? "ALLOW" : "DENY"}</div>
          <div className="metric-note">Hasil langsung dari permission engine.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Grant Permission</div>
          <div className="metric-value" style={{ fontSize: 22 }}>{canGrantPermission ? "ALLOW" : "DENY"}</div>
          <div className="metric-note">Tidak otomatis diberikan kepada Manager.</div>
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
          <h3>Prinsip Keamanan</h3>
          <p className="panel-subtitle">Tombol/menu tidak pernah menjadi satu-satunya kontrol.</p>
          <div className="empty-state">
            Permission engine menggunakan urutan: explicit DENY aktif → explicit ALLOW aktif → role permission aktif. Profil harus ACTIVE dan assignment role harus masih berlaku. Data scope akan menjadi lapisan pemeriksaan berikutnya untuk menentukan data mana yang boleh disentuh.
          </div>
        </article>
      </section>
    </>
  );
}
