-- DEVELOPMENT ONLY.
-- Repairs legacy synthetic opening stock so LOT-tracked demo items have traceable lots.
-- Uses posted inventory movements; never overwrites stock balances or historical movement lines.

do $$
declare
  v_terminal public.pos_terminals%rowtype;
  v_profile uuid;
  v_movement uuid;
  v_bin uuid;
  v_line_no integer:=0;
  v_item record;
  v_lot uuid;
  v_qty numeric;
  v_cost numeric;
begin
  select * into v_terminal from public.pos_terminals where code='DEMO-POS-01' limit 1;
  if v_terminal.id is null then raise exception 'DEMO_POS_TERMINAL_NOT_FOUND'; end if;
  if exists(select 1 from public.inventory_movements where idempotency_key='DEMO-POS-LOT-RECLASS-V1') then return; end if;

  select p.id into v_profile from public.profiles p
  join public.user_roles ur on ur.profile_id=p.id and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())
  join public.roles r on r.id=ur.role_id and r.code='MANAGER'
  where p.organization_id=v_terminal.organization_id and p.status='ACTIVE' order by p.created_at limit 1;
  if v_profile is null then raise exception 'DEMO_MANAGER_NOT_FOUND'; end if;

  select id into v_bin from public.warehouse_nodes
  where warehouse_id=v_terminal.default_warehouse_id and code='RETAIL-BIN-01' and status='ACTIVE' limit 1;
  if v_bin is null then raise exception 'DEMO_RETAIL_BIN_NOT_FOUND'; end if;

  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
    source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at,created_by
  ) values(
    v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.default_warehouse_id,
    'DEMO-POS-LOT-RECLASS-001','OTHER','POSTED','DEMO_SEED','DEVELOPMENT_LOT_RECLASS',
    'Assign synthetic lot identity to pre-existing DEMO stock without changing total quantity/value',
    'DEMO-POS-LOT-RECLASS-V1',now(),now(),v_profile
  ) returning id into v_movement;

  for v_item in
    select i.* from public.inventory_items i
    where i.organization_id=v_terminal.organization_id
      and i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG','DEMO-MINYAK-1L')
    order by i.sku
  loop
    select coalesce(sum(quantity),0) into v_qty
    from public.inventory_stock_balances
    where warehouse_id=v_terminal.default_warehouse_id
      and warehouse_node_id=v_bin
      and inventory_item_id=v_item.id
      and lot_id is null
      and stock_status='AVAILABLE';
    if v_qty<=0 then continue; end if;

    select case v_item.sku
      when 'DEMO-BERAS-5KG' then 13000
      when 'DEMO-GULA-1KG' then 15000
      when 'DEMO-MINYAK-1L' then 16000
    end into v_cost;

    insert into public.inventory_lots(
      organization_id,organization_node_id,inventory_item_id,lot_code,manufacture_date,expiry_date,supplier_lot_reference,status
    ) values(
      v_terminal.organization_id,v_terminal.organization_node_id,v_item.id,
      'DEMO-LOT-202608-'||replace(v_item.sku,'DEMO-',''),
      '2026-08-01',
      case when v_item.sku='DEMO-MINYAK-1L' then '2027-08-01'::date else null end,
      'DEVELOPMENT SYNTHETIC LOT','ACTIVE'
    )
    on conflict (organization_node_id,inventory_item_id,lot_code) do update
    set manufacture_date=excluded.manufacture_date,expiry_date=excluded.expiry_date,status='ACTIVE'
    returning id into v_lot;

    v_line_no:=v_line_no+1;
    insert into public.inventory_movement_lines(
      organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,lot_id,
      from_warehouse_node_id,from_stock_status,quantity,base_quantity,unit_cost,notes
    ) values(
      v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_movement,v_line_no,
      v_item.id,v_item.base_uom_id,null,v_bin,'AVAILABLE',v_qty,v_qty,v_cost,
      'DEVELOPMENT reclassification: remove legacy no-lot position'
    );

    v_line_no:=v_line_no+1;
    insert into public.inventory_movement_lines(
      organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,lot_id,
      to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes
    ) values(
      v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_movement,v_line_no,
      v_item.id,v_item.base_uom_id,v_lot,v_bin,'AVAILABLE',v_qty,v_qty,v_cost,
      'DEVELOPMENT reclassification: restore same quantity/value under synthetic lot'
    );
  end loop;
end $$;
