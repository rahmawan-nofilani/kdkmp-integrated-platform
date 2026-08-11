import type { SupabaseClient } from "@supabase/supabase-js";
import type { MembershipFinanceDatabase } from "./membership-finance";
import type { Json } from "./database";

type FinancialProductTemplateRow = {
  id: string;
  code: string;
  name: string;
  product_category: string;
  description: string;
  default_configuration: Json;
  template_status: string;
  created_at: string;
  updated_at: string;
};

type FinancialProductRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  organization_unit_id: string;
  code: string;
  name: string;
  product_category: string;
  template_code: string | null;
  legal_product_type: string | null;
  purpose_code: string | null;
  description: string | null;
  status: string;
  created_by: string | null;
  created_at: string;
  updated_at: string;
};

type FinancialProductVersionRow = {
  id: string;
  organization_id: string;
  organization_node_id: string;
  organization_unit_id: string;
  financial_product_id: string;
  version_no: number;
  status: string;
  effective_from: string | null;
  effective_until: string | null;
  currency: string;
  core_configuration: Json;
  eligibility_configuration: Json;
  pricing_configuration: Json;
  repayment_configuration: Json;
  channel_configuration: Json;
  collateral_configuration: Json;
  withdrawal_configuration: Json;
  accounting_mapping_status: string;
  regulatory_validation_status: string;
  legal_basis: string | null;
  created_by: string | null;
  approved_by: string | null;
  created_at: string;
  approved_at: string | null;
};

type TableShape<Row> = {
  Row: Row;
  Insert: Partial<Row>;
  Update: Partial<Row>;
  Relationships: [];
};

export type FinancialProductDatabase = Omit<MembershipFinanceDatabase, "public"> & {
  public: Omit<MembershipFinanceDatabase["public"], "Tables" | "Functions"> & {
    Tables: MembershipFinanceDatabase["public"]["Tables"] & {
      financial_product_templates: TableShape<FinancialProductTemplateRow>;
      financial_products: TableShape<FinancialProductRow>;
      financial_product_versions: TableShape<FinancialProductVersionRow>;
    };
    Functions: MembershipFinanceDatabase["public"]["Functions"] & {
      create_financial_product_draft: {
        Args: {
          p_template_code: string;
          p_product_code: string;
          p_product_name: string;
          p_legal_product_type?: string;
          p_purpose_code?: string;
          p_description?: string;
          p_organization_unit_id?: string;
        };
        Returns: undefined;
      };
    };
  };
};

export type FinancialProductClient = SupabaseClient<FinancialProductDatabase>;

export function asFinancialProductClient(client: unknown): FinancialProductClient {
  return client as FinancialProductClient;
}
