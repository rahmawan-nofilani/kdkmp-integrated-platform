import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const supabase = await createClient();

  const [{ count: roleCount }, { count: permissionCount }] = await Promise.all([
    supabase.from("roles").select("id", { count: "exact", head: true }),
    supabase.from("permissions").select("id", { count: "exact", head: true }),
  ]);

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Phase 1 Foundation</p>
          <h1>Dashboard Sistem</h1>
          <p>
            Halaman ini menampilkan kesiapan fondasi aplikasi. KPI usaha belum
            ditampilkan karena transaksi bisnis belum diaktifkan.
          </p>
        </div>
        <span className="status-pill">Development Active</span>
      </section>

      <section className="metric-grid" aria-label="Status fondasi sistem">
        <article className="metric-card">
          <div className="metric-label">Role Terkonfigurasi</div>
          <div className="metric-value">{roleCount ?? "—"}</div>
          <div className="metric-note">Katalog role dasar pada Identity & Access.</div>
        </article>

        <article className="metric-card">
          <div className="metric-label">Permission Terkonfigurasi</div>
          <div className="metric-value">{permissionCount ?? "—"}</div>
          <div className="metric-note">Izin tindakan yang akan dipakai oleh policy engine.</div>
        </article>

        <article className="metric-card">
          <div className="metric-label">Environment</div>
          <div className="metric-value" style={{ fontSize: 22 }}>DEV</div>
          <div className="metric-note">Belum menggunakan data operasional KDKMP sebenarnya.</div>
        </article>

        <article className="metric-card">
          <div className="metric-label">Regulasi</div>
          <div className="metric-value" style={{ fontSize: 22 }}>DRAFT</div>
          <div className="metric-note">Pending legal/regulatory validation sesuai dokumen resmi.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Foundation Readiness</h3>
          <p className="panel-subtitle">Kontrol yang sudah tersedia di Phase 1.</p>
          <div className="check-list">
            <div className="check-item"><span>Supabase PostgreSQL foundation</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Authentication SSR & session refresh</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Role & permission catalog</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Data scope structure</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Audit log foundation</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>User provisioning & delegated access</span><span className="check-state pending">NEXT</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Data Usaha</h3>
          <p className="panel-subtitle">Belum ada angka bisnis palsu di dashboard.</p>
          <div className="empty-state">
            Penjualan, persediaan, arus kas, simpanan, pinjaman, tunggakan,
            distribusi, dan KPI baru akan muncul setelah masing-masing transaction
            engine aktif dan memiliki sumber data yang sah.
          </div>
        </article>
      </section>
    </>
  );
}
