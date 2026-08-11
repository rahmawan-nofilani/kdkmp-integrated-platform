import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database as BaseDatabase, Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type AccountingAccountRow = {
  id: string; organization_id: string; organization_node_id: string; parent_account_id: string | null;
  code: string; name: string; account_class: string; normal_balance: string; is_posting: boolean;
  is_control_account: boolean; control_purpose: string | null; status: string; effective_from: string | null;
  effective_until: string | null; notes: string | null; created_at: string; updated_at: string;
};

type FiscalYearRow = {
  id: string; organization_id: string; organization_node_id: string; fiscal_year: number; start_date: string;
  end_date: string; status: string; created_at: string; updated_at: string;
};

type AccountingPeriodRow = {
  id: string; fiscal_year_id: string; organization_id: string; organization_node_id: string; period_code: string;
  period_name: string; start_date: string; end_date: string; status: string; closed_at: string | null;
  closed_by: string | null; created_at: string; updated_at: string;
};

type JournalEntryRow = {
  id: string; organization_id: string; organization_node_id: string; batch_id: string | null;
  accounting_period_id: string; journal_number: string; entry_date: string; description: string; source_domain: string;
  source_entity_type: string | null; source_entity_id: string | null; source_reference: string | null;
  correlation_id: string | null; idempotency_key: string | null; reversal_of_entry_id: string | null;
  status: string; created_by: string | null; validated_by: string | null; validated_at: string | null;
  posted_by: string | null; posted_at: string | null; created_at: string; updated_at: string;
};

type AccountingEventDefinitionRow = {
  id: string; event_code: string; domain: string; name: string; description: string | null; status: string; created_at: string;
};

type AccountingEventMappingRow = {
  id: string; organization_id: string; organization_node_id: string; event_definition_id: string; version_no: number;
  configuration: Json; status: string; effective_from: string | null; effective_until: string | null;
  created_by: string | null; approved_by: string | null; approved_at: string | null; created_at: string;
};

type ReconciliationRunRow = {
  id: string; organization_id: string; organization_node_id: string; reconciliation_type: string;
  period_id: string | null; as_of_date: string; subledger_amount: number | null; gl_amount: number | null;
  difference_amount: number | null; status: string; generated_by: string | null; generated_at: string;
  reviewed_by: string | null; reviewed_at: string | null; notes: string | null;
};

type ControlAccountRow = {
  id: string; organization_id: string; organization_node_id: string; subledger_code: string; control_account_id: string;
  status: string; effective_from: string | null; effective_until: string | null; notes: string | null; created_at: string;
};

export type AccountingDatabase = Omit<BaseDatabase, "public"> & {
  public: Omit<BaseDatabase["public"], "Tables"> & {
    Tables: BaseDatabase["public"]["Tables"] & {
      accounting_accounts: TableShape<AccountingAccountRow>;
      fiscal_years: TableShape<FiscalYearRow>;
      accounting_periods: TableShape<AccountingPeriodRow>;
      journal_entries: TableShape<JournalEntryRow>;
      accounting_event_definitions: TableShape<AccountingEventDefinitionRow>;
      accounting_event_mappings: TableShape<AccountingEventMappingRow>;
      reconciliation_runs: TableShape<ReconciliationRunRow>;
      subledger_control_accounts: TableShape<ControlAccountRow>;
    };
  };
};

export type AccountingClient = SupabaseClient<AccountingDatabase>;
export function asAccountingClient(client: unknown): AccountingClient { return client as AccountingClient; }
