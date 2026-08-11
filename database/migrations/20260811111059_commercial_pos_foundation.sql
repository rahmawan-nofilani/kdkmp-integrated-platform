insert into public.permissions(code,domain,description,is_privileged)
values
('SALES_VIEW','COMMERCIAL','View sales and POS operational records within assigned scope.',false),
('POS_SHIFT_VIEW','COMMERCIAL','View POS shift and cash reconciliation records.',false),
('POS_SHIFT_MANAGE','COMMERCIAL','Open/close controlled POS shifts and submit reconciliation.',true),
('SALES_ORDER_VIEW','COMMERCIAL','View sales orders and fulfillment records.',false),
('SALES_RETURN','COMMERCIAL','Create controlled sales return workflow.',true)
on conflict(code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on
 (r.code='MANAGER' and p.code in ('SALES_VIEW','POS_SHIFT_VIEW','SALES_ORDER_VIEW')) or
 (r.code='CASHIER' and p.code in ('SALES_VIEW','POS_SHIFT_VIEW','POS_SHIFT_MANAGE','SALES_CREATE','SALES_ORDER_VIEW')) or
 (r.code='ADMIN' and p.code in ('SALES_VIEW','POS_SHIFT_VIEW','SALES_ORDER_VIEW')) or
 (r.code='SUPERVISOR' and p.code in ('SALES_VIEW','POS_SHIFT_VIEW','SALES_ORDER_VIEW')) or
 (r.code='COURIER' and p.code='SALES_ORDER_VIEW')
on conflict do nothing;

create table public.pos_terminals (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 code text not null, name text not null, device_reference text,
 default_warehouse_id uuid references public.warehouses(id) on delete restrict,
 status text not null default 'ACTIVE' check(status in ('DRAFT','ACTIVE','SUSPENDED','INACTIVE')),
 created_at timestamptz not null default now(), unique(organization_unit_id,code)
);

create table public.pos_shifts (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
 cashier_profile_id uuid not null references public.profiles(id) on delete restrict,
 shift_number text, status text not null default 'OPEN' check(status in ('OPEN','CLOSING','CLOSED','RECONCILIATION_EXCEPTION','CANCELLED')),
 opened_at timestamptz not null default now(), closed_at timestamptz,
 opening_cash numeric(20,2) not null default 0 check(opening_cash>=0), expected_cash numeric(20,2), counted_cash numeric(20,2),
 cash_variance numeric(20,2) generated always as (case when expected_cash is null or counted_cash is null then null else counted_cash-expected_cash end) stored,
 reconciliation_status text not null default 'PENDING' check(reconciliation_status in ('PENDING','MATCHED','EXCEPTION','REVIEWED')),
 notes text, created_at timestamptz not null default now(), unique(organization_unit_id,shift_number)
);

create table public.sales_transactions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 terminal_id uuid references public.pos_terminals(id) on delete restrict, pos_shift_id uuid references public.pos_shifts(id) on delete restrict,
 sale_number text, sale_type text not null default 'POS' check(sale_type in ('POS','ORDER_INVOICE','OTHER')),
 customer_member_id uuid references public.members(id) on delete restrict, customer_reference text,
 currency text not null default 'IDR', subtotal numeric(20,2) not null default 0 check(subtotal>=0), discount_amount numeric(20,2) not null default 0 check(discount_amount>=0), tax_amount numeric(20,2) not null default 0 check(tax_amount>=0),
 total_amount numeric(20,2) generated always as (subtotal-discount_amount+tax_amount) stored,
 status text not null default 'DRAFT' check(status in ('DRAFT','PAYMENT_PENDING','PAID','FULFILLMENT_PENDING','COMPLETED','VOID_PENDING','VOIDED','RETURNED','CANCELLED')),
 payment_intent_id uuid references public.payment_intents(id) on delete restrict, inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
 journal_entry_id uuid references public.journal_entries(id) on delete restrict, reversal_of_sale_id uuid references public.sales_transactions(id) on delete restrict,
 receipt_reference text, local_transaction_id text, device_id text, client_sequence bigint, idempotency_key text,
 sync_status text not null default 'SYNCED' check(sync_status in ('SYNCED','PENDING','FAILED','CONFLICT')),
 correlation_id uuid, sold_at timestamptz, completed_at timestamptz, created_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_node_id,sale_number), unique(organization_node_id,idempotency_key)
);

create table public.sales_transaction_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict, line_no integer not null check(line_no>0),
 inventory_item_id uuid references public.inventory_items(id) on delete restrict, item_snapshot jsonb not null default '{}'::jsonb,
 description text not null, uom_id uuid references public.inventory_uoms(id) on delete restrict,
 quantity numeric(20,6) not null check(quantity>0), unit_price numeric(20,2) not null check(unit_price>=0), discount_amount numeric(20,2) not null default 0 check(discount_amount>=0), tax_amount numeric(20,2) not null default 0 check(tax_amount>=0),
 line_total numeric(20,2) generated always as ((quantity*unit_price)-discount_amount+tax_amount) stored,
 unique(sales_transaction_id,line_no)
);

create table public.sales_orders (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 order_number text, customer_member_id uuid references public.members(id) on delete restrict, customer_reference text,
 channel text not null default 'OFFICE' check(channel in ('OFFICE','POS','PHONE','WEB','MARKETPLACE_ADAPTER','OTHER')),
 currency text not null default 'IDR', requested_delivery_date date, delivery_address_snapshot jsonb not null default '{}'::jsonb,
 status text not null default 'DRAFT' check(status in ('DRAFT','CONFIRMED','ALLOCATING','READY','PARTIALLY_FULFILLED','FULFILLED','CANCELLED','CLOSED')),
 payment_intent_id uuid references public.payment_intents(id) on delete restrict,
 created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_node_id,order_number)
);

create table public.sales_order_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 sales_order_id uuid not null references public.sales_orders(id) on delete restrict, line_no integer not null check(line_no>0),
 inventory_item_id uuid not null references public.inventory_items(id) on delete restrict, description text not null, uom_id uuid references public.inventory_uoms(id) on delete restrict,
 ordered_quantity numeric(20,6) not null check(ordered_quantity>0), fulfilled_quantity numeric(20,6) not null default 0 check(fulfilled_quantity>=0), unit_price numeric(20,2) not null check(unit_price>=0),
 unique(sales_order_id,line_no), check(fulfilled_quantity<=ordered_quantity)
);

create table public.fulfillment_orders (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 sales_order_id uuid not null references public.sales_orders(id) on delete restrict, fulfillment_number text,
 warehouse_id uuid references public.warehouses(id) on delete restrict,
 status text not null default 'PLANNED' check(status in ('PLANNED','RESERVED','PICKING','PACKED','READY','DISPATCHED','DELIVERED','FAILED','CANCELLED')),
 inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
 assigned_courier_profile_id uuid references public.profiles(id) on delete restrict,
 dispatched_at timestamptz, delivered_at timestamptz, pod_reference text, created_at timestamptz not null default now(), unique(organization_node_id,fulfillment_number)
);

create table public.sales_returns (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 original_sale_id uuid not null references public.sales_transactions(id) on delete restrict, return_number text, reason_code text,
 status text not null default 'DRAFT' check(status in ('DRAFT','PENDING_APPROVAL','APPROVED','RECEIVING','POSTED','REJECTED','CANCELLED')),
 approval_request_id uuid references public.approval_requests(id) on delete restrict,
 inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
 payment_intent_id uuid references public.payment_intents(id) on delete restrict, journal_entry_id uuid references public.journal_entries(id) on delete restrict,
 created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), unique(organization_node_id,return_number)
);

create index idx_pos_shifts_terminal on public.pos_shifts(terminal_id,status,opened_at desc);
create index idx_sales_transactions_scope on public.sales_transactions(organization_unit_id,status,sold_at desc);
create index idx_sales_orders_scope on public.sales_orders(organization_unit_id,status,created_at desc);
create index idx_fulfillment_status on public.fulfillment_orders(organization_unit_id,status,created_at desc);
create index idx_sales_returns_sale on public.sales_returns(original_sale_id,status);

create or replace function app_private.prevent_completed_sale_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ begin if old.status in ('COMPLETED','VOIDED','RETURNED') then raise exception 'completed_sale_is_immutable_use_void_or_return_flow'; end if; return new; end; $$;
revoke all on function app_private.prevent_completed_sale_mutation() from public,anon,authenticated;
create trigger trg_sales_transaction_immutable before update or delete on public.sales_transactions for each row execute function app_private.prevent_completed_sale_mutation();

create or replace function app_private.prevent_completed_sale_line_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ declare s text; begin select status into s from public.sales_transactions where id=old.sales_transaction_id; if s in ('COMPLETED','VOIDED','RETURNED') then raise exception 'completed_sale_line_is_immutable'; end if; return new; end; $$;
revoke all on function app_private.prevent_completed_sale_line_mutation() from public,anon,authenticated;
create trigger trg_sales_transaction_line_immutable before update or delete on public.sales_transaction_lines for each row execute function app_private.prevent_completed_sale_line_mutation();

alter table public.pos_terminals enable row level security; alter table public.pos_shifts enable row level security; alter table public.sales_transactions enable row level security; alter table public.sales_transaction_lines enable row level security; alter table public.sales_orders enable row level security; alter table public.sales_order_lines enable row level security; alter table public.fulfillment_orders enable row level security; alter table public.sales_returns enable row level security;
create policy pos_terminals_read on public.pos_terminals for select to authenticated using(public.has_permission('SALES_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy pos_shifts_read on public.pos_shifts for select to authenticated using(public.has_permission('POS_SHIFT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy sales_transactions_read on public.sales_transactions for select to authenticated using(public.has_permission('SALES_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,customer_member_id,null));
create policy sales_transaction_lines_read on public.sales_transaction_lines for select to authenticated using(public.has_permission('SALES_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy sales_orders_read on public.sales_orders for select to authenticated using(public.has_permission('SALES_ORDER_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,customer_member_id,null));
create policy sales_order_lines_read on public.sales_order_lines for select to authenticated using(public.has_permission('SALES_ORDER_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy fulfillment_orders_read on public.fulfillment_orders for select to authenticated using(public.has_permission('SALES_ORDER_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy sales_returns_read on public.sales_returns for select to authenticated using(public.has_permission('SALES_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
grant select on public.pos_terminals,public.pos_shifts,public.sales_transactions,public.sales_transaction_lines,public.sales_orders,public.sales_order_lines,public.fulfillment_orders,public.sales_returns to authenticated;
revoke insert,update,delete on public.pos_terminals,public.pos_shifts,public.sales_transactions,public.sales_transaction_lines,public.sales_orders,public.sales_order_lines,public.fulfillment_orders,public.sales_returns from anon,authenticated;

insert into public.accounting_event_definitions(event_code,domain,name,description,status)
values('SALES_RETURN_POST','COMMERCIAL','Sales return posting','Accounting event for approved sales return/reversal.','ACTIVE') on conflict(event_code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1),u as (select id from public.organization_units where code='DEMO-RETAIL' limit 1)
insert into public.warehouses(organization_id,organization_node_id,organization_unit_id,code,name,warehouse_type,status)
select o.id,n.id,u.id,'DEMO-RETAIL-WH','DEMO — Stok Gerai','RETAIL_BACKROOM','ACTIVE' from o,n,u on conflict(organization_node_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-RETAIL-WH' limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select organization_id,organization_node_id,organization_unit_id,id,null,'ZONE','RETAIL-BACKROOM','Backroom Gerai' from wh on conflict(warehouse_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-RETAIL-WH' limit 1),z as (select id from public.warehouse_nodes where warehouse_id=(select id from wh) and code='RETAIL-BACKROOM' limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select wh.organization_id,wh.organization_node_id,wh.organization_unit_id,wh.id,z.id,'LOCATION','RETAIL-RACK-01','Rak Gerai 01' from wh,z on conflict(warehouse_id,code) do nothing;
with wh as (select id,organization_id,organization_node_id,organization_unit_id from public.warehouses where code='DEMO-RETAIL-WH' limit 1),p as (select id from public.warehouse_nodes where warehouse_id=(select id from wh) and code='RETAIL-RACK-01' limit 1)
insert into public.warehouse_nodes(organization_id,organization_node_id,organization_unit_id,warehouse_id,parent_id,node_type,code,name)
select wh.organization_id,wh.organization_node_id,wh.organization_unit_id,wh.id,p.id,'BIN','RETAIL-BIN-01','Bin Gerai 01' from wh,p on conflict(warehouse_id,code) do nothing;
with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1),u as (select id from public.organization_units where code='DEMO-RETAIL' limit 1),wh as (select id from public.warehouses where code='DEMO-RETAIL-WH' limit 1)
insert into public.pos_terminals(organization_id,organization_node_id,organization_unit_id,code,name,device_reference,default_warehouse_id,status)
select o.id,n.id,u.id,'DEMO-POS-01','DEMO — Kasir 01','DEMO-DEVICE-NOT-BOUND',wh.id,'ACTIVE' from o,n,u,wh on conflict(organization_unit_id,code) do nothing;
