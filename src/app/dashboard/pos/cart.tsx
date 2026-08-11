"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { Json } from "@/types/database";
import type { PosCartLine } from "@/types/pos";
import { cancelPosCartAction, changePosCartLineAction } from "./cart-actions";

export type PosCartSale = {
  id: string;
  saleNumber: string | null;
  currency: string;
  subtotal: number;
  discountAmount: number;
  taxAmount: number;
  totalAmount: number;
};

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

function snapshotText(snapshot: Json, key: string) {
  if (!snapshot || Array.isArray(snapshot) || typeof snapshot !== "object") return null;
  const value = snapshot[key];
  return typeof value === "string" ? value : null;
}

export function PosCart({
  sale,
  lines,
  canEdit,
}: {
  sale: PosCartSale | null;
  lines: PosCartLine[];
  canEdit: boolean;
}) {
  const router = useRouter();
  const [message, setMessage] = useState("");
  const [pendingLineId, setPendingLineId] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const itemCount = lines.reduce((sum, line) => sum + Number(line.quantity), 0);

  function changeQuantity(lineId: string, delta: 1 | -1) {
    if (!sale || !canEdit || isPending) return;
    setMessage("");
    setPendingLineId(lineId);
    startTransition(async () => {
      const result = await changePosCartLineAction({ saleId: sale.id, lineId, delta });
      setMessage(result.message);
      if (result.status === "success") router.refresh();
      setPendingLineId(null);
    });
  }

  function cancelSale() {
    if (!sale || !canEdit || isPending) return;
    if (!window.confirm("Batalkan transaksi dan kosongkan seluruh keranjang?")) return;
    setMessage("");
    startTransition(async () => {
      const result = await cancelPosCartAction(sale.id);
      setMessage(result.message);
      if (result.status === "success") router.refresh();
    });
  }

  if (!sale || lines.length === 0) {
    return (
      <>
        <div className="pos-section-heading compact">
          <div>
            <h2>Keranjang</h2>
            <p>0 item</p>
          </div>
        </div>
        <div className="pos-cart-empty">
          <span className="pos-cart-empty-mark" aria-hidden="true">+</span>
          <strong>Belum ada barang</strong>
          <span>Tap Tambah atau scan barcode untuk mulai transaksi.</span>
        </div>
        <div className="pos-total-block">
          <div><span>Subtotal</span><strong>Rp0</strong></div>
          <div className="pos-grand-total"><span>Total</span><strong>Rp0</strong></div>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="pos-section-heading compact pos-cart-heading">
        <div>
          <h2>Keranjang</h2>
          <p>{itemCount} item · {sale.saleNumber ?? "Transaksi aktif"}</p>
        </div>
        <button className="pos-cart-cancel" type="button" disabled={!canEdit || isPending} onClick={cancelSale}>
          Batal
        </button>
      </div>

      {message ? <div className="pos-inline-message" role="status">{message}</div> : null}

      <div className="pos-cart-lines">
        {lines.map((line) => {
          const uomCode = snapshotText(line.item_snapshot, "uom_code") ?? "unit";
          const sku = snapshotText(line.item_snapshot, "sku");
          const linePending = pendingLineId === line.id && isPending;
          return (
            <article className="pos-cart-line" key={line.id}>
              <div className="pos-cart-line-copy">
                <span>{sku ? `${sku} · ${uomCode}` : uomCode}</span>
                <strong>{line.description}</strong>
                <small>{formatMoney(Number(line.unit_price), sale.currency)} / {uomCode}</small>
              </div>
              <div className="pos-cart-line-right">
                <strong>{formatMoney(Number(line.line_total ?? 0), sale.currency)}</strong>
                <div className="pos-qty-control" aria-label={`Jumlah ${line.description}`}>
                  <button
                    type="button"
                    aria-label={`Kurangi ${line.description}`}
                    disabled={!canEdit || isPending}
                    onClick={() => changeQuantity(line.id, -1)}
                  >
                    −
                  </button>
                  <span>{linePending ? "…" : Number(line.quantity)}</span>
                  <button
                    type="button"
                    aria-label={`Tambah ${line.description}`}
                    disabled={!canEdit || isPending}
                    onClick={() => changeQuantity(line.id, 1)}
                  >
                    +
                  </button>
                </div>
              </div>
            </article>
          );
        })}
      </div>

      <div className="pos-total-block pos-cart-totals">
        <div><span>Subtotal</span><strong>{formatMoney(sale.subtotal, sale.currency)}</strong></div>
        {sale.discountAmount > 0 ? <div><span>Diskon</span><strong>− {formatMoney(sale.discountAmount, sale.currency)}</strong></div> : null}
        {sale.taxAmount > 0 ? <div><span>Pajak</span><strong>{formatMoney(sale.taxAmount, sale.currency)}</strong></div> : null}
        <div className="pos-grand-total"><span>Total</span><strong>{formatMoney(sale.totalAmount, sale.currency)}</strong></div>
      </div>
    </>
  );
}
