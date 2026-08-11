import type { SupabaseClient } from "@supabase/supabase-js";
import type { PaymentDatabase } from "./payments";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };
type ViewShape<Row> = { Row: Row; Relationships: [] };

type InventoryUomRow = { id:string; organization_id:string; organization_node_id:string; code:string; name:string; dimension:string; decimal_places:number; status:string; created_at:string };
type InventoryItemRow = { id:string; organization_id:string; organization_node_id:string; sku:string; barcode:string|null; name:string; category_code:string|null; base_uom_id:string; tracking_type:string; expiry_control:boolean; costing_method:string; picking_policy:string; min_stock:number|null; max_stock:number|null; reorder_point:number|null; status:string; created_at:string; updated_at:string };
type WarehouseRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; code:string; name:string; warehouse_type:string; status:string; created_at:string };
type WarehouseNodeRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; parent_id:string|null; node_type:string; code:string; name:string; status:string; created_at:string };
type InventoryLotRow = { id:string; organization_id:string; organization_node_id:string; inventory_item_id:string; lot_code:string; manufacture_date:string|null; expiry_date:string|null; supplier_lot_reference:string|null; status:string; created_at:string };
type InventoryMovementRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; movement_number:string|null; movement_type:string; status:string; source_domain:string|null; source_entity_type:string|null; source_entity_id:string|null; source_reference:string|null; idempotency_key:string|null; correlation_id:string|null; approval_request_id:string|null; journal_entry_id:string|null; reversal_of_movement_id:string|null; occurred_at:string; posted_at:string|null; created_by:string|null; created_at:string };
type StockReservationRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; warehouse_node_id:string; inventory_item_id:string; lot_id:string|null; quantity:number; source_domain:string|null; source_entity_type:string|null; source_entity_id:string|null; status:string; expires_at:string|null; created_at:string };
type StockCountSessionRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; count_number:string|null; scope_description:string|null; snapshot_at:string; status:string; approval_request_id:string|null; adjustment_movement_id:string|null; created_by:string|null; created_at:string; completed_at:string|null };
type AccountingMapRow = { id:string; organization_id:string; organization_node_id:string; movement_type:string; accounting_event_code:string|null; mapping_status:string; notes:string|null };
type StockPositionRow = { organization_id:string; organization_node_id:string; organization_unit_id:string; warehouse_id:string; warehouse_node_id:string; inventory_item_id:string; lot_id:string|null; stock_status:string|null; quantity:number; reserved_quantity:number; available_to_allocate:number };

export type InventoryDatabase = Omit<PaymentDatabase,"public"> & {
  public: Omit<PaymentDatabase["public"],"Tables"|"Views"> & {
    Tables: PaymentDatabase["public"]["Tables"] & {
      inventory_uoms: TableShape<InventoryUomRow>;
      inventory_items: TableShape<InventoryItemRow>;
      warehouses: TableShape<WarehouseRow>;
      warehouse_nodes: TableShape<WarehouseNodeRow>;
      inventory_lots: TableShape<InventoryLotRow>;
      inventory_movements: TableShape<InventoryMovementRow>;
      stock_reservations: TableShape<StockReservationRow>;
      stock_count_sessions: TableShape<StockCountSessionRow>;
      inventory_accounting_event_mappings: TableShape<AccountingMapRow>;
    };
    Views: PaymentDatabase["public"]["Views"] & {
      inventory_available_positions: ViewShape<StockPositionRow>;
    };
  };
};

export type InventoryClient = SupabaseClient<InventoryDatabase>;
export function asInventoryClient(client: unknown): InventoryClient { return client as InventoryClient; }
