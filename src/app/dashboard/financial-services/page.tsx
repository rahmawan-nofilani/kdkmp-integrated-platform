import { requireAccessContext } from "@/lib/auth/access-context";
import { asFinancialServicesClient } from "@/types/financial-services";
import { asApprovalClient } from "@/types/approval";
import { asAccountingClient } from "@/types/accounting";

export const dynamic = "force-dynamic";

export default async function FinancialServicesPage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const canViewSavings = permissionCodes.includes("SAVINGS_VIEW");
  const canViewLoans = permissionCodes.includes("LOAN_VIEW");

  if (!canViewSavings && !canViewLoans) {
    return (
      <section className="panel">
        <h3>Akses Simpan Pinjam tidak tersedia</h3>
        <p className="panel-subtitle">Akun ini tidak memiliki SAVINGS_VIEW maupun LOAN_VIEW.</p>
      </section>
    );
  }

  const db = asFinancialServicesClient(supabase);
  const approvalDb = asApprovalClient(supabase);
  const accountingDb = asAccountingClient(supabase);
  const organizationId = profile.organization_id;

  const [
    unitResult,
    productsResult,
    versionsResult,
    fsProfilesResult,
    savingsAccountsResult,
    savingsLedgerResult,
    loanApplicationsResult,
    loanAccountsResult,
    loanScheduleResult,
    loanLedgerResult,
    collectionResult,
    authorizationsResult,
    approvalPoliciesResult,
    accountingEventsResult,
    accountingMappingsResult,
  ] = await Promise.all([
    organizationId
      ? supabase.from("organization_units").select("id,code,name,unit_type,status").eq("organization_id", organizationId).eq("unit_type", "SAVINGS_LOANS").maybeSingle()
      : Promise.resolve({ data: null, error: null }),
    organizationId
      ? db.from("financial_products").select("id,organization_unit_id,code,name,product_category,legal_product_type,status,template_code").eq("organization_id", organizationId).order("code")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("financial_product_versions").select("id,financial_product_id,version_no,status,accounting_mapping_status,regulatory_validation_status,effective_from,effective_until").eq("organization_id", organizationId).order("version_no", { ascending: false })
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("financial_service_member_profiles").select("id,status,identity_verification_status,kyc_status,pmpj_status,risk_level,source_of_funds_status,next_review_at").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
    canViewSavings && organizationId
      ? db.from("savings_accounts").select("id,member_id,financial_product_id,account_number,currency,status,opened_at").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
    canViewSavings && organizationId
      ? db.from("savings_ledger_entries").select("id,savings_account_id,entry_type,direction,amount,currency,channel,accounting_status,occurred_at").eq("organization_id", organizationId).order("occurred_at", { ascending: false }).limit(25)
      : Promise.resolve({ data: [], error: null }),
    canViewLoans && organizationId
      ? db.from("loan_applications").select("id,member_id,financial_product_id,application_number,requested_amount,currency,status,submitted_at,created_at").eq("organization_id", organizationId).order("created_at", { ascending: false }).limit(50)
      : Promise.resolve({ data: [], error: null }),
    canViewLoans && organizationId
      ? db.from("loan_accounts").select("id,member_id,loan_application_id,financial_product_id,account_number,approved_amount,currency,status,maturity_date").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
    canViewLoans && organizationId
      ? db.from("loan_repayment_schedule").select("id,loan_account_id,installment_no,due_date,total_due,status").eq("organization_id", organizationId).order("due_date").limit(100)
      : Promise.resolve({ data: [], error: null }),
    canViewLoans && organizationId
      ? db.from("loan_ledger_entries").select("id,loan_account_id,entry_type,principal_amount,return_or_margin_amount,fee_amount,penalty_amount,currency,channel,accounting_status,occurred_at").eq("organization_id", organizationId).order("occurred_at", { ascending: false }).limit(25)
      : Promise.resolve({ data: [], error: null }),
    canViewLoans && organizationId
      ? db.from("collection_cases").select("id,loan_account_id,case_number,status,opened_at,resolved_at").eq("organization_id", organizationId).order("opened_at", { ascending: false }).limit(30)
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? supabase.from("regulatory_authorizations").select("id,module_code,authorization_type,status,organization_unit_id,effective_date,expiry_date,notes").eq("organization_id", organizationId).eq("module_code", "SAVINGS_LOANS")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? approvalDb.from("approval_policies").select("id,domain,transaction_type,status,code,name").eq("organization_id", organizationId).eq("domain", "FINANCIAL_SERVICES")
      : Promise.resolve({ data: [], error: null }),
    accountingDb.from("accounting_event_definitions").select("id,event_code,domain,name,status").eq("domain", "FINANCIAL_SERVICES").order("event_code"),
    organizationId
      ? accountingDb.from("accounting_event_mappings").select("id,event_definition_id,status,version_no,effective_from").eq("organization_id", organizationId)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const products = productsResult.data ?? [];
  const versions = versionsResult.data ?? [];
  const fsProfiles = fsProfilesResult.data ?? [];
  const savingsAccounts = savingsAccountsResult.data ?? [];
  const savingsLedger = savingsLedgerResult.data ?? [];
  const loanApplications = loanApplicationsResult.data ?? [];
  const loanAccounts = loanAccountsResult.data ?? [];
  const loanSchedule = loanScheduleResult.data ?? [];
  const loanLedger = loanLedgerResult.data ?? [];
  const collectionCases = collectionResult.data ?? [];
  const authorizations = authorizationsResult.data ?? [];
  const approvalPolicies = approvalPoliciesResult.data ?? [];
  const accountingEvents = accountingEventsResult.data ?? [];
  const accountingMappings = accountingMappingsResult.data ?? [];

  const activeAuthorization = authorizations.some((item) => item.status === "ACTIVE");
  const activeApprovalPolicy = approvalPolicies.some((item) => item.status === "ACTIVE");
  const activeAccountingMappings = accountingMappings.filter((item) => item.status === "ACTIVE");
  const completeKycProfiles = fsProfiles.filter((item) => item.kyc_status === "COMPLETE" && item.pmpj_status === "COMPLETE");
  const overdueLoans = loanAccounts.filter((item) => ["OVERDUE", "COLLECTION", "RESTRUCTURING"].includes(item.status));
  const dueInstallments = loanSchedule.filter((item) => ["DUE", "PARTIALLY_PAID", "OVERDUE"].includes(item.status));

  const productRows = products.map((product) => {
    const version = versions.find((item) => item.financial_product_id === product.id);
    const ready = Boolean(
      product.status === "ACTIVE" &&
      product.legal_product_type &&
      version?.status === "APPROVED" &&
      version.accounting_mapping_status === "COMPLETE" &&
      version.regulatory_validation_status === "PASSED" &&
      activeAuthorization &&
      activeApprovalPolicy,
    );
    return { product, version, ready };
  });

  const readyProducts = productRows.filter((item) => item.ready);
  const overallTransactionReady = readyProducts.length > 0 && activeAccountingMappings.length > 0 && activeAuthorization && activeApprovalPolicy;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Financial Services</p>
          <h1>Simpan Pinjam Control Center</h1>
          <p>
            Fondasi rekening simpanan, pinjaman, KYC/PMPJ, jadwal angsuran, collection, dan subledger sudah tersedia.
            Pergerakan uang tetap diblokir sampai produk, accounting mapping, approval policy, dan authorization semuanya lulus gate.
          </p>
        </div>
        <span className="status-pill">{overallTransactionReady ? "READY" : "TRANSACTION BLOCKED"}</span>
      </section>

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">Produk</div><div className="metric-value">{products.length}</div><div className="metric-note">{readyProducts.length} produk memenuhi seluruh gate.</div></article>
        <article className="metric-card"><div className="metric-label">KYC/PMPJ Complete</div><div className="metric-value">{completeKycProfiles.length}</div><div className="metric-note">Dari {fsProfiles.length} financial-service profile.</div></article>
        <article className="metric-card"><div className="metric-label">Rekening Simpanan</div><div className="metric-value">{savingsAccounts.length}</div><div className="metric-note">Saldo selalu dihitung dari ledger, bukan field editable.</div></article>
        <article className="metric-card"><div className="metric-label">Rekening Pinjaman</div><div className="metric-value">{loanAccounts.length}</div><div className="metric-note">{overdueLoans.length} membutuhkan monitoring overdue/collection.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Activation Gate</h3>
          <p className="panel-subtitle">Semua gate harus terpenuhi sebelum uang boleh bergerak.</p>
          <div className="check-list">
            <div className="check-item"><span>Unit Simpan Pinjam</span><span className={`check-state ${unitResult.data?.status === "ACTIVE" ? "" : "pending"}`}>{unitResult.data?.status ?? "NOT FOUND"}</span></div>
            <div className="check-item"><span>Produk siap transaksi</span><span className={`check-state ${readyProducts.length > 0 ? "" : "pending"}`}>{readyProducts.length}/{products.length}</span></div>
            <div className="check-item"><span>Accounting event mapping ACTIVE</span><span className={`check-state ${activeAccountingMappings.length > 0 ? "" : "pending"}`}>{activeAccountingMappings.length}/{accountingEvents.length}</span></div>
            <div className="check-item"><span>Approval policy FINANCIAL_SERVICES ACTIVE</span><span className={`check-state ${activeApprovalPolicy ? "" : "pending"}`}>{activeApprovalPolicy ? "READY" : "PENDING"}</span></div>
            <div className="check-item"><span>Operating authorization ACTIVE</span><span className={`check-state ${activeAuthorization ? "" : "pending"}`}>{activeAuthorization ? "READY" : authorizations[0]?.status ?? "PENDING"}</span></div>
            <div className="check-item"><span>Money movement</span><span className={`check-state ${overallTransactionReady ? "" : "pending"}`}>{overallTransactionReady ? "ENABLED" : "BLOCKED"}</span></div>
          </div>
        </article>

        <article className="panel">
          <h3>Payment Channel Safety</h3>
          <p className="panel-subtitle">Channel tersedia di model, tetapi integrasi resmi belum dianggap aktif.</p>
          <div className="check-list">
            <div className="check-item"><span>Cash / Teller</span><span className="check-state pending">TRANSACTION GATE</span></div>
            <div className="check-item"><span>Bank Transfer</span><span className="check-state pending">ADAPTER PENDING</span></div>
            <div className="check-item"><span>QRIS</span><span className="check-state pending">PJP ADAPTER PENDING</span></div>
            <div className="check-item"><span>Screenshot sebagai bukti bayar</span><span className="check-state pending">NOT ACCEPTED</span></div>
            <div className="check-item"><span>Ledger posting</span><span className="check-state pending">ONLY AFTER CONFIRMATION</span></div>
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <div className="panel-heading-row"><div><h3>Product Readiness</h3><p className="panel-subtitle">Produk DEMO tetap tidak aktif sampai version/accounting/regulatory/approval gate selesai.</p></div></div>
        <div className="data-table-wrap">
          <table className="data-table">
            <thead><tr><th>Produk</th><th>Kategori</th><th>Product</th><th>Version</th><th>Accounting</th><th>Regulatory</th><th>Ready</th></tr></thead>
            <tbody>{productRows.map(({ product, version, ready }) => <tr key={product.id}>
              <td><strong>{product.name}</strong><small className="item-subtext">{product.code}</small></td>
              <td>{product.product_category}</td><td>{product.status}</td><td>{version ? `v${version.version_no} · ${version.status}` : "—"}</td>
              <td>{version?.accounting_mapping_status ?? "—"}</td><td>{version?.regulatory_validation_status ?? "—"}</td>
              <td><span className={`table-status ${ready ? "" : "pending"}`}>{ready ? "READY" : "BLOCKED"}</span></td>
            </tr>)}</tbody>
          </table>
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>KYC / PMPJ Readiness</h3>
          <p className="panel-subtitle">Hanya status metadata. NIK/dokumen identitas nyata tidak digunakan pada DEVELOPMENT.</p>
          {fsProfiles.length ? <div className="check-list">{fsProfiles.slice(0, 20).map((item) => <div className="check-item" key={item.id}><span>{item.kyc_status} / {item.pmpj_status}<small className="item-subtext">Identity: {item.identity_verification_status} · Risk: {item.risk_level}</small></span><span className="check-state pending">{item.status}</span></div>)}</div> : <div className="empty-state">Belum ada Financial Service Member Profile. Ini disengaja karena produk belum aktif.</div>}
        </article>

        <article className="panel">
          <h3>Loan Monitoring</h3>
          <p className="panel-subtitle">Akan menjadi sumber overdue, collection, dan restructuring monitoring.</p>
          <div className="check-list">
            <div className="check-item"><span>Aplikasi Pinjaman</span><span className="check-state">{loanApplications.length}</span></div>
            <div className="check-item"><span>Rekening Pinjaman</span><span className="check-state">{loanAccounts.length}</span></div>
            <div className="check-item"><span>Angsuran Due/Overdue</span><span className={`check-state ${dueInstallments.length ? "pending" : ""}`}>{dueInstallments.length}</span></div>
            <div className="check-item"><span>Collection Cases</span><span className={`check-state ${collectionCases.length ? "pending" : ""}`}>{collectionCases.length}</span></div>
          </div>
        </article>
      </section>

      <section className="panel section-panel">
        <h3>Financial Subledger</h3>
        <p className="panel-subtitle">Ledger bersifat append-only. Koreksi memakai reversal entry; saldo tidak boleh dioverwrite langsung.</p>
        <div className="check-list">
          <div className="check-item"><span>Savings ledger entries</span><span className="check-state">{savingsLedger.length}</span></div>
          <div className="check-item"><span>Loan ledger entries</span><span className="check-state">{loanLedger.length}</span></div>
          <div className="check-item"><span>Unposted savings entries</span><span className="check-state pending">{savingsLedger.filter((item) => item.accounting_status !== "RECONCILED").length}</span></div>
          <div className="check-item"><span>Unposted loan entries</span><span className="check-state pending">{loanLedger.filter((item) => item.accounting_status !== "RECONCILED").length}</span></div>
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="panel"><h3>Savings Lifecycle</h3><p className="panel-subtitle">Arsitektur target.</p><div className="check-list"><div className="check-item"><span>Product approved</span><span className="check-state">→</span></div><div className="check-item"><span>KYC/PMPJ complete</span><span className="check-state">→</span></div><div className="check-item"><span>Account activation</span><span className="check-state">→</span></div><div className="check-item"><span>Confirmed payment</span><span className="check-state">→</span></div><div className="check-item"><span>Immutable subledger + GL + reconciliation</span><span className="check-state">TARGET</span></div></div></article>
        <article className="panel"><h3>Loan Lifecycle</h3><p className="panel-subtitle">Arsitektur target.</p><div className="check-list"><div className="check-item"><span>Application → eligibility/KYC</span><span className="check-state">→</span></div><div className="check-item"><span>Analysis → risk review</span><span className="check-state">→</span></div><div className="check-item"><span>Approval → contract</span><span className="check-state">→</span></div><div className="check-item"><span>Disbursement → schedule</span><span className="check-state">→</span></div><div className="check-item"><span>Repayment → collection/restructuring → settled</span><span className="check-state">TARGET</span></div></div></article>
      </section>
    </>
  );
}
