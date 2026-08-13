alter table public.pos_sale_commands drop constraint if exists pos_sale_commands_action_check;
alter table public.pos_sale_commands add constraint pos_sale_commands_action_check check (action in ('CREATE_DRAFT','CANCEL_DRAFT'));
alter table public.pos_sale_commands add column target_sale_id uuid references public.sales_transactions(id) on delete restrict;
create index idx_pos_sale_commands_target_sale on public.pos_sale_commands(target_sale_id);

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
  v_sale public.sales_transactions%rowtype;
  v_sale_id uuid;
  v_sale_number text;
  v_correlation uuid:=gen_random_uuid();
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('SALES_CREATE') then raise exception 'SALES_CREATE_DENIED' using errcode='42501'; end if;

  new.action:=upper(trim(coalesce(new.action,'CREATE_DRAFT')));
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;

  select * into v_existing from public.pos_sale_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.action=new.action
       and v_existing.terminal_id is not distinct from new.terminal_id
       and v_existing.pos_shift_id is not distinct from new.pos_shift_id
       and v_existing.customer_member_id is not distinct from new.customer_member_id
       and v_existing.target_sale_id is not distinct from new.target_sale_id then
      return null;
    end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  if new.action='CANCEL_DRAFT' then
    if new.target_sale_id is null then raise exception 'POS_SALE_REQUIRED' using errcode='22023'; end if;
    select * into v_sale from public.sales_transactions where id=new.target_sale_id for update;
    if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
    if v_sale.created_by<>v_profile.id or v_sale.status<>'DRAFT' then raise exception 'POS_OWN_DRAFT_SALE_REQUIRED' using errcode='42501'; end if;
    select * into v_shift from public.pos_shifts where id=v_sale.pos_shift_id and cashier_profile_id=v_profile.id and status='OPEN';
    if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
    if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;

    update public.sales_transactions set status='CANCELLED',updated_at=now() where id=v_sale.id;

    new.organization_id:=v_sale.organization_id;
    new.organization_node_id:=v_sale.organization_node_id;
    new.organization_unit_id:=v_sale.organization_unit_id;
    new.terminal_id:=v_sale.terminal_id;
    new.pos_shift_id:=v_sale.pos_shift_id;
    new.customer_member_id:=v_sale.customer_member_id;
    new.result_sale_id:=v_sale.id;
    new.requested_by:=v_profile.id;
    new.created_at:=now();

    insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
    values(v_sale.organization_id,v_profile.id,'POS_SALE_DRAFT_CANCELLED','SALES_TRANSACTION',v_sale.id,
      jsonb_build_object('status','DRAFT'),jsonb_build_object('status','CANCELLED'),'POS draft cancelled through controlled command');
    return new;
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
  new.target_sale_id:=null;
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

create or replace function public.cancel_pos_sale(
  p_sales_transaction_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
set search_path to ''
as $$
declare
  v_result uuid;
  v_key text:=nullif(trim(p_idempotency_key),'');
  v_sale public.sales_transactions%rowtype;
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_sale_id into v_result from public.pos_sale_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;

  select * into v_sale from public.sales_transactions where id=p_sales_transaction_id;
  if v_sale.id is null then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;

  insert into public.pos_sale_commands(action,terminal_id,pos_shift_id,target_sale_id,idempotency_key)
  values('CANCEL_DRAFT',v_sale.terminal_id,v_sale.pos_shift_id,v_sale.id,v_key)
  returning result_sale_id into v_result;

  if v_result is null then select result_sale_id into v_result from public.pos_sale_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
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
  v_result_line_id uuid;
  v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  if p_delta is null or p_delta=0 then raise exception 'POS_CART_DELTA_INVALID' using errcode='22023'; end if;

  select plc.result_line_id into v_result_line_id
  from public.pos_sale_line_commands plc
  where plc.idempotency_key in ('QTY:'||v_key,'REM:'||v_key)
  order by plc.created_at desc
  limit 1;
  if v_result_line_id is not null then return v_result_line_id; end if;

  select stl.quantity into v_current_qty
  from public.sales_transaction_lines stl
  where stl.id=p_sales_transaction_line_id and stl.sales_transaction_id=p_sales_transaction_id;
  if v_current_qty is null then raise exception 'POS_LINE_NOT_FOUND' using errcode='P0002'; end if;

  v_new_qty:=v_current_qty+p_delta;
  if v_new_qty<=0 then
    v_result_line_id:=public.remove_pos_sale_line(p_sales_transaction_id,p_sales_transaction_line_id,'REM:'||v_key);
    if not exists(select 1 from public.sales_transaction_lines stl where stl.sales_transaction_id=p_sales_transaction_id) then
      perform public.cancel_pos_sale(p_sales_transaction_id,'CANCEL:'||v_key);
    end if;
    return v_result_line_id;
  end if;

  return public.update_pos_sale_line_quantity(p_sales_transaction_id,p_sales_transaction_line_id,v_new_qty,'QTY:'||v_key);
end;
$$;

revoke all on function app_private.pos_sale_command_before_insert() from public,anon,authenticated;
revoke all on function public.cancel_pos_sale(uuid,text) from public,anon;
revoke all on function public.change_pos_cart_line_quantity(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.cancel_pos_sale(uuid,text) to authenticated;
grant execute on function public.change_pos_cart_line_quantity(uuid,uuid,numeric,text) to authenticated;