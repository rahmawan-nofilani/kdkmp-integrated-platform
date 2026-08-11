"use client";

import { useRouter } from "next/navigation";

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

export type PosReceiptView = {
  id: string;
  receiptNumber: string;
  currency: string;
  totalAmount: number;
  cashReceived: number;
  changeAmount: number;
  issuedAt: string;
};

export function PosReceiptSuccess({ receipt }: { receipt: PosReceiptView }) {
  const router = useRouter();

  return (
    <div className="pos-receipt-success">
      <div className="pos-receipt-check" aria-hidden="true">✓</div>
      <span className="pos-receipt-kicker">Transaksi selesai</span>
      <h2>Pembayaran berhasil</h2>
      <p>Stok, jurnal, kas POS, dan struk sudah diposting.</p>

      <div className="pos-print-receipt">
        <div className="pos-receipt-number">
          <span>Nomor struk</span>
          <strong>{receipt.receiptNumber}</strong>
        </div>
        <div className="pos-receipt-row"><span>Total</span><strong>{formatMoney(receipt.totalAmount, receipt.currency)}</strong></div>
        <div className="pos-receipt-row"><span>Tunai diterima</span><strong>{formatMoney(receipt.cashReceived, receipt.currency)}</strong></div>
        <div className="pos-receipt-row change"><span>Kembalian</span><strong>{formatMoney(receipt.changeAmount, receipt.currency)}</strong></div>
        <small>{new Date(receipt.issuedAt).toLocaleString("id-ID")}</small>
      </div>

      <div className="pos-receipt-actions">
        <button className="primary" type="button" onClick={() => router.replace("/dashboard/pos")}>
          Transaksi Baru
        </button>
        <button type="button" onClick={() => window.print()}>
          Cetak Struk
        </button>
      </div>
    </div>
  );
}
