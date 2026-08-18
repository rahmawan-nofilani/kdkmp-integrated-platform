"use client";

import { useMemo, useState } from "react";
import { createMultiLineJournalDraftAction } from "./multi-line-actions";
import type { AccountingAccount, AccountingPeriod } from "@/lib/accounting/dashboard-snapshot";

type Line = { account_id: string; debit: string; credit: string; memo: string };
const emptyLine = (): Line => ({ account_id: "", debit: "", credit: "", memo: "" });

function money(value: string) {
  const n = Number(value || 0);
  return Number.isFinite(n) && n >= 0 ? Math.round(n * 100) / 100 : 0;
}

export default function JournalEditor({ accounts, periods }: { accounts: AccountingAccount[]; periods: AccountingPeriod[] }) {
  const [lines, setLines] = useState<Line[]>([emptyLine(), emptyLine()]);
  const totals = useMemo(() => ({ debit: lines.reduce((sum, line) => sum + money(line.debit), 0), credit: lines.reduce((sum, line) => sum + money(line.credit), 0) }), [lines]);
  const balanced = totals.debit > 0 && Math.abs(totals.debit - totals.credit) < 0.005;
  const validLines = lines.length >= 2 && lines.every((line) => { const debit = money(line.debit); const credit = money(line.credit); return Boolean(line.account_id) && ((debit > 0 && credit === 0) || (credit > 0 && debit === 0)); });
  const payload = JSON.stringify(lines.map((line) => ({ account_id: line.account_id, debit: money(line.debit), credit: money(line.credit), memo: line.memo.trim() || null })));

  function patch(index: number, values: Partial<Line>) { setLines((current) => current.map((line, i) => i === index ? { ...line, ...values } : line)); }

  return <form action={createMultiLineJournalDraftAction} className="form-stack">
    <input type="hidden" name="lines_json" value={payload} />
    <div className="field"><label htmlFor="accounting_period_id">Periode</label><select id="accounting_period_id" name="accounting_period_id" required defaultValue={periods[0]?.id}>{periods.map((period) => <option key={period.id} value={period.id}>{period.period_name} · {period.start_date}—{period.end_date}</option>)}</select></div>
    <div className="field"><label htmlFor="entry_date">Tanggal jurnal</label><input id="entry_date" name="entry_date" type="date" required defaultValue={new Date().toISOString().slice(0,10)} /></div>
    <div className="field"><label htmlFor="description">Deskripsi</label><input id="description" name="description" required maxLength={500} /></div>
    <div className="field"><label htmlFor="source_reference">Referensi</label><input id="source_reference" name="source_reference" maxLength={160} /></div>
    <div className="data-table-wrap"><table className="data-table"><thead><tr><th>#</th><th>Akun</th><th>Debit</th><th>Kredit</th><th>Memo</th><th></th></tr></thead><tbody>{lines.map((line, index) => <tr key={index}>
      <td>{index + 1}</td>
      <td><select aria-label={`Akun baris ${index + 1}`} value={line.account_id} onChange={(e) => patch(index,{account_id:e.target.value})}><option value="">Pilih akun</option>{accounts.map((account) => <option key={account.id} value={account.id}>{account.code} · {account.name}</option>)}</select></td>
      <td><input aria-label={`Debit baris ${index + 1}`} type="number" min="0" step="0.01" value={line.debit} onChange={(e) => patch(index,{debit:e.target.value, ...(Number(e.target.value)>0?{credit:""}:{})})} /></td>
      <td><input aria-label={`Kredit baris ${index + 1}`} type="number" min="0" step="0.01" value={line.credit} onChange={(e) => patch(index,{credit:e.target.value, ...(Number(e.target.value)>0?{debit:""}:{})})} /></td>
      <td><input aria-label={`Memo baris ${index + 1}`} maxLength={500} value={line.memo} onChange={(e) => patch(index,{memo:e.target.value})} /></td>
      <td><button type="button" disabled={lines.length <= 2} onClick={() => setLines((current) => current.filter((_,i)=>i!==index))}>Hapus</button></td>
    </tr>)}</tbody></table></div>
    <button type="button" onClick={() => setLines((current) => current.length < 20 ? [...current, emptyLine()] : current)}>+ Tambah baris</button>
    <div className="check-list"><div className="check-item"><span>Total Debit</span><strong>{totals.debit.toLocaleString("id-ID",{minimumFractionDigits:2})}</strong></div><div className="check-item"><span>Total Kredit</span><strong>{totals.credit.toLocaleString("id-ID",{minimumFractionDigits:2})}</strong></div><div className="check-item"><span>Balance</span><span className={`check-state ${balanced ? "" : "pending"}`}>{balanced ? "BALANCED" : "BELUM BALANCE"}</span></div></div>
    <button className="primary-button" type="submit" disabled={!balanced || !validLines}>Simpan DRAFT Multi-line</button>
    <p className="panel-subtitle">Validasi client hanya membantu input. Database tetap menghitung ulang balance, scope, akun aktif, periode, dan permission secara authoritative.</p>
  </form>;
}
