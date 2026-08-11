"use client";

import { useMemo, useState } from "react";
import type { PosCatalogItem } from "@/types/pos";

function formatMoney(value: number, currency: string) {
  return new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: currency || "IDR",
    maximumFractionDigits: 0,
  }).format(value);
}

export function PosCatalog({ items }: { items: PosCatalogItem[] }) {
  const [query, setQuery] = useState("");
  const normalizedQuery = query.trim().toLowerCase();
  const filteredItems = useMemo(() => {
    if (!normalizedQuery) return items;
    return items.filter((item) =>
      `${item.sku} ${item.barcode ?? ""} ${item.item_name} ${item.uom_code}`.toLowerCase().includes(normalizedQuery),
    );
  }, [items, normalizedQuery]);

  return (
    <>
      <label className="pos-search-shell">
        <span className="pos-search-icon" aria-hidden="true">⌕</span>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Scan barcode atau cari barang…"
          aria-label="Scan barcode atau cari barang"
          autoComplete="off"
          enterKeyHint="search"
        />
        {query ? (
          <button className="pos-search-clear" type="button" onClick={() => setQuery("")} aria-label="Hapus pencarian">×</button>
        ) : null}
      </label>

      <div className="pos-catalog-summary">
        <span>{filteredItems.length} pilihan jual</span>
        <span>Harga & stok dari server</span>
      </div>

      {filteredItems.length > 0 ? (
        <div className="pos-product-grid">
          {filteredItems.map((item) => (
            <article className={`pos-product-card ${item.in_stock ? "" : "out"}`} key={`${item.inventory_item_id}:${item.uom_id}`}>
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
              <button className="pos-product-add" type="button" disabled>
                Tambah
                <small>Keranjang tahap berikutnya</small>
              </button>
            </article>
          ))}
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
