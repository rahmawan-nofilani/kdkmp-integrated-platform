create or replace function public.get_pos_catalog(
  p_terminal_id uuid,
  p_query text default null,
  p_limit integer default 30
)
returns table(
  inventory_item_id uuid,
  sku text,
  barcode text,
  item_name text,
  uom_id uuid,
  uom_code text,
  uom_name text,
  factor_to_base numeric,
  unit_price numeric,
  currency text,
  available_quantity numeric,
  in_stock boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_query text:=lower(coalesce(nullif(trim(p_query),''),''));
  v_limit integer:=least(greatest(coalesce(p_limit,30),1),50);
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
  where id=p_terminal_id and status='ACTIVE';

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

  return query
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
  )
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
  limit v_limit;
end;
$$;

revoke all on function public.get_pos_catalog(uuid,text,integer) from public,anon;
grant execute on function public.get_pos_catalog(uuid,text,integer) to authenticated;
