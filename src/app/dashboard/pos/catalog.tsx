"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { PosCatalogItem } from "@/types/pos";
import { addPosCartItemAction } from "./cart-actions";

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

export function PosCatalog({
  items,
  terminalId,
  shiftId,
  canAdd,
}: {
  items: PosCatalogItem[];
  terminalId: string;
  shiftId: string;
  canAdd: boolean;
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [message, setMessage] = useState("");
  const [pendingKey, setPendingKey] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();
  const normalizedQuery = query.trim().toLowerCase();

  const filteredItems = useMemo(() => {
    if (!normalizedQuery) return items;
    return items.filter((item) =>
      `${item.sku} ${item.barcode ?? ""} ${item.item_name} ${item.uom_code}`.toLowerCase().includes(normalizedQuery),
    );
  }, [items, normalizedQuery]);

  function addItem(item: PosCatalogItem, clearSearch = false) {
    if (!canAdd || !item.in_stock || isPending) return;
    const key = `${item.inventory_item_id}:${item.uom_id}`;
    setPendingKey(key);
    setMessage("");
    startTransition(async () => {
      const result = await addPosCartItemAction({
        terminalId,
        shiftId,
        inventoryItemId: item.inventory_item_id,
        uomId: item.uom_id,
      });
      setMessage(result.message);
      if (result.status === "success") {
        if (clearSearch) setQuery("");
        router.refresh();
      }
      setPendingKey(null);
    });
  }

  function handleSearchKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key !== "Enter" || !normalizedQuery) return;
    const exactItem = items.find((item) =>
      item.sku.toLowerCase() === normalizedQuery || item.barcode?.toLowerCase() === normalizedQuery,
    );
    if (!exactItem || !exactItem.in_stock) return;
    event.preventDefault();
    addItem(exactItem, true);
  }

  return (
    <>
      <label className="pos-search-shell">
        <span className="pos-search-icon" aria-hidden="true">⌕</span>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={handleSearchKeyDown}
          placeholder="Scan barcode atau cari barang…"
          aria-label="Scan barcode atau cari barang"
          autoComplete="off"
          enterKeyHint="done"
        />
        {query ? (
          <button className="pos-search-clear" type="button" onClick={() => setQuery("")} aria-label="Hapus pencarian">×</button>
        ) : null}
      </label>

      <div className="pos-catalog-summary">
        <span>{filteredItems.length} pilihan jual</span>
        <span>Harga & stok dari server</span>
      </div>

      {message ? <div className="pos-inline-message" role="status">{message}</div> : null}

      {filteredItems.length > 0 ? (
        <div className="pos-product-grid">
          {filteredItems.map((item) => {
            const key = `${item.inventory_item_id}:${item.uom_id}`;
            const itemPending = pendingKey === key && isPending;
            return (
              <article className={`pos-product-card ${item.in_stock ? "" : "out"}`} key={key}>
                <div className="pos-product-topline">
                  <span className="pos-product-sku">{item.sku}</span>
                  <span className={`pos-product-stock ${item.in_stock ? "" : "out"}`}>{item.in_stock ? "Tersedia" : "Habis"}</span>
                </div>
                <strong className="pos-product-name">{item.item_name}</strong>
                <span className="pos-product-uom">per {item.uom_name} · {item.uom_code}</span>
                <div className="pos-product-bottom">
                  <strong>{formatMoney(item.unit_price, item.currency)}</strong>
                  <span>Stok {item.available_quantity} {item.uom_code}</span>
                </div>
                <button
                  className="pos-product-add"
                  type="button"
                  disabled={!canAdd || !item.in_stock || isPending}
                  onClick={() => addItem(item)}
                >
                  {itemPending ? "Menambahkan…" : item.in_stock ? "Tambah" : "Stok habis"}
                  <small>{item.in_stock ? "Masuk keranjang" : "Tidak dapat dijual"}</small>
                </button>
              </article>
            );
          })}
        </div>
      ) : (
        <div className="pos-empty-catalog compact">
          <strong>{items.length === 0 ? "Belum ada barang siap jual." : "Barang tidak ditemukan."}</strong>
          <span>
            {items.length === 0
              ? "Katalog hanya menampilkan barang yang memiliki satuan jual dan harga POS aktif."
              : "Coba nama, SKU, atau scan barcode lain."}
          </span>
        </div>
      )}
    </>
  );
}
