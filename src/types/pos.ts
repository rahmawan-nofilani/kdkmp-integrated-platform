import type { SupabaseClient } from "@supabase/supabase-js";
import type { CommercialDatabase } from "./commercial";
import type { Json } from "./database";

type TableShape<Row, Insert = Partial<Row>, Update = Partial<Row>> = { Row: Row; Insert: Insert; Update: Update; Relationships: [] };

type SalesPriceListRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string;
  code:string; name:string; channel:string; currency:string; priority:number; status:string;
  valid_from:string|null; valid_until:string|null; created_by:string|null; approved_by:string|null;
  approved_at:string|null; created_at:string; updated_at:string;
};
type SalesPriceEntryRow = {
  id:string; sales_price_list_id:string; organization_id:string; organization_node_id:string; organization_unit_id:string;
  inventory_item_id:string; uom_id:string; min_quantity:number; unit_price:number; status:string;
  effective_from:string|null; effective_until:string|null; created_by:string|null; created_at:string; updated_at:string;
};
type SalesTransactionLineRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string;
  sales_transaction_id:string; line_no:number; inventory_item_id:string|null; item_snapshot:Json;
  description:string; uom_id:string|null; quantity:number; unit_price:number; discount_amount:number;
  tax_amount:number; line_total:number|null;
};
type PosCashMovementRow = {
  id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; pos_shift_id:string;
  sales_transaction_id:string|null; payment_intent_id:string|null; payment_attempt_id:string|null;
  movement_type:string; direction:string; amount:number; currency:string; status:string;
  reversal_of_movement_id:string|null; reason:string|null; occurred_at:string; created_by:string|null; created_at:string;
};
type PosShiftCommandRow = {
  id:string; action:string; organization_id:string|null; organization_node_id:string|null; organization_unit_id:string|null;
  terminal_id:string; opening_cash:number; notes:string|null; idempotency_key:string; result_shift_id:string|null;
  requested_by:string|null; created_at:string; target_shift_id:string|null; counted_cash:number|null;
};
type PosSaleCommandRow = {
  id:string; action:string; organization_id:string|null; organization_node_id:string|null; organization_unit_id:string|null;
  terminal_id:string; pos_shift_id:string; customer_member_id:string|null; local_transaction_id:string|null; device_id:string|null;
  client_sequence:number|null; idempotency_key:string; result_sale_id:string|null; requested_by:string|null; created_at:string;
  target_sale_id:string|null;
};
type PosSaleLineCommandRow = {
  id:string; action:string; organization_id:string|null; organization_node_id:string|null; organization_unit_id:string|null;
  sales_transaction_id:string; sales_transaction_line_id:string|null; inventory_item_id:string|null; uom_id:string|null;
  quantity:number|null; idempotency_key:string; result_line_id:string|null; requested_by:string|null; created_at:string;
};
type PosPaymentCommandRow = {
  id:string; organization_id:string|null; organization_node_id:string|null; organization_unit_id:string|null;
  sales_transaction_id:string; channel:string; provider_code:string|null; idempotency_key:string;
  result_payment_intent_id:string|null; result_payment_attempt_id:string|null; requested_by:string|null; created_at:string;
};

export type PosCatalogItem = {
  inventory_item_id:string;
  sku:string;
  barcode:string|null;
  item_name:string;
  uom_id:string;
  uom_code:string;
  uom_name:string;
  factor_to_base:number;
  unit_price:number;
  currency:string;
  available_quantity:number;
  in_stock:boolean;
};

export type PosCartLine = SalesTransactionLineRow;

type PosCatalogRequestRow = {
  id:string;
  organization_id:string|null;
  organization_node_id:string|null;
  organization_unit_id:string|null;
  terminal_id:string;
  search_query:string|null;
  result_limit:number;
  result:PosCatalogItem[];
  requested_by:string|null;
  created_at:string;
};

type PosFunctions = CommercialDatabase["public"]["Functions"] & {
  open_pos_shift: { Args: { p_terminal_id:string; p_opening_cash?:number; p_idempotency_key?:string|null; p_notes?:string|null }; Returns:string };
  close_pos_shift: { Args: { p_pos_shift_id:string; p_counted_cash:number; p_idempotency_key:string; p_notes?:string|null }; Returns:string };
  create_pos_sale: { Args: { p_terminal_id:string; p_pos_shift_id:string; p_idempotency_key:string; p_customer_member_id?:string|null; p_local_transaction_id?:string|null; p_device_id?:string|null; p_client_sequence?:number|null }; Returns:string };
  add_pos_sale_line: { Args: { p_sales_transaction_id:string; p_inventory_item_id:string; p_uom_id:string; p_quantity:number; p_idempotency_key:string }; Returns:string };
  update_pos_sale_line_quantity: { Args: { p_sales_transaction_id:string; p_sales_transaction_line_id:string; p_quantity:number; p_idempotency_key:string }; Returns:string };
  remove_pos_sale_line: { Args: { p_sales_transaction_id:string; p_sales_transaction_line_id:string; p_idempotency_key:string }; Returns:string };
  ensure_pos_sale: { Args: { p_terminal_id:string; p_pos_shift_id:string; p_idempotency_key:string }; Returns:string };
  add_pos_item_to_current_sale: { Args: { p_terminal_id:string; p_pos_shift_id:string; p_inventory_item_id:string; p_uom_id:string; p_quantity:number; p_idempotency_key:string }; Returns:{ sales_transaction_id:string; sales_transaction_line_id:string }[] };
  change_pos_cart_line_quantity: { Args: { p_sales_transaction_id:string; p_sales_transaction_line_id:string; p_delta:number; p_idempotency_key:string }; Returns:string };
  cancel_pos_sale: { Args: { p_sales_transaction_id:string; p_idempotency_key:string }; Returns:string };
  start_pos_payment: { Args: { p_sales_transaction_id:string; p_channel:string; p_idempotency_key:string; p_provider_code?:string|null }; Returns:{ payment_intent_id:string; payment_attempt_id:string }[] };
};

export type PosDatabase = Omit<CommercialDatabase,"public"> & {
  public: Omit<CommercialDatabase["public"],"Tables"|"Functions"> & {
    Tables: CommercialDatabase["public"]["Tables"] & {
      sales_transaction_lines: TableShape<SalesTransactionLineRow>;
      sales_price_lists: TableShape<SalesPriceListRow>;
      sales_price_entries: TableShape<SalesPriceEntryRow>;
      pos_cash_movements: TableShape<PosCashMovementRow>;
      pos_shift_commands: TableShape<PosShiftCommandRow>;
      pos_sale_commands: TableShape<PosSaleCommandRow>;
      pos_sale_line_commands: TableShape<PosSaleLineCommandRow>;
      pos_payment_commands: TableShape<PosPaymentCommandRow>;
      pos_catalog_requests: TableShape<PosCatalogRequestRow>;
    };
    Functions: PosFunctions;
  };
};

export type PosClient = SupabaseClient<PosDatabase>;
export function asPosClient(client: unknown): PosClient { return client as PosClient; }
