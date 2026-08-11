import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asPosClient } from "@/types/pos";
import { PosShiftControl } from "./shift-control";

export const dynamic = "force-dynamic";

const ACTIVE_SHIFT_STATES = ["OPEN", "CLOSING", "RECONCILIATION_EXCEPTION"];

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
  const db = asPosClient(supabase);
  const canCreateSale = permissionCodes.includes("SALES_CREATE");
  const canManageShift = permissionCodes.includes("POS_SHIFT_MANAGE");
  const canCapturePayment = permissionCodes.includes("POS_PAYMENT_CAPTURE");

  const [terminalResult, shiftResult, salesResult] = await Promise.all([
    organizationId
      ? db.from("pos_terminals")
          .select("id,code,name,device_reference,default_warehouse_id,status,organization_unit_id")
          .eq("organization_id", organizationId)
          .order("code")
      : Promise.resolve({ data: [], error: null }),
    organizationId
      ? db.from("pos_shifts")
          .select("id,terminal_id,cashier_profile_id,shift_number,status,opened_at,closed_at,opening_cash,expected_cash,counted_cash,reconciliation_status")
          .eq("organization_id", organizationId)
          .order("opened_at", { ascending: false })
          .limit(30)
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
  const activeShifts = shifts.filter((shift) => ACTIVE_SHIFT_STATES.includes(shift.status));
  const ownActiveShift = activeShifts.find((shift) => shift.cashier_profile_id === profile.id);
  const ownOpenShift = ownActiveShift?.status === "OPEN" ? ownActiveShift : undefined;
  const busyTerminalIds = new Set(activeShifts.map((shift) => shift.terminal_id));
  const availableTerminals = activeTerminals.filter((terminal) => !busyTerminalIds.has(terminal.id));
  const selectedTerminal = ownActiveShift
    ? terminals.find((terminal) => terminal.id === ownActiveShift.terminal_id)
    : availableTerminals[0];

  const shiftReady = Boolean(ownOpenShift);
  const terminalReady = Boolean(selectedTerminal && selectedTerminal.status === "ACTIVE");
  const permissionReady = canCreateSale && canCapturePayment;
  const cashierFoundationReady = terminalReady && permissionReady;

  return (
    <div className="pos-workspace">
      <section className="pos-workspace-header">
        <div>
          <p className="eyebrow">POS Kasir</p>
          <h1>Penjualan Cepat</h1>
          <p className="pos-workspace-intro">
            Kasir bekerja dengan bahasa sederhana: barang, keranjang, total, bayar, dan struk. Kontrol stok,
            pembayaran, accounting, idempotency, dan audit tetap berjalan di belakang layar.
          </p>
        </div>
        <div className={`pos-readiness ${shiftReady ? "ready" : "pending"}`}>
          <span className="pos-readiness-dot" aria-hidden="true" />
          {shiftReady ? "Shift aktif" : ownActiveShift ? "Perlu rekonsiliasi" : "Buka shift"}
        </div>
      </section>

      <section className="pos-context-strip" aria-label="Konteks kasir">
        <div>
          <span>Terminal</span>
          <strong>{selectedTerminal ? `${selectedTerminal.code} · ${selectedTerminal.name}` : "Tidak ada terminal tersedia"}</strong>
        </div>
        <div>
          <span>Shift</span>
          <strong>{ownActiveShift?.shift_number ?? "Belum dibuka"}</strong>
        </div>
        <div>
          <span>Status kasir</span>
          <strong>{shiftReady ? "Siap bekerja" : ownActiveShift ? ownActiveShift.status : "Perlu buka shift"}</strong>
        </div>
      </section>

      {ownActiveShift && ownActiveShift.status !== "OPEN" ? (
        <section className="pos-shift-control pos-shift-disabled">
          <strong>Shift memerlukan rekonsiliasi</strong>
          <span>
            Shift {ownActiveShift.shift_number ?? "POS"} berstatus {ownActiveShift.status}. Shift baru tidak dapat dibuka
            sampai selisih/review diselesaikan oleh petugas yang berwenang.
          </span>
        </section>
      ) : (
        <PosShiftControl
          terminalId={selectedTerminal?.id ?? null}
          terminalLabel={selectedTerminal ? `${selectedTerminal.code} · ${selectedTerminal.name}` : "Terminal POS"}
          canManageShift={canManageShift}
          ownShift={ownOpenShift ? {
            id: ownOpenShift.id,
            shiftNumber: ownOpenShift.shift_number,
            openingCash: ownOpenShift.opening_cash,
          } : null}
        />
      )}

      <section className="pos-main-grid">
        <article className="pos-catalog-panel">
          <div className="pos-section-heading">
            <div>
              <h2>Pilih barang</h2>
              <p>Scan barcode dan pencarian barang akan menjadi tindakan utama kasir.</p>
            </div>
            <span className="pos-foundation-badge">CONTROLLED NEXT</span>
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
            <strong>Buka/Tutup Shift sudah menggunakan command engine nyata.</strong>
            <span>
              Katalog transaksi sengaja belum dibuka sampai endpoint katalog kasir, UOM kemasan, harga jual aktif,
              stok gerai, dan accounting mapping siap. Kasir tidak akan diberi akses Gudang yang terlalu luas hanya
              untuk mencari barang.
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
            <small>{shiftReady && cashierFoundationReady ? "Menunggu katalog + completion gate" : "Buka shift dan lengkapi kesiapan POS"}</small>
          </button>

          {!shiftReady ? (
            <div className="pos-action-note">
              <strong>Transaksi belum dapat dimulai.</strong>
              <span>{ownActiveShift ? "Selesaikan rekonsiliasi shift terlebih dahulu." : "Buka shift kasir di bagian atas layar."}</span>
            </div>
          ) : null}
        </aside>
      </section>

      <section className="pos-secondary-grid">
        <article className="panel pos-readiness-card">
          <div className="panel-heading-row">
            <div>
              <h3>Kesiapan POS</h3>
              <p className="panel-subtitle">Kasir melihat status sederhana; kontrol detail tetap tersedia untuk Manager.</p>
            </div>
            <Link className="text-link" href="/dashboard/commercial" prefetch>Control Center</Link>
          </div>
          <div className="check-list">
            <div className="check-item"><span>Terminal aktif</span><span className={`check-state ${terminalReady ? "" : "pending"}`}>{terminalReady ? "SIAP" : "BELUM"}</span></div>
            <div className="check-item"><span>Shift kasir sendiri</span><span className={`check-state ${shiftReady ? "" : "pending"}`}>{shiftReady ? "AKTIF" : ownActiveShift ? "REVIEW" : "BELUM"}</span></div>
            <div className="check-item"><span>Izin transaksi POS</span><span className={`check-state ${permissionReady ? "" : "pending"}`}>{permissionReady ? "SIAP" : "BELUM"}</span></div>
            <div className="check-item"><span>Harga + stok + accounting completion</span><span className="check-state pending">CONTROL GATE</span></div>
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
