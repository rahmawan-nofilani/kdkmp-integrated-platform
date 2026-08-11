import type { SupabaseClient } from "@supabase/supabase-js";
import type { ProcurementDatabase } from "./procurement";
import type { Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };
type PosTerminalRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; code:string; name:string; device_reference:string|null; default_warehouse_id:string|null; status:string; created_at:string };
type PosShiftRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; terminal_id:string; cashier_profile_id:string; shift_number:string|null; status:string; opened_at:string; closed_at:string|null; opening_cash:number; expected_cash:number|null; counted_cash:number|null; cash_variance:number|null; reconciliation_status:string; notes:string|null; created_at:string };
type SaleRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; terminal_id:string|null; pos_shift_id:string|null; sale_number:string|null; sale_type:string; customer_member_id:string|null; customer_reference:string|null; currency:string; subtotal:number; discount_amount:number; tax_amount:number; total_amount:number; status:string; payment_intent_id:string|null; inventory_movement_id:string|null; journal_entry_id:string|null; reversal_of_sale_id:string|null; receipt_reference:string|null; local_transaction_id:string|null; device_id:string|null; client_sequence:number|null; idempotency_key:string|null; sync_status:string; correlation_id:string|null; sold_at:string|null; completed_at:string|null; created_by:string|null; created_at:string; updated_at:string };
type SalesOrderRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; order_number:string|null; customer_member_id:string|null; customer_reference:string|null; channel:string; currency:string; requested_delivery_date:string|null; delivery_address_snapshot:Json; status:string; payment_intent_id:string|null; created_by:string|null; created_at:string; updated_at:string };
type FulfillmentRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; sales_order_id:string; fulfillment_number:string|null; warehouse_id:string|null; status:string; inventory_movement_id:string|null; assigned_courier_profile_id:string|null; dispatched_at:string|null; delivered_at:string|null; pod_reference:string|null; created_at:string };
type SalesReturnRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; original_sale_id:string; return_number:string|null; reason_code:string|null; status:string; approval_request_id:string|null; inventory_movement_id:string|null; payment_intent_id:string|null; journal_entry_id:string|null; created_by:string|null; created_at:string };

export type CommercialDatabase = Omit<ProcurementDatabase,"public"> & {
  public: Omit<ProcurementDatabase["public"],"Tables"> & {
    Tables: ProcurementDatabase["public"]["Tables"] & {
      pos_terminals: TableShape<PosTerminalRow>;
      pos_shifts: TableShape<PosShiftRow>;
      sales_transactions: TableShape<SaleRow>;
      sales_orders: TableShape<SalesOrderRow>;
      fulfillment_orders: TableShape<FulfillmentRow>;
      sales_returns: TableShape<SalesReturnRow>;
    };
  };
};
export type CommercialClient = SupabaseClient<CommercialDatabase>;
export function asCommercialClient(client: unknown): CommercialClient { return client as CommercialClient; }
