import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { getAccountingDashboardSnapshot } from "@/lib/accounting/dashboard-snapshot";
import { authorizeAndPostManualJournalAction, createManualJournalDraftAction, validateManualJournalAction } from "./actions";

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
  "maker-checker-poster": "Maker, checker, dan poster wajib merupakan profil yang berbeda.",
  "not-draft": "Jurnal sudah bukan berstatus DRAFT.",
  "not-validated": "Jurnal belum berada pada status VALIDATED.",
  "post-denied": "Akun Anda tidak memiliki otorisasi ACCOUNTING_POST.",
  "approval-missing": "Approval request posting belum tersedia untuk jurnal ini.",
  "approval-not-open": "Approval request posting sudah tidak terbuka.",
  "conflict-required": "Pengurus wajib menyatakan deklarasi konflik kepentingan sebelum posting.",
  "post-reason-required": "Alasan/otorisasi posting wajib diisi.",
  "poster-not-authorizer": "Jurnal hanya boleh diposting oleh Pengurus yang memberi otorisasi posting.",
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
            Release-1 controlled workflow: FINANCE_OFFICER membuat DRAFT, MANAGER melakukan independent validation,
            dan BOARD/Pengurus memberi otorisasi sekaligus mengeksekusi posting setelah approval gate terpenuhi.
          </p>
        </div>
        <span className="status-pill">CONTROLLED OPERATIONAL</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success === "draft-created" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Draft jurnal berhasil dibuat. Jurnal belum masuk General Ledger dan harus divalidasi actor berbeda.</div> : null}
      {params.success === "validated" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Jurnal berhasil divalidasi. Approval request BOARD dibuat otomatis dan jurnal menunggu otorisasi posting.</div> : null}
      {params.success === "posted" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Jurnal berhasil diotorisasi dan diposting oleh BOARD/Pengurus. Posted journal bersifat immutable.</div> : null}

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">COA</div><div className="metric-value">{accounts.length}</div><div className="metric-note">{postingAccounts.length} posting account · {controlAccounts.length} control candidate.</div></article>
        <article className="metric-card"><div className="metric-label">Periode Open</div><div className="metric-value">{openPeriods.length}</div><div className="metric-note">Draft dan posting hanya berlaku pada periode yang diizinkan engine.</div></article>
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
            <div className="check-item"><span>Posting General Ledger</span><span className={`check-state ${canPost ? "" : "pending"}`}>{canPost ? "BOARD / AUTHORIZED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Kelola Periode</span><span className={`check-state ${canManagePeriod ? "" : "pending"}`}>{canManagePeriod ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Reconciliation</span><span className={`check-state ${canReconcile ? "" : "pending"}`}>{canReconcile ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Posting manual menggunakan tiga aktor bisnis dan approval evidence.</p>
          <div className="check-list">
            <div className="check-item"><span>Balanced journal invariant</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>FINANCE_OFFICER = Maker</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>MANAGER = Checker</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>BOARD = Poster</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>SUPERVISOR = Read/Audit</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>JOURNAL_POST approval policy</span><span className="check-state">ACTIVE</span></div>
            <div className="check-item"><span>Conflict declaration</span><span className="check-state">REQUIRED</span></div>
            <div className="check-item"><span>Posted journal immutable</span><span className="check-state">READY</span></div>
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
          <p className="panel-subtitle">Otorisasi tetap fail-closed meskipun role memiliki ACCOUNTING_POST.</p>
          <div className="check-list">
            <div className="check-item"><span>Finance Officer</span><span className="check-state">MAKER / DRAFT</span></div>
            <div className="check-item"><span>Manager</span><span className="check-state">CHECKER / VALIDATE</span></div>
            <div className="check-item"><span>BOARD / Pengurus</span><span className="check-state">AUTHORIZE + POST</span></div>
            <div className="check-item"><span>Supervisor / Pengawas</span><span className="check-state">READ / AUDIT</span></div>
          </div>
          <div className="empty-state" style={{ marginTop: 18 }}>BOARD wajib menyatakan tidak ada konflik kepentingan. Approval decision dan posting dicatat terpisah, dan hanya BOARD yang memberi approval tersebut yang boleh mengeksekusi POST.</div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Journal Register</h3><p className="panel-subtitle">DRAFT divalidasi Manager; VALIDATED diotorisasi dan diposting oleh BOARD/Pengurus.</p></div></div>
        {journals.length ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead><tr><th>No.</th><th>Tanggal</th><th>Deskripsi</th><th>Sumber</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{journals.map((journal) => <tr key={journal.id}>
                <td>{journal.journal_number}</td><td>{journal.entry_date}</td><td>{journal.description}</td><td>{journal.source_domain}</td><td>{journal.status}</td>
                <td>
                  {canValidate && journal.status === "DRAFT" && journal.source_domain === "MANUAL" ? (
                    <form action={validateManualJournalAction} style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
                      <input type="hidden" name="journal_entry_id" value={journal.id} />
                      <input name="reason" maxLength={500} placeholder="Catatan validasi (opsional)" aria-label={`Catatan validasi ${journal.journal_number}`} />
                      <button className="primary-button" type="submit">Validate</button>
                    </form>
                  ) : null}
                  {canPost && journal.status === "VALIDATED" && journal.source_domain === "MANUAL" ? (
                    <form action={authorizeAndPostManualJournalAction} style={{ display: "grid", gap: 8, minWidth: 260 }}>
                      <input type="hidden" name="journal_entry_id" value={journal.id} />
                      <input name="reason" required maxLength={500} placeholder="Alasan otorisasi posting" aria-label={`Alasan posting ${journal.journal_number}`} />
                      <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
                        <input type="checkbox" name="conflict_declared" required />
                        <span>Saya menyatakan tidak ada konflik kepentingan.</span>
                      </label>
                      <button className="primary-button" type="submit">Authorize &amp; Post</button>
                    </form>
                  ) : null}
                  {!((canValidate && journal.status === "DRAFT" && journal.source_domain === "MANUAL") || (canPost && journal.status === "VALIDATED" && journal.source_domain === "MANUAL")) ? <span className="check-state pending">—</span> : null}
                </td>
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

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Subledger Control</h3>
          <p className="panel-subtitle">Control mappings tetap harus direview sebelum domain subledger baru diaktifkan.</p>
          {controlMappings.length ? <div className="check-list">{controlMappings.map((mapping) => <div className="check-item" key={mapping.id}><span>{mapping.subledger_code}</span><span className={`check-state ${mapping.status === "ACTIVE" ? "" : "pending"}`}>{mapping.status}</span></div>)}</div> : <div className="empty-state">Belum ada subledger control mapping pada scope ini.</div>}
        </article>

        <article className="panel">
          <h3>Reconciliation</h3>
          <p className="panel-subtitle">Reconciliation tetap terpisah dari authorization/posting manual journal.</p>
          {reconciliations.length ? <div className="check-list">{reconciliations.map((run) => <div className="check-item" key={run.id}><span>{run.reconciliation_type}<small className="item-subtext">As of {run.as_of_date}</small></span><span className={`check-state ${run.status === "MATCHED" || run.status === "CLOSED" ? "" : "pending"}`}>{run.status}</span></div>)}</div> : <div className="empty-state">Belum ada reconciliation run tersimpan.</div>}
        </article>
      </section>
    </>
  );
}
