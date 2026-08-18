import type { SupabaseClient } from "@supabase/supabase-js";

type Warehouse = { id:string; code:string; name:string; warehouse_type:string; status:string; organization_unit_id:string|null };
type WarehouseNode = { id:string; warehouse_id:string; parent_id:string|null; node_type:string; code:string; name:string; status:string };
type InventoryItem = { id:string; sku:string; name:string; category_code:string|null; base_uom_id:string; tracking_type:string; expiry_control:boolean; costing_method:string; picking_policy:string; status:string };
type InventoryUom = { id:string; code:string; name:string; dimension:string; decimal_places:number; status:string };
type InventoryLot = { id:string; inventory_item_id:string; lot_code:string; expiry_date:string|null; status:string };
type InventoryMovement = { id:string; movement_number:string|null; movement_type:string; status:string; source_domain:string|null; source_reference:string|null; occurred_at:string; posted_at:string|null };
type StockPosition = { warehouse_id:string; warehouse_node_id:string; inventory_item_id:string; lot_id:string|null; stock_status:string|null; quantity:number; reserved_quantity:number; available_to_allocate:number };
type StockReservation = { id:string; warehouse_node_id:string; inventory_item_id:string; lot_id:string|null; quantity:number; status:string; expires_at:string|null; source_domain:string|null };
type StockCount = { id:string; count_number:string|null; scope_description:string|null; snapshot_at:string; status:string; created_at:string; completed_at:string|null };
type AccountingMapping = { id:string; movement_type:string; accounting_event_code:string|null; mapping_status:string; notes:string|null };

export type InventoryDashboardSnapshot = {
  warehouses: Warehouse[];
  nodes: WarehouseNode[];
  items: InventoryItem[];
  uoms: InventoryUom[];
  lots: InventoryLot[];
  movements: InventoryMovement[];
  positions: StockPosition[];
  reservations: StockReservation[];
  counts: StockCount[];
  mappings: AccountingMapping[];
};

type RpcResult = {
  data: unknown;
  error: { message: string } | null;
};

function asArray<T>(value: unknown): T[] {
  return Array.isArray(value) ? value as T[] : [];
}

function normalizeSnapshot(value: unknown): InventoryDashboardSnapshot | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const row = value as Record<string, unknown>;
  return {
    warehouses: asArray<Warehouse>(row.warehouses),
    nodes: asArray<WarehouseNode>(row.nodes),
    items: asArray<InventoryItem>(row.items),
    uoms: asArray<InventoryUom>(row.uoms),
    lots: asArray<InventoryLot>(row.lots),
    movements: asArray<InventoryMovement>(row.movements),
    positions: asArray<StockPosition>(row.positions),
    reservations: asArray<StockReservation>(row.reservations),
    counts: asArray<StockCount>(row.counts),
    mappings: asArray<AccountingMapping>(row.mappings),
  };
}

export async function getInventoryDashboardSnapshot(client: SupabaseClient) {
  // Generated DB types are refreshed at schema milestones. Keep this new RPC
  // adapter local until the next generated-type refresh.
  const rpc = client.rpc.bind(client) as unknown as (
    fn: "get_inventory_dashboard_snapshot",
  ) => Promise<RpcResult>;
  const { data, error } = await rpc("get_inventory_dashboard_snapshot");

  if (error) return { data: null, error };
  return { data: normalizeSnapshot(data), error: null };
}
