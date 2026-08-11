import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function AuditPage() {
  await requirePermission("AUDIT_VIEW");
  const { profile } = await requireAccessContext();
  const supabase = await createClient();
  const organizationId = profile.organization_id;

  const auditResult = organizationId
    ? await supabase
        .from("audit_logs")
        .select("id,actor_profile_id,action_code,entity_type,entity_id,reason,request_id,created_at")
        .eq("organization_id", organizationId)
        .order("created_at", { ascending: false })
        .limit(100)
    : { data: [], error: null };

  const entries = auditResult.data ?? [];

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Audit & Traceability</p>
          <h1>Audit Log</h1>
          <p>
            Viewer ini read-only dan hanya menampilkan audit aplikasi pada organisasi
            yang diizinkan oleh scope Anda. Histori audit tidak mempunyai tombol hapus.
          </p>
        </div>
        <span className="status-pill">READ ONLY</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Log Terlihat</div>
          <div className="metric-value">{entries.length}</div>
          <div className="metric-note">Maksimum 100 entry terbaru pada halaman ini.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Mode</div>
          <div className="metric-value metric-text">APPEND-ONLY</div>
          <div className="metric-note">Normal UI tidak menyediakan edit/delete histori.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Scope</div>
          <div className="metric-value metric-text">KDKMP</div>
          <div className="metric-note">RLS membatasi log ke organisasi user saat ini.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Authorization</div>
          <div className="metric-value metric-text">AUDIT_VIEW</div>
          <div className="metric-note">Halaman gagal tertutup bila permission tidak tersedia.</div>
        </article>
      </section>

      <section className="panel section-panel">
        <h3>Aktivitas Aplikasi Terbaru</h3>
        <p className="panel-subtitle">
          Auth login/logout juga memiliki audit bawaan Supabase; tabel ini difokuskan pada event bisnis/kontrol aplikasi KDKMP.
        </p>
        {entries.length > 0 ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead>
                <tr><th>Waktu</th><th>Aksi</th><th>Entitas</th><th>Alasan/Keterangan</th><th>Actor</th></tr>
              </thead>
              <tbody>
                {entries.map((entry) => (
                  <tr key={entry.id}>
                    <td>{new Date(entry.created_at).toLocaleString("id-ID")}</td>
                    <td><strong>{entry.action_code}</strong></td>
                    <td>{entry.entity_type ?? "SYSTEM"}</td>
                    <td>{entry.reason ?? "—"}</td>
                    <td>{entry.actor_profile_id ? `${entry.actor_profile_id.slice(0, 8)}…` : "SYSTEM"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="empty-state">Belum ada audit event aplikasi yang terlihat pada scope ini.</div>
        )}
      </section>
    </>
  );
}
