import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { asPosClient, type PosCatalogItem, type PosCartLine } from "@/types/pos";
import { PosCatalog } from "./catalog";
import { PosCart } from "./cart";
import { PosPayment } from "./payment";
import { PosReceiptSuccess, type PosReceiptView } from "./receipt";
import { PosShiftControl } from "./shift-control";

export const dynamic = "force-dynamic";

const ACTIVE_SHIFT_STATES = ["OPEN", "CLOSING", "RECONCILIATION_EXCEPTION"];
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export default async function PosWorkspacePage({
  searchParams,
}: {
  searchParams: Promise<{ receipt?: string | string[] }>;
}) {
  const params = await searchParams;
  const rawReceiptId = Array.isArray(params.receipt) ? params.receipt[0] : params.receipt;
  const receiptId = rawReceiptId && UUID_PATTERN.test(rawReceiptId) ? rawReceiptId : null;
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

  const [terminalResult, shiftResult, salesResult, receiptResult] = await Promise.all([
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
    receiptId
      ? db.from("pos_receipts")
          .select("id,receipt_number,currency,total_amount,cash_received,change_amount,issued_at")
          .eq("id", receiptId)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);

  const terminals = terminalResult.data ?? [];
  const shifts = shiftResult.data ?? [];
  const recentSales = salesResult.data ?? [];
  const receiptData = receiptResult.data;
  const receiptView: PosReceiptView | null = receiptData ? {
    id: receiptData.id,
    receiptNumber: receiptData.receipt_number,
    currency: receiptData.currency,
    totalAmount: Number(receiptData.total_amount),
    cashReceived: Number(receiptData.cash_received),
    changeAmount: Number(receiptData.change_amount ?? 0),
    issuedAt: receiptData.issued_at,
  } : null;

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
  let catalogItems: PosCatalogItem[] = [];
  let catalogReadError = false;
  let activeSale: {
    id: string;
    sale_number: string | null;
    currency: string;
    subtotal: number;
    discount_amount: number;
    tax_amount: number;
    total_amount: number;
  } | null = null;
  let cartLines: PosCartLine[] = [];

  if (shiftReady && selectedTerminal && ownOpenShift) {
    const [catalogResult, activeSaleResult] = await Promise.all([
      db
        .from("pos_catalog_requests")
        .insert({ terminal_id: selectedTerminal.id, search_query: null, result_limit: 50 })
        .select("result")
        .single(),
      db
        .from("sales_transactions")
        .select("id,sale_number,currency,subtotal,discount_amount,tax_amount,total_amount")
        .eq("pos_shift_id", ownOpenShift.id)
        .eq("created_by", profile.id)
        .eq("sale_type", "POS")
        .eq("status", "DRAFT")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    catalogItems = catalogResult.data?.result ?? [];
    catalogReadError = Boolean(catalogResult.error);
    activeSale = activeSaleResult.data ?? null;

    if (activeSale) {
      const lineResult = await db
        .from("sales_transaction_lines")
        .select("id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,description,uom_id,quantity,unit_price,discount_amount,tax_amount,line_total")
        .eq("sales_transaction_id", activeSale.id)
        .order("line_no");
      cartLines = lineResult.data ?? [];
    }
  }

  const catalogReady = shiftReady && !catalogReadError && catalogItems.length > 0;
  const cartReady = Boolean(activeSale && cartLines.length > 0);
  const cashPaymentReady = Boolean(cartReady && shiftReady && canCreateSale && canCapturePayment);

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
          {receiptView ? "Transaksi selesai" : shiftReady ? "Shift aktif" : ownActiveShift ? "Perlu rekonsiliasi" : "Buka shift"}
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
          <strong>{receiptView ? "Serahkan kembalian / struk" : shiftReady ? "Siap bekerja" : ownActiveShift ? ownActiveShift.status : "Perlu buka shift"}</strong>
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
          canManageShift={canManageShift && !receiptView}
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
              <p>Scan barcode, ketik nama/SKU, atau tap Tambah. Harga dan stok selalu diperiksa ulang oleh server.</p>
            </div>
            <span className="pos-foundation-badge">CASH ACTIVE</span>
          </div>

          {shiftReady && selectedTerminal && ownOpenShift ? (
            catalogReadError ? (
              <div className="pos-empty-catalog compact">
                <strong>Katalog belum dapat dibaca.</strong>
                <span>Tidak ada akses inventory tambahan yang diberikan. Muat ulang halaman atau hubungi Manager.</span>
              </div>
            ) : (
              <PosCatalog
                items={catalogItems}
                terminalId={selectedTerminal.id}
                shiftId={ownOpenShift.id}
                canAdd={canCreateSale && !receiptView}
              />
            )
          ) : (
            <div className="pos-empty-catalog compact">
              <strong>Buka shift untuk melihat katalog.</strong>
              <span>Katalog POS hanya tersedia ketika kasir memiliki shift sendiri yang sedang aktif.</span>
            </div>
          )}
        </article>

        <aside className="pos-cart-panel">
          {receiptView ? (
            <PosReceiptSuccess receipt={receiptView} />
          ) : (
            <>
              <PosCart
                sale={activeSale ? {
                  id: activeSale.id,
                  saleNumber: activeSale.sale_number,
                  currency: activeSale.currency,
                  subtotal: activeSale.subtotal,
                  discountAmount: activeSale.discount_amount,
                  taxAmount: activeSale.tax_amount,
                  totalAmount: activeSale.total_amount,
                } : null}
                lines={cartLines}
                canEdit={Boolean(shiftReady && canCreateSale)}
              />

              <PosPayment
                saleId={activeSale?.id ?? null}
                totalAmount={activeSale?.total_amount ?? 0}
                currency={activeSale?.currency ?? "IDR"}
                canPay={cashPaymentReady}
              />
            </>
          )}

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
            <div className="check-item"><span>Katalog harga + stok</span><span className={`check-state ${catalogReady ? "" : "pending"}`}>{catalogReady ? "SIAP" : "BELUM"}</span></div>
            <div className="check-item"><span>Keranjang server-side</span><span className={`check-state ${cartReady ? "" : "pending"}`}>{cartReady ? "AKTIF" : "SIAP DIGUNAKAN"}</span></div>
            <div className="check-item"><span>Pembayaran Tunai + Stock + Journal + Receipt</span><span className="check-state">AKTIF</span></div>
            <div className="check-item"><span>QRIS / Transfer provider</span><span className="check-state pending">BELUM AKTIF</span></div>
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
