import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { runUatThreeWayMatchAction } from "./actions";

export const dynamic = "force-dynamic";

const errorMessages: Record<string, string> = {
  "permission-denied": "Akun ini tidak memiliki hak FINANCE untuk invoice dan three-way match.",
  "scope-denied": "Scope organisasi tidak valid untuk UAT Procurement.",
  "development-only": "Halaman ini hanya tersedia untuk DEVELOPMENT DEMO-KDKMP-DEV.",
  "po-missing": "PO UAT tidak ditemukan.",
  "po-not-matchable": "PO UAT belum berstatus RECEIVED dan belum dapat di-match.",
  "invalid-line": "Line PO UAT tidak valid.",
  idempotency: "Idempotency conflict terdeteksi. Hentikan dan periksa evidence sebelum mengulang.",
  system: "Three-way match gagal. Periksa runtime log sebelum mengulang.",
};

export default async function UatProcurementMatchPage({ searchParams }: { searchParams: Promise<{ error?: string; success?: string }> }) {
  await requirePermission("PURCHASE_INVOICE_CREATE");
  await requirePermission("PURCHASE_MATCH");
  const { profile, supabase } = await requireAccessContext();
  const params = await searchParams;

  const organizationResult = profile.organization_id
    ? await supabase.from("organizations").select("code,name").eq("id", profile.organization_id).maybeSingle()
    : { data: null, error: null };

  const poResult = profile.organization_id
    ? await supabase
        .from("purchase_orders")
        .select("id,po_number,status,currency")
        .eq("organization_id", profile.organization_id)
        .eq("po_number", "PO-20260819-0DF2F8DD")
        .maybeSingle()
    : { data: null, error: null };

  const po = poResult.data;
  const linesResult = po
    ? await supabase.from("purchase_order_lines").select("id,description,ordered_quantity,unit_price,line_total").eq("purchase_order_id", po.id).order("line_no")
    : { data: [], error: null };
  const lines = linesResult.data ?? [];

  const exactInvoice = po
    ? await supabase.from("supplier_invoices").select("invoice_number,status,matching_status,total_amount").eq("purchase_order_id", po.id).eq("invoice_number", "UAT-INV-G6-MATCH-001").maybeSingle()
    : { data: null, error: null };
  const mismatchInvoice = po
    ? await supabase.from("supplier_invoices").select("invoice_number,status,matching_status,total_amount").eq("purchase_order_id", po.id).eq("invoice_number", "UAT-INV-G6-MISMATCH-001").maybeSingle()
    : { data: null, error: null };

  return (
    <>
      <section className="page-heading">
        <div>
          <p className="eyebrow">Procurement · DEVELOPMENT/UAT</p>
          <h1>Finance Three-Way Match UAT</h1>
          <p>Satu aksi FINANCE untuk membuktikan exact match dan intentional mismatch pada fixture Gate 6. Tidak ada pembayaran nyata dan invoice mismatch diberi label DO NOT PAY.</p>
        </div>
        <span className="status-pill">DEVELOPMENT ONLY</span>
      </section>

      {params.error && errorMessages[params.error] ? <div className="alert-error" style={{ marginBottom: 18 }}>{errorMessages[params.error]}</div> : null}
      {params.success === "completed" ? <div className="alert-success" style={{ marginBottom: 18 }}>UAT three-way match selesai. Exact match dan mismatch evidence sudah dibuat.</div> : null}

      <section className="panel section-panel" style={{ maxWidth: 860 }}>
        <h3>Fixture Gate 6</h3>
        <div className="check-list">
          <div className="check-item"><span>Organization</span><span className="check-state">{organizationResult.data?.code ?? "-"}</span></div>
          <div className="check-item"><span>Purchase Order</span><span className="check-state">{po?.po_number ?? "NOT FOUND"}</span></div>
          <div className="check-item"><span>PO Status</span><span className={`check-state ${po?.status === "RECEIVED" ? "" : "pending"}`}>{po?.status ?? "-"}</span></div>
          {lines.map((line) => <div className="check-item" key={line.id}><span>{line.description}<small className="item-subtext">Qty {line.ordered_quantity} · Unit price {line.unit_price}</small></span><span className="check-state">{po?.currency ?? "IDR"} {line.line_total}</span></div>)}
        </div>
      </section>

      <section className="dashboard-grid">
        <article className="panel">
          <h3>Exact Match Evidence</h3>
          <p className="panel-subtitle">Expected: MATCHED, quantity variance 0, amount variance 0.</p>
          <div className="check-list"><div className="check-item"><span>UAT-INV-G6-MATCH-001</span><span className={`check-state ${exactInvoice.data?.matching_status === "MATCHED" ? "" : "pending"}`}>{exactInvoice.data?.matching_status ?? "NOT RUN"}</span></div></div>
        </article>
        <article className="panel">
          <h3>Mismatch Evidence</h3>
          <p className="panel-subtitle">Expected: EXCEPTION karena quantity/price/amount mismatch. DO NOT PAY.</p>
          <div className="check-list"><div className="check-item"><span>UAT-INV-G6-MISMATCH-001</span><span className={`check-state ${mismatchInvoice.data?.matching_status === "EXCEPTION" ? "" : "pending"}`}>{mismatchInvoice.data?.matching_status ?? "NOT RUN"}</span></div></div>
        </article>
      </section>

      <section className="panel section-panel" style={{ maxWidth: 860 }}>
        <h3>Jalankan evidence</h3>
        <p className="panel-subtitle">Tombol ini hanya boleh dijalankan oleh FINANCE_OFFICER pada DEVELOPMENT. Idempotency key tetap membuat retry aman terhadap double-submit identik.</p>
        <form action={runUatThreeWayMatchAction}>
          <button className="primary-button" type="submit" disabled={!po || po.status !== "RECEIVED"}>Jalankan Exact Match + Mismatch UAT</button>
        </form>
        <p className="form-note"><Link href="/dashboard/procurement">Kembali ke Procurement Control Center</Link></p>
      </section>
    </>
  );
}
