"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosPartialReturnClient, type PosPartialReturnLineRequest } from "@/types/pos-partial-return";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REASON_PATTERN = /^[A-Z0-9_\-]{3,80}$/;

export type PartialReturnActionResult =
  | {
      status: "success";
      message: string;
      partialReturn: {
        salesReturnId: string;
        refundReceiptId: string;
        refundNumber: string;
        refundAmount: number;
        currency: string;
        saleFullyReturned: boolean;
      };
    }
  | { status: "error"; message: string };

function safePartialReturnError(message?: string | null) {
  switch (message) {
    case "SALES_RETURN_DENIED":
      return "Akun Anda belum memiliki izin SALES_RETURN untuk memproses retur.";
    case "POS_SHIFT_MANAGE_DENIED":
      return "Akun Anda tidak memiliki izin mengelola shift kas untuk refund.";
    case "POS_COMPLETED_SALE_REQUIRED":
      return "Retur hanya dapat diproses dari transaksi POS tunai yang masih berstatus selesai.";
    case "POS_RETURN_DUPLICATE_LINE":
      return "Barang yang sama tidak boleh dikirim dua kali dalam satu permintaan retur.";
    case "POS_RETURN_QUANTITY_INVALID":
      return "Jumlah barang yang dikembalikan harus lebih besar dari nol.";
    case "POS_RETURN_QUANTITY_EXCEEDS_REMAINING":
    case "POS_RETURN_LINE_ALREADY_FULLY_RETURNED":
      return "Jumlah retur melebihi sisa barang yang masih dapat dikembalikan.";
    case "POS_RETURN_SALE_LINE_NOT_FOUND":
      return "Salah satu baris transaksi tidak lagi cocok dengan transaksi asli.";
    case "POS_REFUND_OPEN_SHIFT_REQUIRED":
      return "Refund tunai memerlukan shift POS yang masih terbuka.";
    case "POS_REFUND_OWN_SHIFT_REQUIRED":
      return "Refund tunai hanya dapat keluar dari shift POS aktif milik Anda sendiri.";
    case "POS_REFUND_CASH_INSUFFICIENT":
      return "Kas pada shift aktif tidak cukup untuk membayar refund ini.";
    case "POS_ACCOUNTING_PERIOD_NOT_OPEN":
      return "Periode akuntansi saat ini tidak terbuka. Retur tidak diposting.";
    case "POS_RETURN_SOURCE_INVENTORY_INSUFFICIENT":
    case "POS_RETURN_SOURCE_COST_REQUIRED":
    case "POS_ORIGINAL_INVENTORY_MOVEMENT_REQUIRED":
      return "Riwayat stok transaksi asli tidak cukup untuk memproses retur secara aman.";
    case "POS_ORIGINAL_POSTED_JOURNAL_REQUIRED":
    case "POS_ORIGINAL_JOURNAL_ACCOUNTS_REQUIRED":
    case "POS_ORIGINAL_TAX_JOURNAL_ACCOUNT_REQUIRED":
      return "Riwayat jurnal transaksi asli tidak lengkap. Retur tidak diposting.";
    case "POS_ORIGINAL_SETTLED_PAYMENT_REQUIRED":
    case "POS_ORIGINAL_SETTLED_CASH_ATTEMPT_REQUIRED":
    case "POS_ORIGINAL_PAYMENT_ALLOCATION_REQUIRED":
    case "POS_ORIGINAL_CASH_MOVEMENT_REQUIRED":
    case "POS_ORIGINAL_RECEIPT_REQUIRED":
      return "Riwayat pembayaran tunai asli tidak lengkap atau tidak konsisten.";
    case "POS_IDEMPOTENCY_CONFLICT":
      return "Permintaan retur bentrok dengan proses sebelumnya. Muat ulang sebelum mencoba lagi.";
    default:
      return "Retur belum dapat diselesaikan. Tidak ada bagian transaksi yang boleh diposting sebagian.";
  }
}

export async function returnCashPosItemsAction(input: {
  saleId: string;
  refundShiftId: string;
  lines: Array<{ salesTransactionLineId: string; quantity: number }>;
  reasonCode: string;
  reasonNote?: string | null;
}): Promise<PartialReturnActionResult> {
  if (!UUID_PATTERN.test(input.saleId) || !UUID_PATTERN.test(input.refundShiftId)) {
    return { status: "error", message: "Transaksi atau shift refund tidak valid." };
  }

  if (!Array.isArray(input.lines) || input.lines.length === 0 || input.lines.length > 100) {
    return { status: "error", message: "Pilih minimal satu barang yang akan dikembalikan." };
  }

  const seen = new Set<string>();
  const lines: PosPartialReturnLineRequest[] = [];
  for (const line of input.lines) {
    if (!UUID_PATTERN.test(line.salesTransactionLineId) || !Number.isFinite(line.quantity) || line.quantity <= 0) {
      return { status: "error", message: "Data jumlah retur tidak valid." };
    }
    if (seen.has(line.salesTransactionLineId)) {
      return { status: "error", message: "Barang yang sama tidak boleh dipilih dua kali." };
    }
    seen.add(line.salesTransactionLineId);
    lines.push({ sales_transaction_line_id: line.salesTransactionLineId, quantity: line.quantity });
  }

  const reasonCode = input.reasonCode.trim().toUpperCase();
  if (!REASON_PATTERN.test(reasonCode)) {
    return { status: "error", message: "Alasan retur tidak valid." };
  }
  const reasonNote = input.reasonNote?.trim() || null;
  if (reasonNote && reasonNote.length > 500) {
    return { status: "error", message: "Catatan retur terlalu panjang." };
  }

  const db = asPosPartialReturnClient(await createClient());
  const { data, error } = await db.rpc("return_cash_pos_items", {
    p_sales_transaction_id: input.saleId,
    p_refund_pos_shift_id: input.refundShiftId,
    p_lines: lines,
    p_reason_code: reasonCode,
    p_reason_note: reasonNote,
    p_idempotency_key: `POS-RET-${randomUUID()}`,
  });
  if (error) return { status: "error", message: safePartialReturnError(error.message) };

  const result = data?.[0];
  if (!result?.sales_return_id || !result.refund_receipt_id || !result.refund_amount) {
    return { status: "error", message: "Retur selesai tetapi bukti hasil belum lengkap. Muat ulang halaman." };
  }

  const { data: receipt, error: receiptError } = await db
    .from("pos_refund_receipts")
    .select("id,refund_number,currency,refund_amount")
    .eq("id", result.refund_receipt_id)
    .single();
  if (receiptError || !receipt) {
    return { status: "error", message: "Retur selesai tetapi struk refund belum dapat dibaca. Muat ulang halaman." };
  }

  revalidatePath("/dashboard/pos");
  return {
    status: "success",
    message: result.sale_fully_returned
      ? "Retur terakhir berhasil. Seluruh barang pada transaksi ini sudah dikembalikan."
      : "Retur sebagian berhasil diposting secara terkendali.",
    partialReturn: {
      salesReturnId: result.sales_return_id,
      refundReceiptId: result.refund_receipt_id,
      refundNumber: receipt.refund_number,
      refundAmount: Number(receipt.refund_amount),
      currency: receipt.currency,
      saleFullyReturned: Boolean(result.sale_fully_returned),
    },
  };
}
