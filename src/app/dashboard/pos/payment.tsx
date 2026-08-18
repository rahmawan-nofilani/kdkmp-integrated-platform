"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { completeCashPaymentAction } from "./payment-actions";

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

function quickTenderAmounts(total: number) {
  const candidates = [
    total,
    Math.ceil(total / 10_000) * 10_000,
    Math.ceil(total / 20_000) * 20_000,
    Math.ceil(total / 50_000) * 50_000,
    Math.ceil(total / 100_000) * 100_000,
  ];
  return [...new Set(candidates.filter((value) => value >= total && value > 0))].slice(0, 4);
}

export function PosPayment({
  saleId,
  totalAmount,
  currency,
  canPay,
}: {
  saleId: string | null;
  totalAmount: number;
  currency: string;
  canPay: boolean;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [cashText, setCashText] = useState("");
  const [message, setMessage] = useState("");
  const [isPending, startTransition] = useTransition();

  const cashReceived = Number(cashText.replace(/\D/g, "") || 0);
  const changeAmount = Math.max(cashReceived - totalAmount, 0);
  const cashEnough = cashReceived >= totalAmount && totalAmount > 0;
  const quickAmounts = useMemo(() => quickTenderAmounts(totalAmount), [totalAmount]);

  function closeSheet() {
    if (isPending) return;
    setOpen(false);
    setCashText("");
    setMessage("");
  }

  function submitCashPayment() {
    if (!saleId || !canPay || !cashEnough || isPending) return;
    setMessage("");
    startTransition(async () => {
      const result = await completeCashPaymentAction({ saleId, cashReceived });
      if (result.status === "error") {
        setMessage(result.message);
        return;
      }
      router.replace(`/dashboard/pos?receipt=${encodeURIComponent(result.receipt.id)}`);
    });
  }

  return (
    <>
      <button
        className="pos-pay-button"
        type="button"
        disabled={!saleId || !canPay || totalAmount <= 0}
        onClick={() => setOpen(true)}
      >
        Bayar
        <small>{saleId && canPay ? formatMoney(totalAmount, currency) : "Tambahkan barang ke keranjang"}</small>
      </button>

      {open ? (
        <div className="pos-payment-backdrop" role="presentation" onMouseDown={(event) => {
          if (event.target === event.currentTarget) closeSheet();
        }}>
          <section className="pos-payment-sheet" role="dialog" aria-modal="true" aria-labelledby="pos-payment-title">
            <div className="pos-payment-handle" aria-hidden="true" />
            <header className="pos-payment-header">
              <div>
                <span>Pembayaran</span>
                <h2 id="pos-payment-title">{formatMoney(totalAmount, currency)}</h2>
              </div>
              <button type="button" onClick={closeSheet} disabled={isPending} aria-label="Tutup pembayaran">×</button>
            </header>

            <div className="pos-payment-methods" aria-label="Metode pembayaran">
              <button className="active" type="button">
                <strong>Tunai</strong>
                <span>Aktif</span>
              </button>
              <button type="button" disabled>
                <strong>QRIS</strong>
                <span>Backend siap · provider resmi belum dikonfigurasi</span>
              </button>
              <button type="button" disabled>
                <strong>Transfer</strong>
                <span>Backend siap · bank/provider belum dikonfigurasi</span>
              </button>
            </div>

            <div className="pos-cash-entry">
              <label htmlFor="pos-cash-received">Uang diterima</label>
              <div className="pos-cash-input-shell">
                <span>Rp</span>
                <input
                  id="pos-cash-received"
                  inputMode="numeric"
                  autoFocus
                  value={cashText ? new Intl.NumberFormat("id-ID").format(cashReceived) : ""}
                  onChange={(event) => setCashText(event.target.value.replace(/\D/g, ""))}
                  placeholder="0"
                  disabled={isPending}
                  aria-describedby="pos-change-info"
                />
              </div>

              <div className="pos-cash-quick" aria-label="Nominal cepat">
                {quickAmounts.map((amount) => (
                  <button key={amount} type="button" disabled={isPending} onClick={() => setCashText(String(amount))}>
                    {amount === totalAmount ? "Uang pas" : formatMoney(amount, currency)}
                  </button>
                ))}
              </div>
            </div>

            <div className={`pos-change-card ${cashEnough ? "ready" : "pending"}`} id="pos-change-info">
              <span>Kembalian</span>
              <strong>{formatMoney(changeAmount, currency)}</strong>
              <small>{cashEnough ? "Siap menerima pembayaran" : `Kurang ${formatMoney(Math.max(totalAmount - cashReceived, 0), currency)}`}</small>
            </div>

            {message ? <div className="pos-payment-error" role="alert">{message}</div> : null}

            <button
              className="pos-cash-submit"
              type="button"
              disabled={!cashEnough || isPending}
              onClick={submitCashPayment}
            >
              {isPending ? "Memproses transaksi…" : "Terima Pembayaran"}
              <small>{isPending ? "Jangan tutup halaman" : `Tunai · ${formatMoney(totalAmount, currency)}`}</small>
            </button>

            <p className="pos-payment-safety">
              Tunai tetap aktif seperti biasa. QRIS/Transfer tidak dapat dipilih sampai provider resmi, verifikasi signature backend,
              mapping rekening clearing, dan struktur fee telah dikonfigurasi. Screenshot pelanggan tidak pernah menjadi bukti pembayaran.
            </p>
          </section>
        </div>
      ) : null}
    </>
  );
}
