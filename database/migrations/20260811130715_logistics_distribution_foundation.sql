insert into public.permissions(code,domain,description,is_privileged)
values
 ('LOGISTICS_VIEW','LOGISTICS','View logistics and distribution operations',false),
 ('LOGISTICS_PLAN','LOGISTICS','Plan shipment, trip and delivery assignment',true),
 ('LOGISTICS_DISPATCH','LOGISTICS','Dispatch and control shipment lifecycle',true),
 ('DELIVERY_ASSIGNED_VIEW','LOGISTICS','View deliveries assigned to the current courier',false),
 ('POD_CAPTURE','LOGISTICS','Capture proof-of-delivery evidence for assigned delivery',false),
 ('POD_REVIEW','LOGISTICS','Review proof-of-delivery evidence and exceptions',true),
 ('FLEET_VIEW','LOGISTICS','View fleet master and operational status',false),
 ('FLEET_MANAGE','LOGISTICS','Manage fleet master, odometer and maintenance controls',true)
on conflict (code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where (r.code='MANAGER' and p.code in ('LOGISTICS_VIEW','LOGISTICS_PLAN','LOGISTICS_DISPATCH','POD_REVIEW','FLEET_VIEW','FLEET_MANAGE'))
   or (r.code='ADMIN' and p.code in ('LOGISTICS_VIEW','LOGISTICS_PLAN','FLEET_VIEW'))
   or (r.code='WAREHOUSE_OPERATOR' and p.code in ('LOGISTICS_VIEW','LOGISTICS_DISPATCH'))
   or (r.code='COURIER' and p.code in ('DELIVERY_ASSIGNED_VIEW','POD_CAPTURE'))
on conflict do nothing;

create table public.fleet_vehicles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  vehicle_code text not null,
  registration_number text,
  vehicle_type text not null check (vehicle_type in ('MOTORCYCLE','CAR','PICKUP','VAN','TRUCK','OTHER')),
  ownership_type text not null default 'OWNED' check (ownership_type in ('OWNED','LEASED','PARTNER','OTHER')),
  capacity_weight_kg numeric(18,3) check (capacity_weight_kg is null or capacity_weight_kg >= 0),
  capacity_volume_m3 numeric(18,3) check (capacity_volume_m3 is null or capacity_volume_m3 >= 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','MAINTENANCE','SUSPENDED','INACTIVE','ARCHIVED')),
  current_odometer_km numeric(18,2) check (current_odometer_km is null or current_odometer_km >= 0),
  document_status text not null default 'NOT_REVIEWED' check (document_status in ('NOT_REVIEWED','VALID','EXPIRING','EXPIRED','REVIEW_REQUIRED')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, vehicle_code)
);

create table public.logistics_route_trips (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  trip_number text,
  trip_date date,
  assigned_courier_profile_id uuid references public.profiles(id) on delete restrict,
  assigned_vehicle_id uuid references public.fleet_vehicles(id) on delete restrict,
  status text not null default 'PLANNED' check (status in ('PLANNED','READY','STARTED','IN_PROGRESS','COMPLETED','CANCELLED')),
  planned_start_at timestamptz,
  actual_start_at timestamptz,
  completed_at timestamptz,
  planned_distance_km numeric(18,2) check (planned_distance_km is null or planned_distance_km >= 0),
  actual_distance_km numeric(18,2) check (actual_distance_km is null or actual_distance_km >= 0),
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, trip_number)
);

create table public.logistics_shipments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  fulfillment_order_id uuid references public.fulfillment_orders(id) on delete restrict,
  shipment_number text,
  shipment_type text not null default 'OUTBOUND_SALE' check (shipment_type in ('OUTBOUND_SALE','INBOUND_PURCHASE','INTERNAL_TRANSFER','OFFTAKING_PICKUP','OTHER')),
  source_domain text not null default 'COMMERCIAL',
  source_entity_type text,
  source_entity_id uuid,
  source_reference text,
  warehouse_from_id uuid references public.warehouses(id) on delete restrict,
  warehouse_to_id uuid references public.warehouses(id) on delete restrict,
  route_trip_id uuid references public.logistics_route_trips(id) on delete restrict,
  assigned_courier_profile_id uuid references public.profiles(id) on delete restrict,
  assigned_vehicle_id uuid references public.fleet_vehicles(id) on delete restrict,
  recipient_snapshot jsonb not null default '{}'::jsonb,
  delivery_address_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'PLANNED' check (status in ('PLANNED','READY','DISPATCHED','IN_TRANSIT','DELIVERED','PARTIAL','FAILED','RETURNED','CANCELLED')),
  inventory_dispatch_movement_id uuid references public.inventory_movements(id) on delete restrict,
  inventory_return_movement_id uuid references public.inventory_movements(id) on delete restrict,
  planned_dispatch_at timestamptz,
  ready_at timestamptz,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  returned_at timestamptz,
  local_transaction_id text,
  device_id text,
  idempotency_key text,
  sync_status text not null default 'SYNCED' check (sync_status in ('SYNCED','PENDING','FAILED','CONFLICT')),
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, shipment_number),
  unique (organization_node_id, idempotency_key)
);

create table public.logistics_route_trip_stops (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  route_trip_id uuid not null references public.logistics_route_trips(id) on delete restrict,
  shipment_id uuid references public.logistics_shipments(id) on delete restrict,
  stop_sequence integer not null check (stop_sequence > 0),
  stop_type text not null default 'DELIVERY' check (stop_type in ('PICKUP','DELIVERY','RETURN','OTHER')),
  address_snapshot jsonb not null default '{}'::jsonb,
  planned_arrival_at timestamptz,
  actual_arrival_at timestamptz,
  actual_departure_at timestamptz,
  status text not null default 'PLANNED' check (status in ('PLANNED','ARRIVED','COMPLETED','SKIPPED','FAILED')),
  notes text,
  created_at timestamptz not null default now(),
  unique (route_trip_id, stop_sequence)
);

create table public.logistics_delivery_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  shipment_id uuid not null references public.logistics_shipments(id) on delete restrict,
  event_type text not null check (event_type in ('PLANNED','READY','DISPATCHED','IN_TRANSIT','ARRIVED','DELIVERED','PARTIAL','FAILED','RETURN_INITIATED','RETURNED','NOTE','LOCATION_CAPTURED')),
  event_at timestamptz not null default now(),
  latitude numeric(10,7) check (latitude is null or latitude between -90 and 90),
  longitude numeric(10,7) check (longitude is null or longitude between -180 and 180),
  accuracy_m numeric(18,2) check (accuracy_m is null or accuracy_m >= 0),
  device_id text,
  captured_by uuid references public.profiles(id) on delete restrict,
  notes text,
  sanitized_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.logistics_pod_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  shipment_id uuid not null references public.logistics_shipments(id) on delete restrict,
  evidence_version integer not null default 1 check (evidence_version > 0),
  status text not null default 'DRAFT' check (status in ('DRAFT','FINALIZED','REVIEW_REQUIRED','ACCEPTED','REJECTED','SUPERSEDED')),
  captured_at timestamptz,
  latitude numeric(10,7) check (latitude is null or latitude between -90 and 90),
  longitude numeric(10,7) check (longitude is null or longitude between -180 and 180),
  accuracy_m numeric(18,2) check (accuracy_m is null or accuracy_m >= 0),
  recipient_name text,
  recipient_relation text,
  photo_references jsonb not null default '[]'::jsonb,
  signature_reference text,
  document_references jsonb not null default '[]'::jsonb,
  courier_notes text,
  captured_by uuid references public.profiles(id) on delete restrict,
  finalized_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shipment_id, evidence_version)
);

create table public.logistics_delivery_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  shipment_id uuid not null references public.logistics_shipments(id) on delete restrict,
  exception_code text not null,
  category text not null check (category in ('RECIPIENT','ADDRESS','VEHICLE','WEATHER','ITEM','DOCUMENT','PAYMENT','SECURITY','OTHER')),
  severity text not null default 'MEDIUM' check (severity in ('LOW','MEDIUM','HIGH','CRITICAL')),
  status text not null default 'OPEN' check (status in ('OPEN','UNDER_REVIEW','ACTION_REQUIRED','RESOLVED','CLOSED')),
  occurred_at timestamptz not null default now(),
  notes text,
  evidence_references jsonb not null default '[]'::jsonb,
  reported_by uuid references public.profiles(id) on delete restrict,
  resolved_by uuid references public.profiles(id) on delete restrict,
  resolved_at timestamptz,
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fleet_odometer_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete restrict,
  route_trip_id uuid references public.logistics_route_trips(id) on delete restrict,
  reading_km numeric(18,2) not null check (reading_km >= 0),
  reading_at timestamptz not null default now(),
  evidence_reference text,
  recorded_by uuid references public.profiles(id) on delete restrict,
  notes text,
  created_at timestamptz not null default now()
);

create table public.fleet_maintenance_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  vehicle_id uuid not null references public.fleet_vehicles(id) on delete restrict,
  maintenance_type text not null check (maintenance_type in ('SCHEDULED','CORRECTIVE','INSPECTION','DOCUMENT','OTHER')),
  status text not null default 'PLANNED' check (status in ('PLANNED','IN_PROGRESS','COMPLETED','CANCELLED')),
  planned_date date,
  completed_date date,
  odometer_km numeric(18,2) check (odometer_km is null or odometer_km >= 0),
  vendor_reference text,
  cost_amount numeric(20,2) check (cost_amount is null or cost_amount >= 0),
  currency text not null default 'IDR',
  document_references jsonb not null default '[]'::jsonb,
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.logistics_status_transition_rules (
  id uuid primary key default gen_random_uuid(),
  from_status text not null,
  to_status text not null,
  requires_pod boolean not null default false,
  requires_exception_resolution boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  unique (from_status,to_status)
);

insert into public.logistics_status_transition_rules(from_status,to_status,requires_pod,requires_exception_resolution)
values
 ('PLANNED','READY',false,false),('PLANNED','CANCELLED',false,false),
 ('READY','DISPATCHED',false,false),('READY','CANCELLED',false,false),
 ('DISPATCHED','IN_TRANSIT',false,false),('DISPATCHED','FAILED',false,false),
 ('IN_TRANSIT','DELIVERED',true,false),('IN_TRANSIT','PARTIAL',true,false),('IN_TRANSIT','FAILED',false,false),('IN_TRANSIT','RETURNED',false,false),
 ('PARTIAL','RETURNED',false,false),('FAILED','RETURNED',false,false)
on conflict do nothing;

create index idx_logistics_shipments_scope_status on public.logistics_shipments(organization_node_id,organization_unit_id,status,created_at desc);
create index idx_logistics_shipments_courier on public.logistics_shipments(assigned_courier_profile_id,status,created_at desc);
create index idx_logistics_trip_courier on public.logistics_route_trips(assigned_courier_profile_id,trip_date,status);
create index idx_logistics_events_shipment on public.logistics_delivery_events(shipment_id,event_at desc);
create index idx_logistics_pod_shipment on public.logistics_pod_evidence(shipment_id,evidence_version desc);
create index idx_logistics_exception_shipment on public.logistics_delivery_exceptions(shipment_id,status,occurred_at desc);
create index idx_fleet_vehicles_scope on public.fleet_vehicles(organization_node_id,status,vehicle_type);
create index idx_fleet_odometer_vehicle on public.fleet_odometer_entries(vehicle_id,reading_at desc);
create index idx_fleet_maintenance_vehicle on public.fleet_maintenance_records(vehicle_id,status,planned_date);

create index idx_fleet_vehicles_organization_id on public.fleet_vehicles(organization_id);
create index idx_fleet_vehicles_organization_unit_id on public.fleet_vehicles(organization_unit_id);
create index idx_logistics_route_trips_organization_id on public.logistics_route_trips(organization_id);
create index idx_logistics_route_trips_organization_unit_id on public.logistics_route_trips(organization_unit_id);
create index idx_logistics_route_trips_assigned_vehicle_id on public.logistics_route_trips(assigned_vehicle_id);
create index idx_logistics_route_trips_created_by on public.logistics_route_trips(created_by);
create index idx_logistics_shipments_organization_id on public.logistics_shipments(organization_id);
create index idx_logistics_shipments_organization_unit_id on public.logistics_shipments(organization_unit_id);
create index idx_logistics_shipments_fulfillment_order_id on public.logistics_shipments(fulfillment_order_id);
create index idx_logistics_shipments_route_trip_id on public.logistics_shipments(route_trip_id);
create index idx_logistics_shipments_assigned_vehicle_id on public.logistics_shipments(assigned_vehicle_id);
create index idx_logistics_shipments_warehouse_from_id on public.logistics_shipments(warehouse_from_id);
create index idx_logistics_shipments_warehouse_to_id on public.logistics_shipments(warehouse_to_id);
create index idx_logistics_shipments_inventory_dispatch_movement_id on public.logistics_shipments(inventory_dispatch_movement_id);
create index idx_logistics_shipments_inventory_return_movement_id on public.logistics_shipments(inventory_return_movement_id);
create index idx_logistics_shipments_created_by on public.logistics_shipments(created_by);
create index idx_logistics_route_trip_stops_organization_id on public.logistics_route_trip_stops(organization_id);
create index idx_logistics_route_trip_stops_organization_node_id on public.logistics_route_trip_stops(organization_node_id);
create index idx_logistics_route_trip_stops_organization_unit_id on public.logistics_route_trip_stops(organization_unit_id);
create index idx_logistics_route_trip_stops_shipment_id on public.logistics_route_trip_stops(shipment_id);
create index idx_logistics_delivery_events_organization_id on public.logistics_delivery_events(organization_id);
create index idx_logistics_delivery_events_organization_node_id on public.logistics_delivery_events(organization_node_id);
create index idx_logistics_delivery_events_organization_unit_id on public.logistics_delivery_events(organization_unit_id);
create index idx_logistics_delivery_events_captured_by on public.logistics_delivery_events(captured_by);
create index idx_logistics_pod_evidence_organization_id on public.logistics_pod_evidence(organization_id);
create index idx_logistics_pod_evidence_organization_node_id on public.logistics_pod_evidence(organization_node_id);
create index idx_logistics_pod_evidence_organization_unit_id on public.logistics_pod_evidence(organization_unit_id);
create index idx_logistics_pod_evidence_captured_by on public.logistics_pod_evidence(captured_by);
create index idx_logistics_pod_evidence_reviewed_by on public.logistics_pod_evidence(reviewed_by);
create index idx_logistics_delivery_exceptions_organization_id on public.logistics_delivery_exceptions(organization_id);
create index idx_logistics_delivery_exceptions_organization_node_id on public.logistics_delivery_exceptions(organization_node_id);
create index idx_logistics_delivery_exceptions_organization_unit_id on public.logistics_delivery_exceptions(organization_unit_id);
create index idx_logistics_delivery_exceptions_reported_by on public.logistics_delivery_exceptions(reported_by);
create index idx_logistics_delivery_exceptions_resolved_by on public.logistics_delivery_exceptions(resolved_by);
create index idx_fleet_odometer_entries_organization_id on public.fleet_odometer_entries(organization_id);
create index idx_fleet_odometer_entries_organization_node_id on public.fleet_odometer_entries(organization_node_id);
create index idx_fleet_odometer_entries_route_trip_id on public.fleet_odometer_entries(route_trip_id);
create index idx_fleet_odometer_entries_recorded_by on public.fleet_odometer_entries(recorded_by);
create index idx_fleet_maintenance_records_organization_id on public.fleet_maintenance_records(organization_id);
create index idx_fleet_maintenance_records_organization_node_id on public.fleet_maintenance_records(organization_node_id);
create index idx_fleet_maintenance_records_created_by on public.fleet_maintenance_records(created_by);

alter table public.fleet_vehicles enable row level security;
alter table public.logistics_route_trips enable row level security;
alter table public.logistics_shipments enable row level security;
alter table public.logistics_route_trip_stops enable row level security;
alter table public.logistics_delivery_events enable row level security;
alter table public.logistics_pod_evidence enable row level security;
alter table public.logistics_delivery_exceptions enable row level security;
alter table public.fleet_odometer_entries enable row level security;
alter table public.fleet_maintenance_records enable row level security;
alter table public.logistics_status_transition_rules enable row level security;

create policy fleet_vehicles_read on public.fleet_vehicles for select to authenticated
using (public.has_permission('FLEET_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));

create policy logistics_route_trips_read on public.logistics_route_trips for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)));

create policy logistics_shipments_read on public.logistics_shipments for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)));

create policy logistics_route_stops_read on public.logistics_route_trip_stops for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and exists(select 1 from public.logistics_route_trips t where t.id=route_trip_id and t.assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1))));

create policy logistics_events_read on public.logistics_delivery_events for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and exists(select 1 from public.logistics_shipments s where s.id=shipment_id and s.assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1))));

create policy logistics_pod_read on public.logistics_pod_evidence for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and exists(select 1 from public.logistics_shipments s where s.id=shipment_id and s.assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1))));

create policy logistics_exceptions_read on public.logistics_delivery_exceptions for select to authenticated
using ((public.has_permission('LOGISTICS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null))
 or (public.has_permission('DELIVERY_ASSIGNED_VIEW') and exists(select 1 from public.logistics_shipments s where s.id=shipment_id and s.assigned_courier_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1))));

create policy fleet_odometer_read on public.fleet_odometer_entries for select to authenticated
using (public.has_permission('FLEET_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy fleet_maintenance_read on public.fleet_maintenance_records for select to authenticated
using (public.has_permission('FLEET_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy logistics_transition_rules_read on public.logistics_status_transition_rules for select to authenticated
using (public.has_permission('LOGISTICS_VIEW') or public.has_permission('DELIVERY_ASSIGNED_VIEW'));

grant select on public.fleet_vehicles,public.logistics_route_trips,public.logistics_shipments,public.logistics_route_trip_stops,public.logistics_delivery_events,public.logistics_pod_evidence,public.logistics_delivery_exceptions,public.fleet_odometer_entries,public.fleet_maintenance_records,public.logistics_status_transition_rules to authenticated;
revoke insert,update,delete on public.fleet_vehicles,public.logistics_route_trips,public.logistics_shipments,public.logistics_route_trip_stops,public.logistics_delivery_events,public.logistics_pod_evidence,public.logistics_delivery_exceptions,public.fleet_odometer_entries,public.fleet_maintenance_records,public.logistics_status_transition_rules from anon,authenticated;

create or replace function app_private.prevent_logistics_event_mutation()
returns trigger language plpgsql set search_path=''
as $$ begin raise exception 'logistics_event_is_append_only'; end; $$;
revoke all on function app_private.prevent_logistics_event_mutation() from public,anon,authenticated;
create trigger trg_logistics_events_immutable before update or delete on public.logistics_delivery_events for each row execute function app_private.prevent_logistics_event_mutation();
create trigger trg_fleet_odometer_immutable before update or delete on public.fleet_odometer_entries for each row execute function app_private.prevent_logistics_event_mutation();

create or replace function app_private.protect_finalized_pod()
returns trigger language plpgsql set search_path=''
as $$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'DRAFT' then
      raise exception 'finalized_pod_is_immutable_create_new_evidence_version';
    end if;
    return old;
  end if;

  if old.status <> 'DRAFT' then
    if new.organization_id is distinct from old.organization_id
       or new.organization_node_id is distinct from old.organization_node_id
       or new.organization_unit_id is distinct from old.organization_unit_id
       or new.shipment_id is distinct from old.shipment_id
       or new.evidence_version is distinct from old.evidence_version
       or new.captured_at is distinct from old.captured_at
       or new.latitude is distinct from old.latitude
       or new.longitude is distinct from old.longitude
       or new.accuracy_m is distinct from old.accuracy_m
       or new.recipient_name is distinct from old.recipient_name
       or new.recipient_relation is distinct from old.recipient_relation
       or new.photo_references is distinct from old.photo_references
       or new.signature_reference is distinct from old.signature_reference
       or new.document_references is distinct from old.document_references
       or new.courier_notes is distinct from old.courier_notes
       or new.captured_by is distinct from old.captured_by
       or new.finalized_at is distinct from old.finalized_at
       or new.created_at is distinct from old.created_at then
      raise exception 'finalized_pod_content_is_immutable_create_new_evidence_version';
    end if;
  end if;

  return new;
end; $$;
revoke all on function app_private.protect_finalized_pod() from public,anon,authenticated;
create trigger trg_pod_finalized_immutable before update or delete on public.logistics_pod_evidence for each row execute function app_private.protect_finalized_pod();
