insert into public.permissions(code,domain,description,is_privileged)
values
('SUPPLIER_VIEW','PROCUREMENT','View supplier master within assigned data scope.',false),
('PURCHASE_VIEW','PROCUREMENT','View procurement requisitions, purchase orders, receipts and matching within assigned scope.',false),
('PURCHASE_RECEIVE','PROCUREMENT','Record controlled goods receiving and QC workflow.',false),
('PURCHASE_INVOICE_VIEW','PROCUREMENT','View supplier invoice records and status.',false),
('PURCHASE_MATCH','PROCUREMENT','Review PO/receipt/invoice matching and exceptions.',true)
on conflict (code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on
 (r.code='MANAGER' and p.code in ('SUPPLIER_VIEW','PURCHASE_VIEW','PURCHASE_INVOICE_VIEW','PURCHASE_MATCH')) or
 (r.code='PROCUREMENT_OFFICER' and p.code in ('SUPPLIER_VIEW','PURCHASE_VIEW','PURCHASE_CREATE','PURCHASE_SUBMIT')) or
 (r.code='WAREHOUSE_OPERATOR' and p.code in ('PURCHASE_VIEW','PURCHASE_RECEIVE')) or
 (r.code='FINANCE_OFFICER' and p.code in ('PURCHASE_VIEW','PURCHASE_INVOICE_VIEW','PURCHASE_MATCH')) or
 (r.code='SUPERVISOR' and p.code in ('SUPPLIER_VIEW','PURCHASE_VIEW','PURCHASE_INVOICE_VIEW'))
on conflict do nothing;

create table public.suppliers (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 code text not null, name text not null, legal_name text,
 supplier_type text not null default 'GENERAL' check (supplier_type in ('GENERAL','PRODUCER','DISTRIBUTOR','SERVICE','GOVERNMENT_PARTNER','OTHER')),
 qualification_status text not null default 'PENDING' check (qualification_status in ('PENDING','QUALIFIED','CONDITIONAL','SUSPENDED','REJECTED','EXPIRED')),
 risk_status text not null default 'NOT_ASSESSED' check (risk_status in ('NOT_ASSESSED','LOW','MEDIUM','HIGH','REVIEW_REQUIRED')),
 payment_term_code text,
 tax_profile_status text not null default 'NOT_CONFIGURED' check (tax_profile_status in ('NOT_CONFIGURED','CONFIGURED','REVIEW_REQUIRED')),
 regulatory_status text not null default 'NOT_REQUIRED' check (regulatory_status in ('NOT_REQUIRED','PENDING_VALIDATION','VALIDATED','EXPIRED','SUSPENDED')),
 status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_node_id,code)
);

create table public.purchase_requisitions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 requisition_number text, requested_by uuid references public.profiles(id) on delete restrict,
 purpose text, required_date date,
 status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','REVIEW','PENDING_APPROVAL','APPROVED','REJECTED','CANCELLED','CONVERTED')),
 approval_request_id uuid references public.approval_requests(id) on delete restrict,
 submitted_at timestamptz, decided_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_node_id,requisition_number)
);

create table public.purchase_requisition_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 purchase_requisition_id uuid not null references public.purchase_requisitions(id) on delete restrict,
 line_no integer not null check(line_no>0), inventory_item_id uuid references public.inventory_items(id) on delete restrict,
 description text not null, uom_id uuid references public.inventory_uoms(id) on delete restrict,
 quantity numeric(20,6) not null check(quantity>0), estimated_unit_price numeric(20,2), notes text,
 unique(purchase_requisition_id,line_no)
);

create table public.purchase_orders (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 purchase_requisition_id uuid references public.purchase_requisitions(id) on delete restrict,
 po_number text, version_no integer not null default 1 check(version_no>0), currency text not null default 'IDR',
 expected_delivery_date date, delivery_location_text text,
 terms_snapshot jsonb not null default '{}'::jsonb, supplier_snapshot jsonb not null default '{}'::jsonb,
 status text not null default 'DRAFT' check(status in ('DRAFT','PENDING_APPROVAL','APPROVED','SENT','PARTIALLY_RECEIVED','RECEIVED','CLOSED','CANCELLED')),
 approval_request_id uuid references public.approval_requests(id) on delete restrict,
 approved_at timestamptz, sent_at timestamptz, closed_at timestamptz,
 created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_node_id,po_number,version_no)
);

create table public.purchase_order_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 line_no integer not null check(line_no>0), inventory_item_id uuid references public.inventory_items(id) on delete restrict,
 description text not null, uom_id uuid references public.inventory_uoms(id) on delete restrict,
 ordered_quantity numeric(20,6) not null check(ordered_quantity>0), unit_price numeric(20,2) not null check(unit_price>=0),
 tax_configuration_snapshot jsonb not null default '{}'::jsonb,
 line_total numeric(20,2) generated always as (ordered_quantity*unit_price) stored,
 unique(purchase_order_id,line_no)
);

create table public.goods_receipts (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 warehouse_id uuid not null references public.warehouses(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete restrict,
 receipt_number text, supplier_delivery_reference text, received_at timestamptz,
 status text not null default 'DRAFT' check(status in ('DRAFT','RECEIVING','QC_PENDING','PARTIALLY_ACCEPTED','ACCEPTED','REJECTED','POSTED','CANCELLED')),
 inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
 accounting_status text not null default 'NOT_POSTED' check(accounting_status in ('NOT_POSTED','GRNI_POSTED','INVOICE_MATCHED','RECONCILED','EXCEPTION')),
 journal_entry_id uuid references public.journal_entries(id) on delete restrict,
 received_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
 unique(organization_node_id,receipt_number)
);

create table public.goods_receipt_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 goods_receipt_id uuid not null references public.goods_receipts(id) on delete restrict,
 purchase_order_line_id uuid not null references public.purchase_order_lines(id) on delete restrict,
 line_no integer not null check(line_no>0), inventory_item_id uuid references public.inventory_items(id) on delete restrict,
 lot_id uuid references public.inventory_lots(id) on delete restrict, uom_id uuid references public.inventory_uoms(id) on delete restrict,
 delivered_quantity numeric(20,6) not null check(delivered_quantity>=0),
 accepted_quantity numeric(20,6) not null default 0 check(accepted_quantity>=0),
 rejected_quantity numeric(20,6) not null default 0 check(rejected_quantity>=0),
 quarantined_quantity numeric(20,6) not null default 0 check(quarantined_quantity>=0),
 qc_status text not null default 'PENDING' check(qc_status in ('PENDING','ACCEPTED','REJECTED','PARTIAL','QUARANTINE','REVIEW_REQUIRED')),
 qc_reason text, evidence_reference text,
 unique(goods_receipt_id,line_no), check(accepted_quantity+rejected_quantity+quarantined_quantity<=delivered_quantity)
);

create table public.supplier_invoices (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 supplier_id uuid not null references public.suppliers(id) on delete restrict,
 purchase_order_id uuid references public.purchase_orders(id) on delete restrict,
 invoice_number text not null, invoice_date date not null, due_date date, currency text not null default 'IDR',
 subtotal numeric(20,2) not null default 0 check(subtotal>=0), tax_amount numeric(20,2) not null default 0 check(tax_amount>=0), other_amount numeric(20,2) not null default 0,
 total_amount numeric(20,2) generated always as (subtotal+tax_amount+other_amount) stored,
 status text not null default 'RECEIVED' check(status in ('RECEIVED','UNDER_REVIEW','MATCH_PENDING','MATCHED','EXCEPTION','APPROVED_FOR_PAYMENT','PAID','CANCELLED')),
 matching_status text not null default 'NOT_RUN' check(matching_status in ('NOT_RUN','PENDING','MATCHED','EXCEPTION')),
 approval_request_id uuid references public.approval_requests(id) on delete restrict,
 journal_entry_id uuid references public.journal_entries(id) on delete restrict,
 payment_intent_id uuid references public.payment_intents(id) on delete restrict,
 created_at timestamptz not null default now(), unique(organization_node_id,supplier_id,invoice_number)
);

create table public.supplier_invoice_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 supplier_invoice_id uuid not null references public.supplier_invoices(id) on delete restrict,
 purchase_order_line_id uuid references public.purchase_order_lines(id) on delete restrict,
 line_no integer not null check(line_no>0), description text not null,
 quantity numeric(20,6) not null check(quantity>=0), unit_price numeric(20,2) not null check(unit_price>=0),
 line_amount numeric(20,2) generated always as (quantity*unit_price) stored,
 unique(supplier_invoice_id,line_no)
);

create table public.purchase_match_results (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
 organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 supplier_invoice_id uuid not null references public.supplier_invoices(id) on delete restrict,
 purchase_order_id uuid references public.purchase_orders(id) on delete restrict,
 match_type text not null default 'THREE_WAY' check(match_type in ('TWO_WAY','THREE_WAY')),
 status text not null default 'PENDING' check(status in ('PENDING','MATCHED','EXCEPTION','OVERRIDDEN')),
 po_amount numeric(20,2), received_value numeric(20,2), invoice_amount numeric(20,2), quantity_variance numeric(20,6), amount_variance numeric(20,2),
 exception_codes text[] not null default '{}', reviewed_by uuid references public.profiles(id) on delete restrict, reviewed_at timestamptz, override_reason text, created_at timestamptz not null default now()
);

create index idx_suppliers_scope on public.suppliers(organization_node_id,status,name);
create index idx_purchase_req_scope on public.purchase_requisitions(organization_unit_id,status,created_at desc);
create index idx_purchase_order_supplier on public.purchase_orders(supplier_id,status,created_at desc);
create index idx_goods_receipts_po on public.goods_receipts(purchase_order_id,status,created_at desc);
create index idx_supplier_invoices_supplier on public.supplier_invoices(supplier_id,status,invoice_date desc);
create index idx_purchase_match_invoice on public.purchase_match_results(supplier_invoice_id,status);

create or replace function app_private.prevent_committed_po_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ begin if old.status in ('APPROVED','SENT','PARTIALLY_RECEIVED','RECEIVED','CLOSED') then raise exception 'committed_purchase_order_is_immutable_create_new_version_or_controlled_change'; end if; return new; end; $$;
revoke all on function app_private.prevent_committed_po_mutation() from public,anon,authenticated;
create trigger trg_purchase_order_immutable before update or delete on public.purchase_orders for each row execute function app_private.prevent_committed_po_mutation();

create or replace function app_private.prevent_committed_po_line_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ declare s text; begin select status into s from public.purchase_orders where id=old.purchase_order_id; if s in ('APPROVED','SENT','PARTIALLY_RECEIVED','RECEIVED','CLOSED') then raise exception 'committed_purchase_order_line_is_immutable'; end if; return new; end; $$;
revoke all on function app_private.prevent_committed_po_line_mutation() from public,anon,authenticated;
create trigger trg_purchase_order_line_immutable before update or delete on public.purchase_order_lines for each row execute function app_private.prevent_committed_po_line_mutation();

alter table public.suppliers enable row level security; alter table public.purchase_requisitions enable row level security; alter table public.purchase_requisition_lines enable row level security;
alter table public.purchase_orders enable row level security; alter table public.purchase_order_lines enable row level security; alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_lines enable row level security; alter table public.supplier_invoices enable row level security; alter table public.supplier_invoice_lines enable row level security; alter table public.purchase_match_results enable row level security;

create policy suppliers_read on public.suppliers for select to authenticated using(public.has_permission('SUPPLIER_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy purchase_req_read on public.purchase_requisitions for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy purchase_req_lines_read on public.purchase_requisition_lines for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy purchase_orders_read on public.purchase_orders for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy purchase_order_lines_read on public.purchase_order_lines for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy goods_receipts_read on public.goods_receipts for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy goods_receipt_lines_read on public.goods_receipt_lines for select to authenticated using(public.has_permission('PURCHASE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy supplier_invoices_read on public.supplier_invoices for select to authenticated using(public.has_permission('PURCHASE_INVOICE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy supplier_invoice_lines_read on public.supplier_invoice_lines for select to authenticated using(public.has_permission('PURCHASE_INVOICE_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy purchase_match_read on public.purchase_match_results for select to authenticated using(public.has_permission('PURCHASE_MATCH') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));

grant select on public.suppliers,public.purchase_requisitions,public.purchase_requisition_lines,public.purchase_orders,public.purchase_order_lines,public.goods_receipts,public.goods_receipt_lines,public.supplier_invoices,public.supplier_invoice_lines,public.purchase_match_results to authenticated;
revoke insert,update,delete on public.suppliers,public.purchase_requisitions,public.purchase_requisition_lines,public.purchase_orders,public.purchase_order_lines,public.goods_receipts,public.goods_receipt_lines,public.supplier_invoices,public.supplier_invoice_lines,public.purchase_match_results from anon,authenticated;

insert into public.accounting_event_definitions(event_code,domain,name,description,status)
values('SUPPLIER_INVOICE_POST','PROCUREMENT','Supplier invoice posting','Recognize supplier invoice and clear GRNI/record AP as applicable.','ACTIVE')
on conflict(event_code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1), n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1), parent as (select id from public.accounting_accounts where code='2000' and organization_node_id=(select id from n) limit 1)
insert into public.accounting_accounts(organization_id,organization_node_id,parent_account_id,code,name,account_class,normal_balance,is_posting,is_control_account,control_purpose,status,effective_from,notes)
select o.id,n.id,parent.id,'2210','DEMO — GRNI / Barang Diterima Belum Ditagih','LIABILITY','CREDIT',true,true,'GRNI','ACTIVE',date '2026-01-01','DEMO technical control account; final COA review required.' from o,n,parent
on conflict(organization_node_id,code) do nothing;

with o as (select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),n as (select id from public.organization_nodes where code='DEMO-KDKMP' limit 1)
insert into public.suppliers(organization_id,organization_node_id,code,name,legal_name,supplier_type,qualification_status,risk_status,status,notes)
select o.id,n.id,x.code,x.name,x.name,x.kind,'PENDING','NOT_ASSESSED','ACTIVE','DEMO supplier master only — qualification and legal details not validated.' from o,n,(values ('DEMO-SUP-PANGAN','DEMO — Supplier Pangan','DISTRIBUTOR'),('DEMO-SUP-PRODUSEN','DEMO — Kelompok/Produsen Lokal','PRODUCER')) x(code,name,kind)
on conflict(organization_node_id,code) do nothing;
