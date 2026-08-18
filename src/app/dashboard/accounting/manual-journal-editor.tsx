"use client";

import { useMemo, useState } from "react";

type PostingAccount = { id: string; code: string; name: string };
type OpenPeriod = { id: string; period_name: string; start_date: string; end_date: string };
type Line = { key: string; accountId: string; debit: string; credit: string; memo: string };

type Props = {
  action: (formData: FormData) => void | Promise<void>;
  accounts: PostingAccount[];
  periods: OpenPeriod[];
  defaultPeriodId?: string;
  defaultEntryDate: string;
};

const newLine = (key: string): Line => ({ key, accountId: "", debit: "", credit: "", memo: "" });
const cents = (value: string) => {
  const number = Number(value || 0);
  return Number.isFinite(number) ? Math.round(number * 100) : 0;
};
const money = (value: number) => new Intl.NumberFormat("id-ID", { style: "currency", currency: "IDR", maximumFractionDigits: 2 }).format(value / 100);

export function ManualJournalEditor({ action, accounts, periods, defaultPeriodId, defaultEntryDate }: Props) {
  const [lines, setLines] = useState<Line[]>([newLine("line-1"), newLine("line-2")]);

  const analysis = useMemo(() => {
    const rowErrors = lines.map((line) => {
      const debit = cents(line.debit);
      const credit = cents(line.credit);
      if (!line.accountId) return "Pilih akun.";
      if (debit < 0 || credit < 0) return "Nilai tidak boleh negatif.";
      if ((debit > 0 && credit > 0) || (debit === 0 && credit === 0)) return "Isi tepat satu sisi: Debit atau Kredit.";
      return null;
    });
    const totalDebit = lines.reduce((sum, line) => sum + Math.max(0, cents(line.debit)), 0);
    const totalCredit = lines.reduce((sum, line) => sum + Math.max(0, cents(line.credit)), 0);
    const balanced = totalDebit > 0 && totalDebit === totalCredit;
    const valid = lines.length >= 2 && rowErrors.every((error) => error === null) && balanced;
    return { rowErrors, totalDebit, totalCredit, balanced, valid };
  }, [lines]);

  const serializedLines = JSON.stringify(lines.map((line) => ({
    account_id: line.accountId,
    debit: cents(line.debit) / 100,
    credit: cents(line.credit) / 100,
    memo: line.memo.trim() || null,
  })));

  function patchLine(index: number, patch: Partial<Line>) {
    setLines((current) => current.map((line, lineIndex) => lineIndex === index ? { ...line, ...patch } : line));
  }

  function addLine() {
    if (lines.length >= 20) return;
    setLines((current) => [...current, newLine(`line-${Date.now()}-${current.length}`)]);
  }

  function removeLine(index: number) {
    if (lines.length <= 2) return;
    setLines((current) => current.filter((_, lineIndex) => lineIndex !== index));
  }

  return (
    <form action={action} className="form-stack">
      <div className="dashboard-grid">
        <div className="field">
          <label htmlFor="accounting_period_id">Periode</label>
          <select id="accounting_period_id" name="accounting_period_id" required defaultValue={defaultPeriodId}>
            {periods.map((period) => <option key={period.id} value={period.id}>{period.period_name} · {period.start_date}—{period.end_date}</option>)}
          </select>
        </div>
        <div className="field">
          <label htmlFor="entry_date">Tanggal Jurnal</label>
          <input id="entry_date" name="entry_date" type="date" required defaultValue={defaultEntryDate} />
        </div>
      </div>

      <div className="field">
        <label htmlFor="description">Deskripsi</label>
        <input id="description" name="description" required maxLength={500} placeholder="Contoh: Koreksi klasifikasi biaya operasional" />
      </div>
      <div className="field">
        <label htmlFor="source_reference">Referensi</label>
        <input id="source_reference" name="source_reference" maxLength={160} placeholder="Opsional: dokumen / memo internal" />
      </div>

      <input type="hidden" name="lines_json" value={serializedLines} />

      <div className="data-table-wrap">
        <table className="data-table">
          <thead><tr><th>#</th><th>Akun</th><th>Debit</th><th>Kredit</th><th>Memo</th><th>Validasi</th><th></th></tr></thead>
          <tbody>
            {lines.map((line, index) => (
              <tr key={line.key}>
                <td>{index + 1}</td>
                <td>
                  <select value={line.accountId} onChange={(event) => patchLine(index, { accountId: event.target.value })} aria-label={`Akun baris ${index + 1}`}>
                    <option value="">Pilih akun</option>
                    {accounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}
                  </select>
                </td>
                <td><input type="number" min="0" step="0.01" value={line.debit} onChange={(event) => patchLine(index, { debit: event.target.value, credit: Number(event.target.value) > 0 ? "" : line.credit })} aria-label={`Debit baris ${index + 1}`} placeholder="0" /></td>
                <td><input type="number" min="0" step="0.01" value={line.credit} onChange={(event) => patchLine(index, { credit: event.target.value, debit: Number(event.target.value) > 0 ? "" : line.debit })} aria-label={`Kredit baris ${index + 1}`} placeholder="0" /></td>
                <td><input value={line.memo} maxLength={500} onChange={(event) => patchLine(index, { memo: event.target.value })} aria-label={`Memo baris ${index + 1}`} placeholder="Opsional" /></td>
                <td><span className={`check-state ${analysis.rowErrors[index] ? "pending" : ""}`}>{analysis.rowErrors[index] ?? "VALID"}</span></td>
                <td><button type="button" onClick={() => removeLine(index)} disabled={lines.length <= 2} aria-label={`Hapus baris ${index + 1}`}>Hapus</button></td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr><th colSpan={2}>Total</th><th>{money(analysis.totalDebit)}</th><th>{money(analysis.totalCredit)}</th><th colSpan={3}><span className={`check-state ${analysis.balanced ? "" : "pending"}`}>{analysis.balanced ? "BALANCED" : "BELUM SEIMBANG"}</span></th></tr>
          </tfoot>
        </table>
      </div>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <button type="button" onClick={addLine} disabled={lines.length >= 20}>+ Tambah Baris</button>
        <small className="item-subtext">Minimal 2 baris · maksimal 20 baris di UI · server tetap memvalidasi ulang seluruh jurnal.</small>
      </div>

      <button className="primary-button" type="submit" disabled={!analysis.valid}>Buat DRAFT Jurnal Multi-line</button>
    </form>
  );
}
