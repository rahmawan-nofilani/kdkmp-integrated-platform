insert into public.permissions(code,domain,description,is_privileged)
values
  ('POS_PAYMENT_CAPTURE','SALES','Capture payment only within controlled POS sale workflow',false),
  ('SALES_PRICE_VIEW','SALES','View sales price configuration',false),
  ('SALES_PRICE_MANAGE','SALES','Create and maintain draft sales price configuration',true),
  ('SALES_PRICE_APPROVE','SALES','Approve and activate sales price configuration',true)
on conflict (code) do update
set domain=excluded.domain,
    description=excluded.description,
    is_privileged=excluded.is_privileged;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on true
where (r.code='MANAGER' and p.code in ('POS_PAYMENT_CAPTURE','POS_SHIFT_MANAGE','SALES_PRICE_VIEW','SALES_PRICE_MANAGE','SALES_PRICE_APPROVE'))
   or (r.code='CASHIER' and p.code='POS_PAYMENT_CAPTURE')
   or (r.code='ADMIN' and p.code='SALES_PRICE_VIEW')
on conflict do nothing;

create table public.sales_price_lists (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  code text not null,
  name text not null,
  channel text not null default 'POS' check (channel in ('POS','ORDER','ALL')),
  currency text not null default 'IDR',
  priority integer not null default 100 check (priority >= 0),
  status text not null default 'DRAFT' check (status in ('DRAFT','REVIEW','ACTIVE','INACTIVE','ARCHIVED')),
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_price_lists_valid_window check (valid_until is null or valid_from is null or valid_until > valid_from),
  constraint sales_price_lists_scope_code_key unique (organization_node_id,organization_unit_id,code)
);

create table public.sales_price_entries (
  id uuid primary key default gen_random_uuid(),
  sales_price_list_id uuid not null references public.sales_price_lists(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  uom_id uuid not null references public.inventory_uoms(id) on delete restrict,
  min_quantity numeric(20,6) not null default 1 check (min_quantity > 0),
  unit_price numeric(20,2) not null check (unit_price > 0),
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')),
  effective_from timestamptz,
  effective_until timestamptz,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sales_price_entries_valid_window check (effective_until is null or effective_from is null or effective_until > effective_from),
  constraint sales_price_entries_tier_key unique (sales_price_list_id,inventory_item_id,uom_id,min_quantity,effective_from)
);

create index idx_sales_price_lists_scope_active
  on public.sales_price_lists(organization_id,organization_node_id,organization_unit_id,status,channel,priority desc);
create index idx_sales_price_lists_validity
  on public.sales_price_lists(valid_from,valid_until) where status='ACTIVE';
create index idx_sales_price_entries_item_active
  on public.sales_price_entries(organization_id,organization_node_id,organization_unit_id,inventory_item_id,uom_id,status,min_quantity desc);
create index idx_sales_price_entries_list
  on public.sales_price_entries(sales_price_list_id);
create index idx_sales_price_entries_created_by
  on public.sales_price_entries(created_by);
create index idx_sales_price_lists_created_by
  on public.sales_price_lists(created_by);
create index idx_sales_price_lists_approved_by
  on public.sales_price_lists(approved_by);

alter table public.sales_price_lists enable row level security;
alter table public.sales_price_entries enable row level security;

revoke all on public.sales_price_lists from public,anon,authenticated;
revoke all on public.sales_price_entries from public,anon,authenticated;
grant select on public.sales_price_lists to authenticated;
grant select on public.sales_price_entries to authenticated;
grant all on public.sales_price_lists to service_role;
grant all on public.sales_price_entries to service_role;

create policy sales_price_lists_read on public.sales_price_lists
for select to authenticated
using (
  public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
  and (
    public.has_permission('SALES_PRICE_VIEW')
    or (
      public.has_permission('SALES_VIEW')
      and status='ACTIVE'
      and channel in ('POS','ALL')
      and (valid_from is null or valid_from <= now())
      and (valid_until is null or valid_until > now())
    )
  )
);

create policy sales_price_entries_read on public.sales_price_entries
for select to authenticated
using (
  public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
  and (
    public.has_permission('SALES_PRICE_VIEW')
    or (
      public.has_permission('SALES_VIEW')
      and status='ACTIVE'
      and exists (
        select 1
        from public.sales_price_lists spl
        where spl.id=sales_price_entries.sales_price_list_id
          and spl.status='ACTIVE'
          and spl.channel in ('POS','ALL')
          and (spl.valid_from is null or spl.valid_from <= now())
          and (spl.valid_until is null or spl.valid_until > now())
      )
    )
  )
);

create or replace function app_private.prevent_active_price_list_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op='DELETE' and old.status='ACTIVE' then
    raise exception 'ACTIVE_PRICE_LIST_DELETE_DENIED' using errcode='42501';
  end if;
  if tg_op='UPDATE' and old.status='ACTIVE' then
    if new.organization_id is distinct from old.organization_id
       or new.organization_node_id is distinct from old.organization_node_id
       or new.organization_unit_id is distinct from old.organization_unit_id
       or new.code is distinct from old.code
       or new.currency is distinct from old.currency
       or new.channel is distinct from old.channel then
      raise exception 'ACTIVE_PRICE_LIST_IDENTITY_IMMUTABLE' using errcode='42501';
    end if;
  end if;
  if tg_op='UPDATE' then new.updated_at:=now(); end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create or replace function app_private.prevent_active_price_entry_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_list_status text;
begin
  select status into v_list_status
  from public.sales_price_lists
  where id=coalesce(new.sales_price_list_id,old.sales_price_list_id);

  if v_list_status='ACTIVE' then
    if tg_op='DELETE' then
      raise exception 'ACTIVE_PRICE_ENTRY_DELETE_DENIED' using errcode='42501';
    end if;
    if new.sales_price_list_id is distinct from old.sales_price_list_id
       or new.organization_id is distinct from old.organization_id
       or new.organization_node_id is distinct from old.organization_node_id
       or new.organization_unit_id is distinct from old.organization_unit_id
       or new.inventory_item_id is distinct from old.inventory_item_id
       or new.uom_id is distinct from old.uom_id
       or new.min_quantity is distinct from old.min_quantity
       or new.unit_price is distinct from old.unit_price
       or new.effective_from is distinct from old.effective_from
       or new.effective_until is distinct from old.effective_until then
      raise exception 'ACTIVE_PRICE_ENTRY_IMMUTABLE' using errcode='42501';
    end if;
  end if;
  if tg_op='UPDATE' then new.updated_at:=now(); end if;
  return case when tg_op='DELETE' then old else new end;
end;
$$;

create trigger trg_sales_price_lists_guard
before update or delete on public.sales_price_lists
for each row execute function app_private.prevent_active_price_list_mutation();

create trigger trg_sales_price_entries_guard
before update or delete on public.sales_price_entries
for each row execute function app_private.prevent_active_price_entry_mutation();

revoke all on function app_private.prevent_active_price_list_mutation() from public,anon,authenticated;
revoke all on function app_private.prevent_active_price_entry_mutation() from public,anon,authenticated;
