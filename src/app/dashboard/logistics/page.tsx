import { requireAccessContext } from "@/lib/auth/access-context";
import { asLogisticsClient } from "@/types/logistics";

export const dynamic = "force-dynamic";

export default async function LogisticsPage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const canViewAll = permissionCodes.includes("LOGISTICS_VIEW");
  const canViewAssigned = permissionCodes.includes("DELIVERY_ASSIGNED_VIEW");
  const canViewFleet = permissionCodes.includes("FLEET_VIEW");

  if (!canViewAll && !canViewAssigned) {
    return <section className="panel"><h3>Akses logistik tidak tersedia</h3><p className="panel-subtitle">Akun tidak memiliki LOGISTICS_VIEW atau DELIVERY_ASSIGNED_VIEW.</p></section>;
  }

  const organizationId = profile.organization_id;
  if (!organizationId) {
    return <section className="panel"><h3>Organisasi belum terikat</h3><p className="panel-subtitle">Profil harus memiliki organisasi aktif sebelum Logistics Control Center dapat dimuat.</p></section>;
  }

  const db = asLogisticsClient(supabase);
  const [shipmentResult,tripResult,podResult,exceptionResult,eventResult,transitionResult] = await Promise.all([
    db.from("logistics_shipments").select("id,shipment_number,shipment_type,source_domain,source_reference,status,assigned_courier_profile_id,assigned_vehicle_id,planned_dispatch_at,dispatched_at,delivered_at,sync_status,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(50),
    db.from("logistics_route_trips").select("id,trip_number,trip_date,assigned_courier_profile_id,assigned_vehicle_id,status,planned_start_at,actual_start_at,completed_at,planned_distance_km,actual_distance_km,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(30),
    db.from("logistics_pod_evidence").select("id,shipment_id,evidence_version,status,captured_at,recipient_name,finalized_at,reviewed_at,created_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(50),
    db.from("logistics_delivery_exceptions").select("id,shipment_id,exception_code,category,severity,status,occurred_at,resolved_at").eq("organization_id",organizationId).order("occurred_at",{ascending:false}).limit(50),
    db.from("logistics_delivery_events").select("id,shipment_id,event_type,event_at,latitude,longitude,accuracy_m,created_at").eq("organization_id",organizationId).order("event_at",{ascending:false}).limit(50),
    db.from("logistics_status_transition_rules").select("id,from_status,to_status,requires_pod,requires_exception_resolution,status").eq("status","ACTIVE").order("from_status"),
  ]);

  const fleetResult = canViewFleet
    ? await db.from("fleet_vehicles").select("id,vehicle_code,registration_number,vehicle_type,ownership_type,status,current_odometer_km,document_status").eq("organization_id",organizationId).order("vehicle_code")
    : null;
  const maintenanceResult = canViewFleet
    ? await db.from("fleet_maintenance_records").select("id,vehicle_id,maintenance_type,status,planned_date,completed_date,odometer_km,cost_amount,currency").eq("organization_id",organizationId).order("planned_date",{ascending:false}).limit(30)
    : null;

  const shipments=shipmentResult.data??[];
  const trips=tripResult.data??[];
  const pods=podResult.data??[];
  const exceptions=exceptionResult.data??[];
  const events=eventResult.data??[];
  const transitions=transitionResult.data??[];
  const fleet=fleetResult?.data??[];
  const maintenance=maintenanceResult?.data??[];

  const activeShipments=shipments.filter((item)=>["READY","DISPATCHED","IN_TRANSIT","PARTIAL"].includes(item.status));
  const deliveredShipments=shipments.filter((item)=>item.status==="DELIVERED");
  const openExceptions=exceptions.filter((item)=>!["RESOLVED","CLOSED"].includes(item.status));
  const podReviewQueue=pods.filter((item)=>["FINALIZED","REVIEW_REQUIRED"].includes(item.status));
  const activeVehicles=fleet.filter((item)=>item.status==="ACTIVE");
  const maintenanceDue=maintenance.filter((item)=>["PLANNED","IN_PROGRESS"].includes(item.status));
  const canPlan=permissionCodes.includes("LOGISTICS_PLAN");
  const canDispatch=permissionCodes.includes("LOGISTICS_DISPATCH");
  const canCapturePod=permissionCodes.includes("POD_CAPTURE");
  const canReviewPod=permissionCodes.includes("POD_REVIEW");
  const isCourierOnly=!canViewAll&&canViewAssigned;

  return <>
    <section className="page-heading"><div><p className="eyebrow">Logistics & Distribution</p><h1>Logistics Control Center</h1><p>Shipment, route trip, kurir, kendaraan, POD, exception, dan inventory movement dipisahkan tetapi ditautkan. GPS atau foto tidak pernah otomatis berarti pengiriman selesai.</p></div><span className="status-pill">FOUNDATION ACTIVE</span></section>

    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">Pengiriman Aktif</div><div className="metric-value">{activeShipments.length}</div><div className="metric-note">Delivered record terlihat: {deliveredShipments.length}.</div></article>
      <article className="metric-card"><div className="metric-label">Trip / Rute</div><div className="metric-value">{trips.length}</div><div className="metric-note">Scope: {isCourierOnly?"assigned delivery only":"organization/data scope"}.</div></article>
      <article className="metric-card"><div className="metric-label">POD Review</div><div className="metric-value">{podReviewQueue.length}</div><div className="metric-note">Evidence record: {pods.length}.</div></article>
      <article className="metric-card"><div className="metric-label">Exception Terbuka</div><div className="metric-value">{openExceptions.length}</div><div className="metric-note">Tidak boleh hilang lewat edit status diam-diam.</div></article>
    </section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Delivery State Machine</h3><p className="panel-subtitle">Status adalah workflow terkontrol; bukti lapangan adalah evidence, bukan shortcut.</p><div className="check-list">
        <div className="check-item"><span>PLANNED → READY → DISPATCHED</span><span className="check-state">CONTROLLED</span></div>
        <div className="check-item"><span>DISPATCHED → IN_TRANSIT</span><span className="check-state">TRACEABLE EVENT</span></div>
        <div className="check-item"><span>IN_TRANSIT → DELIVERED / PARTIAL</span><span className="check-state pending">POD REQUIRED</span></div>
        <div className="check-item"><span>FAILED / RETURNED</span><span className="check-state pending">EXCEPTION + RETURN FLOW</span></div>
        <div className="check-item"><span>Dispatch / return stock</span><span className="check-state">INVENTORY MOVEMENT</span></div>
      </div></article>
      <article className="panel"><h3>Permission Gate</h3><div className="check-list">
        <div className="check-item"><span>Plan shipment/trip</span><span className={`check-state ${canPlan?"":"pending"}`}>{canPlan?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Dispatch</span><span className={`check-state ${canDispatch?"":"pending"}`}>{canDispatch?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Courier POD capture</span><span className={`check-state ${canCapturePod?"":"pending"}`}>{canCapturePod?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Review POD</span><span className={`check-state ${canReviewPod?"":"pending"}`}>{canReviewPod?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Fleet view</span><span className={`check-state ${canViewFleet?"":"pending"}`}>{canViewFleet?"ASSIGNED":"NOT ASSIGNED"}</span></div>
      </div></article>
    </section>

    <section className="panel section-panel"><h3>Shipment Register</h3><p className="panel-subtitle">Kurir hanya menerima record yang lolos RLS sebagai pengiriman yang ditugaskan kepadanya.</p>{shipments.length?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Shipment</th><th>Tipe</th><th>Status</th><th>Kurir</th><th>POD</th><th>Exception</th><th>Sync</th></tr></thead><tbody>{shipments.map((shipment)=><tr key={shipment.id}><td>{shipment.shipment_number??"-"}<small className="item-subtext">{shipment.source_domain} · {shipment.source_reference??"no source ref"}</small></td><td>{shipment.shipment_type}</td><td>{shipment.status}</td><td>{shipment.assigned_courier_profile_id?"ASSIGNED":"—"}</td><td>{pods.filter((pod)=>pod.shipment_id===shipment.id).length}</td><td>{exceptions.filter((item)=>item.shipment_id===shipment.id&&!["RESOLVED","CLOSED"].includes(item.status)).length}</td><td>{shipment.sync_status}</td></tr>)}</tbody></table></div>:<div className="empty-state">Belum ada shipment DEVELOPMENT. Tidak ada pengiriman atau GPS DEMO yang dipalsukan.</div>}</section>

    <section className="dashboard-grid">
      <article className="panel"><h3>POD Evidence</h3><p className="panel-subtitle">Setelah FINALIZED, konten bukti terkunci. Reviewer hanya menambahkan keputusan/review metadata; koreksi bukti membuat version baru.</p>{pods.length?<div className="check-list">{pods.map((pod)=><div className="check-item" key={pod.id}><span>Evidence v{pod.evidence_version}<small className="item-subtext">Recipient: {pod.recipient_name??"belum diisi"}</small></span><span className="check-state pending">{pod.status}</span></div>)}</div>:<div className="empty-state">Belum ada POD evidence.</div>}</article>
      <article className="panel"><h3>Delivery Exceptions</h3><p className="panel-subtitle">Alamat, penerima, kendaraan, barang, cuaca, dokumen, payment, atau security issue masuk case terpisah.</p>{exceptions.length?<div className="check-list">{exceptions.map((item)=><div className="check-item" key={item.id}><span>{item.exception_code}<small className="item-subtext">{item.category} · {item.severity}</small></span><span className="check-state pending">{item.status}</span></div>)}</div>:<div className="empty-state">Tidak ada delivery exception.</div>}</article>
    </section>

    {canViewFleet?<section className="dashboard-grid"><article className="panel"><h3>Fleet Readiness</h3><p className="panel-subtitle">Kendaraan adalah master terpisah dari shipment; satu kendaraan dapat digunakan pada banyak trip sepanjang lifecycle-nya.</p>{fleet.length?<div className="check-list">{fleet.map((vehicle)=><div className="check-item" key={vehicle.id}><span>{vehicle.vehicle_code}<small className="item-subtext">{vehicle.vehicle_type} · {vehicle.registration_number??"nomor belum diisi"}</small></span><span className="check-state pending">{vehicle.status} / {vehicle.document_status}</span></div>)}</div>:<div className="empty-state">0 kendaraan DEVELOPMENT. Tidak ada armada fiktif.</div>}</article><article className="panel"><h3>Maintenance Control</h3><p className="panel-subtitle">Maintenance tidak dicampur dengan transaksi delivery.</p><div className="metric-value">{maintenanceDue.length}</div><p className="panel-subtitle">maintenance PLANNED/IN_PROGRESS dari {maintenance.length} record terlihat.</p></article></section>:null}

    <section className="panel section-panel"><h3>Traceability & Offline Safety</h3><div className="check-list">
      <div className="check-item"><span>Delivery events</span><span className="check-state">APPEND-ONLY · {events.length} RECORD</span></div>
      <div className="check-item"><span>Finalized POD content</span><span className="check-state">IMMUTABLE</span></div>
      <div className="check-item"><span>Courier offline capture</span><span className="check-state pending">PENDING / FAILED / CONFLICT QUEUE</span></div>
      <div className="check-item"><span>GPS proximity = delivered</span><span className="check-state">TIDAK DIIZINKAN</span></div>
      <div className="check-item"><span>Active transition rules</span><span className="check-state">{transitions.length} RULE</span></div>
    </div></section>
  </>;
}
