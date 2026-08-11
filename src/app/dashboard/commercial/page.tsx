import { requireAccessContext } from "@/lib/auth/access-context";
import { asCommercialClient } from "@/types/commercial";

export const dynamic = "force-dynamic";

export default async function CommercialPage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  if (!permissionCodes.includes("SALES_VIEW")) return <section className="panel"><h3>Akses penjualan tidak tersedia</h3><p className="panel-subtitle">Akun tidak memiliki SALES_VIEW.</p></section>;
  const db=asCommercialClient(supabase);
  const organizationId=profile.organization_id;
  const canOrders=permissionCodes.includes("SALES_ORDER_VIEW");
  const canShift=permissionCodes.includes("POS_SHIFT_VIEW");
  const [terminalResult,shiftResult,salesResult,ordersResult,fulfillmentResult,returnResult,retailWarehouseResult] = await Promise.all([
    organizationId?db.from("pos_terminals").select("id,organization_unit_id,code,name,device_reference,default_warehouse_id,status").eq("organization_id",organizationId).order("code"):Promise.resolve({data:[],error:null}),
    canShift&&organizationId?db.from("pos_shifts").select("id,terminal_id,shift_number,status,opened_at,closed_at,opening_cash,expected_cash,counted_cash,cash_variance,reconciliation_status").eq("organization_id",organizationId).order("opened_at",{ascending:false}).limit(30):Promise.resolve({data:[],error:null}),
    organizationId?db.from("sales_transactions").select("id,terminal_id,pos_shift_id,sale_number,sale_type,currency,total_amount,status,payment_intent_id,inventory_movement_id,journal_entry_id,sync_status,sold_at,completed_at,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(50):Promise.resolve({data:[],error:null}),
    canOrders&&organizationId?db.from("sales_orders").select("id,order_number,channel,currency,requested_delivery_date,status,payment_intent_id,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40):Promise.resolve({data:[],error:null}),
    canOrders&&organizationId?db.from("fulfillment_orders").select("id,sales_order_id,fulfillment_number,warehouse_id,status,inventory_movement_id,assigned_courier_profile_id,dispatched_at,delivered_at,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40):Promise.resolve({data:[],error:null}),
    organizationId?db.from("sales_returns").select("id,original_sale_id,return_number,reason_code,status,approval_request_id,inventory_movement_id,payment_intent_id,journal_entry_id,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(40):Promise.resolve({data:[],error:null}),
    organizationId?db.from("warehouses").select("id,code,name,warehouse_type,status,organization_unit_id").eq("organization_id",organizationId).eq("warehouse_type","RETAIL_BACKROOM").order("code"):Promise.resolve({data:[],error:null}),
  ]);
  const terminals=terminalResult.data??[]; const shifts=shiftResult.data??[]; const sales=salesResult.data??[]; const orders=ordersResult.data??[]; const fulfillments=fulfillmentResult.data??[]; const returns=returnResult.data??[]; const retailWarehouses=retailWarehouseResult.data??[];
  const terminalById=new Map(terminals.map((t)=>[t.id,t]));
  const openShifts=shifts.filter((s)=>["OPEN","CLOSING","RECONCILIATION_EXCEPTION"].includes(s.status));
  const completedSales=sales.filter((s)=>s.status==="COMPLETED");
  const pendingSales=sales.filter((s)=>["DRAFT","PAYMENT_PENDING","PAID","FULFILLMENT_PENDING"].includes(s.status));
  const canCreate=permissionCodes.includes("SALES_CREATE"); const canVoid=permissionCodes.includes("SALES_VOID"); const canReturn=permissionCodes.includes("SALES_RETURN"); const canManageShift=permissionCodes.includes("POS_SHIFT_MANAGE");

  return <>
    <section className="page-heading"><div><p className="eyebrow">Commercial & POS</p><h1>Commercial & POS Control Center</h1><p>POS, Sales Order, Payment, Inventory, Accounting, dan shift close dipisahkan tetapi ditautkan. Memilih channel pembayaran tidak pernah sama dengan pembayaran terkonfirmasi.</p></div><span className="status-pill">FOUNDATION ACTIVE</span></section>
    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">POS Terminal</div><div className="metric-value">{terminals.length}</div><div className="metric-note">Retail stock location: {retailWarehouses.length}.</div></article>
      <article className="metric-card"><div className="metric-label">Shift Open</div><div className="metric-value">{openShifts.length}</div><div className="metric-note">{shifts.length} shift record terlihat.</div></article>
      <article className="metric-card"><div className="metric-label">Completed Sales</div><div className="metric-value">{completedSales.length}</div><div className="metric-note">Pending/draft: {pendingSales.length}.</div></article>
      <article className="metric-card"><div className="metric-label">Sales Order</div><div className="metric-value">{orders.length}</div><div className="metric-note">Fulfillment: {fulfillments.length}.</div></article>
    </section>
    <section className="dashboard-grid">
      <article className="panel"><h3>POS Completion Gate</h3><p className="panel-subtitle">Sale COMPLETED harus menghasilkan jejak lintas domain, bukan hanya receipt UI.</p><div className="check-list">
        <div className="check-item"><span>Sale draft + item snapshot</span><span className="check-state">COMMERCIAL</span></div>
        <div className="check-item"><span>Payment intent</span><span className="check-state pending">PAYMENT ORCHESTRATION</span></div>
        <div className="check-item"><span>Payment confirmed/settled sesuai policy</span><span className="check-state pending">PROVIDER / CASH RECON</span></div>
        <div className="check-item"><span>Stock issue</span><span className="check-state pending">INVENTORY MOVEMENT</span></div>
        <div className="check-item"><span>Revenue + COGS journal</span><span className="check-state pending">ACCOUNTING EVENT</span></div>
        <div className="check-item"><span>Completed sale</span><span className="check-state">IMMUTABLE</span></div>
      </div></article>
      <article className="panel"><h3>Permission Gate</h3><div className="check-list">
        <div className="check-item"><span>Create sale</span><span className={`check-state ${canCreate?"":"pending"}`}>{canCreate?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Manage shift</span><span className={`check-state ${canManageShift?"":"pending"}`}>{canManageShift?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Void sale</span><span className="check-state pending">{canVoid?"ASSIGNED — CONTROL FLOW REQUIRED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Return sale</span><span className="check-state pending">{canReturn?"ASSIGNED — APPROVAL REQUIRED":"NOT ASSIGNED"}</span></div>
      </div></article>
    </section>
    <section className="panel section-panel"><h3>Terminal & Retail Stock Location</h3><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Terminal</th><th>Device</th><th>Warehouse</th><th>Status</th></tr></thead><tbody>{terminals.map((terminal)=><tr key={terminal.id}><td>{terminal.code} · {terminal.name}</td><td>{terminal.device_reference??"Belum terikat"}</td><td>{retailWarehouses.find((w)=>w.id===terminal.default_warehouse_id)?.name??"Belum dikonfigurasi"}</td><td>{terminal.status}</td></tr>)}</tbody></table></div></section>
    <section className="dashboard-grid">
      <article className="panel"><h3>POS Shift & Daily Close</h3><p className="panel-subtitle">Opening cash, expected cash, counted cash, dan variance dipisahkan. Selisih tidak boleh dihapus dengan edit angka.</p>{shifts.length?<div className="check-list">{shifts.map((shift)=><div className="check-item" key={shift.id}><span>{shift.shift_number??"Shift"}<small className="item-subtext">{terminalById.get(shift.terminal_id)?.code??"POS"} · variance {shift.cash_variance??"-"}</small></span><span className="check-state pending">{shift.status} / {shift.reconciliation_status}</span></div>)}</div>:<div className="empty-state">Belum ada shift POS. Tidak ada kas/penjualan DEMO yang dipalsukan.</div>}</article>
      <article className="panel"><h3>Sales Order ≠ POS</h3><p className="panel-subtitle">Pesanan non-counter punya allocation/fulfillment sendiri dan dapat memakai kurir/POD tanpa mencampurnya ke transaksi kasir.</p>{orders.length?<div className="check-list">{orders.map((order)=><div className="check-item" key={order.id}><span>{order.order_number??"Sales Order"}<small className="item-subtext">{order.channel} · fulfillment {fulfillments.filter((f)=>f.sales_order_id===order.id).length}</small></span><span className="check-state pending">{order.status}</span></div>)}</div>:<div className="empty-state">Belum ada Sales Order DEVELOPMENT.</div>}</article>
    </section>
    <section className="panel section-panel"><h3>Sales Register</h3>{sales.length?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Sale</th><th>Status</th><th>Payment</th><th>Inventory</th><th>Accounting</th><th>Sync</th></tr></thead><tbody>{sales.map((sale)=><tr key={sale.id}><td>{sale.sale_number??"-"}</td><td>{sale.status}</td><td>{sale.payment_intent_id?"LINKED":"—"}</td><td>{sale.inventory_movement_id?"LINKED":"—"}</td><td>{sale.journal_entry_id?"LINKED":"—"}</td><td>{sale.sync_status}</td></tr>)}</tbody></table></div>:<div className="empty-state">0 transaksi penjualan. Dashboard tidak menampilkan omzet/KPI palsu.</div>}</section>
    <section className="panel section-panel"><h3>Offline & Reversal Safety</h3><div className="check-list">
      <div className="check-item"><span>Offline sale draft</span><span className="check-state">IDEMPOTENT QUEUE READY</span></div>
      <div className="check-item"><span>Offline payment confirmation</span><span className="check-state">TIDAK DIIZINKAN</span></div>
      <div className="check-item"><span>Edit completed sale/items</span><span className="check-state">TIDAK DIIZINKAN</span></div>
      <div className="check-item"><span>Void / return</span><span className="check-state pending">CONTROLLED REVERSAL FLOW</span></div>
      <div className="check-item"><span>Receipt</span><span className="check-state">TRACEABLE REFERENCE</span></div>
    </div><p className="panel-subtitle" style={{marginTop:14}}>Return records: {returns.length}.</p></section>
  </>;
}
