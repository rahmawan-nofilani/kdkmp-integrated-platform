import { requirePermission } from "@/lib/auth/permissions";
import { requireAccessContext } from "@/lib/auth/access-context";
import { getFinancialProductsDashboardSnapshot } from "@/lib/financial-products/dashboard-snapshot";
import { createFinancialProductDraftAction } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "duplicate-code": "Kode produk sudah digunakan pada Unit Simpan Pinjam yang sama.",
  "invalid-template": "Template produk tidak valid atau sudah tidak aktif.",
  "unit-required": "Sistem tidak dapat menentukan Unit Simpan Pinjam secara otomatis.",
  "invalid-unit": "Unit tujuan bukan Unit Simpan Pinjam aktif.",
  "scope-denied": "Anda tidak memiliki Data Scope untuk Unit Simpan Pinjam tersebut.",
  "missing-identity": "Template, kode produk, dan nama produk wajib diisi.",
  system: "Draft produk tidak dapat dibuat. Detail teknis tidak ditampilkan kepada pengguna.",
};

export default async function FinancialProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  await requirePermission("FINANCIAL_PRODUCT_VIEW");
  const { permissionCodes, supabase } = await requireAccessContext();
  const params = await searchParams;
  const canCreate = permissionCodes.includes("FINANCIAL_PRODUCT_CREATE");
  const canEditDraft = permissionCodes.includes("FINANCIAL_PRODUCT_EDIT_DRAFT");
  const canApprove = permissionCodes.includes("FINANCIAL_PRODUCT_APPROVE");

  const { data: snapshot, error: snapshotError } = await getFinancialProductsDashboardSnapshot(supabase);
  if (snapshotError || !snapshot) {
    return <section className="panel"><h3>Data produk finansial belum dapat dimuat</h3><p className="panel-subtitle">Snapshot produk gagal dibaca. Tidak ada fallback lintas-scope yang digunakan.</p></section>;
  }

  const { templates, products, versions, authorizations } = snapshot;
  const latestVersion = new Map<string, (typeof versions)[number]>();
  for (const version of versions) {
    if (!latestVersion.has(version.financial_product_id)) latestVersion.set(version.financial_product_id, version);
  }

  function authorizationActive(unitId: string) {
    const today = new Date().toISOString().slice(0, 10);
    return authorizations.some((authorization) =>
      ["SAVINGS_LOANS", "FINANCIAL_SERVICES"].includes(authorization.module_code) &&
      (authorization.organization_unit_id === unitId || authorization.organization_unit_id === null) &&
      authorization.status === "ACTIVE" &&
      (!authorization.effective_date || authorization.effective_date <= today) &&
      (!authorization.expiry_date || authorization.expiry_date >= today),
    );
  }

  function activationState(product: (typeof products)[number]) {
    const version = latestVersion.get(product.id);
    const ready = Boolean(
      product.legal_product_type &&
      version?.status === "APPROVED" &&
      version.accounting_mapping_status === "COMPLETE" &&
      version.regulatory_validation_status === "PASSED" &&
      authorizationActive(product.organization_unit_id),
    );
    return { ready, version };
  }

  const savingsTemplates = templates.filter((item) => item.product_category === "SAVINGS");
  const loanTemplates = templates.filter((item) => item.product_category === "LOAN");
  const readyCount = products.filter((product) => activationState(product).ready).length;

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Financial Services · Product Engine</p>
          <h1>Produk Simpan Pinjam</h1>
          <p>
            Product Builder membuat produk dan version snapshot tanpa mengubah kode aplikasi.
            Template adalah pola teknis, bukan otomatis klasifikasi hukum. Aktivasi transaksi tetap diblokir sampai approval,
            accounting mapping, regulatory validation, dan authorization lengkap.
          </p>
        </div>
        <span className="status-pill">CONFIGURATION ONLY</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success === "created" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Draft produk dan Version 1 berhasil dibuat. Produk belum aktif untuk transaksi.</div> : null}

      <section className="metric-grid">
        <article className="metric-card"><div className="metric-label">Template Simpanan</div><div className="metric-value">{savingsTemplates.length}</div><div className="metric-note">Fleksibel, Berjangka, Target/Event, Berkala.</div></article>
        <article className="metric-card"><div className="metric-label">Template Pinjaman</div><div className="metric-value">{loanTemplates.length}</div><div className="metric-note">Bulanan, mingguan, musiman, jatuh tempo, balloon, custom.</div></article>
        <article className="metric-card"><div className="metric-label">Produk Dikonfigurasi</div><div className="metric-value">{products.length}</div><div className="metric-note">Semua produk memiliki version snapshot.</div></article>
        <article className="metric-card"><div className="metric-label">Siap Aktivasi</div><div className="metric-value">{readyCount}</div><div className="metric-note">Expected 0 selama regulasi/accounting masih pending.</div></article>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Katalog Produk</h3>
          <p className="panel-subtitle">Status readiness dihitung dari data kontrol, bukan badge hardcoded.</p>
          {products.length > 0 ? (
            <div className="data-table-wrap">
              <table className="data-table">
                <thead><tr><th>Kode</th><th>Nama</th><th>Jenis</th><th>Template</th><th>Version</th><th>Accounting</th><th>Regulasi</th><th>Activation</th></tr></thead>
                <tbody>
                  {products.map((product) => {
                    const { ready, version } = activationState(product);
                    return (
                      <tr key={product.id}>
                        <td>{product.code}</td>
                        <td><strong>{product.name}</strong><small className="item-subtext">{product.legal_product_type ?? "Legal type: pending"}</small></td>
                        <td>{product.product_category}</td>
                        <td>{product.template_code ?? "CUSTOM"}</td>
                        <td>v{version?.version_no ?? "?"} · {version?.status ?? "UNKNOWN"}</td>
                        <td>{version?.accounting_mapping_status ?? "UNKNOWN"}</td>
                        <td>{version?.regulatory_validation_status ?? "UNKNOWN"}</td>
                        <td><span className={`table-badge ${ready ? "success" : "warning"}`}>{ready ? "READY" : "BLOCKED"}</span></td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          ) : <div className="empty-state">Belum ada produk DRAFT. Gunakan Product Builder untuk membuat contoh DEVELOPMENT.</div>}
        </article>

        <aside className="panel">
          <h3>Product Builder — Draft Baru</h3>
          <p className="panel-subtitle">Tidak ada rate, nominal, tenor, atau legal classification yang dipaksakan oleh template.</p>
          {canCreate ? (
            <form action={createFinancialProductDraftAction} className="form-stack">
              <div className="field">
                <label htmlFor="template_code">Template</label>
                <select id="template_code" name="template_code" required defaultValue="" style={{ minHeight: 48, border: "1px solid #d0d5dd", borderRadius: 10, padding: "0 12px", background: "white" }}>
                  <option value="" disabled>Pilih template</option>
                  <optgroup label="Simpanan">{savingsTemplates.map((template) => <option key={template.id} value={template.code}>{template.name}</option>)}</optgroup>
                  <optgroup label="Pinjaman">{loanTemplates.map((template) => <option key={template.id} value={template.code}>{template.name}</option>)}</optgroup>
                </select>
              </div>
              <div className="field"><label htmlFor="product_code">Kode Produk</label><input id="product_code" name="product_code" required maxLength={60} placeholder="Contoh: SIM-KURBAN-2027" /></div>
              <div className="field"><label htmlFor="product_name">Nama Produk</label><input id="product_name" name="product_name" required maxLength={160} placeholder="Contoh: Simpanan Kurban 2027" /></div>
              <div className="field"><label htmlFor="legal_product_type">Legal Product Type</label><input id="legal_product_type" name="legal_product_type" maxLength={160} placeholder="Kosongkan bila belum divalidasi" /></div>
              <div className="field"><label htmlFor="purpose_code">Purpose / Event</label><input id="purpose_code" name="purpose_code" maxLength={80} placeholder="Contoh: QURBAN / EDUCATION / BUSINESS" /></div>
              <div className="field"><label htmlFor="description">Catatan Produk</label><input id="description" name="description" maxLength={300} placeholder="Data DEVELOPMENT / kebijakan pending" /></div>
              <button className="primary-button" type="submit">Buat DRAFT Version 1</button>
            </form>
          ) : <div className="empty-state">Role Anda tidak mempunyai FINANCIAL_PRODUCT_CREATE.</div>}
        </aside>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Template Teknis Tersedia</h3>
          <p className="panel-subtitle">Template menyediakan struktur konfigurasi, bukan angka kebijakan.</p>
          <div className="check-list">
            {templates.map((template) => <div className="check-item" key={template.id}><span>{template.name}<small className="item-subtext">{template.code} · {template.description}</small></span><span className="check-state">{template.product_category}</span></div>)}
          </div>
        </article>
        <article className="panel">
          <h3>Control Gate</h3>
          <div className="check-list">
            <div className="check-item"><span>Create DRAFT</span><span className={`check-state ${canCreate ? "" : "pending"}`}>{canCreate ? "ALLOWED" : "DENIED"}</span></div>
            <div className="check-item"><span>Edit DRAFT</span><span className={`check-state ${canEditDraft ? "" : "pending"}`}>{canEditDraft ? "PERMISSION READY" : "DENIED"}</span></div>
            <div className="check-item"><span>Approve product</span><span className={`check-state ${canApprove ? "" : "pending"}`}>{canApprove ? "ALLOWED" : "SEPARATED"}</span></div>
            <div className="check-item"><span>Transaksi Simpan Pinjam</span><span className="check-state pending">NOT ENABLED</span></div>
          </div>
          <div className="empty-state" style={{ marginTop: 18 }}>Manager dapat membuat dan menyusun draft, tetapi approval/activation tetap dipisahkan untuk mencegah self-approval produk finansial.</div>
        </article>
      </section>
    </>
  );
}
