\set ON_ERROR_STOP on

select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
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

select * from app_private.resolve_pos_price(
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'item_id'::uuid,:'uom_id'::uuid,1,now()
);
