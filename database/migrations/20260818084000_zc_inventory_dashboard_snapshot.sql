-- ZC inventory dashboard snapshot
--
-- The inventory dashboard previously issued ten parallel PostgREST requests.
-- This migration preserves the same INVENTORY_VIEW + data-scope contract while
-- collapsing the dashboard read into one RPC. The exposed public function stays
-- SECURITY INVOKER; privileged table reads live behind an app_private
-- SECURITY DEFINER helper that re-applies permission and data-scope checks
-- explicitly for every dataset.

create or replace function app_private.get_inventory_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
begin
  if v_auth_user_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  select p.id, p.organization_id
  into v_profile_id, v_organization_id
  from public.profiles p
  where p.auth_user_id = v_auth_user_id
    and p.status = 'ACTIVE'
  limit 1;

  if v_profile_id is null or v_organization_id is null then
    raise exception using errcode = '42501', message = 'INVENTORY_CONTEXT_UNAVAILABLE';
  end if;

  if not public.has_permission('INVENTORY_VIEW') then
    raise exception using errcode = '42501', message = 'INVENTORY_VIEW_DENIED';
  end if;

  return jsonb_build_object(
    'warehouses', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select w.id, w.code, w.name, w.warehouse_type, w.status, w.organization_unit_id
        from public.warehouses w
        where w.organization_id = v_organization_id
          and public.has_data_scope(w.organization_id, w.organization_node_id, w.organization_unit_id, null, null)
        order by w.code
      ) x
    ), '[]'::jsonb),
    'nodes', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select n.id, n.warehouse_id, n.parent_id, n.node_type, n.code, n.name, n.status
        from public.warehouse_nodes n
        where n.organization_id = v_organization_id
          and public.has_data_scope(n.organization_id, n.organization_node_id, n.organization_unit_id, null, null)
        order by n.node_type, n.code
      ) x
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select i.id, i.sku, i.name, i.category_code, i.base_uom_id, i.tracking_type,
               i.expiry_control, i.costing_method, i.picking_policy, i.status
        from public.inventory_items i
        where i.organization_id = v_organization_id
          and public.has_data_scope(i.organization_id, i.organization_node_id, null, null, null)
        order by i.sku
      ) x
    ), '[]'::jsonb),
    'uoms', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select u.id, u.code, u.name, u.dimension, u.decimal_places, u.status
        from public.inventory_uoms u
        where u.organization_id = v_organization_id
          and public.has_data_scope(u.organization_id, u.organization_node_id, null, null, null)
        order by u.code
      ) x
    ), '[]'::jsonb),
    'lots', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select l.id, l.inventory_item_id, l.lot_code, l.expiry_date, l.status
        from public.inventory_lots l
        where l.organization_id = v_organization_id
          and public.has_data_scope(l.organization_id, l.organization_node_id, null, null, null)
        order by l.expiry_date asc nulls last
        limit 50
      ) x
    ), '[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select m.id, m.movement_number, m.movement_type, m.status, m.source_domain,
               m.source_reference, m.occurred_at, m.posted_at
        from public.inventory_movements m
        where m.organization_id = v_organization_id
          and public.has_data_scope(m.organization_id, m.organization_node_id, m.organization_unit_id, null, null)
        order by m.occurred_at desc
        limit 50
      ) x
    ), '[]'::jsonb),
    'positions', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select p.warehouse_id, p.warehouse_node_id, p.inventory_item_id, p.lot_id,
               p.stock_status, p.quantity, p.reserved_quantity, p.available_to_allocate
        from public.inventory_available_positions p
        where p.organization_id = v_organization_id
          and public.has_data_scope(p.organization_id, p.organization_node_id, p.organization_unit_id, null, null)
        order by p.warehouse_node_id, p.inventory_item_id, p.lot_id nulls first, p.stock_status
        limit 100
      ) x
    ), '[]'::jsonb),
    'reservations', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select r.id, r.warehouse_node_id, r.inventory_item_id, r.lot_id, r.quantity,
               r.status, r.expires_at, r.source_domain
        from public.stock_reservations r
        where r.organization_id = v_organization_id
          and public.has_data_scope(r.organization_id, r.organization_node_id, r.organization_unit_id, null, null)
        order by r.created_at desc, r.id
        limit 50
      ) x
    ), '[]'::jsonb),
    'counts', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select c.id, c.count_number, c.scope_description, c.snapshot_at, c.status,
               c.created_at, c.completed_at
        from public.stock_count_sessions c
        where c.organization_id = v_organization_id
          and public.has_data_scope(c.organization_id, c.organization_node_id, c.organization_unit_id, null, null)
        order by c.created_at desc, c.id
        limit 30
      ) x
    ), '[]'::jsonb),
    'mappings', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select m.id, m.movement_type, m.accounting_event_code, m.mapping_status, m.notes
        from public.inventory_accounting_event_mappings m
        where m.organization_id = v_organization_id
          and public.has_data_scope(m.organization_id, m.organization_node_id, null, null, null)
        order by m.movement_type, m.id
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_inventory_dashboard_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.get_inventory_dashboard_snapshot();
$$;

revoke all on function app_private.get_inventory_dashboard_snapshot() from public;
revoke all on function app_private.get_inventory_dashboard_snapshot() from anon;
grant execute on function app_private.get_inventory_dashboard_snapshot() to authenticated;
grant execute on function app_private.get_inventory_dashboard_snapshot() to service_role;

revoke all on function public.get_inventory_dashboard_snapshot() from public;
revoke all on function public.get_inventory_dashboard_snapshot() from anon;
grant execute on function public.get_inventory_dashboard_snapshot() to authenticated;
grant execute on function public.get_inventory_dashboard_snapshot() to service_role;

comment on function app_private.get_inventory_dashboard_snapshot() is
  'Private scoped Inventory dashboard snapshot. SECURITY DEFINER is bounded by auth.uid(), INVENTORY_VIEW and explicit has_data_scope checks.';
comment on function public.get_inventory_dashboard_snapshot() is
  'Authenticated SECURITY INVOKER wrapper for the scoped Inventory dashboard snapshot.';

do $$
declare
  v_private pg_proc%rowtype;
  v_public pg_proc%rowtype;
begin
  select * into v_private
  from pg_proc
  where oid = 'app_private.get_inventory_dashboard_snapshot()'::regprocedure;

  select * into v_public
  from pg_proc
  where oid = 'public.get_inventory_dashboard_snapshot()'::regprocedure;

  if not v_private.prosecdef then
    raise exception 'inventory_snapshot_private_must_be_security_definer';
  end if;

  if v_public.prosecdef then
    raise exception 'inventory_snapshot_public_must_be_security_invoker';
  end if;

  if not exists (
    select 1 from unnest(coalesce(v_private.proconfig, array[]::text[])) setting
    where setting in ('search_path=', 'search_path=""')
  ) then
    raise exception 'inventory_snapshot_private_search_path_must_be_empty';
  end if;

  if not exists (
    select 1 from unnest(coalesce(v_public.proconfig, array[]::text[])) setting
    where setting in ('search_path=', 'search_path=""')
  ) then
    raise exception 'inventory_snapshot_public_search_path_must_be_empty';
  end if;

  if has_function_privilege('anon', 'public.get_inventory_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'anon_must_not_execute_inventory_dashboard_snapshot';
  end if;

  if exists (
    select 1
    from aclexplode(coalesce(v_public.proacl, acldefault('f', v_public.proowner))) acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'public_must_not_execute_inventory_dashboard_snapshot';
  end if;

  if not has_function_privilege('authenticated', 'public.get_inventory_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'authenticated_inventory_dashboard_snapshot_execute_missing';
  end if;

  if not has_function_privilege('authenticated', 'app_private.get_inventory_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'authenticated_inventory_dashboard_snapshot_private_execute_missing';
  end if;
end $$;
