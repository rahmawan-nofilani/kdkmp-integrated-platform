"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { reverseCashPosSaleAction } from "./reversal-actions";
import styles from "./reversal.module.css";

const REVERSAL_REASONS = [
  { value: "CUSTOMER_REQUEST", label: "Permintaan pelanggan" },
  { value: "CASHIER_ERROR", label: "Kesalahan kasir" },
  { value: "DUPLICATE_SALE", label: "Transaksi ganda" },
  { value: "ITEM_ERROR", label: "Kesalahan barang/transaksi" },
  { value: "OTHER", label: "Alasan lain" },
] as const;

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

export function PosCashReversal({
  saleId,
  saleNumber,
  totalAmount,
  currency,
  refundShiftId,
  canReverse,
}: {
  saleId: string;
  saleNumber: string | null;
  totalAmount: number;
  currency: string;
  refundShiftId: string | null;
  canReverse: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reasonCode, setReasonCode] = useState<(typeof REVERSAL_REASONS)[number]["value"]>("CUSTOMER_REQUEST");
  const [reasonNote, setReasonNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [message, setMessage] = useState("");
  const [refundProof, setRefundProof] = useState<{
    refundNumber: string;
    refundAmount: number;
    currency: string;
  } | null>(null);
  const [isPending, startTransition] = useTransition();

  if (!canReverse || !refundShiftId) return null;

  function closeDialog() {
    if (isPending) return;
    setOpen(false);
    setReasonCode("CUSTOMER_REQUEST");
    setReasonNote("");
    setConfirmed(false);
    setMessage("");
    setRefundProof(null);
  }

  function submitReversal() {
    if (!confirmed || isPending || refundProof || !refundShiftId) return;

    setMessage("");
    startTransition(async () => {
      const result = await reverseCashPosSaleAction({
        saleId,
        refundShiftId,
        reasonCode,
        reasonNote: reasonNote.trim() || null,
      });

      if (result.status === "error") {
        setMessage(result.message);
        return;
      }

      setRefundProof({
        refundNumber: result.reversal.refundNumber,
        refundAmount: result.reversal.refundAmount,
        currency: result.reversal.currency,
      });
      setMessage(result.message);
      router.refresh();
    });
  }

  return (
    <>
      <button className={styles.trigger} type="button" onClick={() => setOpen(true)}>
        Void / Refund
      </button>

      {open ? (
        <div
          className={styles.backdrop}
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) closeDialog();
          }}
        >
          <section className={styles.dialog} role="dialog" aria-modal="true" aria-labelledby={`pos-reversal-${saleId}`}>
            <header className={styles.header}>
              <div>
                <span>Controlled CASH reversal</span>
                <h2 id={`pos-reversal-${saleId}`}>Void transaksi {saleNumber ?? "POS"}</h2>
              </div>
              <button type="button" className={styles.close} onClick={closeDialog} disabled={isPending} aria-label="Tutup dialog reversal">
                ×
              </button>
            </header>

            <div className={styles.amountCard}>
              <span>Refund tunai penuh</span>
              <strong>{formatMoney(totalAmount, currency)}</strong>
              <small>Refund keluar dari shift POS Anda yang sedang OPEN.</small>
            </div>

            <div className={styles.warning}>
              <strong>Tindakan finansial sensitif.</strong>
              <span>
                Jika berhasil, transaksi menjadi VOIDED, pembayaran asli menjadi REFUNDED, stok dikembalikan,
                jurnal pembalik diposting, dan CASH_REFUND dicatat. Bukti transaksi asli tidak dihapus.
              </span>
            </div>

            <label className={styles.field}>
              <span>Alasan void</span>
              <select value={reasonCode} onChange={(event) => setReasonCode(event.target.value as (typeof REVERSAL_REASONS)[number]["value"])} disabled={isPending || Boolean(refundProof)}>
                {REVERSAL_REASONS.map((reason) => (
                  <option key={reason.value} value={reason.value}>{reason.label}</option>
                ))}
              </select>
            </label>

            <label className={styles.field}>
              <span>Catatan</span>
              <textarea
                value={reasonNote}
                onChange={(event) => setReasonNote(event.target.value.slice(0, 500))}
                placeholder="Opsional. Jelaskan detail yang membantu audit."
                rows={4}
                disabled={isPending || Boolean(refundProof)}
              />
              <small>{reasonNote.length}/500 karakter</small>
            </label>

            {!refundProof ? (
              <label className={styles.confirmation}>
                <input
                  type="checkbox"
                  checked={confirmed}
                  onChange={(event) => setConfirmed(event.target.checked)}
                  disabled={isPending}
                />
                <span>Saya sudah mencocokkan transaksi dan memastikan uang kas shift cukup untuk refund penuh.</span>
              </label>
            ) : null}

            {message ? (
              <div className={refundProof ? styles.success : styles.error} role="status">
                <strong>{message}</strong>
                {refundProof ? (
                  <span>
                    Bukti refund {refundProof.refundNumber} · {formatMoney(refundProof.refundAmount, refundProof.currency)}
                  </span>
                ) : null}
              </div>
            ) : null}

            <div className={styles.actions}>
              <button type="button" className={styles.secondary} onClick={closeDialog} disabled={isPending}>
                {refundProof ? "Selesai" : "Batal"}
              </button>
              {!refundProof ? (
                <button type="button" className={styles.danger} onClick={submitReversal} disabled={!confirmed || isPending}>
                  {isPending ? "Memproses reversal…" : "Konfirmasi Void + Refund"}
                </button>
              ) : null}
            </div>
          </section>
        </div>
      ) : null}
    </>
  );
}
