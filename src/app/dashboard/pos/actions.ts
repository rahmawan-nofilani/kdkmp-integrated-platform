"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosClient } from "@/types/pos";

export type PosShiftActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

export const initialPosShiftActionState: PosShiftActionState = {
  status: "idle",
  message: "",
};

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readNonNegativeAmount(value: FormDataEntryValue | null) {
  const text = typeof value === "string" ? value.trim() : "";
  if (text === "") return 0;
  const amount = Number(text);
  return Number.isFinite(amount) && amount >= 0 ? amount : null;
}

function safeShiftError(message?: string | null) {
  switch (message) {
    case "POS_TERMINAL_SHIFT_ALREADY_OPEN":
      return "Terminal ini sedang digunakan oleh shift yang masih aktif.";
    case "POS_CASHIER_SHIFT_ALREADY_OPEN":
      return "Anda masih memiliki shift aktif. Tutup shift tersebut terlebih dahulu.";
    case "POS_TERMINAL_NOT_AVAILABLE":
    case "POS_TERMINAL_WAREHOUSE_REQUIRED":
    case "POS_TERMINAL_WAREHOUSE_NOT_ACTIVE":
      return "Terminal POS belum siap digunakan. Hubungi Manager untuk memeriksa konfigurasi terminal dan stok gerai.";
    case "POS_SHIFT_HAS_UNFINISHED_SALES":
      return "Shift belum dapat ditutup karena masih ada transaksi yang belum selesai.";
    case "POS_OWN_OPEN_SHIFT_REQUIRED":
      return "Shift aktif Anda tidak ditemukan. Muat ulang halaman dan periksa kembali.";
    case "POS_SHIFT_NOT_FOUND":
      return "Shift tidak ditemukan. Muat ulang halaman dan coba lagi.";
    case "POS_SHIFT_AND_COUNTED_CASH_REQUIRED":
    case "POS_COUNTED_CASH_INVALID":
      return "Masukkan jumlah kas fisik yang valid sebelum menutup shift.";
    case "POS_SHIFT_MANAGE_DENIED":
      return "Akun Anda tidak memiliki izin untuk mengelola shift POS.";
    default:
      return "Operasi shift belum dapat diproses. Tidak ada perubahan transaksi yang dilakukan.";
  }
}

export async function openPosShiftAction(
  _previousState: PosShiftActionState,
  formData: FormData,
): Promise<PosShiftActionState> {
  const terminalId = String(formData.get("terminal_id") ?? "").trim();
  const openingCash = readNonNegativeAmount(formData.get("opening_cash"));

  if (!UUID_PATTERN.test(terminalId)) {
    return { status: "error", message: "Pilih terminal POS yang valid." };
  }
  if (openingCash === null) {
    return { status: "error", message: "Kas awal laci harus berupa angka nol atau lebih." };
  }

  const supabase = asPosClient(await createClient());
  const { error } = await supabase.rpc("open_pos_shift", {
    p_terminal_id: terminalId,
    p_opening_cash: openingCash,
    p_idempotency_key: `POS-OPEN-${randomUUID()}`,
    p_notes: "Opened from cashier workspace",
  });

  if (error) {
    return { status: "error", message: safeShiftError(error.message) };
  }

  revalidatePath("/dashboard/pos");
  return { status: "success", message: "Shift berhasil dibuka. POS siap untuk memulai pekerjaan kasir." };
}

export async function closePosShiftAction(
  _previousState: PosShiftActionState,
  formData: FormData,
): Promise<PosShiftActionState> {
  const shiftId = String(formData.get("pos_shift_id") ?? "").trim();
  const countedCash = readNonNegativeAmount(formData.get("counted_cash"));

  if (!UUID_PATTERN.test(shiftId)) {
    return { status: "error", message: "Shift POS tidak valid. Muat ulang halaman dan coba lagi." };
  }
  if (countedCash === null) {
    return { status: "error", message: "Kas fisik harus berupa angka nol atau lebih." };
  }

  const supabase = asPosClient(await createClient());
  const { error } = await supabase.rpc("close_pos_shift", {
    p_pos_shift_id: shiftId,
    p_counted_cash: countedCash,
    p_idempotency_key: `POS-CLOSE-${randomUUID()}`,
    p_notes: "Closed from cashier workspace",
  });

  if (error) {
    return { status: "error", message: safeShiftError(error.message) };
  }

  revalidatePath("/dashboard/pos");
  return {
    status: "success",
    message: "Shift selesai diproses. Jika terdapat selisih kas, status rekonsiliasi akan ditandai untuk ditinjau.",
  };
}
