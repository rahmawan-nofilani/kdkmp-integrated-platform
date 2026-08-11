import type { SupabaseClient } from "@supabase/supabase-js";
import type { CommercialDatabase } from "./commercial";
import type { Json } from "./database";

type TableShape<Row> = { Row: Row; Insert: Partial<Row>; Update: Partial<Row>; Relationships: [] };

type FleetVehicleRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; vehicle_code:string; registration_number:string|null; vehicle_type:string; ownership_type:string; capacity_weight_kg:number|null; capacity_volume_m3:number|null; status:string; current_odometer_km:number|null; document_status:string; notes:string|null; created_at:string; updated_at:string };
type RouteTripRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; trip_number:string|null; trip_date:string|null; assigned_courier_profile_id:string|null; assigned_vehicle_id:string|null; status:string; planned_start_at:string|null; actual_start_at:string|null; completed_at:string|null; planned_distance_km:number|null; actual_distance_km:number|null; notes:string|null; created_by:string|null; created_at:string; updated_at:string };
type ShipmentRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; fulfillment_order_id:string|null; shipment_number:string|null; shipment_type:string; source_domain:string; source_entity_type:string|null; source_entity_id:string|null; source_reference:string|null; warehouse_from_id:string|null; warehouse_to_id:string|null; route_trip_id:string|null; assigned_courier_profile_id:string|null; assigned_vehicle_id:string|null; recipient_snapshot:Json; delivery_address_snapshot:Json; status:string; inventory_dispatch_movement_id:string|null; inventory_return_movement_id:string|null; planned_dispatch_at:string|null; ready_at:string|null; dispatched_at:string|null; delivered_at:string|null; failed_at:string|null; returned_at:string|null; local_transaction_id:string|null; device_id:string|null; idempotency_key:string|null; sync_status:string; notes:string|null; created_by:string|null; created_at:string; updated_at:string };
type RouteTripStopRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string|null; route_trip_id:string; shipment_id:string|null; stop_sequence:number; stop_type:string; address_snapshot:Json; planned_arrival_at:string|null; actual_arrival_at:string|null; actual_departure_at:string|null; status:string; notes:string|null; created_at:string };
type DeliveryEventRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; shipment_id:string; event_type:string; event_at:string; latitude:number|null; longitude:number|null; accuracy_m:number|null; device_id:string|null; captured_by:string|null; notes:string|null; sanitized_metadata:Json; created_at:string };
type PodEvidenceRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; shipment_id:string; evidence_version:number; status:string; captured_at:string|null; latitude:number|null; longitude:number|null; accuracy_m:number|null; recipient_name:string|null; recipient_relation:string|null; photo_references:Json; signature_reference:string|null; document_references:Json; courier_notes:string|null; captured_by:string|null; finalized_at:string|null; reviewed_by:string|null; reviewed_at:string|null; review_notes:string|null; created_at:string; updated_at:string };
type DeliveryExceptionRow = { id:string; organization_id:string; organization_node_id:string; organization_unit_id:string; shipment_id:string; exception_code:string; category:string; severity:string; status:string; occurred_at:string; notes:string|null; evidence_references:Json; reported_by:string|null; resolved_by:string|null; resolved_at:string|null; resolution_notes:string|null; created_at:string; updated_at:string };
type FleetOdometerRow = { id:string; organization_id:string; organization_node_id:string; vehicle_id:string; route_trip_id:string|null; reading_km:number; reading_at:string; evidence_reference:string|null; recorded_by:string|null; notes:string|null; created_at:string };
type FleetMaintenanceRow = { id:string; organization_id:string; organization_node_id:string; vehicle_id:string; maintenance_type:string; status:string; planned_date:string|null; completed_date:string|null; odometer_km:number|null; vendor_reference:string|null; cost_amount:number|null; currency:string; document_references:Json; notes:string|null; created_by:string|null; created_at:string; updated_at:string };
type LogisticsTransitionRuleRow = { id:string; from_status:string; to_status:string; requires_pod:boolean; requires_exception_resolution:boolean; status:string; created_at:string };

export type LogisticsDatabase = Omit<CommercialDatabase,"public"> & {
  public: Omit<CommercialDatabase["public"],"Tables"> & {
    Tables: CommercialDatabase["public"]["Tables"] & {
      fleet_vehicles: TableShape<FleetVehicleRow>;
      logistics_route_trips: TableShape<RouteTripRow>;
      logistics_shipments: TableShape<ShipmentRow>;
      logistics_route_trip_stops: TableShape<RouteTripStopRow>;
      logistics_delivery_events: TableShape<DeliveryEventRow>;
      logistics_pod_evidence: TableShape<PodEvidenceRow>;
      logistics_delivery_exceptions: TableShape<DeliveryExceptionRow>;
      fleet_odometer_entries: TableShape<FleetOdometerRow>;
      fleet_maintenance_records: TableShape<FleetMaintenanceRow>;
      logistics_status_transition_rules: TableShape<LogisticsTransitionRuleRow>;
    };
  };
};

export type LogisticsClient = SupabaseClient<LogisticsDatabase>;
export function asLogisticsClient(client: unknown): LogisticsClient { return client as LogisticsClient; }
