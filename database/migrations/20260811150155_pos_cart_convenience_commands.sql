create unique index if not exists ux_sales_transactions_pos_active_shift_cashier
on public.sales_transactions(pos_shift_id,created_by)
where sale_type='POS'
  and pos_shift_id is not null
  and created_by is not null
  and status in ('DRAFT','PAYMENT_PENDING','PAID','FULFILLMENT_PENDING','VOID_PENDING');

create or replace function public.ensure_pos_sale(
  p_terminal_id uuid,
  p_pos_shift_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
set search_path to ''
as $$
declare
  v_profile_id uuid;
  v_sale_id uuid;
  v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;

  select p.id into v_profile_id
  from public.profiles p
  where p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
  limit 1;
  if v_profile_id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_pos_shift_id::text,0));

  select st.id into v_sale_id
  from public.sales_transactions st
  where st.pos_shift_id=p_pos_shift_id
    and st.created_by=v_profile_id
    and st.sale_type='POS'
    and st.status='DRAFT'
  order by st.created_at desc
  limit 1;

  if v_sale_id is not null then
    return v_sale_id;
  end if;

  if exists(
    select 1
    from public.sales_transactions st
    where st.pos_shift_id=p_pos_shift_id
      and st.created_by=v_profile_id
      and st.sale_type='POS'
      and st.status in ('PAYMENT_PENDING','PAID','FULFILLMENT_PENDING','VOID_PENDING')
  ) then
    raise exception 'POS_SALE_IN_PROGRESS' using errcode='55000';
  end if;

  return public.create_pos_sale(p_terminal_id,p_pos_shift_id,v_key,null,null,null,null);
end;
$$;

create or replace function public.add_pos_item_to_current_sale(
  p_terminal_id uuid,
  p_pos_shift_id uuid,
  p_inventory_item_id uuid,
  p_uom_id uuid,
  p_quantity numeric,
  p_idempotency_key text
)
returns table(sales_transaction_id uuid,sales_transaction_line_id uuid)
language plpgsql
set search_path to ''
as $$
declare
  v_sale_id uuid;
  v_line_id uuid;
  v_existing_qty numeric;
  v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;
  if p_quantity is null or p_quantity<=0 then
    raise exception 'POS_LINE_ITEM_UOM_QUANTITY_REQUIRED' using errcode='22023';
  end if;

  v_sale_id:=public.ensure_pos_sale(p_terminal_id,p_pos_shift_id,'ENSURE:'||v_key);

  select stl.id,stl.quantity into v_line_id,v_existing_qty
  from public.sales_transaction_lines stl
  where stl.sales_transaction_id=v_sale_id
    and stl.inventory_item_id=p_inventory_item_id
    and stl.uom_id=p_uom_id
  order by stl.line_no
  limit 1;

  if v_line_id is null then
    v_line_id:=public.add_pos_sale_line(v_sale_id,p_inventory_item_id,p_uom_id,p_quantity,'ADD:'||v_key);
  else
    v_line_id:=public.update_pos_sale_line_quantity(v_sale_id,v_line_id,v_existing_qty+p_quantity,'UPD:'||v_key);
  end if;

  return query select v_sale_id,v_line_id;
end;
$$;

create or replace function public.change_pos_cart_line_quantity(
  p_sales_transaction_id uuid,
  p_sales_transaction_line_id uuid,
  p_delta numeric,
  p_idempotency_key text
)
returns uuid
language plpgsql
set search_path to ''
as $$
declare
  v_current_qty numeric;
  v_new_qty numeric;
  v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;
  if p_delta is null or p_delta=0 then
    raise exception 'POS_CART_DELTA_INVALID' using errcode='22023';
  end if;

  select stl.quantity into v_current_qty
  from public.sales_transaction_lines stl
  where stl.id=p_sales_transaction_line_id
    and stl.sales_transaction_id=p_sales_transaction_id;

  if v_current_qty is null then
    raise exception 'POS_LINE_NOT_FOUND' using errcode='P0002';
  end if;

  v_new_qty:=v_current_qty+p_delta;
  if v_new_qty<=0 then
    return public.remove_pos_sale_line(p_sales_transaction_id,p_sales_transaction_line_id,'REM:'||v_key);
  end if;

  return public.update_pos_sale_line_quantity(p_sales_transaction_id,p_sales_transaction_line_id,v_new_qty,'QTY:'||v_key);
end;
$$;

revoke all on function public.ensure_pos_sale(uuid,uuid,text) from public,anon;
revoke all on function public.add_pos_item_to_current_sale(uuid,uuid,uuid,uuid,numeric,text) from public,anon;
revoke all on function public.change_pos_cart_line_quantity(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.ensure_pos_sale(uuid,uuid,text) to authenticated;
grant execute on function public.add_pos_item_to_current_sale(uuid,uuid,uuid,uuid,numeric,text) to authenticated;
grant execute on function public.change_pos_cart_line_quantity(uuid,uuid,numeric,text) to authenticated;
