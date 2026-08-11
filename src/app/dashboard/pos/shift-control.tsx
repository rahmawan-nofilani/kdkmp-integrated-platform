"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import {
  closePosShiftAction,
  initialPosShiftActionState,
  openPosShiftAction,
} from "./actions";

type ShiftControlProps = {
  terminalId: string | null;
  terminalLabel: string;
  canManageShift: boolean;
  ownShift: {
    id: string;
    shiftNumber: string | null;
    openingCash: number;
  } | null;
};

function SubmitButton({ children }: { children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <button className="pos-shift-submit" type="submit" disabled={pending}>
      {pending ? "Memproses…" : children}
    </button>
  );
}

function ActionMessage({ state }: { state: typeof initialPosShiftActionState }) {
  if (state.status === "idle" || !state.message) return null;
  return (
    <div className={`pos-shift-message ${state.status}`} role={state.status === "error" ? "alert" : "status"}>
      {state.message}
    </div>
  );
}

export function PosShiftControl({ terminalId, terminalLabel, canManageShift, ownShift }: ShiftControlProps) {
  const [openState, openAction] = useActionState(openPosShiftAction, initialPosShiftActionState);
  const [closeState, closeAction] = useActionState(closePosShiftAction, initialPosShiftActionState);

  if (!canManageShift) {
    return (
      <div className="pos-shift-control pos-shift-disabled">
        <strong>Shift dikelola petugas berwenang</strong>
        <span>Akun ini dapat melihat POS, tetapi tidak memiliki izin untuk membuka atau menutup shift.</span>
      </div>
    );
  }

  if (ownShift) {
    return (
      <div className="pos-shift-control">
        <div className="pos-shift-control-heading">
          <div>
            <span className="pos-shift-kicker">SHIFT AKTIF</span>
            <strong>{ownShift.shiftNumber ?? "Shift POS"}</strong>
            <small>Kas awal: {new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 0 }).format(ownShift.openingCash)}</small>
          </div>
          <span className="pos-shift-live-dot" aria-label="Shift aktif" />
        </div>

        <form action={closeAction} className="pos-shift-form">
          <input type="hidden" name="pos_shift_id" value={ownShift.id} />
          <label>
            <span>Kas fisik saat tutup</span>
            <input
              name="counted_cash"
              inputMode="numeric"
              type="number"
              min="0"
              step="1000"
              defaultValue="0"
              required
              aria-describedby="counted-cash-help"
            />
          </label>
          <p id="counted-cash-help" className="pos-shift-help">
            Hitung uang fisik terlebih dahulu. Sistem membandingkan hasilnya setelah Anda menekan Tutup Shift.
          </p>
          <SubmitButton>Tutup Shift</SubmitButton>
        </form>
        <ActionMessage state={closeState} />
      </div>
    );
  }

  if (!terminalId) {
    return (
      <div className="pos-shift-control pos-shift-disabled">
        <strong>Terminal belum siap</strong>
        <span>Belum ada terminal POS aktif yang dapat digunakan pada scope akun ini.</span>
      </div>
    );
  }

  return (
    <div className="pos-shift-control">
      <div className="pos-shift-control-heading">
        <div>
          <span className="pos-shift-kicker">MULAI KASIR</span>
          <strong>{terminalLabel}</strong>
          <small>Buka shift sebelum memulai transaksi.</small>
        </div>
      </div>

      <form action={openAction} className="pos-shift-form">
        <input type="hidden" name="terminal_id" value={terminalId} />
        <label>
          <span>Kas awal laci</span>
          <input
            name="opening_cash"
            inputMode="numeric"
            type="number"
            min="0"
            step="1000"
            defaultValue="0"
            required
          />
        </label>
        <SubmitButton>Buka Shift</SubmitButton>
      </form>
      <ActionMessage state={openState} />
    </div>
  );
}
