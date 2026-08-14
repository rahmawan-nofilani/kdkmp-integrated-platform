"use server";

import { randomUUID } from "crypto";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { asPosClient, type PosCustomerOption } from "@/types/pos";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type PosCustomerSearchResult = {
  status: "success" | "error";
  message: string;
  customers: PosCustomerOption[];
};

export type PosCustomerLinkResult = {
  status: "success" | "error";
  message: string;
};

function validUuid(value: string) {
  return UUID_PATTERN.test(value);
}

function normalizeQuery(value: string) {
  return value.trim().replace(/\s+/g, " ");
}

function safeCustomerError(message?: string | null) {
  switch (message) {
    case "POS_CUSTOMER_SEARCH_QUERY_INVALID":
      return "Masukkan minimal 2 karakter nama atau nomor anggota.";
    case "POS_CUSTOMER_MEMBER_NOT_ACTIVE":
      return "Anggota tidak aktif atau tidak berada dalam scope KDKMP ini.";
    case "POS_OWN_OPEN_SHIFT_REQUIRED":
      return "Shift kasir tidak aktif. Muat ulang halaman dan periksa shift Anda.";
    case "POS_OWN_DRAFT_SALE_REQUIRED":
    case "POS_SALE_NOT_FOUND":
      return "Transaksi sudah berubah atau tidak lagi dapat diperbarui.";
    case "POS_CUSTOMER_LOOKUP_SCOPE_DENIED":
    case "POS_SALE_SCOPE_DENIED":
      return "Akses anggota ditolak untuk scope transaksi ini.";
    case "SALES_CREATE_DENIED":
      return "Akun Anda tidak memiliki izin transaksi POS.";
    case "POS_IDEMPOTENCY_CONFLICT":
      return "Permintaan bentrok dengan proses sebelumnya. Muat ulang halaman dan coba lagi.";
    default:
      return "Anggota belum dapat diproses. Transaksi dan data anggota tidak diubah.";
  }
}

export async function searchPosCustomersAction(input: {
  terminalId: string;
  query: string;
}): Promise<PosCustomerSearchResult> {
  const query = normalizeQuery(input.query);

  if (!validUuid(input.terminalId) || query.length < 2 || query.length > 80) {
    return {
      status: "error",
      message: "Masukkan minimal 2 karakter nama atau nomor anggota.",
      customers: [],
    };
  }

  const db = asPosClient(await createClient());
  const { data, error } = await db
    .from("pos_customer_lookup_requests")
    .insert({
      terminal_id: input.terminalId,
      customer_member_id: null,
      search_query: query,
      result_limit: 10,
    })
    .select("result")
    .single();

  if (error) {
    return { status: "error", message: safeCustomerError(error.message), customers: [] };
  }

  const customers = Array.isArray(data?.result) ? data.result : [];
  return {
    status: "success",
    message: customers.length > 0 ? `${customers.length} anggota ditemukan.` : "Anggota tidak ditemukan.",
    customers,
  };
}

export async function setPosSaleCustomerAction(input: {
  saleId: string;
  customerMemberId: string | null;
}): Promise<PosCustomerLinkResult> {
  if (!validUuid(input.saleId) || (input.customerMemberId !== null && !validUuid(input.customerMemberId))) {
    return { status: "error", message: "Data transaksi atau anggota tidak valid. Muat ulang halaman." };
  }

  const db = asPosClient(await createClient());
  const { error } = await db.rpc("link_pos_sale_customer", {
    p_sales_transaction_id: input.saleId,
    p_customer_member_id: input.customerMemberId,
    p_idempotency_key: `POS-CUSTOMER-${randomUUID()}`,
  });

  if (error) return { status: "error", message: safeCustomerError(error.message) };

  revalidatePath("/dashboard/pos");
  return {
    status: "success",
    message: input.customerMemberId ? "Anggota ditautkan ke transaksi." : "Tautan anggota dihapus. Transaksi menjadi pelanggan umum.",
  };
}
