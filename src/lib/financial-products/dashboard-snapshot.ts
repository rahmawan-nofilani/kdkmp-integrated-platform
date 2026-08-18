import type { SupabaseClient } from "@supabase/supabase-js";

type FinancialProductTemplate = {
  id:string;
  code:string;
  name:string;
  product_category:string;
  description:string|null;
  default_configuration:unknown;
  template_status:string;
};

type FinancialProduct = {
  id:string;
  code:string;
  name:string;
  product_category:string;
  template_code:string|null;
  legal_product_type:string|null;
  purpose_code:string|null;
  status:string;
  organization_unit_id:string;
  created_at:string;
};

type FinancialProductVersion = {
  id:string;
  financial_product_id:string;
  version_no:number;
  status:string;
  accounting_mapping_status:string;
  regulatory_validation_status:string;
  legal_basis:string|null;
  created_at:string;
};

type RegulatoryAuthorization = {
  id:string;
  module_code:string;
  organization_unit_id:string|null;
  status:string;
  effective_date:string|null;
  expiry_date:string|null;
};

export type FinancialProductsDashboardSnapshot = {
  templates: FinancialProductTemplate[];
  products: FinancialProduct[];
  versions: FinancialProductVersion[];
  authorizations: RegulatoryAuthorization[];
};

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? value as T[] : [];
}

function normalizeSnapshot(value: unknown): FinancialProductsDashboardSnapshot | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  return {
    templates: asArray<FinancialProductTemplate>(row.templates),
    products: asArray<FinancialProduct>(row.products),
    versions: asArray<FinancialProductVersion>(row.versions),
    authorizations: asArray<RegulatoryAuthorization>(row.authorizations),
  };
}

export async function getFinancialProductsDashboardSnapshot(client: SupabaseClient) {
  // Generated database types are refreshed on schema milestones. Keep the new
  // RPC cast local until the next generated-type refresh.
  const rpc = client.rpc.bind(client) as unknown as (
    fn: "get_financial_products_dashboard_snapshot",
  ) => Promise<RpcResult>;
  const { data, error } = await rpc("get_financial_products_dashboard_snapshot");

  if (error) return { data: null, error };
  return { data: normalizeSnapshot(data), error: null };
}
