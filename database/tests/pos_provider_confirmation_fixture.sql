\set ON_ERROR_STOP on

select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
select id as warehouse_id from public.warehouses where organization_unit_id=:'unit_id'::uuid and code='DEMO-RETAIL-WH' limit 1\gset
select id as warehouse_node_id from public.warehouse_nodes where warehouse_id=:'warehouse_id'::uuid and code='RETAIL-BIN-01' limit 1\gset
select id as item_id,base_uom_id as uom_id from public.inventory_items where sku='DEMO-GULA-1KG' limit 1\gset

insert into public.sales_price_lists(
  id,organization_id,organization_node_id,organization_unit_id,code,name,channel,currency,priority,status,valid_from,approved_at
) values(
  '10900000-0000-4000-8000-000000000090',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  'CI-PROVIDER-PRICE','CI Provider POS Price','POS','IDR',1,'ACTIVE',now()-interval '1 day',now()
);

insert into public.sales_price_entries(
  id,sales_price_list_id,organization_id,organization_node_id,organization_unit_id,inventory_item_id,uom_id,
  min_quantity,unit_price,status,effective_from
) values(
  '10900000-0000-4000-8000-000000000091','10900000-0000-4000-8000-000000000090',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  :'item_id'::uuid,:'uom_id'::uuid,1,125000,'ACTIVE',now()-interval '1 day'
);

insert into public.inventory_lots(
  id,organization_id,organization_node_id,inventory_item_id,lot_code,manufacture_date,expiry_date,status
) values(
  '10900000-0000-4000-8000-000000000092',:'org_id'::uuid,:'node_id'::uuid,:'item_id'::uuid,
  'CI-PROVIDER-LOT',current_date-30,current_date+365,'ACTIVE'
);

insert into public.inventory_movements(
  id,organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
  source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at
) values(
  '10900000-0000-4000-8000-000000000093',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'warehouse_id'::uuid,
  'CI-PROVIDER-LOT-STOCK','ADJUSTMENT_IN','POSTED','INVENTORY','CI_PROVIDER_FIXTURE','CI-PROVIDER-LOT-STOCK','CI-PROVIDER-LOT-STOCK',now(),now()
);
insert into public.inventory_movement_lines(
  organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,lot_id,
  to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes
) values(
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10900000-0000-4000-8000-000000000093',1,:'item_id'::uuid,:'uom_id'::uuid,
  '10900000-0000-4000-8000-000000000092',:'warehouse_node_id'::uuid,'AVAILABLE',10,10,60000,'Disposable lot-tracked provider stock'
);

select * from app_private.resolve_pos_price(
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'item_id'::uuid,:'uom_id'::uuid,1,now()
);
