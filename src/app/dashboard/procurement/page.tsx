import { requireAccessContext } from "@/lib/auth/access-context";
import { asProcurementClient } from "@/types/procurement";

export const dynamic = "force-dynamic";

export default async function ProcurementPage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const canView = permissionCodes.includes("PURCHASE_VIEW");
  if (!canView) return <section className="panel"><h3>Akses procurement tidak tersedia</h3><p className="panel-subtitle">Akun tidak memiliki PURCHASE_VIEW.</p></section>;

  const db = asProcurementClient(supabase);
  const organizationId = profile.organization_id;
  const canViewSuppliers = permissionCodes.includes("SUPPLIER_VIEW");
  const canViewInvoices = permissionCodes.includes("PURCHASE_INVOICE_VIEW");
  const canMatch = permissionCodes.includes("PURCHASE_MATCH");
  const [suppliersResult,reqResult,poResult,receiptResult,invoiceResult,matchResult,grniResult] = await Promise.all([
    canViewSuppliers && organizationId ? db.from("suppliers").select("id,code,name,supplier_type,qualification_status,risk_status,regulatory_status,status,notes").eq("organization_id",organizationId).order("code") : Promise.resolve({data:[],error:null}),
    organizationId ? db.from("purchase_requisitions").select("id,requisition_number,purpose,required_date,status,submitted_at,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40) : Promise.resolve({data:[],error:null}),
    organizationId ? db.from("purchase_orders").select("id,supplier_id,po_number,version_no,currency,expected_delivery_date,status,approved_at,sent_at,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40) : Promise.resolve({data:[],error:null}),
    organizationId ? db.from("goods_receipts").select("id,supplier_id,purchase_order_id,receipt_number,supplier_delivery_reference,received_at,status,accounting_status,inventory_movement_id,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40) : Promise.resolve({data:[],error:null}),
    canViewInvoices && organizationId ? db.from("supplier_invoices").select("id,supplier_id,purchase_order_id,invoice_number,invoice_date,due_date,currency,total_amount,status,matching_status,created_at").eq("organization_id",organizationId).order("invoice_date",{ascending:false}).limit(40) : Promise.resolve({data:[],error:null}),
    canMatch && organizationId ? db.from("purchase_match_results").select("id,supplier_invoice_id,purchase_order_id,match_type,status,po_amount,received_value,invoice_amount,quantity_variance,amount_variance,exception_codes,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40) : Promise.resolve({data:[],error:null}),
    organizationId ? db.from("accounting_accounts").select("id,code,name,control_purpose,status").eq("organization_id",organizationId).eq("control_purpose","GRNI").limit(5) : Promise.resolve({data:[],error:null}),
  ]);

  const suppliers=suppliersResult.data??[];
  const requisitions=reqResult.data??[];
  const orders=poResult.data??[];
  const receipts=receiptResult.data??[];
  const invoices=invoiceResult.data??[];
  const matches=matchResult.data??[];
  const grniAccounts=grniResult.data??[];
  const supplierById=new Map(suppliers.map((supplier)=>[supplier.id,supplier]));
  const pendingSupplierQualification=suppliers.filter((supplier)=>supplier.qualification_status!=="QUALIFIED");
  const openRequisitions=requisitions.filter((item)=>!["REJECTED","CANCELLED","CONVERTED"].includes(item.status));
  const openOrders=orders.filter((item)=>!["CLOSED","CANCELLED"].includes(item.status));
  const receiptExceptions=receipts.filter((item)=>["REJECTED"].includes(item.status)||item.accounting_status==="EXCEPTION");
  const matchExceptions=matches.filter((item)=>item.status==="EXCEPTION");
  const canCreate=permissionCodes.includes("PURCHASE_CREATE");
  const canSubmit=permissionCodes.includes("PURCHASE_SUBMIT");
  const canApprove=permissionCodes.includes("PURCHASE_APPROVE");
  const canReceive=permissionCodes.includes("PURCHASE_RECEIVE");

  return <>
    <section className="page-heading"><div><p className="eyebrow">Procurement</p><h1>Procurement Control Center</h1><p>Fondasi pengadaan dari permintaan sampai penerimaan, invoice, dan three-way match. Receiving terhubung ke Inventory Movement; pembayaran tidak boleh melewati invoice, matching, approval, dan accounting controls.</p></div><span className="status-pill">FOUNDATION ACTIVE</span></section>

    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">Supplier</div><div className="metric-value">{suppliers.length}</div><div className="metric-note">{pendingSupplierQualification.length} belum QUALIFIED.</div></article>
      <article className="metric-card"><div className="metric-label">Requisition Open</div><div className="metric-value">{openRequisitions.length}</div><div className="metric-note">{requisitions.length} requisition terlihat.</div></article>
      <article className="metric-card"><div className="metric-label">PO Open</div><div className="metric-value">{openOrders.length}</div><div className="metric-note">{orders.length} PO total.</div></article>
      <article className="metric-card"><div className="metric-label">Match Exception</div><div className="metric-value">{matchExceptions.length}</div><div className="metric-note">Receipt exception: {receiptExceptions.length}.</div></article>
    </section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Procure-to-Pay Gate</h3><p className="panel-subtitle">Urutan transaksi tidak boleh dipotong.</p><div className="check-list">
        <div className="check-item"><span>Permintaan kebutuhan</span><span className="check-state">REQUISITION</span></div>
        <div className="check-item"><span>Review & approval</span><span className="check-state pending">APPROVAL ENGINE</span></div>
        <div className="check-item"><span>Purchase Order</span><span className="check-state">VERSIONED SNAPSHOT</span></div>
        <div className="check-item"><span>Supplier delivery → Receiving/QC</span><span className="check-state pending">INVENTORY MOVEMENT</span></div>
        <div className="check-item"><span>Barang diterima sebelum invoice</span><span className="check-state">GRNI</span></div>
        <div className="check-item"><span>Invoice → Three-way match</span><span className="check-state pending">PO / RECEIPT / INVOICE</span></div>
        <div className="check-item"><span>Payment</span><span className="check-state pending">ONLY AFTER CONTROLS</span></div>
      </div></article>

      <article className="panel"><h3>Permission Gate</h3><p className="panel-subtitle">Approval tetap dipisahkan dari create/receive/match.</p><div className="check-list">
        <div className="check-item"><span>Create purchase</span><span className={`check-state ${canCreate?"":"pending"}`}>{canCreate?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Submit purchase</span><span className={`check-state ${canSubmit?"":"pending"}`}>{canSubmit?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Approve purchase</span><span className="check-state pending">{canApprove?"ASSIGNED — POLICY STILL REQUIRED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Receive/QC</span><span className={`check-state ${canReceive?"":"pending"}`}>{canReceive?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Three-way match</span><span className={`check-state ${canMatch?"":"pending"}`}>{canMatch?"ASSIGNED":"NOT ASSIGNED"}</span></div>
      </div></article>
    </section>

    <section className="panel section-panel"><h3>Supplier Master</h3><p className="panel-subtitle">DEMO supplier belum dianggap qualified hanya karena master record tersedia.</p><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Kode</th><th>Supplier</th><th>Tipe</th><th>Qualification</th><th>Risk</th><th>Regulatory</th><th>Status</th></tr></thead><tbody>{suppliers.map((supplier)=><tr key={supplier.id}><td>{supplier.code}</td><td>{supplier.name}</td><td>{supplier.supplier_type}</td><td>{supplier.qualification_status}</td><td>{supplier.risk_status}</td><td>{supplier.regulatory_status}</td><td>{supplier.status}</td></tr>)}</tbody></table></div></section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Receiving & QC</h3><p className="panel-subtitle">Accepted stock baru boleh menghasilkan Inventory Movement; rejected/quarantine tetap terpisah.</p>{receipts.length?<div className="check-list">{receipts.map((receipt)=><div className="check-item" key={receipt.id}><span>{receipt.receipt_number??"Receipt"}<small className="item-subtext">{supplierById.get(receipt.supplier_id)?.name??"Supplier"} · Accounting {receipt.accounting_status}</small></span><span className="check-state pending">{receipt.status}</span></div>)}</div>:<div className="empty-state">Belum ada goods receipt. Tidak ada stok pembelian DEMO yang dipalsukan.</div>}</article>
      <article className="panel"><h3>GRNI Control</h3><p className="panel-subtitle">Barang diterima boleh mendahului invoice; liability sementara tidak langsung dipaksakan menjadi AP supplier.</p>{grniAccounts.length?<div className="check-list">{grniAccounts.map((account)=><div className="check-item" key={account.id}><span>{account.code} · {account.name}<small className="item-subtext">Control purpose: {account.control_purpose}</small></span><span className="check-state">{account.status}</span></div>)}</div>:<div className="empty-state">GRNI account belum dikonfigurasi.</div>}</article>
    </section>

    <section className="panel section-panel"><h3>Purchase & Invoice Register</h3><p className="panel-subtitle">Development saat ini sengaja belum mempunyai transaksi purchase finansial.</p>{orders.length||invoices.length?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Dokumen</th><th>Supplier</th><th>Status</th><th>Match</th><th>Nilai</th></tr></thead><tbody>{orders.map((order)=><tr key={`po-${order.id}`}><td>PO · {order.po_number??"-"} v{order.version_no}</td><td>{supplierById.get(order.supplier_id)?.name??"-"}</td><td>{order.status}</td><td>—</td><td>{order.currency}</td></tr>)}{invoices.map((invoice)=><tr key={`inv-${invoice.id}`}><td>Invoice · {invoice.invoice_number}</td><td>{supplierById.get(invoice.supplier_id)?.name??"-"}</td><td>{invoice.status}</td><td>{invoice.matching_status}</td><td>{invoice.currency} {invoice.total_amount}</td></tr>)}</tbody></table></div>:<div className="empty-state">Requisition: {requisitions.length} · PO: {orders.length} · Receipt: {receipts.length} · Invoice: {invoices.length} · Match: {matches.length}.</div>}</section>

    <section className="panel section-panel"><h3>Control Rules</h3><div className="check-list">
      <div className="check-item"><span>Approved/Sent PO content</span><span className="check-state">IMMUTABLE</span></div>
      <div className="check-item"><span>PO lifecycle status</span><span className="check-state">CONTROLLED TRANSITION</span></div>
      <div className="check-item"><span>Receiving stock</span><span className="check-state pending">INVENTORY MOVEMENT ONLY</span></div>
      <div className="check-item"><span>Invoice sebelum barang</span><span className="check-state pending">MATCH / POLICY REVIEW</span></div>
      <div className="check-item"><span>Barang sebelum invoice</span><span className="check-state">GRNI SUPPORTED</span></div>
      <div className="check-item"><span>Payment tanpa match/approval</span><span className="check-state">BLOCKED BY DESIGN</span></div>
    </div></section>
  </>;
}
