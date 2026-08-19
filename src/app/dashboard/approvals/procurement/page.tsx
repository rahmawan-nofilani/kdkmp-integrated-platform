import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { asApprovalClient } from "@/types/approval";
import { approvePurchaseOrderAction } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "invalid-po": "Purchase Order yang dipilih tidak valid.",
  "permission-denied": "Akun ini tidak memiliki PURCHASE_APPROVE.",
  "scope-denied": "Purchase Order berada di luar data scope akun ini.",
  "approval-missing": "Approval request untuk Purchase Order tidak ditemukan.",
  "approval-not-open": "Approval request sudah tidak terbuka.",
  "requester-cannot-approve": "Requester tidak boleh menyetujui transaksi yang dibuat/diajukannya sendiri.",
  "conflict-required": "Deklarasi konflik kepentingan wajib dicentang sebelum keputusan BOARD.",
  "reason-required": "Alasan approval wajib diisi.",
  "not-pending": "Purchase Order sudah tidak berstatus PENDING_APPROVAL.",
  idempotency: "Permintaan approval bertabrakan dengan idempotency key yang sudah ada.",
  system: "Approval Procurement gagal. Detail teknis tidak ditampilkan kepada pengguna.",
};

export default async function ProcurementApprovalPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; success?: string }>;
}) {
  await requirePermission("PURCHASE_APPROVE");
  const { profile, supabase } = await requireAccessContext();
  const params = await searchParams;
  const organizationId = profile.organization_id;

  if (!organizationId) {
    return <section className="panel"><h3>Organization context tidak tersedia</h3><p className="panel-subtitle">Approval dihentikan secara fail-closed.</p></section>;
  }

  const db = asApprovalClient(supabase);
  const { data, error } = await db
    .from("approval_requests")
    .select("id,source_entity_id,source_reference,status,requested_at,requested_by")
    .eq("organization_id", organizationId)
    .eq("source_domain", "PROCUREMENT")
    .eq("source_entity_type", "PURCHASE_ORDER")
    .in("status", ["PENDING", "IN_REVIEW"])
    .order("requested_at", { ascending: false })
    .limit(20);

  if (error) {
    return <section className="panel"><h3>Approval queue tidak dapat dimuat</h3><p className="panel-subtitle">Tidak ada fallback atau bypass scope yang digunakan.</p></section>;
  }

  const requests = data ?? [];

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Governance · Procurement</p>
          <h1>BOARD Procurement Approval</h1>
          <p>
            Keputusan Purchase Order dijalankan melalui sesi BOARD yang sedang login. Database tetap memvalidasi permission,
            data scope, requester separation, approval state, conflict declaration, dan idempotency.
          </p>
        </div>
        <span className="status-pill">CONTROLLED APPROVAL</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success === "approved" ? <div className="empty-state" style={{ marginBottom: 18, borderStyle: "solid" }}>Purchase Order berhasil disetujui oleh BOARD.</div> : null}

      <section className="panel section-panel">
        <div className="panel-heading-row">
          <div>
            <h3>Pending Purchase Orders</h3>
            <p className="panel-subtitle">Hanya approval request Procurement yang masih terbuka dan berada pada scope akun ini.</p>
          </div>
          <Link className="secondary-button" href="/dashboard/approvals">Kembali ke Approval & SoD</Link>
        </div>

        {requests.length ? (
          <div className="form-stack">
            {requests.map((request) => (
              <article className="panel" key={request.id} style={{ margin: 0 }}>
                <div className="panel-heading-row">
                  <div>
                    <h3>{request.source_reference ?? "Purchase Order"}</h3>
                    <p className="panel-subtitle">Request {request.id} · {request.requested_at}</p>
                  </div>
                  <span className="check-state pending">{request.status}</span>
                </div>

                {request.source_entity_id ? (
                  <form action={approvePurchaseOrderAction} className="form-stack">
                    <input type="hidden" name="purchase_order_id" value={request.source_entity_id} />
                    <div className="field">
                      <label htmlFor={`reason-${request.id}`}>Alasan / catatan keputusan</label>
                      <input
                        id={`reason-${request.id}`}
                        name="reason"
                        required
                        maxLength={500}
                        defaultValue={`UAT Gate 6 BOARD approval for ${request.source_reference ?? request.source_entity_id}`}
                      />
                    </div>
                    <label className="check-item" htmlFor={`conflict-${request.id}`}>
                      <span>Saya menyatakan tidak ada konflik kepentingan yang menghalangi keputusan ini.</span>
                      <input id={`conflict-${request.id}`} type="checkbox" name="conflict_declared" value="true" required />
                    </label>
                    <button className="primary-button" type="submit">Approve Purchase Order</button>
                  </form>
                ) : <div className="alert-error">Approval request tidak memiliki source entity. Keputusan dinonaktifkan.</div>}
              </article>
            ))}
          </div>
        ) : <div className="empty-state">Tidak ada Purchase Order yang menunggu approval BOARD pada scope ini.</div>}
      </section>
    </>
  );
}
