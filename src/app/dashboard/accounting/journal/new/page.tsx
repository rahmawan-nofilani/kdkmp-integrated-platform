import Link from "next/link";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";
import { getAccountingDashboardSnapshot } from "@/lib/accounting/dashboard-snapshot";
import JournalEditor from "./journal-editor";

export const dynamic = "force-dynamic";

export default async function NewJournalPage() {
  await requirePermission("ACCOUNTING_DRAFT_CREATE");
  const { supabase } = await requireAccessContext();
  const { data, error } = await getAccountingDashboardSnapshot(supabase);
  if (error || !data) return <section className="panel"><h3>Editor jurnal belum dapat dimuat</h3><p className="panel-subtitle">Snapshot accounting gagal dibaca. Tidak ada fallback lintas-scope.</p></section>;

  const accounts = data.accounts.filter((account) => account.is_posting && account.status === "ACTIVE");
  const periods = data.periods.filter((period) => period.status === "OPEN");

  return <>
    <section className="page-heading"><div><p className="eyebrow">Finance & Accounting</p><h1>Manual Journal · Multi-line Editor</h1><p>Buat jurnal hingga 20 baris. Hanya DRAFT yang dibuat; validasi dan posting tetap melalui Manager dan BOARD.</p></div><Link className="secondary-button" href="/dashboard/accounting">Kembali</Link></section>
    <section className="panel section-panel">
      {periods.length && accounts.length >= 2 ? <JournalEditor accounts={accounts} periods={periods} /> : <div className="empty-state">Periode OPEN atau posting account belum tersedia.</div>}
    </section>
  </>;
}
