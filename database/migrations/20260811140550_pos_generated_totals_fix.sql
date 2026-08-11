create or replace function app_private.pos_sale_command_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_shift public.pos_shifts%rowtype;
  v_warehouse public.warehouses%rowtype;
  v_existing public.pos_sale_commands%rowtype;
  v_sale_id uuid;
  v_sale_number text;
  v_correlation uuid:=gen_random_uuid();
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('SALES_CREATE') then raise exception 'SALES_CREATE_DENIED' using errcode='42501'; end if;
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;

  select * into v_existing from public.pos_sale_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id and v_existing.terminal_id=new.terminal_id and v_existing.pos_shift_id=new.pos_shift_id and v_existing.customer_member_id is not distinct from new.customer_member_id then return null; end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_terminal from public.pos_terminals where id=new.terminal_id and status='ACTIVE';
  if v_terminal.id is null or v_terminal.organization_id<>v_profile.organization_id then raise exception 'POS_TERMINAL_NOT_AVAILABLE' using errcode='22023'; end if;
  select * into v_shift from public.pos_shifts where id=new.pos_shift_id and terminal_id=v_terminal.id and cashier_profile_id=v_profile.id and status='OPEN';
  if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
  if not public.has_data_scope(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;
  if v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_WAREHOUSE_REQUIRED' using errcode='22023'; end if;
  select * into v_warehouse from public.warehouses where id=v_terminal.default_warehouse_id and status='ACTIVE';
  if v_warehouse.id is null then raise exception 'POS_TERMINAL_WAREHOUSE_NOT_ACTIVE' using errcode='22023'; end if;
  if new.customer_member_id is not null and not exists(select 1 from public.members m where m.id=new.customer_member_id and m.organization_id=v_profile.organization_id and m.status='ACTIVE') then raise exception 'POS_CUSTOMER_MEMBER_NOT_ACTIVE' using errcode='22023'; end if;

  v_sale_number:='POS-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.sales_transactions(organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,sale_number,sale_type,customer_member_id,currency,subtotal,discount_amount,tax_amount,status,local_transaction_id,device_id,client_sequence,idempotency_key,sync_status,correlation_id,created_by)
  values(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.id,v_shift.id,v_sale_number,'POS',new.customer_member_id,'IDR',0,0,0,'DRAFT',nullif(trim(new.local_transaction_id),''),nullif(trim(new.device_id),''),new.client_sequence,new.idempotency_key,'SYNCED',v_correlation,v_profile.id)
  returning id into v_sale_id;

  new.organization_id:=v_terminal.organization_id;
  new.organization_node_id:=v_terminal.organization_node_id;
  new.organization_unit_id:=v_terminal.organization_unit_id;
  new.result_sale_id:=v_sale_id;
  new.requested_by:=v_profile.id;
  new.local_transaction_id:=nullif(trim(new.local_transaction_id),'');
  new.device_id:=nullif(trim(new.device_id),'');
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_terminal.organization_id,v_profile.id,'POS_SALE_DRAFT_CREATED','SALES_TRANSACTION',v_sale_id,jsonb_build_object('sale_number',v_sale_number,'terminal_id',v_terminal.id,'shift_id',v_shift.id,'status','DRAFT','idempotency_key',new.idempotency_key),'POS sale draft created through controlled command');
  return new;
end;
$$;

create or replace function app_private.pos_sale_line_command_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_sale public.sales_transactions%rowtype;
  v_shift public.pos_shifts%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_item public.inventory_items%rowtype;
  v_line public.sales_transaction_lines%rowtype;
  v_existing public.pos_sale_line_commands%rowtype;
  v_factor numeric;
  v_available numeric;
  v_price record;
  v_line_id uuid;
  v_line_no integer;
  v_subtotal numeric;
  v_discount numeric;
  v_tax numeric;
  v_uom_code text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('SALES_CREATE') then raise exception 'SALES_CREATE_DENIED' using errcode='42501'; end if;
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;

  select * into v_existing from public.pos_sale_line_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id and v_existing.action=new.action and v_existing.sales_transaction_id=new.sales_transaction_id and v_existing.sales_transaction_line_id is not distinct from new.sales_transaction_line_id and v_existing.inventory_item_id is not distinct from new.inventory_item_id and v_existing.uom_id is not distinct from new.uom_id and v_existing.quantity is not distinct from new.quantity then return null; end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_sale from public.sales_transactions where id=new.sales_transaction_id for update;
  if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
  if v_sale.created_by<>v_profile.id or v_sale.status<>'DRAFT' then raise exception 'POS_OWN_DRAFT_SALE_REQUIRED' using errcode='42501'; end if;
  select * into v_shift from public.pos_shifts where id=v_sale.pos_shift_id and cashier_profile_id=v_profile.id and status='OPEN';
  if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
  select * into v_terminal from public.pos_terminals where id=v_sale.terminal_id and status='ACTIVE';
  if v_terminal.id is null or v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_NOT_READY' using errcode='22023'; end if;
  if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  if new.action='ADD' then
    if new.inventory_item_id is null or new.uom_id is null or new.quantity is null or new.quantity<=0 then raise exception 'POS_LINE_ITEM_UOM_QUANTITY_REQUIRED' using errcode='22023'; end if;
    select * into v_item from public.inventory_items where id=new.inventory_item_id and organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and status='ACTIVE';
    if v_item.id is null then raise exception 'POS_ITEM_NOT_AVAILABLE' using errcode='22023'; end if;
    if new.uom_id=v_item.base_uom_id then v_factor:=1;
    else select factor_to_base into v_factor from public.inventory_item_uom_conversions where inventory_item_id=v_item.id and uom_id=new.uom_id and status='ACTIVE' limit 1;
    end if;
    if v_factor is null or v_factor<=0 then raise exception 'POS_ITEM_UOM_NOT_CONFIGURED' using errcode='22023'; end if;
    select code into v_uom_code from public.inventory_uoms where id=new.uom_id;
    select * into v_price from app_private.resolve_pos_price(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_item.id,new.uom_id,new.quantity,now());
    if v_price.price_entry_id is null then raise exception 'POS_PRICE_NOT_CONFIGURED' using errcode='22023'; end if;
    select coalesce(sum(available_to_allocate),0) into v_available from public.inventory_available_positions where warehouse_id=v_terminal.default_warehouse_id and inventory_item_id=v_item.id and stock_status='AVAILABLE';
    if v_available < (new.quantity*v_factor) then raise exception 'POS_INSUFFICIENT_STOCK' using errcode='22023'; end if;
    select coalesce(max(line_no),0)+1 into v_line_no from public.sales_transaction_lines where sales_transaction_id=v_sale.id;
    insert into public.sales_transaction_lines(organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,description,uom_id,quantity,unit_price,discount_amount,tax_amount)
    values(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.id,v_line_no,v_item.id,jsonb_build_object('sku',v_item.sku,'barcode',v_item.barcode,'name',v_item.name,'uom_id',new.uom_id,'uom_code',v_uom_code,'factor_to_base',v_factor,'price_entry_id',v_price.price_entry_id,'price_list_id',v_price.price_list_id,'unit_price',v_price.unit_price,'currency',v_price.currency,'priced_at',now()),v_item.name,new.uom_id,new.quantity,v_price.unit_price,0,0)
    returning id into v_line_id;
  elsif new.action='UPDATE_QTY' then
    if new.sales_transaction_line_id is null or new.quantity is null or new.quantity<=0 then raise exception 'POS_LINE_AND_QUANTITY_REQUIRED' using errcode='22023'; end if;
    select * into v_line from public.sales_transaction_lines where id=new.sales_transaction_line_id and sales_transaction_id=v_sale.id;
    if v_line.id is null or v_line.inventory_item_id is null or v_line.uom_id is null then raise exception 'POS_LINE_NOT_FOUND' using errcode='P0002'; end if;
    select * into v_item from public.inventory_items where id=v_line.inventory_item_id and status='ACTIVE';
    if v_line.uom_id=v_item.base_uom_id then v_factor:=1;
    else select factor_to_base into v_factor from public.inventory_item_uom_conversions where inventory_item_id=v_item.id and uom_id=v_line.uom_id and status='ACTIVE' limit 1;
    end if;
    if v_factor is null or v_factor<=0 then raise exception 'POS_ITEM_UOM_NOT_CONFIGURED' using errcode='22023'; end if;
    select code into v_uom_code from public.inventory_uoms where id=v_line.uom_id;
    select * into v_price from app_private.resolve_pos_price(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_item.id,v_line.uom_id,new.quantity,now());
    if v_price.price_entry_id is null then raise exception 'POS_PRICE_NOT_CONFIGURED' using errcode='22023'; end if;
    select coalesce(sum(available_to_allocate),0) into v_available from public.inventory_available_positions where warehouse_id=v_terminal.default_warehouse_id and inventory_item_id=v_item.id and stock_status='AVAILABLE';
    if v_available < (new.quantity*v_factor) then raise exception 'POS_INSUFFICIENT_STOCK' using errcode='22023'; end if;
    update public.sales_transaction_lines
    set quantity=new.quantity,unit_price=v_price.unit_price,item_snapshot=jsonb_build_object('sku',v_item.sku,'barcode',v_item.barcode,'name',v_item.name,'uom_id',v_line.uom_id,'uom_code',v_uom_code,'factor_to_base',v_factor,'price_entry_id',v_price.price_entry_id,'price_list_id',v_price.price_list_id,'unit_price',v_price.unit_price,'currency',v_price.currency,'priced_at',now())
    where id=v_line.id;
    v_line_id:=v_line.id;
    new.inventory_item_id:=v_line.inventory_item_id;
    new.uom_id:=v_line.uom_id;
  elsif new.action='REMOVE' then
    if new.sales_transaction_line_id is null then raise exception 'POS_LINE_REQUIRED' using errcode='22023'; end if;
    select * into v_line from public.sales_transaction_lines where id=new.sales_transaction_line_id and sales_transaction_id=v_sale.id;
    if v_line.id is null then raise exception 'POS_LINE_NOT_FOUND' using errcode='P0002'; end if;
    v_line_id:=v_line.id;
    new.inventory_item_id:=v_line.inventory_item_id;
    new.uom_id:=v_line.uom_id;
    new.quantity:=v_line.quantity;
    delete from public.sales_transaction_lines where id=v_line.id;
  end if;

  select coalesce(sum(line_total),0),coalesce(sum(discount_amount),0),coalesce(sum(tax_amount),0)
  into v_subtotal,v_discount,v_tax
  from public.sales_transaction_lines where sales_transaction_id=v_sale.id;
  update public.sales_transactions set subtotal=v_subtotal,discount_amount=v_discount,tax_amount=v_tax,updated_at=now() where id=v_sale.id;
  new.result_line_id:=v_line_id;

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_sale.organization_id,v_profile.id,'POS_CART_LINE_'||new.action,'SALES_TRANSACTION',v_sale.id,jsonb_build_object('line_id',v_line_id,'item_id',new.inventory_item_id,'uom_id',new.uom_id,'quantity',new.quantity,'subtotal',v_subtotal,'total',v_subtotal-v_discount+v_tax),'POS cart changed through controlled command');
  return new;
end;
$$;

revoke all on function app_private.pos_sale_command_before_insert() from public,anon,authenticated;
revoke all on function app_private.pos_sale_line_command_before_insert() from public,anon,authenticated;
