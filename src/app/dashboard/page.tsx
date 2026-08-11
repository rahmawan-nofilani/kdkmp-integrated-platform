import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const { profile, supabase } = await requireAccessContext();
  const organizationId = profile.organization_id;

  const [
    organizationResult,
    unitsResult,
    activeUsersResult,
    pendingUsersResult,
    modulesResult,
    authorizationsResult,
    auditResult,
  ] = await Promise.all([
    organizationId
      ? supabase.from("organizations").select("id,code,name,status").eq("id", organizationId).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    organizationId
      ? supabase.from("organization_units").select("id,code,name,unit_type,status").eq("organization_id", organizationId).order("name")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("profiles").select("id", { count: "exact", head: true }).eq("organization_id", organizationId).eq("status", "ACTIVE")
      : Promise.resolve({ count: 0, error: null }),
    organizationId
      ? supabase.from("profiles").select("id", { count: "exact", head: true }).eq("organization_id", organizationId).eq("status", "PENDING")
      : Promise.resolve({ count: 0, error: null }),
    organizationId
      ? supabase.from("feature_modules").select("id,module_code,enabled,organization_unit_id").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("regulatory_authorizations").select("id,module_code,authorization_type,status,expiry_date").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("audit_logs").select("id,action_code,entity_type,reason,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(5)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const units = unitsResult.data ?? [];
  const modules = modulesResult.data ?? [];
  const authorizations = authorizationsResult.data ?? [];
  const recentAudit = auditResult.data ?? [];
  const enabledModules = modules.filter((module) => module.enabled);
  const pendingAuthorizations = authorizations.filter((authorization) =>
    ["DRAFT", "PENDING_VALIDATION"].includes(authorization.status),
  );

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Manager Command Center</p>
          <h1>{organizationResult.data?.name ?? "Dashboard KDKMP"}</h1>
          <p>
            Ringkasan ini berasal dari data DEVELOPMENT yang benar-benar tersimpan di database.
            KPI penjualan, stok, simpanan, dan pinjaman belum ditampilkan sampai transaction engine-nya aktif.
          </p>
        </div>
        <span className="status-pill">Development Active</span>
      </section>

      <section className="metric-grid" aria-label="Ringkasan organisasi">
        <article className="metric-card">
          <div className="metric-label">User Aktif</div>
          <div className="metric-value">{activeUsersResult.count ?? 0}</div>
          <div className="metric-note">Profile ACTIVE dalam scope organisasi Anda.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Unit Usaha</div>
          <div className="metric-value">{units.length}</div>
          <div className="metric-note">Unit yang lolos RLS dan data scope saat ini.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Modul Aktif</div>
          <div className="metric-value">{enabledModules.length}</div>
          <div className="metric-note">Feature module yang diaktifkan untuk environment ini.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Perlu Validasi</div>
          <div className="metric-value">{pendingAuthorizations.length}</div>
          <div className="metric-note">Authorization/regulasi masih DRAFT atau PENDING_VALIDATION.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Operational Readiness</h3>
              <p className="panel-subtitle">Status fondasi yang sudah berjalan secara nyata.</p>
            </div>
            <Link className="text-link" href="/dashboard/organization" prefetch>Lihat organisasi</Link>
          </div>
          <div className="check-list">
            <div className="check-item"><span>Authentication & session</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Manager role & permission engine</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Data scope & tenant isolation</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Organization & unit scoped reads</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Active user</span><span className="check-state">{activeUsersResult.count ?? 0}</span></div>
            <div className="check-item"><span>Pending user</span><span className={`check-state ${(pendingUsersResult.count ?? 0) > 0 ? "pending" : ""}`}>{pendingUsersResult.count ?? 0}</span></div>
          </div>
        </article>

        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Actions Required</h3>
              <p className="panel-subtitle">Hal yang belum boleh dianggap selesai.</p>
            </div>
          </div>
          {pendingAuthorizations.length > 0 ? (
            <div className="check-list">
              {pendingAuthorizations.map((authorization) => (
                <div className="check-item" key={authorization.id}>
                  <span>{authorization.module_code} · {authorization.authorization_type}</span>
                  <span className="check-state pending">{authorization.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada authorization yang menunggu validasi pada scope ini.</div>
          )}
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Unit dalam Scope</h3>
              <p className="panel-subtitle">Data ini bukan daftar hardcoded dari UI.</p>
            </div>
          </div>
          <div className="check-list">
            {units.map((unit) => (
              <div className="check-item" key={unit.id}>
                <span>{unit.name}<small className="item-subtext">{unit.unit_type} · {unit.code}</small></span>
                <span className={`check-state ${unit.status === "ACTIVE" ? "" : "pending"}`}>{unit.status}</span>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Audit Terbaru</h3>
              <p className="panel-subtitle">Aktivitas aplikasi yang tercatat pada audit foundation.</p>
            </div>
            <Link className="text-link" href="/dashboard/audit" prefetch>Lihat audit</Link>
          </div>
          {recentAudit.length > 0 ? (
            <div className="check-list">
              {recentAudit.map((entry) => (
                <div className="check-item" key={entry.id}>
                  <span>{entry.action_code}<small className="item-subtext">{entry.entity_type ?? "SYSTEM"} · {new Date(entry.created_at).toLocaleString("id-ID")}</small></span>
                  <span className="check-state">LOG</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada activity log aplikasi yang terlihat pada scope ini.</div>
          )}
        </article>
      </section>
    </>
  );
}
