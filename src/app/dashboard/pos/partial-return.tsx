"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { returnCashPosItemsAction } from "./partial-return-actions";
import styles from "./partial-return.module.css";

const RETURN_REASONS = [
  { value: "CUSTOMER_REQUEST", label: "Permintaan pelanggan" },
  { value: "ITEM_DAMAGED", label: "Barang bermasalah" },
  { value: "WRONG_ITEM", label: "Barang tidak sesuai" },
  { value: "CASHIER_ERROR", label: "Kesalahan transaksi" },
  { value: "OTHER", label: "Alasan lain" },
] as const;

export type PartialReturnOption = {
  id: string;
  description: string;
  quantity: number;
  returnedQuantity: number;
  remainingQuantity: number;
};

export function PosPartialReturn({
  saleId,
  saleNumber,
  refundShiftId,
  canReturn,
  lines,
}: {
  saleId: string;
  saleNumber: string | null;
  refundShiftId: string | null;
  canReturn: boolean;
  lines: PartialReturnOption[];
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reasonCode, setReasonCode] = useState<(typeof RETURN_REASONS)[number]["value"]>("CUSTOMER_REQUEST");
  const [reasonNote, setReasonNote] = useState("");
  const [quantities, setQuantities] = useState<Record<string, string>>({});
  const [confirmed, setConfirmed] = useState(false);
  const [message, setMessage] = useState("");
  const [proof, setProof] = useState<{ refundNumber: string; refundAmount: number; currency: string; fullyReturned: boolean } | null>(null);
  const [isPending, startTransition] = useTransition();

  const returnableLines = useMemo(() => lines.filter((line) => line.remainingQuantity > 0), [lines]);
  const selectedLines = useMemo(() => returnableLines.flatMap((line) => {
    const quantity = Number(quantities[line.id] ?? 0);
    if (!Number.isFinite(quantity) || quantity <= 0) return [];
    return [{ salesTransactionLineId: line.id, quantity }];
  }), [quantities, returnableLines]);

  if (!canReturn || !refundShiftId || returnableLines.length === 0) return null;

  function closeDialog() {
    if (isPending) return;
    setOpen(false);
    setReasonCode("CUSTOMER_REQUEST");
    setReasonNote("");
    setQuantities({});
    setConfirmed(false);
    setMessage("");
    setProof(null);
  }

  function submitReturn() {
    if (!confirmed || selectedLines.length === 0 || isPending || proof || !refundShiftId) return;
    const invalid = selectedLines.some((selected) => {
      const line = returnableLines.find((candidate) => candidate.id === selected.salesTransactionLineId);
      return !line || selected.quantity > line.remainingQuantity;
    });
    if (invalid) {
      setMessage("Jumlah retur melebihi sisa yang dapat dikembalikan.");
      return;
    }

    setMessage("");
    startTransition(async () => {
      const result = await returnCashPosItemsAction({
        saleId,
        refundShiftId,
        lines: selectedLines,
        reasonCode,
        reasonNote: reasonNote.trim() || null,
      });
      if (result.status === "error") {
        setMessage(result.message);
        return;
      }
      setProof({
        refundNumber: result.partialReturn.refundNumber,
        refundAmount: result.partialReturn.refundAmount,
        currency: result.partialReturn.currency,
        fullyReturned: result.partialReturn.saleFullyReturned,
      });
      setMessage(result.message);
      router.refresh();
    });
  }

  return (
    <>
      <button className={styles.trigger} type="button" onClick={() => setOpen(true)}>Retur barang</button>
      {open ? (
        <div className={styles.backdrop} role="presentation" onMouseDown={(event) => {
          if (event.target === event.currentTarget) closeDialog();
        }}>
          <section className={styles.dialog} role="dialog" aria-modal="true" aria-labelledby={`partial-return-${saleId}`}>
            <header className={styles.header}>
              <div>
                <span>Controlled Partial Return</span>
                <h2 id={`partial-return-${saleId}`}>Retur sebagian</h2>
                <p>{saleNumber ?? "Transaksi POS"}</p>
              </div>
              <button className={styles.close} type="button" onClick={closeDialog} disabled={isPending} aria-label="Tutup">×</button>
            </header>

            <div className={styles.lines}>
              {returnableLines.map((line) => (
                <label className={styles.line} key={line.id}>
                  <span>
                    <strong>{line.description}</strong>
                    <small>Terjual {line.quantity} · sudah retur {line.returnedQuantity} · sisa {line.remainingQuantity}</small>
                  </span>
                  <input
                    type="number"
                    min="0"
                    max={line.remainingQuantity}
                    step="0.001"
                    inputMode="decimal"
                    value={quantities[line.id] ?? ""}
                    onChange={(event) => setQuantities((current) => ({ ...current, [line.id]: event.target.value }))}
                    placeholder="0"
                    disabled={isPending || Boolean(proof)}
                  />
                </label>
              ))}
            </div>

            <label className={styles.field}>
              <span>Alasan retur</span>
              <select value={reasonCode} onChange={(event) => setReasonCode(event.target.value as typeof reasonCode)} disabled={isPending || Boolean(proof)}>
                {RETURN_REASONS.map((reason) => <option key={reason.value} value={reason.value}>{reason.label}</option>)}
              </select>
            </label>

            <label className={styles.field}>
              <span>Catatan (opsional)</span>
              <textarea maxLength={500} value={reasonNote} onChange={(event) => setReasonNote(event.target.value)} disabled={isPending || Boolean(proof)} />
              <small>{reasonNote.length}/500</small>
            </label>

            <label className={styles.confirmation}>
              <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} disabled={isPending || Boolean(proof)} />
              <span>Saya sudah memeriksa barang dan jumlahnya. Refund tunai, stok, jurnal, dan bukti retur akan diposting atomik oleh server.</span>
            </label>

            {message ? <div className={proof ? styles.success : styles.error}>{message}{proof ? <small>{proof.refundNumber} · {new Intl.NumberFormat("id-ID", { style: "currency", currency: proof.currency, maximumFractionDigits: 0 }).format(proof.refundAmount)}{proof.fullyReturned ? " · transaksi sudah RETURNED" : ""}</small> : null}</div> : null}

            <div className={styles.actions}>
              <button className={styles.secondary} type="button" onClick={closeDialog} disabled={isPending}>{proof ? "Selesai" : "Batal"}</button>
              {!proof ? <button className={styles.danger} type="button" onClick={submitReturn} disabled={isPending || !confirmed || selectedLines.length === 0}>{isPending ? "Memproses…" : "Posting retur & refund"}</button> : null}
            </div>
          </section>
        </div>
      ) : null}
    </>
  );
}
