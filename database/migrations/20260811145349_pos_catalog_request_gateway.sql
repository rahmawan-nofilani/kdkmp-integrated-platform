revoke all on function public.get_pos_catalog(uuid,text,integer) from public,anon,authenticated;
drop function public.get_pos_catalog(uuid,text,integer);

create table public.pos_catalog_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  search_query text,
  result_limit integer not null default 30 check (result_limit between 1 and 50),
  result jsonb not null default '[]'::jsonb,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index idx_pos_catalog_requests_requested_by on public.pos_catalog_requests(requested_by,created_at desc);
create index idx_pos_catalog_requests_terminal on public.pos_catalog_requests(terminal_id,created_at desc);
create index idx_pos_catalog_requests_organization_id on public.pos_catalog_requests(organization_id);
create index idx_pos_catalog_requests_organization_node_id on public.pos_catalog_requests(organization_node_id);
create index idx_pos_catalog_requests_organization_unit_id on public.pos_catalog_requests(organization_unit_id);

alter table public.pos_catalog_requests enable row level security;
revoke all on public.pos_catalog_requests from public,anon,authenticated;
grant select,insert on public.pos_catalog_requests to authenticated;
grant all on public.pos_catalog_requests to service_role;

create policy pos_catalog_requests_read_own on public.pos_catalog_requests
for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
);

create policy pos_catalog_requests_insert on public.pos_catalog_requests
for insert to authenticated
with check (
  public.has_permission('SALES_VIEW')
  and exists (
    select 1 from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create or replace function app_private.pos_catalog_request_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_query text;
  v_limit integer;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;

  if v_profile.id is null or v_profile.organization_id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;
  if not public.has_permission('SALES_VIEW') then
    raise exception 'SALES_VIEW_DENIED' using errcode='42501';
  end if;

  select * into v_terminal
  from public.pos_terminals
  where id=new.terminal_id and status='ACTIVE';

  if v_terminal.id is null or v_terminal.organization_id<>v_profile.organization_id then
    raise exception 'POS_TERMINAL_NOT_AVAILABLE' using errcode='22023';
  end if;
  if not public.has_data_scope(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,null,null) then
    raise exception 'POS_TERMINAL_SCOPE_DENIED' using errcode='42501';
  end if;
  if v_terminal.default_warehouse_id is null then
    raise exception 'POS_TERMINAL_WAREHOUSE_REQUIRED' using errcode='22023';
  end if;
  if not exists(
    select 1
    from public.pos_shifts ps
    where ps.terminal_id=v_terminal.id
      and ps.cashier_profile_id=v_profile.id
      and ps.status='OPEN'
  ) then
    raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501';
  end if;

  v_query:=lower(coalesce(nullif(trim(new.search_query),''),''));
  v_limit:=least(greatest(coalesce(new.result_limit,30),1),50);

  new.organization_id:=v_terminal.organization_id;
  new.organization_node_id:=v_terminal.organization_node_id;
  new.organization_unit_id:=v_terminal.organization_unit_id;
  new.search_query:=nullif(trim(new.search_query),'');
  new.result_limit:=v_limit;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  with candidates as (
    select
      i.id as inventory_item_id,
      i.sku,
      i.barcode,
      i.name as item_name,
      c.uom_id,
      u.code as uom_code,
      u.name as uom_name,
      u.decimal_places,
      c.factor_to_base,
      price.unit_price,
      price.currency
    from public.inventory_items i
    join public.inventory_item_uom_conversions c
      on c.inventory_item_id=i.id and c.status='ACTIVE'
    join public.inventory_uoms u
      on u.id=c.uom_id and u.status='ACTIVE'
    join lateral app_private.resolve_pos_price(
      v_terminal.organization_id,
      v_terminal.organization_node_id,
      v_terminal.organization_unit_id,
      i.id,
      c.uom_id,
      1,
      now()
    ) price on true
    where i.organization_id=v_terminal.organization_id
      and i.organization_node_id=v_terminal.organization_node_id
      and i.status='ACTIVE'
      and (
        v_query=''
        or position(v_query in lower(coalesce(i.sku,'')||' '||coalesce(i.barcode,'')||' '||coalesce(i.name,'')))>0
      )
  ), stock as (
    select
      p.inventory_item_id,
      coalesce(sum(p.available_to_allocate) filter (where p.stock_status='AVAILABLE'),0) as available_base
    from public.inventory_available_positions p
    where p.warehouse_id=v_terminal.default_warehouse_id
    group by p.inventory_item_id
  ), safe_rows as (
    select
      c.inventory_item_id,
      c.sku,
      c.barcode,
      c.item_name,
      c.uom_id,
      c.uom_code,
      c.uom_name,
      c.factor_to_base,
      c.unit_price,
      c.currency,
      trunc(coalesce(s.available_base,0)/c.factor_to_base,c.decimal_places) as available_quantity,
      coalesce(s.available_base,0)>=c.factor_to_base as in_stock
    from candidates c
    left join stock s on s.inventory_item_id=c.inventory_item_id
    order by (coalesce(s.available_base,0)>=c.factor_to_base) desc,c.item_name,c.uom_name
    limit v_limit
  )
  select coalesce(jsonb_agg(to_jsonb(safe_rows)),'[]'::jsonb)
  into new.result
  from safe_rows;

  delete from public.pos_catalog_requests
  where requested_by=v_profile.id
    and created_at < now()-interval '15 minutes';

  return new;
end;
$$;

create trigger trg_pos_catalog_request_before_insert
before insert on public.pos_catalog_requests
for each row execute function app_private.pos_catalog_request_before_insert();

revoke all on function app_private.pos_catalog_request_before_insert() from public,anon,authenticated;
