import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asCommercialClient } from "@/types/commercial";

export const dynamic = "force-dynamic";

const OPEN_SHIFT_STATES = ["OPEN", "CLOSING", "RECONCILIATION_EXCEPTION"];

export default async function PosWorkspacePage() {
  const { profile, permissionCodes, supabase } = await requireAccessContext();

  if (!permissionCodes.includes("SALES_VIEW")) {
    return (
      <section className="panel">
        <h3>POS tidak tersedia</h3>
        <p className="panel-subtitle">Akun ini tidak memiliki SALES_VIEW.</p>
      </section>
    );
  }

  const organizationId = profile.organization_id;
  const db = asCommercialClient(supabase);
  const canCreateSale = permissionCodes.includes("SALES_CREATE");
  const canManageShift = permissionCodes.includes("POS_SHIFT_MANAGE");
  const canCreatePayment = permissionCodes.includes("PAYMENT_CREATE");

  const [terminalResult, shiftResult, salesResult] = await Promise.all([
    organizationId
      ? db.from("pos_terminals")
          .select("id,code,name,device_reference,default_warehouse_id,status,organization_unit_id")
          .eq("organization_id", organizationId)
          .order("code")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("pos_shifts")
          .select("id,terminal_id,cashier_profile_id,shift_number,status,opened_at,closed_at,reconciliation_status")
          .eq("organization_id", organizationId)
          .order("opened_at", { ascending: false })
          .limit(20)
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("sales_transactions")
          .select("id,sale_number,total_amount,currency,status,sync_status,created_at")
          .eq("organization_id", organizationId)
          .order("created_at", { ascending: false })
          .limit(8)
      : Promise.resolve({ data: [], error: null }),
  ]);

  const terminals = terminalResult.data ?? [];
  const shifts = shiftResult.data ?? [];
  const recentSales = salesResult.data ?? [];
  const activeTerminals = terminals.filter((terminal) => terminal.status === "ACTIVE");
  const ownOpenShift = shifts.find(
    (shift) => shift.cashier_profile_id === profile.id && OPEN_SHIFT_STATES.includes(shift.status),
  );
  const visibleOpenShift = ownOpenShift ?? shifts.find((shift) => OPEN_SHIFT_STATES.includes(shift.status));
  const selectedTerminal = visibleOpenShift
    ? terminals.find((terminal) => terminal.id === visibleOpenShift.terminal_id)
    : activeTerminals[0];

  const shiftReady = Boolean(ownOpenShift);
  const terminalReady = Boolean(selectedTerminal && selectedTerminal.status === "ACTIVE");
  const permissionReady = canCreateSale && canCreatePayment;
  const operationalReady = shiftReady && terminalReady && permissionReady;

  return (
    <div className="pos-workspace">
      <section className="pos-workspace-header">
        <div>
          <p className="eyebrow">POS Kasir</p>
          <h1>Penjualan Cepat</h1>
          <p className="pos-workspace-intro">
            Layar kerja kasir dibuat sederhana. Detail payment, inventory, dan accounting tetap berjalan di belakang layar
            dan tidak perlu dipahami kasir saat transaksi.
          </p>
        </div>
        <div className={`pos-readiness ${operationalReady ? "ready" : "pending"}`}>
          <span className="pos-readiness-dot" aria-hidden="true" />
          {operationalReady ? "Siap transaksi" : "Persiapan operasional"}
        </div>
      </section>

      <section className="pos-context-strip" aria-label="Konteks kasir">
        <div>
          <span>Terminal</span>
          <strong>{selectedTerminal ? `${selectedTerminal.code} · ${selectedTerminal.name}` : "Belum dikonfigurasi"}</strong>
        </div>
        <div>
          <span>Shift</span>
          <strong>{ownOpenShift?.shift_number ?? "Belum dibuka"}</strong>
        </div>
        <div>
          <span>Kasir</span>
          <strong>{shiftReady ? "Shift saya aktif" : "Perlu buka shift"}</strong>
        </div>
      </section>

      <section className="pos-main-grid">
        <article className="pos-catalog-panel">
          <div className="pos-section-heading">
            <div>
              <h2>Pilih barang</h2>
              <p>Scan barcode atau cari nama barang akan menjadi tindakan utama di tahap transaction engine.</p>
            </div>
            <span className="pos-foundation-badge">FOUNDATION</span>
          </div>

          <label className="pos-search-shell" aria-disabled="true">
            <span className="pos-search-icon" aria-hidden="true">⌕</span>
            <input disabled placeholder="Scan barcode atau cari barang…" aria-label="Cari barang" />
          </label>

          <div className="pos-shortcuts" aria-label="Aksi cepat POS">
            <button type="button" disabled><strong>Scan</strong><span>Barcode / SKU</span></button>
            <button type="button" disabled><strong>Favorit</strong><span>Barang cepat</span></button>
            <button type="button" disabled><strong>Anggota</strong><span>Hubungkan pembeli</span></button>
            <button type="button" disabled><strong>Diskon</strong><span>Sesuai izin</span></button>
          </div>

          <div className="pos-empty-catalog">
            <strong>Transaction command belum diaktifkan.</strong>
            <span>
              Ini disengaja agar UI tidak membuat transaksi palsu. Slice berikutnya akan menghubungkan pencarian barang,
              stock availability, cart, payment confirmation, stock issue, journal, dan receipt secara atomik/idempotent.
            </span>
          </div>
        </article>

        <aside className="pos-cart-panel">
          <div className="pos-section-heading compact">
            <div>
              <h2>Keranjang</h2>
              <p>0 item</p>
            </div>
          </div>

          <div className="pos-cart-empty">
            <span className="pos-cart-empty-mark" aria-hidden="true">+</span>
            <strong>Belum ada barang</strong>
            <span>Barang yang dipilih akan muncul di sini.</span>
          </div>

          <div className="pos-total-block">
            <div><span>Subtotal</span><strong>Rp0</strong></div>
            <div className="pos-grand-total"><span>Total</span><strong>Rp0</strong></div>
          </div>

          <button className="pos-pay-button" type="button" disabled>
            Bayar
            <small>{operationalReady ? "Transaction engine berikutnya" : "Lengkapi terminal, shift, dan izin"}</small>
          </button>

          {!shiftReady ? (
            <div className="pos-action-note">
              <strong>Shift kasir belum aktif.</strong>
              <span>{canManageShift ? "Flow Buka Shift akan diaktifkan pada command engine POS." : "Hubungi petugas yang memiliki izin POS_SHIFT_MANAGE."}</span>
            </div>
          ) : null}
        </aside>
      </section>

      <section className="pos-secondary-grid">
        <article className="panel pos-readiness-card">
          <div className="panel-heading-row">
            <div>
              <h3>Kesiapan POS</h3>
              <p className="panel-subtitle">Kasir cukup melihat status sederhana; detail kontrol tetap tersedia untuk Manager.</p>
            </div>
            <Link className="text-link" href="/dashboard/commercial" prefetch>Control Center</Link>
          </div>
          <div className="check-list">
            <div className="check-item"><span>Terminal aktif</span><span className={`check-state ${terminalReady ? "" : "pending"}`}>{terminalReady ? "SIAP" : "BELUM"}</span></div>
            <div className="check-item"><span>Shift kasir sendiri</span><span className={`check-state ${shiftReady ? "" : "pending"}`}>{shiftReady ? "AKTIF" : "BELUM"}</span></div>
            <div className="check-item"><span>Izin transaksi + pembayaran</span><span className={`check-state ${permissionReady ? "" : "pending"}`}>{permissionReady ? "SIAP" : "BELUM"}</span></div>
            <div className="check-item"><span>Payment + stock + accounting completion</span><span className="check-state pending">NEXT SLICE</span></div>
          </div>
        </article>

        <article className="panel">
          <div className="panel-heading-row">
            <div>
              <h3>Transaksi Terbaru</h3>
              <p className="panel-subtitle">Hanya data yang benar-benar ada di database.</p>
            </div>
          </div>
          {recentSales.length > 0 ? (
            <div className="pos-recent-sales">
              {recentSales.map((sale) => (
                <div className="pos-recent-sale" key={sale.id}>
                  <span>
                    <strong>{sale.sale_number ?? "Transaksi"}</strong>
                    <small>{new Date(sale.created_at).toLocaleString("id-ID")} · {sale.sync_status}</small>
                  </span>
                  <span>
                    <strong>{new Intl.NumberFormat("id-ID", { style: "currency", currency: sale.currency || "IDR", maximumFractionDigits: 0 }).format(sale.total_amount)}</strong>
                    <small>{sale.status}</small>
                  </span>
                </div>
              ))}
            </div>
          ) : (
            <div className="empty-state">Belum ada transaksi DEVELOPMENT. Sistem tidak menampilkan omzet atau struk palsu.</div>
          )}
        </article>
      </section>
    </div>
  );
}
