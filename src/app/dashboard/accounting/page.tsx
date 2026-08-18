import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { getAccountingDashboardSnapshot } from "@/lib/accounting/dashboard-snapshot";

export const dynamic = "force-dynamic";

export default async function AccountingPage() {
  await requirePermission("ACCOUNTING_VIEW");
  const { permissionCodes, supabase } = await requireAccessContext();
  const { data: snapshot, error: snapshotError } = await getAccountingDashboardSnapshot(supabase);
  if (snapshotError || !snapshot) {
    return <section className="panel"><h3>Data accounting belum dapat dimuat</h3><p className="panel-subtitle">Snapshot accounting gagal dibaca. Tidak ada fallback lintas-scope yang digunakan.</p></section>;
  }

  const { accounts, periods, journals, events, mappings, reconciliations, control_mappings: controlMappings } = snapshot;
  const postingAccounts = accounts.filter((account) => account.is_posting);
  const controlAccounts = accounts.filter((account) => account.is_control_account);
  const openPeriods = periods.filter((period) => period.status === "OPEN");
  const activeMappings = mappings.filter((mapping) => mapping.status === "ACTIVE");
  const canDraft = permissionCodes.includes("ACCOUNTING_DRAFT_CREATE");
  const canValidate = permissionCodes.includes("ACCOUNTING_VALIDATE");
  const canPost = permissionCodes.includes("ACCOUNTING_POST");
  const canManagePeriod = permissionCodes.includes("ACCOUNTING_PERIOD_MANAGE");
  const canReconcile = permissionCodes.includes("ACCOUNTING_RECONCILE");

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Finance & Accounting</p>
          <h1>Accounting Control Center</h1>
          <p>
            Fondasi General Ledger untuk KDKMP. COA saat ini masih DEMO, jurnal aplikasi belum dibuka untuk posting,
            dan semua transaksi Simpan Pinjam/Modal Keanggotaan tetap diblokir sampai event mapping, approval, serta reconciliation siap.
          </p>
        </div>
        <span className="status-pill">FOUNDATION</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">COA</div><div className="metric-value">{accounts.length}</div><div className="metric-note">{postingAccounts.length} posting account · {controlAccounts.length} control candidate.</div></article>
        <article className="metric-card"><div className="metric-label">Periode Open</div><div className="metric-value">{openPeriods.length}</div><div className="metric-note">Periode harus OPEN sebelum jurnal boleh diposting.</div></article>
        <article className="metric-card"><div className="metric-label">Event Mapping Aktif</div><div className="metric-value">{activeMappings.length}/{events.length}</div><div className="metric-note">Belum ada mapping aktif berarti transaksi domain belum boleh masuk GL.</div></article>
        <article className="metric-card"><div className="metric-label">Reconciliation</div><div className="metric-value">{reconciliations.length}</div><div className="metric-note">Run reconciliation akan muncul setelah subledger mulai terintegrasi.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row"><div><h3>Segregation of Duties</h3><p className="panel-subtitle">Permission efektif untuk akun Anda saat ini.</p></div></div>
          <div className="check-list">
            <div className="check-item"><span>Lihat Accounting</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Buat Draft Jurnal</span><span className={`check-state ${canDraft ? "" : "pending"}`}>{canDraft ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Validasi Jurnal</span><span className={`check-state ${canValidate ? "" : "pending"}`}>{canValidate ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Posting General Ledger</span><span className={`check-state ${canPost ? "" : "pending"}`}>{canPost ? "ALLOWED" : "BLOCKED"}</span></div>
            <div className="check-item"><span>Kelola Periode</span><span className={`check-state ${canManagePeriod ? "" : "pending"}`}>{canManagePeriod ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Reconciliation</span><span className={`check-state ${canReconcile ? "" : "pending"}`}>{canReconcile ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Kondisi minimum sebelum transaksi finansial dinyalakan.</p>
          <div className="check-list">
            <div className="check-item"><span>COA foundation</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Balanced journal invariant</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Posted journal immutable</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Accounting event mapping</span><span className="check-state pending">PENDING</span></div>
            <div className="check-item"><span>Subledger control mapping</span><span className="check-state pending">{controlMappings.length > 0 ? "DRAFT" : "PENDING"}</span></div>
            <div className="check-item"><span>Posting role policy</span><span className="check-state pending">PENDING</span></div>
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Chart of Accounts — DEVELOPMENT</h3><p className="panel-subtitle">Struktur awal untuk menguji engine. Bukan COA final organisasi.</p></div></div>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Kode</th><th>Nama</th><th>Kelas</th><th>Normal</th><th>Posting</th><th>Control</th><th>Status</th></tr></thead>
            <tbody>{accounts.map((account) => <tr key={account.id}>
              <td>{account.code}</td><td><strong>{account.name}</strong>{account.control_purpose ? <small className="item-subtext">Control: {account.control_purpose}</small> : null}</td>
              <td>{account.account_class}</td><td>{account.normal_balance}</td><td>{account.is_posting ? "YA" : "HEADER"}</td>
              <td>{account.is_control_account ? "YA" : "—"}</td><td><span className="table-status">{account.status}</span></td>
            </tr>)}</tbody>
          </table>
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Accounting Period</h3>
          <p className="panel-subtitle">Period lock akan menjadi gate utama posting.</p>
          {periods.length ? <div className="check-list">{periods.map((period) => <div className="check-item" key={period.id}>
            <span>{period.period_name}<small className="item-subtext">{period.start_date} — {period.end_date}</small></span>
            <span className={`check-state ${period.status === "OPEN" ? "" : "pending"}`}>{period.status}</span>
          </div>)}</div> : <div className="empty-state">Belum ada periode yang terlihat pada scope ini.</div>}
        </article>

        <article className="panel">
          <h3>Accounting Events</h3>
          <p className="panel-subtitle">Definisi event ada, tetapi mapping debit/kredit belum diaktifkan.</p>
          <div className="check-list">{events.map((event) => {
            const mappingCount = mappings.filter((mapping) => mapping.event_definition_id === event.id && mapping.status === "ACTIVE").length;
            return <div className="check-item" key={event.id}><span>{event.name}<small className="item-subtext">{event.domain} · {event.event_code}</small></span><span className={`check-state ${mappingCount > 0 ? "" : "pending"}`}>{mappingCount > 0 ? "MAPPED" : "UNMAPPED"}</span></div>;
          })}</div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Journal Register</h3><p className="panel-subtitle">Belum ada tombol posting. Jurnal test invariant dijalankan dalam transaksi rollback sehingga tidak tersimpan.</p></div></div>
        {journals.length ? <div className="data-table-wrap"><table className="data-table"><thead><tr><th>No.</th><th>Tanggal</th><th>Deskripsi</th><th>Sumber</th><th>Status</th></tr></thead><tbody>{journals.map((journal) => <tr key={journal.id}><td>{journal.journal_number}</td><td>{journal.entry_date}</td><td>{journal.description}</td><td>{journal.source_domain}</td><td>{journal.status}</td></tr>)}</tbody></table></div> : <div className="empty-state">Belum ada jurnal tersimpan. Ini kondisi yang disengaja sampai write workflow disetujui.</div>}
      </section>
    </>
  );
}
