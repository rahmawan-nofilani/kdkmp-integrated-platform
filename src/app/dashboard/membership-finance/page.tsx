import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asMembershipFinanceClient } from "@/types/membership-finance";

export const dynamic = "force-dynamic";

const categoryLabels: Record<string, string> = {
  CAPITAL_RELATED: "Terkait Modal Anggota",
  MEMBERSHIP_SAVINGS_RELATED: "Terkait Simpanan Keanggotaan",
  OTHER_MEMBERSHIP: "Keanggotaan Lainnya",
};

export default async function MembershipFinancePage() {
  await requirePermission("MEMBERSHIP_FINANCE_VIEW");
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const db = asMembershipFinanceClient(supabase);
  const organizationId = profile.organization_id;

  const [typesResult, versionsResult, accountsResult, ledgerResult] = await Promise.all([
    organizationId
      ? db.from("membership_contribution_types")
          .select("id,code,name,category,legal_classification,status,notes,organization_node_id,created_at")
          .eq("organization_id", organizationId)
          .order("name")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("membership_contribution_versions")
          .select("id,contribution_type_id,version_no,effective_from,effective_until,status,legal_basis,organization_node_id,created_at")
          .eq("organization_id", organizationId)
          .order("version_no", { ascending: false })
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("member_membership_accounts")
          .select("id,member_id,contribution_type_id,policy_version_id,status,opened_at,organization_node_id")
          .eq("organization_id", organizationId)
          .order("opened_at", { ascending: false })
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("member_membership_ledger")
          .select("id,account_id,member_id,entry_type,direction,amount,currency,transaction_date,status,accounting_status,reference_number,organization_node_id")
          .eq("organization_id", organizationId)
          .order("created_at", { ascending: false })
          .limit(100)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const types = typesResult.data ?? [];
  const versions = versionsResult.data ?? [];
  const accounts = accountsResult.data ?? [];
  const ledger = ledgerResult.data ?? [];
  const activeTypes = types.filter((type) => type.status === "ACTIVE");
  const openAccounts = accounts.filter((account) => account.status === "OPEN");
  const accountingPending = ledger.filter((entry) => entry.accounting_status !== "POSTED");
  const canDraft = permissionCodes.includes("MEMBERSHIP_FINANCE_POLICY_DRAFT");
  const canPost = permissionCodes.includes("MEMBERSHIP_FINANCE_POST");

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Cooperative Core · Membership Finance</p>
          <h1>Modal & Kontribusi Keanggotaan</h1>
          <p>
            Domain ini khusus hak/kewajiban finansial yang melekat pada keanggotaan koperasi.
            Ia tidak memakai ledger Simpan Pinjam dan tidak akan dicampur dengan Simpanan Berjangka,
            Simpanan Event, atau rekening pinjaman anggota.
          </p>
        </div>
        <span className="status-pill">FOUNDATION ONLY</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card">
          <div className="metric-label">Jenis Kontribusi</div>
          <div className="metric-value">{types.length}</div>
          <div className="metric-note">{activeTypes.length} ACTIVE; belum ada jenis yang di-hardcode sebagai aturan final.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Policy Version</div>
          <div className="metric-value">{versions.length}</div>
          <div className="metric-note">Nominal/frekuensi/legal basis disimpan versioned dan effective-dated.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Rekening Keanggotaan</div>
          <div className="metric-value">{openAccounts.length}</div>
          <div className="metric-note">Saldo nantinya dihitung dari ledger; tidak ada kolom balance yang boleh dioverwrite.</div>
        </article>
        <article className="metric-card">
          <div className="metric-label">Posting Accounting</div>
          <div className="metric-value metric-text">BELUM AKTIF</div>
          <div className="metric-note">{accountingPending.length} entry belum terintegrasi; transaksi uang belum dibuka pada Phase 2B.</div>
        </article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Contribution / Capital Type Engine</h3>
              <p className="panel-subtitle">
                Nama seperti “Simpanan Pokok/Wajib” atau istilah organisasi lain baru dimasukkan setelah AD/ART/kebijakan Anda tersedia.
              </p>
            </div>
          </div>
          {types.length > 0 ? (
            <div className="data-table-wrap">
              <table className="data-table">
                <thead><tr><th>Kode</th><th>Nama</th><th>Kategori</th><th>Klasifikasi</th><th>Status</th></tr></thead>
                <tbody>
                  {types.map((type) => (
                    <tr key={type.id}>
                      <td>{type.code}</td>
                      <td><strong>{type.name}</strong></td>
                      <td>{categoryLabels[type.category] ?? type.category}</td>
                      <td>{type.legal_classification ?? "Pending validation"}</td>
                      <td><span className={`table-badge ${type.status === "ACTIVE" ? "success" : "warning"}`}>{type.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="empty-state">
              Belum ada jenis kontribusi/modal anggota. Ini disengaja agar aplikasi tidak mengarang nominal, nama hukum, atau kewajiban keanggotaan sebelum AD/ART dan kebijakan resmi tersedia.
            </div>
          )}
        </article>

        <aside className="panel">
          <h3>Control Gate</h3>
          <p className="panel-subtitle">Status kemampuan role Anda pada domain ini.</p>
          <div className="check-list">
            <div className="check-item"><span>Melihat konfigurasi & ledger</span><span className="check-state">READY</span></div>
            <div className="check-item"><span>Draft policy</span><span className={`check-state ${canDraft ? "" : "pending"}`}>{canDraft ? "ALLOWED" : "DENIED"}</span></div>
            <div className="check-item"><span>Posting transaksi uang</span><span className="check-state pending">SYSTEM BLOCKED</span></div>
            <div className="check-item"><span>Accounting integration</span><span className="check-state pending">NEXT PHASE</span></div>
          </div>
          <div className="empty-state" style={{ marginTop: 18 }}>
            Permission <strong>MEMBERSHIP_FINANCE_POST</strong> memang sudah dikenali sistem, tetapi tidak dipetakan ke Manager dan belum mempunyai UI/API posting. Nilai <strong>{canPost ? "TERDETEKSI" : "TIDAK DIBERIKAN"}</strong> untuk akun Anda.
          </div>
        </aside>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Rekening & Ledger</h3>
          <p className="panel-subtitle">Ledger bersifat append-oriented dan saldo merupakan read model hasil penjumlahan entry INCREASE/DECREASE.</p>
          {accounts.length > 0 ? (
            <div className="check-list">
              {accounts.slice(0, 20).map((account) => (
                <div className="check-item" key={account.id}>
                  <span>Account {account.id.slice(0, 8)}…<small className="item-subtext">Member {account.member_id.slice(0, 8)}…</small></span>
                  <span className={`check-state ${account.status === "OPEN" ? "" : "pending"}`}>{account.status}</span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada rekening finansial keanggotaan. Tidak ada saldo DEMO yang dibuat-buat.</div>
          )}
        </article>

        <article className="panel">
          <h3>Pemisahan Domain</h3>
          <p className="panel-subtitle">Kontrol ini menjadi aturan arsitektur tetap.</p>
          <div className="check-list">
            <div className="check-item"><span>Cooperative Core membership ledger</span><span className="check-state">SEPARATE</span></div>
            <div className="check-item"><span>Simpan Pinjam savings subledger</span><span className="check-state">SEPARATE</span></div>
            <div className="check-item"><span>Loan subledger</span><span className="check-state">SEPARATE</span></div>
            <div className="check-item"><span>General Ledger</span><span className="check-state pending">FUTURE RECONCILIATION</span></div>
          </div>
        </article>
      </section>
    </>
  );
}
