"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosClient } from "@/types/pos";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PosCartActionResult = {
  status: "success" | "error";
  message: string;
};

function validUuid(value: string) {
  return UUID_PATTERN.test(value);
}

function safeCartError(message?: string | null) {
  switch (message) {
    case "POS_INSUFFICIENT_STOCK":
      return "Stok barang tidak mencukupi untuk jumlah tersebut.";
    case "POS_PRICE_NOT_CONFIGURED":
      return "Harga jual barang belum aktif. Hubungi Manager.";
    case "POS_ITEM_NOT_AVAILABLE":
    case "POS_ITEM_UOM_NOT_CONFIGURED":
      return "Barang atau satuan jual belum siap digunakan di POS.";
    case "POS_OWN_OPEN_SHIFT_REQUIRED":
      return "Shift kasir tidak aktif. Muat ulang halaman dan periksa shift Anda.";
    case "POS_SALE_IN_PROGRESS":
      return "Ada transaksi yang sedang diproses. Selesaikan transaksi tersebut terlebih dahulu.";
    case "POS_OWN_DRAFT_SALE_REQUIRED":
    case "POS_SALE_NOT_FOUND":
      return "Keranjang sudah berubah atau tidak lagi aktif. Muat ulang halaman.";
    case "POS_LINE_NOT_FOUND":
      return "Barang sudah tidak ada di keranjang. Muat ulang halaman.";
    case "SALES_CREATE_DENIED":
      return "Akun Anda tidak memiliki izin transaksi POS.";
    case "POS_IDEMPOTENCY_CONFLICT":
      return "Permintaan transaksi bentrok dengan proses sebelumnya. Muat ulang halaman dan coba lagi.";
    default:
      return "Keranjang belum dapat diperbarui. Tidak ada transaksi pembayaran yang dibuat.";
  }
}

export async function addPosCartItemAction(input: {
  terminalId: string;
  shiftId: string;
  inventoryItemId: string;
  uomId: string;
}): Promise<PosCartActionResult> {
  if (![input.terminalId, input.shiftId, input.inventoryItemId, input.uomId].every(validUuid)) {
    return { status: "error", message: "Data barang atau shift POS tidak valid. Muat ulang halaman." };
  }

  const supabase = asPosClient(await createClient());
  const { error } = await supabase.rpc("add_pos_item_to_current_sale", {
    p_terminal_id: input.terminalId,
    p_pos_shift_id: input.shiftId,
    p_inventory_item_id: input.inventoryItemId,
    p_uom_id: input.uomId,
    p_quantity: 1,
    p_idempotency_key: `POS-CART-ADD-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safeCartError(error.message) };

  revalidatePath("/dashboard/pos");
  return { status: "success", message: "Barang ditambahkan ke keranjang." };
}

export async function changePosCartLineAction(input: {
  saleId: string;
  lineId: string;
  delta: 1 | -1;
}): Promise<PosCartActionResult> {
  if (!validUuid(input.saleId) || !validUuid(input.lineId) || ![1, -1].includes(input.delta)) {
    return { status: "error", message: "Perubahan jumlah barang tidak valid." };
  }

  const supabase = asPosClient(await createClient());
  const { error } = await supabase.rpc("change_pos_cart_line_quantity", {
    p_sales_transaction_id: input.saleId,
    p_sales_transaction_line_id: input.lineId,
    p_delta: input.delta,
    p_idempotency_key: `POS-CART-QTY-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safeCartError(error.message) };

  revalidatePath("/dashboard/pos");
  return { status: "success", message: input.delta > 0 ? "Jumlah barang ditambah." : "Jumlah barang dikurangi." };
}

export async function cancelPosCartAction(saleId: string): Promise<PosCartActionResult> {
  if (!validUuid(saleId)) {
    return { status: "error", message: "Keranjang tidak valid. Muat ulang halaman." };
  }

  const supabase = asPosClient(await createClient());
  const { error } = await supabase.rpc("cancel_pos_sale", {
    p_sales_transaction_id: saleId,
    p_idempotency_key: `POS-CART-CANCEL-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safeCartError(error.message) };

  revalidatePath("/dashboard/pos");
  return { status: "success", message: "Transaksi dibatalkan. Keranjang dikosongkan." };
}
