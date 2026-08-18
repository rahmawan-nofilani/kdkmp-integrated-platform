import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { getAccountingDashboardSnapshot } from "@/lib/accounting/dashboard-snapshot";
import {
  authorizeAndPostManualJournalAction,
  authorizeAndPostManualJournalReversalAction,
  createManualJournalDraftAction,
  createManualJournalReversalAction,
  hardCloseAccountingPeriodAction,
  softCloseAccountingPeriodAction,
  validateManualJournalAction,
  validateManualJournalReversalAction,
} from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "invalid-draft-input": "Data draft jurnal belum lengkap atau akun Debit dan Kredit sama.",
  "invalid-journal": "Jurnal yang dipilih tidak valid.",
  "period-access": "Periode accounting tidak dapat diakses pada scope Anda.",
  "period-closed": "Periode accounting tidak OPEN.",
  "period-not-soft-closed": "Periode belum berada pada status SOFT_CLOSED.",
  "period-not-ended": "Periode belum berakhir sehingga belum dapat ditutup.",
  "period-manage-denied": "Akun Anda tidak memiliki ACCOUNTING_PERIOD_MANAGE.",
  "period-close-reason-required": "Alasan penutupan periode wajib diisi.",
  "period-has-unposted": "Periode masih memiliki jurnal DRAFT/VALIDATED yang belum diposting.",
  "period-has-approvals": "Periode masih memiliki approval Accounting yang terbuka.",
  "period-has-reconciliation": "Periode masih memiliki reconciliation PENDING/EXCEPTION.",
  "period-has-unbalanced": "Periode memiliki jurnal POSTED yang tidak seimbang.",
  "period-soft-evidence-missing": "Bukti SOFT_CLOSE Manager tidak ditemukan.",
  "period-close-separation": "Actor HARD_CLOSE wajib berbeda dari actor SOFT_CLOSE.",
  "date-outside-period": "Tanggal jurnal berada di luar periode accounting yang dipilih.",
  "scope-denied": "Data Scope tidak mengizinkan operasi accounting tersebut.",
  "not-balanced": "Jurnal tidak seimbang.",
  "account-invalid": "Akun jurnal tidak aktif, bukan posting account, atau berada di scope lain.",
  "lines-invalid": "Baris jurnal tidak valid.",
  "maker-checker": "Pembuat jurnal tidak boleh memvalidasi jurnalnya sendiri.",
  "maker-checker-poster": "Maker, checker, dan poster wajib merupakan profil yang berbeda.",
  "not-draft": "Jurnal sudah bukan berstatus DRAFT.",
  "not-validated": "Jurnal belum berada pada status VALIDATED.",
  "reversal-reason-required": "Alasan reversal wajib diisi.",
  "reversal-source-not-posted": "Hanya jurnal POSTED yang dapat direversal.",
  "reversal-source-manual": "Reversal dari layar Accounting hanya berlaku untuk manual journal.",
  "reversal-exists": "Jurnal tersebut sudah memiliki reversal aktif.",
  "reversal-date-before-source": "Tanggal reversal tidak boleh lebih awal dari jurnal sumber.",
  "reversal-journal-required": "Jurnal yang dipilih bukan manual reversal journal.",
  "reversal-not-validated": "Reversal belum berada pada status VALIDATED.",
  "reversal-approval-missing": "Approval reversal belum tersedia.",
  "reversal-approval-not-open": "Approval reversal sudah tidak terbuka.",
  "reversal-authorization-required": "Reversal belum memiliki otorisasi BOARD yang sesuai.",
  "reversal-poster-not-authorizer": "Reversal hanya dapat diposting oleh BOARD yang memberi otorisasi.",
  "post-denied": "Akun Anda tidak memiliki otorisasi ACCOUNTING_POST.",
  "approval-missing": "Approval request posting belum tersedia untuk jurnal ini.",
  "approval-not-open": "Approval request posting sudah tidak terbuka.",
  "conflict-required": "Pengurus wajib menyatakan deklarasi konflik kepentingan sebelum tindakan governance.",
  "post-reason-required": "Alasan/otorisasi posting wajib diisi.",
  "poster-not-authorizer": "Jurnal hanya boleh diposting oleh Pengurus yang memberi otorisasi posting.",
  idempotency: "Permintaan accounting bertabrakan dengan idempotency key yang sudah ada.",
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
  const reversibleJournals = journals.filter((journal) => journal.source_domain === "MANUAL" && journal.status === "POSTED");
  const reversalJournals = journals.filter((journal) => journal.source_domain === "MANUAL_REVERSAL");
  const canDraft = permissionCodes.includes("ACCOUNTING_DRAFT_CREATE");
  const canValidate = permissionCodes.includes("ACCOUNTING_VALIDATE");
  const canPost = permissionCodes.includes("ACCOUNTING_POST");
  const canManagePeriod = permissionCodes.includes("ACCOUNTING_PERIOD_MANAGE");
  const canReconcile = permissionCodes.includes("ACCOUNTING_RECONCILE");
  const today = new Date().toISOString().slice(0, 10);
  const defaultPeriod = openPeriods.find((period) => period.start_date <= today && period.end_date >= today) ?? openPeriods[0];
  const defaultEntryDate = defaultPeriod && (today < defaultPeriod.start_date || today > defaultPeriod.end_date) ? defaultPeriod.start_date : today;

  const successMessages: Record<string, string> = {
    "draft-created": "Draft jurnal berhasil dibuat. Jurnal belum masuk General Ledger dan harus divalidasi actor berbeda.",
    validated: "Jurnal berhasil divalidasi. Approval request BOARD dibuat otomatis dan jurnal menunggu otorisasi posting.",
    posted: "Jurnal berhasil diotorisasi dan diposting oleh BOARD/Pengurus. Posted journal bersifat immutable.",
    "reversal-created": "Reversal DRAFT berhasil dibuat dari jurnal POSTED tanpa mengubah jurnal sumber.",
    "reversal-validated": "Reversal berhasil divalidasi Manager dan menunggu otorisasi BOARD.",
    "reversal-posted": "Reversal berhasil diotorisasi dan diposting BOARD. Jurnal sumber tetap immutable.",
    "period-soft-closed": "Periode berhasil SOFT_CLOSED oleh Manager. BOARD dapat melakukan HARD_CLOSE setelah seluruh gate tetap bersih.",
    "period-hard-closed": "Periode berhasil HARD_CLOSED oleh BOARD dan tidak lagi menerima posting baru.",
  };

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Finance & Accounting</p>
          <h1>Accounting Control Center</h1>
          <p>
            Workflow Release-1: FINANCE_OFFICER membuat DRAFT/reversal, MANAGER melakukan validation dan SOFT_CLOSE,
            sedangkan BOARD/Pengurus memberi otorisasi POST serta HARD_CLOSE dengan conflict declaration.
          </p>
        </div>
        <span className="status-pill">CONTROLLED OPERATIONAL</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success && successMessages[params.success] ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>{successMessages[params.success]}</div> : null}

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">COA</div><div className="metric-value">{accounts.length}</div><div className="metric-note">{postingAccounts.length} posting account · {controlAccounts.length} control candidate.</div></article>
        <article className="metric-card"><div className="metric-label">Periode Open</div><div className="metric-value">{openPeriods.length}</div><div className="metric-note">Close hanya diproses setelah end date dan seluruh database gate bersih.</div></article>
        <article className="metric-card"><div className="metric-label">Manual Reversal</div><div className="metric-value">{reversalJournals.length}</div><div className="metric-note">Append-only; jurnal sumber POSTED tidak pernah diubah.</div></article>
        <article className="metric-card"><div className="metric-label">Reconciliation</div><div className="metric-value">{reconciliations.length}</div><div className="metric-note">PENDING/EXCEPTION akan memblokir period close.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row"><div><h3>Segregation of Duties</h3><p className="panel-subtitle">Permission efektif untuk akun Anda saat ini.</p></div></div>
          <div className="check-list">
            <div className="check-item"><span>Lihat Accounting</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Buat Draft / Reversal</span><span className={`check-state ${canDraft ? "" : "pending"}`}>{canDraft ? "FINANCE / ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Validasi</span><span className={`check-state ${canValidate ? "" : "pending"}`}>{canValidate ? "MANAGER / ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Posting / Hard Close</span><span className={`check-state ${canPost ? "" : "pending"}`}>{canPost ? "BOARD / AUTHORIZED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Soft Close Periode</span><span className={`check-state ${canManagePeriod ? "" : "pending"}`}>{canManagePeriod ? "MANAGER / ALLOWED" : "NOT ASSIGNED"}</span></div>
            <div className="check-item"><span>Reconciliation</span><span className={`check-state ${canReconcile ? "" : "pending"}`}>{canReconcile ? "ALLOWED" : "NOT ASSIGNED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Database tetap menjadi enforcement layer terakhir.</p>
          <div className="check-list">
            <div className="check-item"><span>Maker ≠ Checker ≠ Poster</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>Manual reversal append-only</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>Non-manual journal reversal</span><span className="check-state pending">DOMAIN ENGINE ONLY</span></div>
            <div className="check-item"><span>SOFT_CLOSE = Manager</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>HARD_CLOSE = distinct BOARD</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>Unposted / approval / reconciliation blockers</span><span className="check-state">ENFORCED</span></div>
            <div className="check-item"><span>Conflict declaration</span><span className="check-state">REQUIRED</span></div>
          </div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div><h3>Manual Journal Draft</h3><p className="panel-subtitle">Quick entry dua sisi tetap tersedia; gunakan editor multi-line untuk jurnal dengan lebih dari dua baris.</p></div>
            {canDraft ? <Link className="secondary-button" href="/dashboard/accounting/journal/new">Buka Editor Multi-line</Link> : null}
          </div>
          {canDraft ? (
            openPeriods.length > 0 && postingAccounts.length >= 2 ? (
              <form action={createManualJournalDraftAction} className="form-stack">
                <div className="field"><label htmlFor="accounting_period_id">Periode</label><select id="accounting_period_id" name="accounting_period_id" required defaultValue={defaultPeriod?.id}>{openPeriods.map((period) => <option key={period.id} value={period.id}>{period.period_name} · {period.start_date}—{period.end_date}</option>)}</select></div>
                <div className="field"><label htmlFor="entry_date">Tanggal Jurnal</label><input id="entry_date" name="entry_date" type="date" required defaultValue={defaultEntryDate} /></div>
                <div className="field"><label htmlFor="description">Deskripsi</label><input id="description" name="description" required maxLength={500} placeholder="Contoh: Koreksi klasifikasi biaya operasional" /></div>
                <div className="field"><label htmlFor="source_reference">Referensi</label><input id="source_reference" name="source_reference" maxLength={160} placeholder="Opsional: dokumen / memo internal" /></div>
                <div className="field"><label htmlFor="debit_account_id">Akun Debit</label><select id="debit_account_id" name="debit_account_id" required defaultValue=""><option value="" disabled>Pilih posting account</option>{postingAccounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}</select></div>
                <div className="field"><label htmlFor="credit_account_id">Akun Kredit</label><select id="credit_account_id" name="credit_account_id" required defaultValue=""><option value="" disabled>Pilih posting account</option>{postingAccounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}</select></div>
                <div className="field"><label htmlFor="amount">Nominal</label><input id="amount" name="amount" type="number" min="0.01" step="0.01" required placeholder="0.00" /></div>
                <button className="primary-button" type="submit">Buat DRAFT Jurnal</button>
              </form>
            ) : <div className="empty-state">Periode OPEN atau posting account belum cukup untuk membuat manual journal.</div>
          ) : <div className="empty-state">Role Anda tidak mempunyai ACCOUNTING_DRAFT_CREATE.</div>}
        </article>

        <article className="panel">
          <h3>Manual Reversal Wizard</h3>
          <p className="panel-subtitle">Hanya manual journal POSTED. Engine membalik Debit/Kredit otomatis; jurnal sumber tidak disentuh.</p>
          {canDraft ? (
            reversibleJournals.length && openPeriods.length ? (
              <div className="form-stack">
                {reversibleJournals.map((journal) => (
                  <form action={createManualJournalReversalAction} className="form-stack" key={journal.id} style={{ borderTop: "1px solid var(--border)", paddingTop: 14 }}>
                    <input type="hidden" name="original_journal_entry_id" value={journal.id} />
                    <strong>{journal.journal_number} · {journal.entry_date}</strong>
                    <small className="item-subtext">{journal.description}</small>
                    <div className="field"><label htmlFor={`reversal-period-${journal.id}`}>Periode reversal</label><select id={`reversal-period-${journal.id}`} name="accounting_period_id" required defaultValue={defaultPeriod?.id}>{openPeriods.map((period) => <option key={period.id} value={period.id}>{period.period_name} · {period.start_date}—{period.end_date}</option>)}</select></div>
                    <div className="field"><label htmlFor={`reversal-date-${journal.id}`}>Tanggal reversal</label><input id={`reversal-date-${journal.id}`} name="entry_date" type="date" required defaultValue={defaultEntryDate} /></div>
                    <div className="field"><label htmlFor={`reversal-reason-${journal.id}`}>Alasan koreksi</label><input id={`reversal-reason-${journal.id}`} name="reason" required maxLength={500} placeholder="Jelaskan mengapa jurnal harus dibalik" /></div>
                    <button className="primary-button" type="submit">Create Reversal DRAFT</button>
                  </form>
                ))}
              </div>
            ) : <div className="empty-state">Belum ada manual journal POSTED yang dapat direversal atau tidak ada periode OPEN.</div>
          ) : <div className="empty-state">Reversal DRAFT hanya tersedia untuk FINANCE_OFFICER.</div>}
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Journal Register</h3><p className="panel-subtitle">Manual journal dan reversal mengikuti workflow tiga aktor yang sama.</p></div></div>
        {journals.length ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead><tr><th>No.</th><th>Tanggal</th><th>Deskripsi</th><th>Sumber</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{journals.map((journal) => {
                const canValidateManual = canValidate && journal.status === "DRAFT" && journal.source_domain === "MANUAL";
                const canPostManual = canPost && journal.status === "VALIDATED" && journal.source_domain === "MANUAL";
                const canValidateReversal = canValidate && journal.status === "DRAFT" && journal.source_domain === "MANUAL_REVERSAL";
                const canPostReversal = canPost && journal.status === "VALIDATED" && journal.source_domain === "MANUAL_REVERSAL";
                return <tr key={journal.id}>
                  <td>{journal.journal_number}</td><td>{journal.entry_date}</td><td>{journal.description}</td><td>{journal.source_domain}</td><td>{journal.status}</td>
                  <td>
                    {canValidateManual ? <form action={validateManualJournalAction} style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}><input type="hidden" name="journal_entry_id" value={journal.id} /><input name="reason" maxLength={500} placeholder="Catatan validasi" /><button className="primary-button" type="submit">Validate</button></form> : null}
                    {canPostManual ? <form action={authorizeAndPostManualJournalAction} style={{ display: "grid", gap: 8, minWidth: 260 }}><input type="hidden" name="journal_entry_id" value={journal.id} /><input name="reason" required maxLength={500} placeholder="Alasan otorisasi posting" /><label style={{ display: "flex", gap: 8, alignItems: "center" }}><input type="checkbox" name="conflict_declared" required /><span>Tidak ada konflik kepentingan.</span></label><button className="primary-button" type="submit">Authorize &amp; Post</button></form> : null}
                    {canValidateReversal ? <form action={validateManualJournalReversalAction} style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}><input type="hidden" name="journal_entry_id" value={journal.id} /><input name="reason" maxLength={500} placeholder="Catatan reversal" /><button className="primary-button" type="submit">Validate Reversal</button></form> : null}
                    {canPostReversal ? <form action={authorizeAndPostManualJournalReversalAction} style={{ display: "grid", gap: 8, minWidth: 260 }}><input type="hidden" name="journal_entry_id" value={journal.id} /><input name="reason" required maxLength={500} placeholder="Alasan otorisasi reversal" /><label style={{ display: "flex", gap: 8, alignItems: "center" }}><input type="checkbox" name="conflict_declared" required /><span>Tidak ada konflik kepentingan.</span></label><button className="primary-button" type="submit">Authorize &amp; Post Reversal</button></form> : null}
                    {!(canValidateManual || canPostManual || canValidateReversal || canPostReversal) ? <span className="check-state pending">—</span> : null}
                  </td>
                </tr>;
              })}</tbody>
            </table>
          </div>
        ) : <div className="empty-state">Belum ada jurnal tersimpan.</div>}
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Period Close Checklist</h3><p className="panel-subtitle">UI menunjukkan eligibility dasar; database memeriksa seluruh blocker lagi saat command dijalankan.</p></div></div>
        <div className="check-list" style={{ marginBottom: 18 }}>
          <div className="check-item"><span>Periode harus sudah melewati end date</span><span className="check-state">DB GATE</span></div>
          <div className="check-item"><span>Tidak ada DRAFT / VALIDATED journal</span><span className="check-state">DB GATE</span></div>
          <div className="check-item"><span>Tidak ada approval Accounting terbuka</span><span className="check-state">DB GATE</span></div>
          <div className="check-item"><span>Tidak ada reconciliation PENDING / EXCEPTION</span><span className="check-state">DB GATE</span></div>
          <div className="check-item"><span>Semua jurnal POSTED harus balanced</span><span className="check-state">DB GATE</span></div>
        </div>
        {periods.length ? (
          <div className="data-table-wrap">
            <table className="data-table">
              <thead><tr><th>Periode</th><th>Tanggal</th><th>Status</th><th>Eligibility</th><th>Action</th></tr></thead>
              <tbody>{periods.map((period) => {
                const ended = period.end_date < today;
                const canSoftClose = canManagePeriod && period.status === "OPEN" && ended;
                const canHardClose = canPost && period.status === "SOFT_CLOSED" && ended;
                return <tr key={period.id}>
                  <td>{period.period_name}</td><td>{period.start_date} — {period.end_date}</td><td>{period.status}</td>
                  <td><span className={`check-state ${ended ? "" : "pending"}`}>{ended ? "ENDED" : "WAIT END DATE"}</span></td>
                  <td>
                    {canSoftClose ? <form action={softCloseAccountingPeriodAction} style={{ display: "flex", gap: 8, flexWrap: "wrap" }}><input type="hidden" name="accounting_period_id" value={period.id} /><input name="reason" required maxLength={500} placeholder="Catatan month-end review" /><button className="primary-button" type="submit">Manager SOFT_CLOSE</button></form> : null}
                    {canHardClose ? <form action={hardCloseAccountingPeriodAction} style={{ display: "grid", gap: 8, minWidth: 260 }}><input type="hidden" name="accounting_period_id" value={period.id} /><input name="reason" required maxLength={500} placeholder="Alasan final close" /><label style={{ display: "flex", gap: 8, alignItems: "center" }}><input type="checkbox" name="conflict_declared" required /><span>Tidak ada konflik kepentingan.</span></label><button className="primary-button" type="submit">BOARD HARD_CLOSE</button></form> : null}
                    {!(canSoftClose || canHardClose) ? <span className="check-state pending">—</span> : null}
                  </td>
                </tr>;
              })}</tbody>
            </table>
          </div>
        ) : <div className="empty-state">Belum ada periode yang terlihat pada scope ini.</div>}
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Chart of Accounts — DEVELOPMENT</h3><p className="panel-subtitle">Struktur awal untuk menguji engine. Bukan COA final organisasi.</p></div></div>
        <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Kode</th><th>Nama</th><th>Kelas</th><th>Normal</th><th>Posting</th><th>Control</th><th>Status</th></tr></thead><tbody>{accounts.map((account) => <tr key={account.id}><td>{account.code}</td><td><strong>{account.name}</strong>{account.control_purpose ? <small className="item-subtext">Control: {account.control_purpose}</small> : null}</td><td>{account.account_class}</td><td>{account.normal_balance}</td><td>{account.is_posting ? "YA" : "HEADER"}</td><td>{account.is_control_account ? "YA" : "—"}</td><td><span className="table-status">{account.status}</span></td></tr>)}</tbody></table></div>
      </section>

      <section className="dashboard-grid">
        <article className="panel"><h3>Accounting Events</h3><p className="panel-subtitle">Definisi event dan mapping domain tetap terpisah dari manual journal.</p><div className="check-list">{events.map((event) => { const mappingCount = mappings.filter((mapping) => mapping.event_definition_id === event.id && mapping.status === "ACTIVE").length; return <div className="check-item" key={event.id}><span>{event.name}<small className="item-subtext">{event.domain} · {event.event_code}</small></span><span className={`check-state ${mappingCount > 0 ? "" : "pending"}`}>{mappingCount > 0 ? "MAPPED" : "UNMAPPED"}</span></div>; })}</div></article>
        <article className="panel"><h3>Subledger Control</h3><p className="panel-subtitle">Control mappings tetap harus direview sebelum domain subledger baru diaktifkan.</p>{controlMappings.length ? <div className="check-list">{controlMappings.map((mapping) => <div className="check-item" key={mapping.id}><span>{mapping.subledger_code}</span><span className={`check-state ${mapping.status === "ACTIVE" ? "" : "pending"}`}>{mapping.status}</span></div>)}</div> : <div className="empty-state">Belum ada subledger control mapping pada scope ini.</div>}</article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Reconciliation</h3><p className="panel-subtitle">Status exception perlu diselesaikan sebelum period close; setiap run dapat dibuka sebagai drill-down read-only.</p></div></div>
        {reconciliations.length ? <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Type</th><th>As of</th><th>Subledger</th><th>GL</th><th>Difference</th><th>Status</th><th>Detail</th></tr></thead><tbody>{reconciliations.map((run) => <tr key={run.id}><td>{run.reconciliation_type}</td><td>{run.as_of_date}</td><td>{run.subledger_amount ?? "—"}</td><td>{run.gl_amount ?? "—"}</td><td>{run.difference_amount ?? "—"}</td><td><span className={`check-state ${run.status === "MATCHED" || run.status === "CLOSED" ? "" : "pending"}`}>{run.status}</span></td><td><Link className="secondary-button" href={`/dashboard/accounting/reconciliation/${run.id}`}>Buka Detail</Link></td></tr>)}</tbody></table></div> : <div className="empty-state">Belum ada reconciliation run tersimpan.</div>}
      </section>
    </>
  );
}
