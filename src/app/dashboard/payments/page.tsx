import { requireAccessContext } from "@/lib/auth/access-context";
import { asPaymentClient } from "@/types/payments";

export const dynamic = "force-dynamic";

export default async function PaymentsPage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();
  const canViewPayments = permissionCodes.includes("PAYMENT_VIEW");
  const canViewTeller = permissionCodes.includes("TELLER_SESSION_VIEW");

  if (!canViewPayments && !canViewTeller) {
    return <section className="panel"><h3>Akses pembayaran tidak tersedia</h3><p className="panel-subtitle">Akun tidak memiliki PAYMENT_VIEW/TELLER_SESSION_VIEW.</p></section>;
  }

  const db = asPaymentClient(supabase);
  const organizationId = profile.organization_id;
  const [providersResult,sessionsResult,intentsResult,attemptsResult,eventsResult,cashResult,settlementsResult] = await Promise.all([
    canViewPayments && organizationId ? db.from("payment_provider_configs").select("id,code,provider_type,provider_name,supported_channels,config_status,status,notes").eq("organization_id",organizationId).order("code") : Promise.resolve({data:[],error:null}),
    canViewTeller && organizationId ? db.from("teller_sessions").select("id,session_number,business_date,opening_cash,expected_closing_cash,actual_closing_cash,variance_amount,status,opened_at,closed_at").eq("organization_id",organizationId).order("business_date",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
    canViewPayments && organizationId ? db.from("payment_intents").select("id,intent_number,business_purpose,source_domain,source_reference,amount,currency,status,created_at,confirmed_at,settled_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
    canViewPayments && organizationId ? db.from("payment_attempts").select("id,payment_intent_id,attempt_no,channel,amount,currency,status,provider_reference,failure_code,created_at,confirmed_at,settled_at").eq("organization_id",organizationId).order("created_at",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
    canViewPayments && organizationId ? db.from("payment_external_events").select("id,event_type,received_at,signature_validation_status,processing_status,error_message").eq("organization_id",organizationId).order("received_at",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
    canViewTeller && organizationId ? db.from("cash_movements").select("id,movement_type,direction,amount,currency,receipt_number,accounting_status,occurred_at").eq("organization_id",organizationId).order("occurred_at",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
    permissionCodes.includes("PAYMENT_RECONCILE") && organizationId ? db.from("payment_settlement_batches").select("id,settlement_reference,settlement_date,currency,gross_amount,fee_amount,net_amount,status,received_at,reconciled_at").eq("organization_id",organizationId).order("settlement_date",{ascending:false}).limit(30) : Promise.resolve({data:[],error:null}),
  ]);

  const providers=providersResult.data??[];
  const sessions=sessionsResult.data??[];
  const intents=intentsResult.data??[];
  const attempts=attemptsResult.data??[];
  const events=eventsResult.data??[];
  const cashMovements=cashResult.data??[];
  const settlements=settlementsResult.data??[];
  const validatedProviders=providers.filter((item)=>item.status==="ACTIVE"&&item.config_status==="VALIDATED");
  const openSessions=sessions.filter((item)=>item.status==="OPEN");
  const pendingIntents=intents.filter((item)=>["CREATED","PENDING","CONFIRMED","SETTLEMENT_PENDING"].includes(item.status));
  const exceptionSettlements=settlements.filter((item)=>item.status==="EXCEPTION");
  const canManageSession=permissionCodes.includes("TELLER_SESSION_MANAGE");
  const canCreatePayment=permissionCodes.includes("PAYMENT_CREATE");
  const canApprovePayment=permissionCodes.includes("PAYMENT_APPROVE");
  const canReconcile=permissionCodes.includes("PAYMENT_RECONCILE");

  return <>
    <section className="page-heading"><div><p className="eyebrow">Payment Orchestration</p><h1>Teller & Payment Control Center</h1><p>Fondasi pembayaran untuk kas/teller, transfer bank, dan QRIS. Tidak ada channel yang boleh dianggap berhasil hanya karena dipilih di UI; ledger baru boleh diposting setelah konfirmasi/settlement yang sah dan control gate domain terpenuhi.</p></div><span className="status-pill">EXECUTION BLOCKED</span></section>

    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">Provider</div><div className="metric-value">{providers.length}</div><div className="metric-note">{validatedProviders.length} ACTIVE + VALIDATED.</div></article>
      <article className="metric-card"><div className="metric-label">Teller Session Open</div><div className="metric-value">{openSessions.length}</div><div className="metric-note">Dari {sessions.length} session yang terlihat.</div></article>
      <article className="metric-card"><div className="metric-label">Payment Intent</div><div className="metric-value">{intents.length}</div><div className="metric-note">{pendingIntents.length} belum selesai.</div></article>
      <article className="metric-card"><div className="metric-label">Settlement Exception</div><div className="metric-value">{exceptionSettlements.length}</div><div className="metric-note">Provider settlement reconciliation.</div></article>
    </section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Channel Readiness</h3><p className="panel-subtitle">Adapter metadata ada, tetapi provider belum dikonfigurasi/diaktifkan.</p><div className="check-list">{providers.map((provider)=><div className="check-item" key={provider.id}><span>{provider.provider_name}<small className="item-subtext">{provider.provider_type} · {provider.supported_channels.join(", ")||"no channel"}</small></span><span className="check-state pending">{provider.status} / {provider.config_status}</span></div>)}</div></article>
      <article className="panel"><h3>Permission Gate</h3><p className="panel-subtitle">Permission ada tidak berarti transaksi sudah diaktifkan.</p><div className="check-list">
        <div className="check-item"><span>Payment view</span><span className="check-state">{canViewPayments?"ALLOWED":"NO"}</span></div>
        <div className="check-item"><span>Payment create</span><span className={`check-state ${canCreatePayment?"":"pending"}`}>{canCreatePayment?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Payment approve</span><span className={`check-state ${canApprovePayment?"":"pending"}`}>{canApprovePayment?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Teller session manage</span><span className={`check-state ${canManageSession?"":"pending"}`}>{canManageSession?"ASSIGNED":"NOT ASSIGNED"}</span></div>
        <div className="check-item"><span>Reconcile</span><span className={`check-state ${canReconcile?"":"pending"}`}>{canReconcile?"ASSIGNED":"NOT ASSIGNED"}</span></div>
      </div></article>
    </section>

    <section className="panel section-panel"><div className="panel-heading-row"><div><h3>Payment State Machine</h3><p className="panel-subtitle">Konfirmasi bukan sekadar screenshot atau tombol berhasil.</p></div></div><div className="check-list">
      <div className="check-item"><span>CREATED → PENDING</span><span className="check-state">REQUEST</span></div>
      <div className="check-item"><span>PENDING → CONFIRMED</span><span className="check-state pending">VERIFIED EVENT / CASH CONTROL</span></div>
      <div className="check-item"><span>CONFIRMED → SETTLEMENT_PENDING → SETTLED</span><span className="check-state pending">PROVIDER / RECONCILIATION</span></div>
      <div className="check-item"><span>FAILED / EXPIRED / CANCELLED / REFUNDED</span><span className="check-state">TERMINAL / CONTROLLED</span></div>
      <div className="check-item"><span>Allocate to subledger + GL</span><span className="check-state pending">ONLY AFTER GATES</span></div>
    </div></section>

    <section className="dashboard-grid">
      <article className="panel"><h3>Teller Reconciliation</h3><p className="panel-subtitle">Kas tidak disimpan sebagai angka bebas; cash movement harus berada dalam session.</p>{sessions.length?<div className="check-list">{sessions.map((session)=><div className="check-item" key={session.id}><span>{session.session_number}<small className="item-subtext">{session.business_date} · Opening {session.opening_cash}</small></span><span className="check-state pending">{session.status}</span></div>)}</div>:<div className="empty-state">Belum ada teller session. Ini disengaja sampai transaction gate dibuka.</div>}</article>
      <article className="panel"><h3>Provider Events</h3><p className="panel-subtitle">Hanya event/provider evidence yang tervalidasi dapat menggerakkan status.</p>{events.length?<div className="check-list">{events.map((event)=><div className="check-item" key={event.id}><span>{event.event_type}<small className="item-subtext">Signature: {event.signature_validation_status}</small></span><span className="check-state pending">{event.processing_status}</span></div>)}</div>:<div className="empty-state">Belum ada provider event. Screenshot pengguna tidak dimasukkan sebagai authoritative event.</div>}</article>
    </section>

    <section className="panel section-panel"><h3>Transaction Register</h3><p className="panel-subtitle">Belum ada intent/attempt/cash movement karena execution path belum diaktifkan.</p>{intents.length?<div className="data-table-wrap"><table className="data-table"><thead><tr><th>Intent</th><th>Purpose</th><th>Amount</th><th>Status</th><th>Created</th></tr></thead><tbody>{intents.map((intent)=><tr key={intent.id}><td>{intent.intent_number}</td><td>{intent.business_purpose}</td><td>{intent.currency} {intent.amount}</td><td>{intent.status}</td><td>{intent.created_at}</td></tr>)}</tbody></table></div>:<div className="empty-state">Payment intent: 0 · Attempt: {attempts.length} · Cash movement: {cashMovements.length} · Settlement batch: {settlements.length}.</div>}</section>
  </>;
}
