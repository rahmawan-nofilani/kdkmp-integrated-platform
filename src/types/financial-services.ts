import type { SupabaseClient } from "@supabase/supabase-js";
import type { FinancialProductDatabase } from "./financial-products";
import type { Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type FinancialServiceMemberProfileRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; member_id:string;
  status:string; identity_verification_status:string; kyc_status:string; pmpj_status:string; risk_level:string;
  source_of_funds_status:string; last_review_at:string|null; next_review_at:string|null; notes:string|null;
  created_at:string; updated_at:string;
};

type SavingsAccountRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; member_id:string;
  financial_service_profile_id:string; financial_product_id:string; financial_product_version_id:string;
  account_number:string|null; currency:string; product_snapshot:Json; status:string; opened_at:string|null;
  closed_at:string|null; created_by:string|null; created_at:string;
};

type SavingsLedgerRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; savings_account_id:string;
  entry_type:string; direction:string; amount:number; currency:string; channel:string; payment_reference:string|null;
  source_transaction_id:string|null; idempotency_key:string|null; reversal_of_entry_id:string|null; accounting_status:string;
  journal_entry_id:string|null; approval_request_id:string|null; occurred_at:string; value_date:string; created_by:string|null; created_at:string;
};

type LoanApplicationRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; member_id:string;
  financial_service_profile_id:string; financial_product_id:string; financial_product_version_id:string;
  application_number:string|null; requested_amount:number; currency:string; requested_term:number|null;
  requested_term_unit:string|null; purpose_text:string|null; product_snapshot:Json; analysis_snapshot:Json; risk_snapshot:Json;
  status:string; approval_request_id:string|null; submitted_at:string|null; decided_at:string|null;
  created_by:string|null; created_at:string; updated_at:string;
};

type LoanAccountRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; member_id:string;
  financial_service_profile_id:string; loan_application_id:string; financial_product_id:string; financial_product_version_id:string;
  account_number:string|null; approved_amount:number; currency:string; contract_snapshot:Json; repayment_configuration_snapshot:Json;
  status:string; disbursed_at:string|null; maturity_date:string|null; settled_at:string|null; created_at:string;
};

type LoanScheduleRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; loan_account_id:string;
  installment_no:number; due_date:string; principal_due:number; return_or_margin_due:number; fee_due:number; total_due:number;
  status:string; paid_at:string|null; created_at:string;
};

type LoanLedgerRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; loan_account_id:string;
  entry_type:string; principal_amount:number; return_or_margin_amount:number; fee_amount:number; penalty_amount:number;
  currency:string; channel:string; payment_reference:string|null; source_transaction_id:string|null; idempotency_key:string|null;
  reversal_of_entry_id:string|null; accounting_status:string; journal_entry_id:string|null; approval_request_id:string|null;
  occurred_at:string; value_date:string; created_by:string|null; created_at:string;
};

type CollectionCaseRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; loan_account_id:string;
  case_number:string|null; status:string; assigned_profile_id:string|null; opened_at:string; resolved_at:string|null; notes:string|null;
};

export type FinancialServicesDatabase = Omit<FinancialProductDatabase,"public"> & {
  public: Omit<FinancialProductDatabase["public"],"Tables"> & {
    Tables: FinancialProductDatabase["public"]["Tables"] & {
      financial_service_member_profiles: TableShape<FinancialServiceMemberProfileRow>;
      savings_accounts: TableShape<SavingsAccountRow>;
      savings_ledger_entries: TableShape<SavingsLedgerRow>;
      loan_applications: TableShape<LoanApplicationRow>;
      loan_accounts: TableShape<LoanAccountRow>;
      loan_repayment_schedule: TableShape<LoanScheduleRow>;
      loan_ledger_entries: TableShape<LoanLedgerRow>;
      collection_cases: TableShape<CollectionCaseRow>;
    };
  };
};

export type FinancialServicesClient = SupabaseClient<FinancialServicesDatabase>;
export function asFinancialServicesClient(client: unknown): FinancialServicesClient { return client as FinancialServicesClient; }
