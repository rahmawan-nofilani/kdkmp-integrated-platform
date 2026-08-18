import type { SupabaseClient } from "@supabase/supabase-js";

export type AccountingAccount={id:string;code:string;name:string;account_class:string;normal_balance:string;is_posting:boolean;is_control_account:boolean;control_purpose:string|null;status:string;notes:string|null};
export type AccountingPeriod={id:string;period_code:string;period_name:string;start_date:string;end_date:string;status:string};
export type AccountingJournal={id:string;journal_number:string;entry_date:string;description:string;source_domain:string;status:string;posted_at:string|null};
export type AccountingEvent={id:string;event_code:string;domain:string;name:string;status:string};
export type AccountingMapping={id:string;event_definition_id:string;version_no:number;status:string;effective_from:string|null;effective_until:string|null};
export type AccountingReconciliation={id:string;reconciliation_type:string;as_of_date:string;subledger_amount:number|null;gl_amount:number|null;difference_amount:number|null;status:string;generated_at:string};
export type AccountingControlMapping={id:string;subledger_code:string;control_account_id:string;status:string;effective_from:string|null};

export type AccountingDashboardSnapshot={
  accounts:AccountingAccount[];periods:AccountingPeriod[];journals:AccountingJournal[];events:AccountingEvent[];mappings:AccountingMapping[];reconciliations:AccountingReconciliation[];control_mappings:AccountingControlMapping[];
};
type RpcResult={data:unknown;error:{message:string}|null};
const asArray=<T>(value:unknown):T[]=>Array.isArray(value)?value as T[]:[];
function normalize(value:unknown):AccountingDashboardSnapshot|null{
  if(!value||typeof value!=="object"||Array.isArray(value)) return null;
  const row=value as Record<string,unknown>;
  return {accounts:asArray<AccountingAccount>(row.accounts),periods:asArray<AccountingPeriod>(row.periods),journals:asArray<AccountingJournal>(row.journals),events:asArray<AccountingEvent>(row.events),mappings:asArray<AccountingMapping>(row.mappings),reconciliations:asArray<AccountingReconciliation>(row.reconciliations),control_mappings:asArray<AccountingControlMapping>(row.control_mappings)};
}
export async function getAccountingDashboardSnapshot(client:SupabaseClient){
  const rpc=client.rpc.bind(client) as unknown as (fn:"get_accounting_dashboard_snapshot")=>Promise<RpcResult>;
  const {data,error}=await rpc("get_accounting_dashboard_snapshot");
  if(error) return {data:null,error};
  return {data:normalize(data),error:null};
}
