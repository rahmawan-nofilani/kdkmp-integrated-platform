create table public.inventory_uoms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  code text not null,
  name text not null,
  dimension text not null default 'COUNT' check (dimension in ('COUNT','WEIGHT','VOLUME','LENGTH','OTHER')),
  decimal_places integer not null default 0 check (decimal_places between 0 and 6),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  created_at timestamptz not null default now(),
  unique (organization_node_id, code)
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  sku text not null,
  barcode text,
  name text not null,
  category_code text,
  base_uom_id uuid not null references public.inventory_uoms(id) on delete restrict,
  tracking_type text not null default 'NONE' check (tracking_type in ('NONE','LOT','SERIAL')),
  expiry_control boolean not null default false,
  costing_method text not null default 'WEIGHTED_AVERAGE' check (costing_method in ('WEIGHTED_AVERAGE','FIFO','SPECIFIC')),
  picking_policy text not null default 'FIFO' check (picking_policy in ('FIFO','FEFO','MANUAL')),
  min_stock numeric(20,6), max_stock numeric(20,6), reorder_point numeric(20,6),
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_node_id, sku)
);

create table public.inventory_item_uom_conversions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  uom_id uuid not null references public.inventory_uoms(id) on delete restrict,
  factor_to_base numeric(20,8) not null check (factor_to_base > 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  unique (inventory_item_id, uom_id)
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  code text not null, name text not null,
  warehouse_type text not null default 'GENERAL' check (warehouse_type in ('GENERAL','RETAIL_BACKROOM','TRANSIT','QUARANTINE','OTHER')),
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','SUSPENDED','INACTIVE')),
  created_at timestamptz not null default now(), unique (organization_node_id, code)
);

create table public.warehouse_nodes (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  parent_id uuid references public.warehouse_nodes(id) on delete restrict,
  node_type text not null check (node_type in ('ZONE','LOCATION','BIN')),
  code text not null, name text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','BLOCKED')),
  created_at timestamptz not null default now(), unique (warehouse_id, code)
);

create table public.inventory_lots (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  lot_code text not null, manufacture_date date, expiry_date date, supplier_lot_reference text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','QUARANTINE','EXPIRED','CLOSED')),
  created_at timestamptz not null default now(), unique (organization_node_id, inventory_item_id, lot_code),
  check (expiry_date is null or manufacture_date is null or expiry_date >= manufacture_date)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  movement_number text,
  movement_type text not null check (movement_type in ('RECEIPT','TRANSFER','SALE_ISSUE','RETURN_IN','RETURN_OUT','ADJUSTMENT_IN','ADJUSTMENT_OUT','DAMAGE','EXPIRY','LOSS','STOCK_COUNT_ADJUSTMENT','TRANSIT','OTHER')),
  status text not null default 'DRAFT' check (status in ('DRAFT','VALIDATED','PENDING_APPROVAL','APPROVED','POSTED','REVERSED','CANCELLED')),
  source_domain text, source_entity_type text, source_entity_id uuid, source_reference text, idempotency_key text, correlation_id uuid,
  approval_request_id uuid references public.approval_requests(id) on delete restrict,
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  reversal_of_movement_id uuid references public.inventory_movements(id) on delete restrict,
  occurred_at timestamptz not null default now(), posted_at timestamptz,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
  unique (organization_node_id, movement_number), unique (organization_node_id, idempotency_key)
);

create table public.inventory_movement_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  inventory_movement_id uuid not null references public.inventory_movements(id) on delete restrict,
  line_no integer not null check (line_no > 0), inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  uom_id uuid not null references public.inventory_uoms(id) on delete restrict, lot_id uuid references public.inventory_lots(id) on delete restrict,
  from_warehouse_node_id uuid references public.warehouse_nodes(id) on delete restrict,
  to_warehouse_node_id uuid references public.warehouse_nodes(id) on delete restrict,
  from_stock_status text check (from_stock_status is null or from_stock_status in ('AVAILABLE','QUARANTINE','DAMAGED','EXPIRED','IN_TRANSIT')),
  to_stock_status text check (to_stock_status is null or to_stock_status in ('AVAILABLE','QUARANTINE','DAMAGED','EXPIRED','IN_TRANSIT')),
  quantity numeric(20,6) not null check (quantity > 0), base_quantity numeric(20,6) not null check (base_quantity > 0), unit_cost numeric(20,6), notes text,
  unique (inventory_movement_id, line_no),
  check (from_warehouse_node_id is not null or to_warehouse_node_id is not null),
  check (from_warehouse_node_id is null or from_stock_status is not null),
  check (to_warehouse_node_id is null or to_stock_status is not null)
);

create table public.stock_reservations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  warehouse_node_id uuid not null references public.warehouse_nodes(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict, lot_id uuid references public.inventory_lots(id) on delete restrict,
  quantity numeric(20,6) not null check (quantity > 0), source_domain text, source_entity_type text, source_entity_id uuid,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','RELEASED','CONSUMED','EXPIRED','CANCELLED')),
  expires_at timestamptz, created_at timestamptz not null default now()
);

create table public.stock_count_sessions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  warehouse_id uuid not null references public.warehouses(id) on delete restrict,
  count_number text, scope_description text, snapshot_at timestamptz not null default now(),
  status text not null default 'DRAFT' check (status in ('DRAFT','COUNTING','REVIEW','PENDING_APPROVAL','APPROVED','POSTED','CANCELLED')),
  approval_request_id uuid references public.approval_requests(id) on delete restrict,
  adjustment_movement_id uuid references public.inventory_movements(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), completed_at timestamptz,
  unique (organization_node_id, count_number)
);

create table public.stock_count_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  stock_count_session_id uuid not null references public.stock_count_sessions(id) on delete restrict,
  warehouse_node_id uuid not null references public.warehouse_nodes(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict, lot_id uuid references public.inventory_lots(id) on delete restrict,
  stock_status text not null check (stock_status in ('AVAILABLE','QUARANTINE','DAMAGED','EXPIRED','IN_TRANSIT')),
  system_quantity numeric(20,6) not null, physical_quantity numeric(20,6),
  variance_quantity numeric(20,6) generated always as (physical_quantity - system_quantity) stored,
  reason_code text, evidence_reference text, notes text,
  counted_by uuid references public.profiles(id) on delete restrict, counted_at timestamptz,
  unique (stock_count_session_id, warehouse_node_id, inventory_item_id, lot_id, stock_status)
);

create table public.inventory_accounting_event_mappings (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  movement_type text not null, accounting_event_code text,
  mapping_status text not null default 'NOT_CONFIGURED' check (mapping_status in ('NOT_CONFIGURED','MAPPED','NO_GL_REQUIRED','BLOCKED')),
  notes text, unique (organization_node_id, movement_type)
);

create index idx_inventory_items_scope on public.inventory_items(organization_node_id,status,sku);
create index idx_warehouse_nodes_hierarchy on public.warehouse_nodes(warehouse_id,parent_id,node_type,status);
create index idx_inventory_lots_expiry on public.inventory_lots(inventory_item_id,expiry_date,status);
create index idx_inventory_movements_scope on public.inventory_movements(organization_unit_id,status,occurred_at desc);
create index idx_inventory_movement_lines_item on public.inventory_movement_lines(inventory_item_id,lot_id);
create index idx_stock_reservations_active on public.stock_reservations(warehouse_node_id,inventory_item_id,status,expires_at);
create index idx_stock_count_sessions_status on public.stock_count_sessions(organization_unit_id,status,created_at desc);

create or replace function app_private.validate_warehouse_node_hierarchy()
returns trigger language plpgsql security definer set search_path=''
as $$ declare p_type text; p_warehouse uuid; begin
  if new.node_type='ZONE' then if new.parent_id is not null then raise exception 'warehouse_zone_parent_must_be_null'; end if;
  else
    if new.parent_id is null then raise exception 'warehouse_node_parent_required'; end if;
    select node_type,warehouse_id into p_type,p_warehouse from public.warehouse_nodes where id=new.parent_id;
    if p_warehouse is distinct from new.warehouse_id then raise exception 'warehouse_node_parent_cross_warehouse'; end if;
    if new.node_type='LOCATION' and p_type<>'ZONE' then raise exception 'warehouse_location_parent_must_be_zone'; end if;
    if new.node_type='BIN' and p_type<>'LOCATION' then raise exception 'warehouse_bin_parent_must_be_location'; end if;
  end if; return new; end; $$;
revoke all on function app_private.validate_warehouse_node_hierarchy() from public,anon,authenticated;
create trigger trg_validate_warehouse_node_hierarchy before insert or update of parent_id,node_type,warehouse_id on public.warehouse_nodes for each row execute function app_private.validate_warehouse_node_hierarchy();

create or replace function app_private.prevent_posted_inventory_movement_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ begin if old.status in ('POSTED','REVERSED') then raise exception 'posted_inventory_movement_is_immutable_use_reversal'; end if; return new; end; $$;
revoke all on function app_private.prevent_posted_inventory_movement_mutation() from public,anon,authenticated;
create trigger trg_inventory_movement_immutable before update or delete on public.inventory_movements for each row execute function app_private.prevent_posted_inventory_movement_mutation();

create or replace function app_private.prevent_posted_inventory_line_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ declare s text; begin select status into s from public.inventory_movements where id=old.inventory_movement_id; if s in ('POSTED','REVERSED') then raise exception 'posted_inventory_movement_line_is_immutable_use_reversal'; end if; return new; end; $$;
revoke all on function app_private.prevent_posted_inventory_line_mutation() from public,anon,authenticated;
create trigger trg_inventory_movement_line_immutable before update or delete on public.inventory_movement_lines for each row execute function app_private.prevent_posted_inventory_line_mutation();

alter table public.inventory_uoms enable row level security; alter table public.inventory_items enable row level security; alter table public.inventory_item_uom_conversions enable row level security;
alter table public.warehouses enable row level security; alter table public.warehouse_nodes enable row level security; alter table public.inventory_lots enable row level security;
alter table public.inventory_movements enable row level security; alter table public.inventory_movement_lines enable row level security; alter table public.stock_reservations enable row level security;
alter table public.stock_count_sessions enable row level security; alter table public.stock_count_lines enable row level security; alter table public.inventory_accounting_event_mappings enable row level security;

create policy inventory_uoms_read on public.inventory_uoms for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy inventory_items_read on public.inventory_items for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy inventory_item_uom_read on public.inventory_item_uom_conversions for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy warehouses_read on public.warehouses for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy warehouse_nodes_read on public.warehouse_nodes for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy inventory_lots_read on public.inventory_lots for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy inventory_movements_read on public.inventory_movements for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy inventory_movement_lines_read on public.inventory_movement_lines for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy stock_reservations_read on public.stock_reservations for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy stock_count_sessions_read on public.stock_count_sessions for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy stock_count_lines_read on public.stock_count_lines for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy inventory_accounting_map_read on public.inventory_accounting_event_mappings for select to authenticated using (public.has_permission('INVENTORY_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));

grant select on public.inventory_uoms,public.inventory_items,public.inventory_item_uom_conversions,public.warehouses,public.warehouse_nodes,public.inventory_lots,public.inventory_movements,public.inventory_movement_lines,public.stock_reservations,public.stock_count_sessions,public.stock_count_lines,public.inventory_accounting_event_mappings to authenticated;
revoke insert,update,delete on public.inventory_uoms,public.inventory_items,public.inventory_item_uom_conversions,public.warehouses,public.warehouse_nodes,public.inventory_lots,public.inventory_movements,public.inventory_movement_lines,public.stock_reservations,public.stock_count_sessions,public.stock_count_lines,public.inventory_accounting_event_mappings from anon,authenticated;

create view public.inventory_stock_balances with (security_invoker=true) as
with ledger as (
  select ml.organization_id,ml.organization_node_id,ml.organization_unit_id,m.warehouse_id,ml.from_warehouse_node_id warehouse_node_id,ml.inventory_item_id,ml.lot_id,ml.from_stock_status stock_status,-ml.base_quantity quantity
  from public.inventory_movement_lines ml join public.inventory_movements m on m.id=ml.inventory_movement_id where m.status='POSTED' and ml.from_warehouse_node_id is not null
  union all
  select ml.organization_id,ml.organization_node_id,ml.organization_unit_id,m.warehouse_id,ml.to_warehouse_node_id warehouse_node_id,ml.inventory_item_id,ml.lot_id,ml.to_stock_status stock_status,ml.base_quantity quantity
  from public.inventory_movement_lines ml join public.inventory_movements m on m.id=ml.inventory_movement_id where m.status='POSTED' and ml.to_warehouse_node_id is not null
)
select organization_id,organization_node_id,organization_unit_id,warehouse_id,warehouse_node_id,inventory_item_id,lot_id,stock_status,sum(quantity)::numeric(20,6) quantity
from ledger group by organization_id,organization_node_id,organization_unit_id,warehouse_id,warehouse_node_id,inventory_item_id,lot_id,stock_status;
grant select on public.inventory_stock_balances to authenticated;

create view public.inventory_available_positions with (security_invoker=true) as
select b.*,coalesce(r.reserved_quantity,0)::numeric(20,6) reserved_quantity,
  case when b.stock_status='AVAILABLE' then (b.quantity-coalesce(r.reserved_quantity,0)) else b.quantity end::numeric(20,6) available_to_allocate
from public.inventory_stock_balances b
left join (
  select warehouse_node_id,inventory_item_id,lot_id,sum(quantity)::numeric(20,6) reserved_quantity
  from public.stock_reservations where status='ACTIVE' and (expires_at is null or expires_at>now()) group by warehouse_node_id,inventory_item_id,lot_id
) r on r.warehouse_node_id=b.warehouse_node_id and r.inventory_item_id=b.inventory_item_id and r.lot_id is not distinct from b.lot_id;
grant select on public.inventory_available_positions to authenticated;

insert into public.accounting_event_definitions(event_code,domain,name,description,status) values
('INVENTORY_ADJUSTMENT_POST','INVENTORY','Inventory adjustment posting','Accounting event for approved stock adjustment movements.','ACTIVE'),
('INVENTORY_DAMAGE_POST','INVENTORY','Inventory damage posting','Accounting event for approved damaged stock recognition.','ACTIVE'),
('INVENTORY_EXPIRY_POST','INVENTORY','Inventory expiry posting','Accounting event for approved expired stock recognition.','ACTIVE'),
('INVENTORY_LOSS_POST','INVENTORY','Inventory loss posting','Accounting event for approved inventory loss recognition.','ACTIVE')
on conflict (event_code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1)
insert into public.inventory_uoms(organization_id,organization_node_id,code,name,dimension,decimal_places)
select o.id,n.id,x.code,x.name,x.dimension,x.decimals from o,n,(values ('EA','Each','COUNT',0),('KG','Kilogram','WEIGHT',3),('L','Liter','VOLUME',3)) x(code,name,dimension,decimals)
on conflict (organization_node_id,code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1),u as (select id from public.organization_units where code='DEMO-WAREHOUSE' limit 1)
insert into public.warehouses(organization_id,organization_node_id,organization_unit_id,code,name,warehouse_type,status)
select o.id,n.id,u.id,'DEMO-WH-01','DEMO — Gudang Utama','GENERAL','ACTIVE' from o,n,u on conflict (organization_node_id,code) do nothing;

with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-WH-01' limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select organization_id,organization_node_id,organization_unit_id,id,null,'ZONE','RECEIVING','Area Penerimaan' from wh on conflict (warehouse_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-WH-01' limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select organization_id,organization_node_id,organization_unit_id,id,null,'ZONE','STORAGE','Area Penyimpanan' from wh on conflict (warehouse_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-WH-01' limit 1),z as (select id from public.warehouse_nodes where code='STORAGE' and warehouse_id=(select id from wh) limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select wh.organization_id,wh.organization_node_id,wh.organization_unit_id,wh.id,z.id,'LOCATION','RACK-A','Rak A' from wh,z on conflict (warehouse_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-WH-01' limit 1),p as (select id from public.warehouse_nodes where code='RACK-A' and warehouse_id=(select id from wh) limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select wh.organization_id,wh.organization_node_id,wh.organization_unit_id,wh.id,p.id,'BIN','A-01','Bin A-01' from wh,p on conflict (warehouse_id,code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1),ea as (select id from public.inventory_uoms where code='EA' and organization_node_id=(select id from n) limit 1),kg as (select id from public.inventory_uoms where code='KG' and organization_node_id=(select id from n) limit 1),l as (select id from public.inventory_uoms where code='L' and organization_node_id=(select id from n) limit 1)
insert into public.inventory_items(organization_id,organization_node_id,sku,name,category_code,base_uom_id,tracking_type,expiry_control,costing_method,picking_policy,status)
select o.id,n.id,x.sku,x.name,'GENERAL_RETAIL',case x.uom when 'KG' then kg.id when 'L' then l.id else ea.id end,x.tracking,x.expiry,'WEIGHTED_AVERAGE',case when x.expiry then 'FEFO' else 'FIFO' end,'ACTIVE'
from o,n,ea,kg,l,(values ('DEMO-BERAS-5KG','DEMO — Beras 5 Kg','KG','LOT'::text,false),('DEMO-MINYAK-1L','DEMO — Minyak Goreng 1 L','L','LOT'::text,true),('DEMO-GULA-1KG','DEMO — Gula Pasir 1 Kg','KG','LOT'::text,false)) x(sku,name,uom,tracking,expiry)
on conflict (organization_node_id,sku) do nothing;

insert into public.inventory_item_uom_conversions(organization_id,organization_node_id,inventory_item_id,uom_id,factor_to_base)
select i.organization_id,i.organization_node_id,i.id,i.base_uom_id,1 from public.inventory_items i where i.sku like 'DEMO-%' on conflict (inventory_item_id,uom_id) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1)
insert into public.inventory_accounting_event_mappings(organization_id,organization_node_id,movement_type,accounting_event_code,mapping_status,notes)
select o.id,n.id,x.movement_type,x.event_code,x.status,'DEMO mapping foundation — final accounting mapping requires review.' from o,n,(values
('RECEIPT','PURCHASE_RECEIPT_POST','MAPPED'),('SALE_ISSUE','SALE_POST','MAPPED'),('TRANSFER',null,'NO_GL_REQUIRED'),('ADJUSTMENT_IN','INVENTORY_ADJUSTMENT_POST','MAPPED'),('ADJUSTMENT_OUT','INVENTORY_ADJUSTMENT_POST','MAPPED'),('STOCK_COUNT_ADJUSTMENT','INVENTORY_ADJUSTMENT_POST','MAPPED'),('DAMAGE','INVENTORY_DAMAGE_POST','MAPPED'),('EXPIRY','INVENTORY_EXPIRY_POST','MAPPED'),('LOSS','INVENTORY_LOSS_POST','MAPPED')) x(movement_type,event_code,status)
on conflict (organization_node_id,movement_type) do nothing;