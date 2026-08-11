import type { SupabaseClient } from "@supabase/supabase-js";
import type { CooperativeDatabase } from "./cooperative-core";
import type { Json } from "./database";

type ContributionTypeRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  code: string;
  name: string;
  category: string;
  legal_classification: string | null;
  status: string;
  notes: string | null;
  created_at: string;
  updated_at: string;
};

type ContributionVersionRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  contribution_type_id: string;
  version_no: number;
  effective_from: string | null;
  effective_until: string | null;
  configuration: Json;
  legal_basis: string | null;
  status: string;
  created_by: string | null;
  approved_by: string | null;
  created_at: string;
  approved_at: string | null;
};

type MembershipAccountRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  member_id: string;
  contribution_type_id: string;
  policy_version_id: string | null;
  status: string;
  opened_at: string;
  closed_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

type MembershipLedgerRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  account_id: string;
  member_id: string;
  entry_type: string;
  direction: string;
  amount: number;
  currency: string;
  transaction_date: string;
  reference_number: string | null;
  source_channel: string | null;
  reversal_of: string | null;
  status: string;
  reason: string | null;
  accounting_status: string;
  accounting_reference: string | null;
  created_by: string | null;
  created_at: string;
};

type TableShape<Row> = {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  Relationships: [];
};

export type MembershipFinanceDatabase = Omit<CooperativeDatabase, "public"> & {
  public: Omit<CooperativeDatabase["public"], "Tables"> & {
    Tables: CooperativeDatabase["public"]["Tables"] & {
      membership_contribution_types: TableShape<ContributionTypeRow>;
      membership_contribution_versions: TableShape<ContributionVersionRow>;
      member_membership_accounts: TableShape<MembershipAccountRow>;
      member_membership_ledger: TableShape<MembershipLedgerRow>;
    };
  };
};

export type MembershipFinanceClient = SupabaseClient<MembershipFinanceDatabase>;

export function asMembershipFinanceClient(client: unknown): MembershipFinanceClient {
  return client as MembershipFinanceClient;
}
