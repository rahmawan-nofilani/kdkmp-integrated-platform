import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { getAccountingDashboardSnapshot } from "@/lib/accounting/dashboard-snapshot";
import { createManualJournalDraftAction, validateManualJournalAction } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "invalid-draft-input": "Data draft jurnal belum lengkap atau akun Debit dan Kredit sama.",
  "invalid-journal": "Jurnal yang dipilih tidak valid.",
  "period-access": "Periode accounting tidak dapat diakses pada scope Anda.",
  "period-closed": "Periode accounting tidak OPEN.",
  "date-outside-period": "Tanggal jurnal berada di luar periode accounting yang dipilih.",
  "scope-denied": "Data Scope tidak mengizinkan operasi accounting tersebut.",
  "not-balanced": "Jurnal tidak seimbang.",
  "account-invalid": "Akun jurnal tidak aktif, bukan posting account, atau berada di scope lain.",
  "lines-invalid": "Baris jurnal tidak valid.",
  "maker-checker": "Pembuat jurnal tidak boleh memvalidasi jurnalnya sendiri.",
  "not-draft": "Jurnal sudah bukan berstatus DRAFT.",
  idempotency: "Permintaan jurnal bertabrakan dengan idempotency key yang sudah ada.",
  system: "Perintah accounting gagal. Detail teknis tidak ditampilkan kepada pengguna.",
};

export default async function AccountingPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  await requirePermission("ACCOUNTING_VIEW");
  const { permissionCodes, supabase } = await requireAccessContext();
  const { data: snapshot, error: snapshotError } = await getAccountingDashboardSnapshot(supabase);
  const params = await searchParams;
  if (snapshotError || !snapshot) {
    return <section className="panel"><h3>Data accounting belum dapat dimuat</h3><p className="panel-subtitle">Snapshot accounting gagal dibaca. Tidak ada fallback lintas-scope yang digunakan.</p></section>;
  }

  const { accounts, periods, journals, events, mappings, reconciliations, control_mappings: controlMappings } = snapshot;
  const postingAccounts = accounts.filter((account) => account.is_posting && account.status === "ACTIVE");
  const controlAccounts = accounts.filter((account) => account.is_control_account);
  const openPeriods = periods.filter((period) => period.status === "OPEN");
  const activeMappings = mappings.filter((mapping) => mapping.status === "ACTIVE");
  const canDraft = permissionCodes.includes("ACCOUNTING_DRAFT_CREATE");
  const canValidate = permissionCodes.includes("ACCOUNTING_VALIDATE");
  const canPost = permissionCodes.includes("ACCOUNTING_POST");
  const canManagePeriod = permissionCodes.includes("ACCOUNTING_PERIOD_MANAGE");
  const canReconcile = permissionCodes.includes("ACCOUNTING_RECONCILE");
  const today = new Date().toISOString().slice(0, 10);
  const defaultPeriod = openPeriods.find((period) => period.start_date <= today && period.end_date >= today) ?? openPeriods[0];
  const defaultEntryDate = defaultPeriod && (today < defaultPeriod.start_date || today > defaultPeriod.end_date) ? defaultPeriod.start_date : today;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Finance & Accounting</p>
          <h1>Accounting Control Center</h1>
          <p>
            Manual journal DRAFT dan independent validation memakai command engine terkontrol. Posting General Ledger tetap dikunci sampai
            role `ACCOUNTING_POST` dan approval policy JOURNAL_POST disetujui secara terpisah.
          </p>
        </div>
        <span className="status-pill">CONTROLLED FOUNDATION</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success === "draft-created" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Draft jurnal berhasil dibuat. Jurnal belum masuk General Ledger dan harus divalidasi actor berbeda.</div> : null}
      {params.success === "validated" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Jurnal berhasil divalidasi. Posting tetap terkunci sampai SoD dan approval policy diaktifkan.</div> : null}

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">COA</div><div className="metric-value">{accounts.length}</div><div className="metric-note">{postingAccounts.length} posting account · {controlAccounts.length} control candidate.</div></article>
        <article className="metric-card"><div className="metric-label">Periode Open</div><div className="metric-value">{openPeriods.length}</div><div className="metric-note">Manual draft hanya dapat dibuat pada periode OPEN.</div></article>
        <article className="metric-card"><div className="metric-label">Event Mapping Aktif</div><div className="metric-value">{activeMappings.length}/{events.length}</div><div className="metric-note">Domain event tetap mengikuti mapping authoritative.</div></article>
        <article className="metric-card"><div className="metric-label">Reconciliation</div><div className="metric-value">{reconciliations.length}</div><div className="metric-note">Run reconciliation akan muncul setelah subledger mulai terintegrasi.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row"><div><h3>Segregation of Duties</h3><p className="panel-subtitle">Permission efektif untuk akun Anda saat ini.</p></div></div>
          <div className="check-list">
            <div className="check-item"><span>Lihat Accounting</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Buat Draft Jurnal</span><span className={`check-state ${canDraft ? "" : "pending"}`}>{canDraft ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Validasi Jurnal</span><span className={`check-state ${canValidate ? "" : "pending"}`}>{canValidate ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Posting General Ledger</span><span className={`check-state ${canPost ? "" : "pending"}`}>{canPost ? "PERMISSION PRESENT — APPROVAL STILL REQUIRED" : "LOCKED"}</span></div>
            <div className="check-item"><span>Kelola Periode</span><span className={`check-state ${canManagePeriod ? "" : "pending"}`}>{canManagePeriod ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Reconciliation</span><span className={`check-state ${canReconcile ? "" : "pending"}`}>{canReconcile ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Kondisi minimum sebelum posting manual dinyalakan.</p>
          <div className="check-list">
            <div className="check-item"><span>Balanced journal invariant</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Maker ≠ Checker</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>Maker ≠ Checker ≠ Poster</span><span className="check-state">ENGINE READY</span></div>
            <div className="check-item"><span>Posted journal immutable</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>JOURNAL_POST approval policy</span><span className="check-state pending">DRAFT / NOT ACTIVE</span></div>
            <div className="check-item"><span>Posting role policy</span><span className="check-state pending">NO BASELINE MAPPING</span></div>
          </div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Manual Journal Draft</h3>
          <p className="panel-subtitle">Form awal Release 1 membuat jurnal dua sisi yang seimbang. Editor multi-line tetap menjadi UX lanjutan.</p>
          {canDraft ? (
            openPeriods.length > 0 && postingAccounts.length >= 2 ? (
              <form action={createManualJournalDraftAction} className="form-stack">
                <div className="field">
                  <label htmlFor="accounting_period_id">Periode</label>
                  <select id="accounting_period_id" name="accounting_period_id" required defaultValue={defaultPeriod?.id}>
                    {openPeriods.map((period) => <option key={period.id} value={period.id}>{period.period_name} · {period.start_date}—{period.end_date}</option>)}
                  </select>
                </div>
                <div className="field"><label htmlFor="entry_date">Tanggal Jurnal</label><input id="entry_date" name="entry_date" type="date" required defaultValue={defaultEntryDate} /></div>
                <div className="field"><label htmlFor="description">Deskripsi</label><input id="description" name="description" required maxLength={500} placeholder="Contoh: Koreksi klasifikasi biaya operasional" /></div>
                <div className="field"><label htmlFor="source_reference">Referensi</label><input id="source_reference" name="source_reference" maxLength={160} placeholder="Opsional: dokumen / memo internal" /></div>
                <div className="field">
                  <label htmlFor="debit_account_id">Akun Debit</label>
                  <select id="debit_account_id" name="debit_account_id" required defaultValue="">
                    <option value="" disabled>Pilih posting account</option>
                    {postingAccounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}
                  </select>
                </div>
                <div className="field">
                  <label htmlFor="credit_account_id">Akun Kredit</label>
                  <select id="credit_account_id" name="credit_account_id" required defaultValue="">
                    <option value="" disabled>Pilih posting account</option>
                    {postingAccounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}
                  </select>
                </div>
                <div className="field"><label htmlFor="amount">Nominal</label><input id="amount" name="amount" type="number" min="0.01" step="0.01" required placeholder="0.00" /></div>
                <button className="primary-button" type="submit">Buat DRAFT Jurnal</button>
              </form>
            ) : <div className="empty-state">Periode OPEN atau posting account belum cukup untuk membuat manual journal.</div>
          ) : <div className="empty-state">Role Anda tidak mempunyai ACCOUNTING_DRAFT_CREATE.</div>}
        </article>

        <article className="panel">
          <h3>Posting Boundary</h3>
          <p className="panel-subtitle">Tidak ada tombol POST pada tahap ini.</p>
          <div className="check-list">
            <div className="check-item"><span>Finance Officer</span><span className="check-state">MAKER / DRAFT</span></div>
            <div className="check-item"><span>Manager</span><span className="check-state">CHECKER / VALIDATE</span></div>
            <div className="check-item"><span>Poster</span><span className="check-state pending">OWNER DECISION REQUIRED</span></div>
            <div className="check-item"><span>Approval request</span><span className="check-state pending">MUST BE APPROVED</span></div>
          </div>
          <div className="empty-state" style={{ marginTop: 18 }}>Memberikan ACCOUNTING_POST saja tidak cukup. Engine juga mensyaratkan actor ketiga yang berbeda dan approval policy JOURNAL_POST aktif dengan request APPROVED.</div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Journal Register</h3><p className="panel-subtitle">DRAFT manual dapat divalidasi checker. POST tetap tidak tersedia dari UI.</p></div></div>
        {journals.length ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead><tr><th>No.</th><th>Tanggal</th><th>Deskripsi</th><th>Sumber</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{journals.map((journal) => <tr key={journal.id}>
                <td>{journal.journal_number}</td><td>{journal.entry_date}</td><td>{journal.description}</td><td>{journal.source_domain}</td><td>{journal.status}</td>
                <td>{canValidate && journal.status === "DRAFT" && journal.source_domain === "MANUAL" ? (
                  <form action={validateManualJournalAction} style={{ display: "flex", gap: 8, alignItems: "center" }}>
                    <input type="hidden" name="journal_entry_id" value={journal.id} />
                    <input name="reason" maxLength={500} placeholder="Catatan (opsional)" aria-label={`Catatan validasi ${journal.journal_number}`} />
                    <button className="primary-button" type="submit">Validate</button>
                  </form>
                ) : <span className="check-state pending">—</span>}</td>
              </tr>)}</tbody>
            </table>
          </div>
        ) : <div className="empty-state">Belum ada jurnal tersimpan.</div>}
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
          <p className="panel-subtitle">Period lock tetap menjadi gate utama validation/posting.</p>
          {periods.length ? <div className="check-list">{periods.map((period) => <div className="check-item" key={period.id}>
            <span>{period.period_name}<small className="item-subtext">{period.start_date} — {period.end_date}</small></span>
            <span className={`check-state ${period.status === "OPEN" ? "" : "pending"}`}>{period.status}</span>
          </div>)}</div> : <div className="empty-state">Belum ada periode yang terlihat pada scope ini.</div>}
        </article>

        <article className="panel">
          <h3>Accounting Events</h3>
          <p className="panel-subtitle">Definisi event dan mapping domain tetap terpisah dari manual journal.</p>
          <div className="check-list">{events.map((event) => {
            const mappingCount = mappings.filter((mapping) => mapping.event_definition_id === event.id && mapping.status === "ACTIVE").length;
            return <div className="check-item" key={event.id}><span>{event.name}<small className="item-subtext">{event.domain} · {event.event_code}</small></span><span className={`check-state ${mappingCount > 0 ? "" : "pending"}`}>{mappingCount > 0 ? "MAPPED" : "UNMAPPED"}</span></div>;
          })}</div>
        </article>
      </section>
    </>
  );
}
