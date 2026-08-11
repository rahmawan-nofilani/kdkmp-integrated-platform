-- DEVELOPMENT ONLY.
-- Synthetic POS catalog data for UI/integration testing. Not production prices, costs, or stock.

do $$
declare
  v_terminal public.pos_terminals%rowtype;
  v_price_list_id uuid;
  v_seed_profile uuid;
  v_pack uuid;
  v_btl uuid;
  v_movement_id uuid;
  v_bin_id uuid;
begin
  select * into v_terminal from public.pos_terminals where code='DEMO-POS-01' limit 1;
  if v_terminal.id is null then
    raise exception 'DEMO_POS_TERMINAL_NOT_FOUND';
  end if;

  select p.id into v_seed_profile
  from public.profiles p
  join public.user_roles ur on ur.profile_id=p.id and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())
  join public.roles r on r.id=ur.role_id and r.code='MANAGER'
  where p.organization_id=v_terminal.organization_id and p.status='ACTIVE'
  order by p.created_at
  limit 1;

  insert into public.inventory_uoms(organization_id,organization_node_id,code,name,dimension,decimal_places,status)
  values
    (v_terminal.organization_id,v_terminal.organization_node_id,'PACK','Kemasan','COUNT',0,'ACTIVE'),
    (v_terminal.organization_id,v_terminal.organization_node_id,'BTL','Botol','COUNT',0,'ACTIVE')
  on conflict (organization_node_id,code) do update
  set name=excluded.name,dimension=excluded.dimension,decimal_places=excluded.decimal_places,status='ACTIVE';

  select id into v_pack from public.inventory_uoms where organization_node_id=v_terminal.organization_node_id and code='PACK';
  select id into v_btl from public.inventory_uoms where organization_node_id=v_terminal.organization_node_id and code='BTL';

  insert into public.inventory_item_uom_conversions(organization_id,organization_node_id,inventory_item_id,uom_id,factor_to_base,status)
  select i.organization_id,i.organization_node_id,i.id,
         case when i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG') then v_pack else v_btl end,
         case i.sku when 'DEMO-BERAS-5KG' then 5 else 1 end,
         'ACTIVE'
  from public.inventory_items i
  where i.organization_id=v_terminal.organization_id
    and i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG','DEMO-MINYAK-1L')
  on conflict (inventory_item_id,uom_id) do update
  set factor_to_base=excluded.factor_to_base,status='ACTIVE';

  insert into public.sales_price_lists(
    organization_id,organization_node_id,organization_unit_id,code,name,channel,currency,priority,status,valid_from,created_by,approved_by,approved_at
  ) values(
    v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,
    'DEMO-POS-RETAIL','DEMO DEVELOPMENT — Harga POS Gerai','POS','IDR',100,'ACTIVE','2026-08-11T00:00:00+07',v_seed_profile,v_seed_profile,now()
  )
  on conflict (organization_node_id,organization_unit_id,code) do update
  set name=excluded.name,channel='POS',currency='IDR',priority=100,status='ACTIVE',valid_from=excluded.valid_from,
      approved_by=excluded.approved_by,approved_at=excluded.approved_at,updated_at=now()
  returning id into v_price_list_id;

  insert into public.sales_price_entries(
    sales_price_list_id,organization_id,organization_node_id,organization_unit_id,inventory_item_id,uom_id,min_quantity,unit_price,status,effective_from,created_by
  )
  select v_price_list_id,v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,i.id,
         case when i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG') then v_pack else v_btl end,
         1,
         case i.sku when 'DEMO-BERAS-5KG' then 75000 when 'DEMO-GULA-1KG' then 17000 when 'DEMO-MINYAK-1L' then 18000 end,
         'ACTIVE','2026-08-11T00:00:00+07',v_seed_profile
  from public.inventory_items i
  where i.organization_id=v_terminal.organization_id
    and i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG','DEMO-MINYAK-1L')
  on conflict (sales_price_list_id,inventory_item_id,uom_id,min_quantity,effective_from) do update
  set unit_price=excluded.unit_price,status='ACTIVE',updated_at=now();

  if not exists(select 1 from public.inventory_movements where idempotency_key='DEMO-POS-OPENING-STOCK-V1') then
    select id into v_bin_id
    from public.warehouse_nodes
    where warehouse_id=v_terminal.default_warehouse_id and code='RETAIL-BIN-01' and status='ACTIVE'
    limit 1;

    insert into public.inventory_movements(
      organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
      source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at,created_by
    ) values(
      v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.default_warehouse_id,
      'DEMO-POS-OPENING-001','RECEIPT','POSTED','DEMO_SEED','DEVELOPMENT_OPENING_STOCK','DEMO POS opening stock',
      'DEMO-POS-OPENING-STOCK-V1',now(),now(),v_seed_profile
    ) returning id into v_movement_id;

    insert into public.inventory_movement_lines(
      organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,
      to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes
    )
    select v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_movement_id,
           row_number() over(order by i.sku),i.id,i.base_uom_id,v_bin_id,'AVAILABLE',
           case i.sku when 'DEMO-BERAS-5KG' then 100 when 'DEMO-GULA-1KG' then 50 when 'DEMO-MINYAK-1L' then 60 end,
           case i.sku when 'DEMO-BERAS-5KG' then 100 when 'DEMO-GULA-1KG' then 50 when 'DEMO-MINYAK-1L' then 60 end,
           case i.sku when 'DEMO-BERAS-5KG' then 13000 when 'DEMO-GULA-1KG' then 15000 when 'DEMO-MINYAK-1L' then 16000 end,
           'DEMO DEVELOPMENT synthetic opening stock/cost; not production data'
    from public.inventory_items i
    where i.organization_id=v_terminal.organization_id
      and i.sku in ('DEMO-BERAS-5KG','DEMO-GULA-1KG','DEMO-MINYAK-1L');
  end if;
end $$;
