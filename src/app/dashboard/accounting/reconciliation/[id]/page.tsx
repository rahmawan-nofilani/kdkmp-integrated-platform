import Link from "next/link";
import { notFound } from "next/navigation";
import { requireAccessContext } from "@/lib/auth/access-context";
import { requirePermission } from "@/lib/auth/permissions";

export const dynamic = "force-dynamic";

type Run = { id:string; reconciliation_type:string; as_of_date:string; subledger_amount:number|null; gl_amount:number|null; difference_amount:number|null; status:string; generated_at:string; reviewed_at:string|null; notes:string|null };
type ExceptionRow = { id:string; exception_code:string; description:string; amount:number|null; status:string; resolution_notes:string|null; created_at:string; resolved_at:string|null };
type QueryResult<T> = { data:T; error:{message:string}|null };
type QueryChain<T> = { eq:(column:string,value:string)=>QueryChain<T>; order:(column:string,options:{ascending:boolean})=>QueryChain<T>; limit:(count:number)=>Promise<QueryResult<T[]>>; maybeSingle:()=>Promise<QueryResult<T|null>> };
type ReconciliationClient = { from:(table:"reconciliation_runs"|"reconciliation_exceptions")=>{ select:(columns:string)=>QueryChain<Run|ExceptionRow> } };

export default async function ReconciliationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  await requirePermission("ACCOUNTING_VIEW");
  const { id } = await params;
  const { supabase } = await requireAccessContext();
  const client = supabase as unknown as ReconciliationClient;
  const runQuery = client.from("reconciliation_runs").select("id,reconciliation_type,as_of_date,subledger_amount,gl_amount,difference_amount,status,generated_at,reviewed_at,notes").eq("id", id).maybeSingle() as Promise<QueryResult<Run|null>>;
  const exceptionQuery = client.from("reconciliation_exceptions").select("id,exception_code,description,amount,status,resolution_notes,created_at,resolved_at").eq("reconciliation_run_id", id).order("created_at", { ascending: true }).limit(200) as Promise<QueryResult<ExceptionRow[]>>;
  const [{ data: run, error: runError }, { data: exceptions, error: exceptionsError }] = await Promise.all([runQuery, exceptionQuery]);
  if (runError || exceptionsError || !run) notFound();
  const rows = exceptions ?? [];
  return <>
    <section className="page-heading"><div><p className="eyebrow">Finance & Accounting</p><h1>Reconciliation Drill-down</h1><p>{run.reconciliation_type} · as of {run.as_of_date}</p></div><Link className="secondary-button" href="/dashboard/accounting">Kembali</Link></section>
    <section className="metric-grid">
      <article className="metric-card"><div className="metric-label">Subledger</div><div className="metric-value">{Number(run.subledger_amount ?? 0).toLocaleString("id-ID")}</div></article>
      <article className="metric-card"><div className="metric-label">General Ledger</div><div className="metric-value">{Number(run.gl_amount ?? 0).toLocaleString("id-ID")}</div></article>
      <article className="metric-card"><div className="metric-label">Difference</div><div className="metric-value">{Number(run.difference_amount ?? 0).toLocaleString("id-ID")}</div></article>
      <article className="metric-card"><div className="metric-label">Status</div><div className="metric-value">{run.status}</div></article>
    </section>
    <section className="panel section-panel"><h3>Exception Register</h3><p className="panel-subtitle">Detail ini read-only dan tetap dibatasi RLS/data scope.</p>{rows.length ? <div className="data-table-wrap"><table className="data-table"><thead><tr><th>Kode</th><th>Deskripsi</th><th>Nominal</th><th>Status</th><th>Resolusi</th></tr></thead><tbody>{rows.map((row) => <tr key={row.id}><td>{row.exception_code}</td><td>{row.description}</td><td>{row.amount == null ? "—" : Number(row.amount).toLocaleString("id-ID")}</td><td>{row.status}</td><td>{row.resolution_notes ?? "—"}</td></tr>)}</tbody></table></div> : <div className="empty-state">Tidak ada exception pada reconciliation run ini.</div>}</section>
  </>;
}
