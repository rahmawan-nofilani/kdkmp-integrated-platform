"use client";

import { type FormEvent, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { PosCustomerOption } from "@/types/pos";
import { searchPosCustomersAction, setPosSaleCustomerAction } from "./customer-actions";

export function PosCustomer({
  saleId,
  terminalId,
  selectedCustomer,
  canEdit,
}: {
  saleId: string | null;
  terminalId: string | null;
  selectedCustomer: PosCustomerOption | null;
  canEdit: boolean;
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<PosCustomerOption[]>([]);
  const [message, setMessage] = useState("");
  const [isPending, startTransition] = useTransition();
  const searchReady = Boolean(saleId && terminalId && canEdit && query.trim().length >= 2);

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!terminalId || !searchReady || isPending) return;

    setMessage("");
    startTransition(async () => {
      const result = await searchPosCustomersAction({ terminalId, query });
      setResults(result.customers);
      setMessage(result.message);
    });
  }

  function changeCustomer(customerMemberId: string | null) {
    if (!saleId || !canEdit || isPending) return;

    setMessage("");
    startTransition(async () => {
      const result = await setPosSaleCustomerAction({ saleId, customerMemberId });
      setMessage(result.message);
      if (result.status === "success") {
        setQuery("");
        setResults([]);
        router.refresh();
      }
    });
  }

  return (
    <section className="pos-customer" aria-labelledby="pos-customer-title">
      <div className="pos-customer-heading">
        <div>
          <span>Pelanggan</span>
          <h3 id="pos-customer-title">{selectedCustomer ? "Anggota terhubung" : "Pelanggan umum"}</h3>
        </div>
        <span className="pos-customer-optional">Opsional</span>
      </div>

      {selectedCustomer ? (
        <div className="pos-customer-selected">
          <span>
            <strong>{selectedCustomer.full_name}</strong>
            <small>{selectedCustomer.member_number ?? "Nomor anggota belum ditetapkan"}</small>
          </span>
          <button
            type="button"
            disabled={!canEdit || isPending}
            onClick={() => changeCustomer(null)}
          >
            {isPending ? "Memproses…" : "Hapus"}
          </button>
        </div>
      ) : (
        <p className="pos-customer-note">
          Transaksi tetap dapat diselesaikan tanpa memilih anggota. Data kontak, identitas, dan keuangan tidak ditampilkan.
        </p>
      )}

      <form className="pos-customer-search" onSubmit={submitSearch}>
        <label htmlFor="pos-customer-query">Cari anggota aktif</label>
        <div>
          <input
            id="pos-customer-query"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              if (results.length > 0) setResults([]);
            }}
            placeholder={saleId ? "Nama atau nomor anggota" : "Tambahkan barang terlebih dahulu"}
            minLength={2}
            maxLength={80}
            autoComplete="off"
            disabled={!saleId || !terminalId || !canEdit || isPending}
          />
          <button type="submit" disabled={!searchReady || isPending}>
            {isPending ? "Mencari…" : "Cari"}
          </button>
        </div>
      </form>

      {!saleId ? (
        <p className="pos-customer-help">Tambahkan barang pertama untuk membuat transaksi, lalu anggota dapat dipilih.</p>
      ) : null}

      {message ? <div className="pos-customer-message" role="status">{message}</div> : null}

      {results.length > 0 ? (
        <div className="pos-customer-results" aria-label="Hasil pencarian anggota">
          {results.map((customer) => (
            <button
              key={customer.member_id}
              type="button"
              disabled={!canEdit || isPending}
              onClick={() => changeCustomer(customer.member_id)}
            >
              <span>
                <strong>{customer.full_name}</strong>
                <small>{customer.member_number ?? "Nomor belum ditetapkan"}</small>
              </span>
              <span>{selectedCustomer?.member_id === customer.member_id ? "Dipilih" : "Pilih"}</span>
            </button>
          ))}
        </div>
      ) : null}
    </section>
  );
}
