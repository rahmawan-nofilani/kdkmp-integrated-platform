import type { SupabaseClient } from "@supabase/supabase-js";
import type { InventoryDatabase } from "./inventory";
import type { Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type SupplierRow = { id:string; organization_id:string; organization_node_id:string; code:string; name:string; legal_name:string|null; supplier_type:string; qualification_status:string; risk_status:string; payment_term_code:string|null; tax_profile_status:string; regulatory_status:string; status:string; notes:string|null; created_at:string; updated_at:string };
type RequisitionRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; requisition_number:string|null; requested_by:string|null; purpose:string|null; required_date:string|null; status:string; approval_request_id:string|null; submitted_at:string|null; decided_at:string|null; created_at:string; updated_at:string };
type PurchaseOrderRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; supplier_id:string; purchase_requisition_id:string|null; po_number:string|null; version_no:number; currency:string; expected_delivery_date:string|null; delivery_location_text:string|null; terms_snapshot:Json; supplier_snapshot:Json; status:string; approval_request_id:string|null; approved_at:string|null; sent_at:string|null; closed_at:string|null; created_by:string|null; created_at:string; updated_at:string };
type GoodsReceiptRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; supplier_id:string; purchase_order_id:string; receipt_number:string|null; supplier_delivery_reference:string|null; received_at:string|null; status:string; inventory_movement_id:string|null; accounting_status:string; journal_entry_id:string|null; received_by:string|null; created_at:string };
type SupplierInvoiceRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; supplier_id:string; purchase_order_id:string|null; invoice_number:string; invoice_date:string; due_date:string|null; currency:string; subtotal:number; tax_amount:number; other_amount:number; total_amount:number; status:string; matching_status:string; approval_request_id:string|null; journal_entry_id:string|null; payment_intent_id:string|null; created_at:string };
type MatchResultRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; supplier_invoice_id:string; purchase_order_id:string|null; match_type:string; status:string; po_amount:number|null; received_value:number|null; invoice_amount:number|null; quantity_variance:number|null; amount_variance:number|null; exception_codes:string[]; reviewed_by:string|null; reviewed_at:string|null; override_reason:string|null; created_at:string };

export type ProcurementDatabase = Omit<InventoryDatabase,"public"> & {
  public: Omit<InventoryDatabase["public"],"Tables"> & {
    Tables: InventoryDatabase["public"]["Tables"] & {
      suppliers: TableShape<SupplierRow>;
      purchase_requisitions: TableShape<RequisitionRow>;
      purchase_orders: TableShape<PurchaseOrderRow>;
      goods_receipts: TableShape<GoodsReceiptRow>;
      supplier_invoices: TableShape<SupplierInvoiceRow>;
      purchase_match_results: TableShape<MatchResultRow>;
    };
  };
};

export type ProcurementClient = SupabaseClient<ProcurementDatabase>;
export function asProcurementClient(client: unknown): ProcurementClient { return client as ProcurementClient; }
