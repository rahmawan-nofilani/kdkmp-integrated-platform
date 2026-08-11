"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosClient } from "@/types/pos";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type CashPaymentResult =
  | {
      status: "success";
      message: string;
      receipt: {
        id: string;
        receiptNumber: string;
        currency: string;
        totalAmount: number;
        cashReceived: number;
        changeAmount: number;
        issuedAt: string;
      };
    }
  | { status: "error"; message: string };

function safePaymentError(message?: string | null) {
  switch (message) {
    case "POS_CASH_RECEIVED_INSUFFICIENT":
      return "Uang diterima masih kurang dari total transaksi.";
    case "POS_CASH_RECEIVED_INVALID":
      return "Nominal uang diterima tidak valid.";
    case "POS_PRICE_CHANGED_RELOAD_CART":
      return "Harga barang berubah. Tutup pembayaran, muat ulang keranjang, lalu periksa kembali.";
    case "POS_INSUFFICIENT_STOCK":
    case "POS_STOCK_PICK_FAILED":
      return "Stok berubah atau tidak mencukupi. Tutup pembayaran dan periksa keranjang.";
    case "POS_ACCOUNTING_MAPPING_NOT_READY":
    case "POS_ACCOUNTING_ACCOUNTS_NOT_CONFIGURED":
    case "POS_ACCOUNTING_PERIOD_NOT_OPEN":
      return "Konfigurasi akuntansi POS belum siap. Tidak ada pembayaran yang diposting. Hubungi Manager.";
    case "POS_INVENTORY_COST_NOT_READY":
    case "POS_COSTING_METHOD_NOT_READY":
      return "Biaya persediaan barang belum siap untuk posting. Tidak ada pembayaran yang diposting.";
    case "POS_SERIAL_ITEM_REQUIRES_SERIAL_SELECTION":
    case "POS_MANUAL_PICK_ITEM_NOT_SUPPORTED":
      return "Keranjang berisi barang yang memerlukan pemilihan stok khusus. Hubungi petugas Gudang.";
    case "POS_OWN_DRAFT_SALE_REQUIRED":
    case "POS_SALE_NOT_FOUND":
      return "Transaksi sudah berubah atau tidak lagi aktif. Muat ulang halaman.";
    case "POS_OWN_OPEN_SHIFT_REQUIRED":
      return "Shift kasir tidak lagi aktif. Tidak ada pembayaran yang diposting.";
    case "POS_PAYMENT_CAPTURE_DENIED":
    case "SALES_CREATE_DENIED":
      return "Akun Anda tidak memiliki izin menerima pembayaran POS.";
    case "POS_IDEMPOTENCY_CONFLICT":
      return "Permintaan pembayaran bentrok dengan proses sebelumnya. Muat ulang halaman sebelum mencoba lagi.";
    default:
      return "Pembayaran belum dapat diselesaikan. Tidak ada transaksi parsial yang diposting.";
  }
}

export async function completeCashPaymentAction(input: {
  saleId: string;
  cashReceived: number;
}): Promise<CashPaymentResult> {
  if (!UUID_PATTERN.test(input.saleId)) {
    return { status: "error", message: "Transaksi POS tidak valid. Muat ulang halaman." };
  }
  if (!Number.isFinite(input.cashReceived) || input.cashReceived <= 0 || input.cashReceived > 999_999_999_999) {
    return { status: "error", message: "Nominal uang diterima tidak valid." };
  }

  const db = asPosClient(await createClient());
  const { data, error } = await db.rpc("complete_cash_pos_sale", {
    p_sales_transaction_id: input.saleId,
    p_cash_received: input.cashReceived,
    p_idempotency_key: `POS-CASH-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safePaymentError(error.message) };
  const completion = data?.[0];
  if (!completion?.receipt_id) {
    return { status: "error", message: "Struk transaksi belum terbentuk. Tidak ada status sukses yang ditampilkan." };
  }

  const { data: receipt, error: receiptError } = await db
    .from("pos_receipts")
    .select("id,receipt_number,currency,total_amount,cash_received,change_amount,issued_at")
    .eq("id", completion.receipt_id)
    .single();

  if (receiptError || !receipt) {
    return { status: "error", message: "Transaksi selesai tetapi struk belum dapat dibaca. Muat ulang halaman." };
  }

  revalidatePath("/dashboard/pos");
  return {
    status: "success",
    message: "Pembayaran tunai berhasil dan transaksi sudah selesai.",
    receipt: {
      id: receipt.id,
      receiptNumber: receipt.receipt_number,
      currency: receipt.currency,
      totalAmount: Number(receipt.total_amount),
      cashReceived: Number(receipt.cash_received),
      changeAmount: Number(receipt.change_amount ?? 0),
      issuedAt: receipt.issued_at,
    },
  };
}
