import { requireAccessContext } from "@/lib/auth/access-context";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function OrganizationPage() {
  const { profile } = await requireAccessContext();
  const supabase = await createClient();
  const organizationId = profile.organization_id;

  const [organizationResult, nodesResult, unitsResult, modulesResult, authorizationsResult] = await Promise.all([
    organizationId
      ? supabase.from("organizations").select("id,code,name,status,created_at").eq("id", organizationId).maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    organizationId
      ? supabase.from("organization_nodes").select("id,parent_id,node_type,code,name,status").eq("organization_id", organizationId).order("created_at")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("organization_units").select("id,code,name,unit_type,status,organization_node_id").eq("organization_id", organizationId).order("name")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("feature_modules").select("id,module_code,enabled,organization_unit_id").eq("organization_id", organizationId).order("module_code")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("regulatory_authorizations").select("id,module_code,authorization_type,authorization_number,issuing_authority,effective_date,expiry_date,status,organization_unit_id").eq("organization_id", organizationId).order("module_code")
      : Promise.resolve({ data: [], error: null }),
  ]);

  const organization = organizationResult.data;
  const nodes = nodesResult.data ?? [];
  const units = unitsResult.data ?? [];
  const modules = modulesResult.data ?? [];
  const authorizations = authorizationsResult.data ?? [];

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Organization & Scope</p>
          <h1>Organisasi & Unit Usaha</h1>
          <p>
            Hanya struktur yang diperbolehkan oleh tenant dan data scope user yang sedang login yang dapat dibaca di halaman ini.
          </p>
        </div>
        <span className="status-pill">{organization?.status ?? "NO ORG"}</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Kode Organisasi</div>
          <div className="metric-value metric-text">{organization?.code ?? "—"}</div>
          <div className="metric-note">Identifier tenant DEVELOPMENT.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Node Hierarki</div>
          <div className="metric-value">{nodes.length}</div>
          <div className="metric-note">Jalur organisasi yang dapat dibaca user.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Unit Usaha</div>
          <div className="metric-value">{units.length}</div>
          <div className="metric-note">Unit yang berada dalam data scope aktif.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Module Enabled</div>
          <div className="metric-value">{modules.filter((module) => module.enabled).length}</div>
          <div className="metric-note">Feature flag bukan bukti izin regulasi.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Hierarki Organisasi</h3>
          <p className="panel-subtitle">Path organisasi dari struktur DEVELOPMENT.</p>
          <div className="check-list">
            {nodes.map((node) => (
              <div className="check-item" key={node.id}>
                <span>{node.name}<small className="item-subtext">{node.node_type} · {node.code}</small></span>
                <span className={`check-state ${node.status === "ACTIVE" ? "" : "pending"}`}>{node.status}</span>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <h3>Kontrol Modul</h3>
          <p className="panel-subtitle">Enabled dan authorized adalah dua hal yang berbeda.</p>
          {modules.length > 0 ? (
            <div className="check-list">
              {modules.map((module) => (
                <div className="check-item" key={module.id}>
                  <span>{module.module_code}</span>
                  <span className={`check-state ${module.enabled ? "" : "pending"}`}>{module.enabled ? "ENABLED" : "DISABLED"}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada feature module yang dikonfigurasi pada scope ini.</div>
          )}
        </article>
      </section>

      <section className="panel section-panel">
        <h3>Unit Usaha dalam Scope</h3>
        <p className="panel-subtitle">Daftar ini dibaca dari database dan dipotong oleh RLS.</p>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Unit</th><th>Kode</th><th>Tipe</th><th>Status</th><th>Modul</th></tr></thead>
            <tbody>
              {units.map((unit) => {
                const unitModules = modules.filter((module) => module.organization_unit_id === unit.id && module.enabled);
                return (
                  <tr key={unit.id}>
                    <td><strong>{unit.name}</strong></td>
                    <td>{unit.code}</td>
                    <td>{unit.unit_type}</td>
                    <td><span className={`table-badge ${unit.status === "ACTIVE" ? "success" : "warning"}`}>{unit.status}</span></td>
                    <td>{unitModules.map((module) => module.module_code).join(", ") || "—"}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <section className="panel section-panel">
        <h3>Regulatory / Authorization Status</h3>
        <p className="panel-subtitle">Masih DRAFT/PENDING sampai dokumen resmi dimasukkan dan diverifikasi.</p>
        {authorizations.length > 0 ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead><tr><th>Modul</th><th>Jenis</th><th>Nomor</th><th>Otoritas</th><th>Status</th></tr></thead>
              <tbody>
                {authorizations.map((authorization) => (
                  <tr key={authorization.id}>
                    <td><strong>{authorization.module_code}</strong></td>
                    <td>{authorization.authorization_type}</td>
                    <td>{authorization.authorization_number ?? "—"}</td>
                    <td>{authorization.issuing_authority ?? "Belum ditetapkan"}</td>
                    <td><span className={`table-badge ${authorization.status === "ACTIVE" ? "success" : "warning"}`}>{authorization.status}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty-state">Belum ada regulatory authorization yang dapat dibaca pada scope ini.</div>
        )}
      </section>
    </>
  );
}
