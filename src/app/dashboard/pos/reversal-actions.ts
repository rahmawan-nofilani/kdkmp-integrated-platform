"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosReversalClient } from "@/types/pos-reversal";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REASON_PATTERN = /^[A-Z0-9_\-]{3,80}$/;

export type CashReversalActionResult =
  | {
      status: "success";
      message: string;
      reversal: {
        salesReturnId: string;
        refundPaymentIntentId: string;
        refundPaymentAttemptId: string;
        inventoryMovementId: string;
        journalEntryId: string;
        cashMovementId: string;
        refundReceiptId: string;
        refundNumber: string;
        refundAmount: number;
        currency: string;
      };
    }
  | { status: "error"; message: string };

function safeReversalError(message?: string | null) {
  switch (message) {
    case "SALES_VOID_DENIED":
      return "Akun Anda tidak memiliki izin membatalkan transaksi POS yang sudah selesai.";
    case "POS_SHIFT_MANAGE_DENIED":
      return "Akun Anda tidak memiliki izin mengelola shift kas untuk refund.";
    case "POS_COMPLETED_SALE_REQUIRED":
      return "Hanya transaksi POS yang sudah selesai yang dapat dibalik melalui proses ini.";
    case "POS_SALE_ALREADY_REVERSED_OR_RETURNING":
      return "Transaksi ini sudah memiliki proses void/return aktif atau sudah selesai dibalik.";
    case "POS_REFUND_OPEN_SHIFT_REQUIRED":
      return "Refund tunai memerlukan shift POS yang masih terbuka.";
    case "POS_REFUND_OWN_SHIFT_REQUIRED":
      return "Refund tunai hanya dapat keluar dari shift POS aktif milik Anda sendiri.";
    case "POS_REFUND_SHIFT_SCOPE_MISMATCH":
      return "Shift refund tidak berada pada unit transaksi yang sama.";
    case "POS_REFUND_TERMINAL_NOT_ACTIVE":
      return "Terminal pada shift refund tidak lagi aktif.";
    case "POS_REFUND_CASH_INSUFFICIENT":
      return "Kas pada shift aktif tidak cukup untuk membayar refund ini.";
    case "POS_ORIGINAL_CASH_MOVEMENT_REQUIRED":
    case "POS_ORIGINAL_SETTLED_PAYMENT_REQUIRED":
    case "POS_ORIGINAL_SETTLED_CASH_ATTEMPT_REQUIRED":
    case "POS_ORIGINAL_PAYMENT_CASH_LINK_MISMATCH":
    case "POS_ORIGINAL_PAYMENT_ALLOCATION_REQUIRED":
      return "Riwayat pembayaran tunai asli tidak lengkap atau tidak konsisten. Reversal tidak dijalankan.";
    case "POS_ORIGINAL_RECEIPT_REQUIRED":
      return "Struk transaksi asli tidak lengkap. Reversal tidak dijalankan.";
    case "POS_ORIGINAL_INVENTORY_MOVEMENT_REQUIRED":
    case "POS_ORIGINAL_INVENTORY_LINES_REQUIRED":
      return "Riwayat pengeluaran stok asli tidak lengkap. Reversal tidak dijalankan.";
    case "POS_ORIGINAL_POSTED_JOURNAL_REQUIRED":
    case "POS_ORIGINAL_JOURNAL_LINES_REQUIRED":
      return "Jurnal transaksi asli tidak lengkap. Reversal tidak dijalankan.";
    case "POS_ACCOUNTING_PERIOD_NOT_OPEN":
      return "Periode akuntansi saat ini tidak terbuka. Reversal tidak dijalankan.";
    case "POS_SALE_REVERSAL_STATE_CHANGED":
      return "Status transaksi berubah saat reversal diproses. Muat ulang dan periksa kembali.";
    case "POS_IDEMPOTENCY_CONFLICT":
      return "Permintaan reversal bentrok dengan proses sebelumnya. Muat ulang sebelum mencoba lagi.";
    default:
      return "Reversal belum dapat diselesaikan. Tidak ada reversal parsial yang boleh diposting.";
  }
}

export async function reverseCashPosSaleAction(input: {
  saleId: string;
  refundShiftId: string;
  reasonCode: string;
  reasonNote?: string | null;
}): Promise<CashReversalActionResult> {
  if (!UUID_PATTERN.test(input.saleId) || !UUID_PATTERN.test(input.refundShiftId)) {
    return { status: "error", message: "Transaksi atau shift refund tidak valid." };
  }

  const reasonCode = input.reasonCode.trim().toUpperCase();
  if (!REASON_PATTERN.test(reasonCode)) {
    return { status: "error", message: "Alasan reversal tidak valid." };
  }

  const reasonNote = input.reasonNote?.trim() || null;
  if (reasonNote && reasonNote.length > 500) {
    return { status: "error", message: "Catatan reversal terlalu panjang." };
  }

  const db = asPosReversalClient(await createClient());
  const { data, error } = await db.rpc("reverse_cash_pos_sale", {
    p_sales_transaction_id: input.saleId,
    p_refund_pos_shift_id: input.refundShiftId,
    p_reason_code: reasonCode,
    p_reason_note: reasonNote,
    p_idempotency_key: `POS-REV-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safeReversalError(error.message) };

  const reversal = data?.[0];
  if (
    !reversal?.sales_return_id ||
    !reversal.refund_payment_intent_id ||
    !reversal.refund_payment_attempt_id ||
    !reversal.inventory_movement_id ||
    !reversal.journal_entry_id ||
    !reversal.cash_movement_id ||
    !reversal.refund_receipt_id
  ) {
    return {
      status: "error",
      message: "Reversal belum menghasilkan seluruh bukti pembalik. Status sukses tidak ditampilkan.",
    };
  }

  const { data: refundReceipt, error: refundReceiptError } = await db
    .from("pos_refund_receipts")
    .select("id,refund_number,currency,refund_amount")
    .eq("id", reversal.refund_receipt_id)
    .single();

  if (refundReceiptError || !refundReceipt) {
    return {
      status: "error",
      message: "Reversal selesai tetapi bukti refund belum dapat dibaca. Muat ulang halaman sebelum tindakan lanjutan.",
    };
  }

  revalidatePath("/dashboard/pos");

  return {
    status: "success",
    message: "Reversal tunai berhasil diposting secara terkendali.",
    reversal: {
      salesReturnId: reversal.sales_return_id,
      refundPaymentIntentId: reversal.refund_payment_intent_id,
      refundPaymentAttemptId: reversal.refund_payment_attempt_id,
      inventoryMovementId: reversal.inventory_movement_id,
      journalEntryId: reversal.journal_entry_id,
      cashMovementId: reversal.cash_movement_id,
      refundReceiptId: reversal.refund_receipt_id,
      refundNumber: refundReceipt.refund_number,
      refundAmount: Number(refundReceipt.refund_amount),
      currency: refundReceipt.currency,
    },
  };
}
