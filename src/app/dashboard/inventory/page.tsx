import { requireAccessContext } from "@/lib/auth/access-context";
import { getInventoryDashboardSnapshot } from "@/lib/inventory/dashboard-snapshot";

export const dynamic = "force-dynamic";

export default async function InventoryPage() {
  const { permissionCodes, supabase } = await requireAccessContext();
  if (!permissionCodes.includes("INVENTORY_VIEW")) {
    return <section className="panel"><h3>Akses persediaan tidak tersedia</h3><p className="panel-subtitle">Akun tidak memiliki INVENTORY_VIEW.</p></section>;
  }

  const { data: snapshot, error: snapshotError } = await getInventoryDashboardSnapshot(supabase);
  if (snapshotError || !snapshot) {
    return <section className="panel"><h3>Data persediaan belum dapat dimuat</h3><p className="panel-subtitle">Snapshot persediaan gagal dibaca. Tidak ada data fallback lintas-scope yang digunakan.</p></section>;
  }

  const { warehouses, nodes, items, uoms, lots, movements, positions, reservations, counts, mappings } = snapshot;
  const uomById=new Map(uoms.map((uom)=>[uom.id,uom.code]));
  const nodeById=new Map(nodes.map((node)=>[node.id,node]));
  const itemById=new Map(items.map((item)=>[item.id,item]));
  const postedMovements=movements.filter((movement)=>movement.status==="POSTED");
  const activeReservations=reservations.filter((reservation)=>reservation.status==="ACTIVE");
  const activeCounts=counts.filter((count)=>!["POSTED","CANCELLED"].includes(count.status));
  const mappedEvents=mappings.filter((mapping)=>["MAPPED","NO_GL_REQUIRED"].includes(mapping.mapping_status));
  const canReceive=permissionCodes.includes("INVENTORY_RECEIVE");
  const canTransfer=permissionCodes.includes("INVENTORY_TRANSFER");
  const canCount=permissionCodes.includes("STOCK_OPNAME");
  const canAdjust=permissionCodes.includes("INVENTORY_ADJUST");

  return <>
    <section className="page-heading"><div><p className="eyebrow">Inventory & Warehouse</p><h1>Inventory & Warehouse Control Center</h1><p>Fondasi persediaan berbasis movement ledger. Tidak ada angka stok yang boleh diedit langsung; saldo berasal dari movement POSTED, reservation dipisahkan, dan selisih stock opname harus menjadi adjustment movement yang disetujui.</p></div><span className="status-pill">FOUNDATION ACTIVE</span></section>

    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">Gudang</div><div className="metric-value">{warehouses.length}</div><div className="metric-note">{nodes.length} zone/location/bin terdaftar.</div></article>
      <article className="metric-card"><div className="metric-label">Master SKU</div><div className="metric-value">{items.length}</div><div className="metric-note">{lots.length} lot/batch tercatat.</div></article>
      <article className="metric-card"><div className="metric-label">Stock Position</div><div className="metric-value">{positions.length}</div><div className="metric-note">Saat ini harus 0 sampai ada movement POSTED.</div></article>
      <article className="metric-card"><div className="metric-label">Movement Posted</div><div className="metric-value">{postedMovements.length}</div><div className="metric-note">{movements.length} movement total terlihat.</div></article>
    </section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Struktur Gudang</h3><p className="panel-subtitle">Hierarki wajib: Warehouse → Zone → Location → Bin.</p>{warehouses.map((warehouse)=><div className="check-list" key={warehouse.id}><div className="check-item"><span><strong>{warehouse.name}</strong><small className="item-subtext">{warehouse.code} · {warehouse.warehouse_type}</small></span><span className="check-state">{warehouse.status}</span></div>{nodes.filter((node)=>node.warehouse_id===warehouse.id).map((node)=>{const parent=node.parent_id?nodeById.get(node.parent_id):null;return <div className="check-item" key={node.id}><span>{node.node_type} · {node.name}<small className="item-subtext">{node.code}{parent?` · parent ${parent.code}`:""}</small></span><span className="check-state">{node.status}</span></div>;})}</div>)}</article>
      <article className="panel"><h3>Permission Gate</h3><p className="panel-subtitle">Permission operasional sudah dipisah dari adjustment stok.</p><div className="check-list">
        <div className="check-item"><span>Inventory view</span><span className="check-state">ALLOWED</span></div>
        <div className="check-item"><span>Receive</span><span className={`check-state ${canReceive?"":"pending"}`}>{canReceive?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Transfer</span><span className={`check-state ${canTransfer?"":"pending"}`}>{canTransfer?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Stock opname</span><span className={`check-state ${canCount?"":"pending"}`}>{canCount?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Direct adjustment</span><span className="check-state pending">{canAdjust?"PERMISSION EXISTS — APPROVAL STILL REQUIRED":"NOT ASSIGNED"}</span></div>
      </div></article>
    </section>

    <section className="panel section-panel"><h3>Master Barang / SKU</h3><p className="panel-subtitle">DEMO master saja; belum ada kuantitas stok palsu.</p><div className="data-table-wrap"><table className="data-table"><thead><tr><th>SKU</th><th>Nama</th><th>UOM</th><th>Tracking</th><th>Expiry</th><th>Costing</th><th>Picking</th><th>Status</th></tr></thead><tbody>{items.map((item)=><tr key={item.id}><td>{item.sku}</td><td>{item.name}</td><td>{uomById.get(item.base_uom_id)??"-"}</td><td>{item.tracking_type}</td><td>{item.expiry_control?"YA":"TIDAK"}</td><td>{item.costing_method}</td><td>{item.picking_policy}</td><td>{item.status}</td></tr>)}</tbody></table></div></section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Stock State & Reservation</h3><p className="panel-subtitle">AVAILABLE, QUARANTINE, DAMAGED, EXPIRED, dan IN_TRANSIT dipisahkan; reservation tidak mengubah stok fisik.</p>{positions.length?<div className="check-list">{positions.slice(0,20).map((position,index)=><div className="check-item" key={`${position.warehouse_node_id}-${position.inventory_item_id}-${index}`}><span>{itemById.get(position.inventory_item_id)?.name??position.inventory_item_id}<small className="item-subtext">{nodeById.get(position.warehouse_node_id)?.code??"?"} · {position.stock_status}</small></span><span className="check-state">{position.quantity} / available {position.available_to_allocate}</span></div>)}</div>:<div className="empty-state">Belum ada stock position karena belum ada movement POSTED. Ini kondisi yang benar untuk DEVELOPMENT.</div>}<p className="panel-subtitle" style={{marginTop:16}}>Active reservation: {activeReservations.length}</p></article>
      <article className="panel"><h3>Stock Opname</h3><p className="panel-subtitle">System quantity disnapshot, physical quantity dicatat, variance direview, lalu adjustment dibuat sebagai movement baru.</p>{counts.length?<div className="check-list">{counts.map((count)=><div className="check-item" key={count.id}><span>{count.count_number??"Count session"}<small className="item-subtext">{count.scope_description??"Scope belum diisi"}</small></span><span className="check-state pending">{count.status}</span></div>)}</div>:<div className="empty-state">Belum ada stock count session. Active count: {activeCounts.length}.</div>}</article>
    </section>

    <section className="panel section-panel"><h3>Accounting Event Mapping</h3><p className="panel-subtitle">Movement yang memengaruhi nilai persediaan harus mempunyai jalur accounting; transfer internal dapat NO_GL_REQUIRED.</p><div className="data-table-wrap"><table className="data-table"><thead><tr><th>Movement</th><th>Accounting Event</th><th>Status</th></tr></thead><tbody>{mappings.map((mapping)=><tr key={mapping.id}><td>{mapping.movement_type}</td><td>{mapping.accounting_event_code??"—"}</td><td>{mapping.mapping_status}</td></tr>)}</tbody></table></div><p className="panel-subtitle" style={{marginTop:14}}>Readiness: {mappedEvents.length}/{mappings.length} mapping memiliki status MAPPED atau NO_GL_REQUIRED.</p></section>

    <section className="panel section-panel"><h3>Safety Rules</h3><div className="check-list">
      <div className="check-item"><span>Direct overwrite saldo stok</span><span className="check-state">TIDAK TERSEDIA</span></div>
      <div className="check-item"><span>Posted movement mutation</span><span className="check-state">IMMUTABLE</span></div>
      <div className="check-item"><span>Correction</span><span className="check-state pending">REVERSAL / NEW MOVEMENT</span></div>
      <div className="check-item"><span>Stock opname variance</span><span className="check-state pending">APPROVAL → ADJUSTMENT MOVEMENT</span></div>
      <div className="check-item"><span>Cost valuation</span><span className="check-state">CONFIGURABLE PER SKU</span></div>
      <div className="check-item"><span>Expiry picking</span><span className="check-state">FEFO SUPPORTED</span></div>
    </div></section>
  </>;
}
