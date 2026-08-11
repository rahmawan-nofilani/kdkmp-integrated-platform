alter table public.payment_attempts drop constraint if exists payment_attempts_channel_check;
alter table public.payment_attempts add constraint payment_attempts_channel_check
check (channel in ('CASH_TELLER','CASH_POS','BANK_TRANSFER','QRIS','VIRTUAL_ACCOUNT','AUTODEBIT','INTERNAL','OTHER'));

create unique index if not exists ux_pos_shifts_active_terminal
on public.pos_shifts(terminal_id)
where status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION');

create unique index if not exists ux_pos_shifts_active_cashier
on public.pos_shifts(cashier_profile_id)
where status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION');

create table public.pos_shift_commands (
  id uuid primary key default gen_random_uuid(),
  action text not null default 'OPEN' check (action='OPEN'),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  opening_cash numeric(20,2) not null default 0 check (opening_cash >= 0),
  notes text,
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  result_shift_id uuid references public.pos_shifts(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.pos_sale_commands (
  id uuid primary key default gen_random_uuid(),
  action text not null default 'CREATE_DRAFT' check (action='CREATE_DRAFT'),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  customer_member_id uuid references public.members(id) on delete restrict,
  local_transaction_id text,
  device_id text,
  client_sequence bigint,
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  result_sale_id uuid references public.sales_transactions(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.pos_sale_line_commands (
  id uuid primary key default gen_random_uuid(),
  action text not null check (action in ('ADD','UPDATE_QTY','REMOVE')),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  sales_transaction_line_id uuid references public.sales_transaction_lines(id) on delete restrict,
  inventory_item_id uuid references public.inventory_items(id) on delete restrict,
  uom_id uuid references public.inventory_uoms(id) on delete restrict,
  quantity numeric(20,6),
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  result_line_id uuid references public.sales_transaction_lines(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.pos_payment_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  channel text not null check (channel in ('CASH_POS','BANK_TRANSFER','QRIS')),
  provider_code text,
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  result_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  result_payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index idx_pos_shift_commands_requested_by on public.pos_shift_commands(requested_by,created_at desc);
create index idx_pos_sale_commands_requested_by on public.pos_sale_commands(requested_by,created_at desc);
create index idx_pos_sale_commands_shift on public.pos_sale_commands(pos_shift_id);
create index idx_pos_sale_line_commands_requested_by on public.pos_sale_line_commands(requested_by,created_at desc);
create index idx_pos_sale_line_commands_sale on public.pos_sale_line_commands(sales_transaction_id);
create index idx_pos_payment_commands_requested_by on public.pos_payment_commands(requested_by,created_at desc);
create index idx_pos_payment_commands_sale on public.pos_payment_commands(sales_transaction_id);

alter table public.pos_shift_commands enable row level security;
alter table public.pos_sale_commands enable row level security;
alter table public.pos_sale_line_commands enable row level security;
alter table public.pos_payment_commands enable row level security;

revoke all on public.pos_shift_commands from public,anon,authenticated;
revoke all on public.pos_sale_commands from public,anon,authenticated;
revoke all on public.pos_sale_line_commands from public,anon,authenticated;
revoke all on public.pos_payment_commands from public,anon,authenticated;
grant select,insert on public.pos_shift_commands to authenticated;
grant select,insert on public.pos_sale_commands to authenticated;
grant select,insert on public.pos_sale_line_commands to authenticated;
grant select,insert on public.pos_payment_commands to authenticated;
grant all on public.pos_shift_commands to service_role;
grant all on public.pos_sale_commands to service_role;
grant all on public.pos_sale_line_commands to service_role;
grant all on public.pos_payment_commands to service_role;

create policy pos_shift_commands_read_own on public.pos_shift_commands
for select to authenticated
using (exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'));
create policy pos_shift_commands_insert on public.pos_shift_commands
for insert to authenticated
with check (
  public.has_permission('POS_SHIFT_MANAGE')
  and exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_sale_commands_read_own on public.pos_sale_commands
for select to authenticated
using (exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'));
create policy pos_sale_commands_insert on public.pos_sale_commands
for insert to authenticated
with check (
  public.has_permission('SALES_CREATE')
  and exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_sale_line_commands_read_own on public.pos_sale_line_commands
for select to authenticated
using (exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'));
create policy pos_sale_line_commands_insert on public.pos_sale_line_commands
for insert to authenticated
with check (
  public.has_permission('SALES_CREATE')
  and exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_payment_commands_read_own on public.pos_payment_commands
for select to authenticated
using (exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'));
create policy pos_payment_commands_insert on public.pos_payment_commands
for insert to authenticated
with check (
  public.has_permission('POS_PAYMENT_CAPTURE')
  and exists (select 1 from public.profiles p where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_cashier_payment_intents_read on public.payment_intents
for select to authenticated
using (
  public.has_permission('POS_PAYMENT_CAPTURE')
  and exists (
    select 1
    from public.sales_transactions st
    join public.profiles p on p.id=st.created_by
    where st.payment_intent_id=payment_intents.id
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
      and public.has_data_scope(st.organization_id,st.organization_node_id,st.organization_unit_id,null,null)
  )
);

create policy pos_cashier_payment_attempts_read on public.payment_attempts
for select to authenticated
using (
  public.has_permission('POS_PAYMENT_CAPTURE')
  and exists (
    select 1
    from public.sales_transactions st
    join public.profiles p on p.id=st.created_by
    where st.payment_intent_id=payment_attempts.payment_intent_id
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
      and public.has_data_scope(st.organization_id,st.organization_node_id,st.organization_unit_id,null,null)
  )
);

create or replace function app_private.resolve_pos_price(
  p_organization_id uuid,
  p_organization_node_id uuid,
  p_organization_unit_id uuid,
  p_inventory_item_id uuid,
  p_uom_id uuid,
  p_quantity numeric,
  p_at timestamptz default now()
)
returns table(price_entry_id uuid,price_list_id uuid,unit_price numeric,currency text)
language sql
stable
security definer
set search_path to ''
as $$
  select spe.id,spl.id,spe.unit_price,spl.currency
  from public.sales_price_entries spe
  join public.sales_price_lists spl on spl.id=spe.sales_price_list_id
  where spl.organization_id=p_organization_id
    and spl.organization_node_id=p_organization_node_id
    and spl.organization_unit_id=p_organization_unit_id
    and spl.status='ACTIVE'
    and spl.channel in ('POS','ALL')
    and (spl.valid_from is null or spl.valid_from<=p_at)
    and (spl.valid_until is null or spl.valid_until>p_at)
    and spe.organization_id=p_organization_id
    and spe.organization_node_id=p_organization_node_id
    and spe.organization_unit_id=p_organization_unit_id
    and spe.inventory_item_id=p_inventory_item_id
    and spe.uom_id=p_uom_id
    and spe.status='ACTIVE'
    and spe.min_quantity<=p_quantity
    and (spe.effective_from is null or spe.effective_from<=p_at)
    and (spe.effective_until is null or spe.effective_until>p_at)
  order by spl.priority desc,spe.min_quantity desc,coalesce(spe.effective_from,'-infinity'::timestamptz) desc,spe.created_at desc
  limit 1
$$;
revoke all on function app_private.resolve_pos_price(uuid,uuid,uuid,uuid,uuid,numeric,timestamptz) from public,anon,authenticated;

create or replace function app_private.pos_shift_command_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_warehouse public.warehouses%rowtype;
  v_existing public.pos_shift_commands%rowtype;
  v_shift_id uuid;
  v_shift_number text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('POS_SHIFT_MANAGE') then raise exception 'POS_SHIFT_MANAGE_DENIED' using errcode='42501'; end if;
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;

  select * into v_existing from public.pos_shift_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id and v_existing.terminal_id=new.terminal_id and v_existing.opening_cash=new.opening_cash then return null; end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_terminal from public.pos_terminals where id=new.terminal_id and status='ACTIVE';
  if v_terminal.id is null or v_terminal.organization_id<>v_profile.organization_id then raise exception 'POS_TERMINAL_NOT_AVAILABLE' using errcode='22023'; end if;
  if not public.has_data_scope(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,null,null) then raise exception 'POS_TERMINAL_SCOPE_DENIED' using errcode='42501'; end if;
  if v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_WAREHOUSE_REQUIRED' using errcode='22023'; end if;
  select * into v_warehouse from public.warehouses where id=v_terminal.default_warehouse_id and status='ACTIVE';
  if v_warehouse.id is null then raise exception 'POS_TERMINAL_WAREHOUSE_NOT_ACTIVE' using errcode='22023'; end if;
  if exists(select 1 from public.pos_shifts where terminal_id=v_terminal.id and status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION')) then raise exception 'POS_TERMINAL_SHIFT_ALREADY_OPEN' using errcode='23505'; end if;
  if exists(select 1 from public.pos_shifts where cashier_profile_id=v_profile.id and status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION')) then raise exception 'POS_CASHIER_SHIFT_ALREADY_OPEN' using errcode='23505'; end if;

  v_shift_number:='POSSHIFT-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.pos_shifts(organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,shift_number,status,opening_cash,reconciliation_status,notes)
  values(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.id,v_profile.id,v_shift_number,'OPEN',new.opening_cash,'PENDING',nullif(trim(new.notes),''))
  returning id into v_shift_id;

  new.organization_id:=v_terminal.organization_id;
  new.organization_node_id:=v_terminal.organization_node_id;
  new.organization_unit_id:=v_terminal.organization_unit_id;
  new.result_shift_id:=v_shift_id;
  new.requested_by:=v_profile.id;
  new.notes:=nullif(trim(new.notes),'');
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_terminal.organization_id,v_profile.id,'POS_SHIFT_OPENED','POS_SHIFT',v_shift_id,jsonb_build_object('terminal_id',v_terminal.id,'shift_number',v_shift_number,'opening_cash',new.opening_cash),'POS shift opened through controlled command');
  return new;
end;
$$;

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
  insert into public.sales_transactions(organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,sale_number,sale_type,customer_member_id,currency,subtotal,discount_amount,tax_amount,total_amount,status,local_transaction_id,device_id,client_sequence,idempotency_key,sync_status,correlation_id,created_by)
  values(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.id,v_shift.id,v_sale_number,'POS',new.customer_member_id,'IDR',0,0,0,0,'DRAFT',nullif(trim(new.local_transaction_id),''),nullif(trim(new.device_id),''),new.client_sequence,new.idempotency_key,'SYNCED',v_correlation,v_profile.id)
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
    insert into public.sales_transaction_lines(organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,description,uom_id,quantity,unit_price,discount_amount,tax_amount,line_total)
    values(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.id,v_line_no,v_item.id,jsonb_build_object('sku',v_item.sku,'barcode',v_item.barcode,'name',v_item.name,'uom_id',new.uom_id,'uom_code',v_uom_code,'factor_to_base',v_factor,'price_entry_id',v_price.price_entry_id,'price_list_id',v_price.price_list_id,'unit_price',v_price.unit_price,'currency',v_price.currency,'priced_at',now()),v_item.name,new.uom_id,new.quantity,v_price.unit_price,0,0,round(new.quantity*v_price.unit_price,2))
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
    set quantity=new.quantity,unit_price=v_price.unit_price,line_total=round(new.quantity*v_price.unit_price,2),item_snapshot=jsonb_build_object('sku',v_item.sku,'barcode',v_item.barcode,'name',v_item.name,'uom_id',v_line.uom_id,'uom_code',v_uom_code,'factor_to_base',v_factor,'price_entry_id',v_price.price_entry_id,'price_list_id',v_price.price_list_id,'unit_price',v_price.unit_price,'currency',v_price.currency,'priced_at',now())
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
  update public.sales_transactions set subtotal=v_subtotal,discount_amount=v_discount,tax_amount=v_tax,total_amount=v_subtotal-v_discount+v_tax,updated_at=now() where id=v_sale.id;
  new.result_line_id:=v_line_id;

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_sale.organization_id,v_profile.id,'POS_CART_LINE_'||new.action,'SALES_TRANSACTION',v_sale.id,jsonb_build_object('line_id',v_line_id,'item_id',new.inventory_item_id,'uom_id',new.uom_id,'quantity',new.quantity,'subtotal',v_subtotal,'total',v_subtotal-v_discount+v_tax),'POS cart changed through controlled command');
  return new;
end;
$$;

create or replace function app_private.pos_payment_command_before_insert()
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
  v_existing public.pos_payment_commands%rowtype;
  v_provider public.payment_provider_configs%rowtype;
  v_line record;
  v_stock record;
  v_price record;
  v_available numeric;
  v_required numeric;
  v_intent_id uuid;
  v_attempt_id uuid;
  v_intent_number text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('POS_PAYMENT_CAPTURE') then raise exception 'POS_PAYMENT_CAPTURE_DENIED' using errcode='42501'; end if;
  new.channel:=upper(trim(new.channel));
  new.provider_code:=nullif(trim(new.provider_code),'');
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;

  select * into v_existing from public.pos_payment_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id and v_existing.sales_transaction_id=new.sales_transaction_id and v_existing.channel=new.channel and v_existing.provider_code is not distinct from new.provider_code then return null; end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_sale from public.sales_transactions where id=new.sales_transaction_id for update;
  if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
  if v_sale.created_by<>v_profile.id or v_sale.status<>'DRAFT' then raise exception 'POS_OWN_DRAFT_SALE_REQUIRED' using errcode='42501'; end if;
  if coalesce(v_sale.total_amount,0)<=0 or not exists(select 1 from public.sales_transaction_lines where sales_transaction_id=v_sale.id) then raise exception 'POS_CART_EMPTY' using errcode='22023'; end if;
  select * into v_shift from public.pos_shifts where id=v_sale.pos_shift_id and cashier_profile_id=v_profile.id and status='OPEN';
  if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
  select * into v_terminal from public.pos_terminals where id=v_sale.terminal_id and status='ACTIVE';
  if v_terminal.id is null or v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_NOT_READY' using errcode='22023'; end if;
  if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;

  for v_line in select * from public.sales_transaction_lines where sales_transaction_id=v_sale.id order by line_no loop
    select * into v_price from app_private.resolve_pos_price(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_line.inventory_item_id,v_line.uom_id,v_line.quantity,now());
    if v_price.price_entry_id is null
       or (v_line.item_snapshot->>'price_entry_id') is distinct from v_price.price_entry_id::text
       or v_line.unit_price is distinct from v_price.unit_price then
      raise exception 'POS_PRICE_CHANGED_RELOAD_CART' using errcode='22023';
    end if;
  end loop;

  for v_stock in
    select inventory_item_id,sum(quantity*coalesce(nullif(item_snapshot->>'factor_to_base','')::numeric,1)) as required_base
    from public.sales_transaction_lines
    where sales_transaction_id=v_sale.id
    group by inventory_item_id
  loop
    select coalesce(sum(available_to_allocate),0) into v_available
    from public.inventory_available_positions
    where warehouse_id=v_terminal.default_warehouse_id and inventory_item_id=v_stock.inventory_item_id and stock_status='AVAILABLE';
    v_required:=v_stock.required_base;
    if v_available<v_required then raise exception 'POS_INSUFFICIENT_STOCK' using errcode='22023'; end if;
  end loop;

  if not exists(
    select 1
    from public.accounting_event_mappings aem
    join public.accounting_event_definitions aed on aed.id=aem.event_definition_id
    where aed.event_code='SALE_POST' and aed.status='ACTIVE'
      and aem.organization_id=v_sale.organization_id
      and aem.organization_node_id=v_sale.organization_node_id
      and aem.status='ACTIVE'
      and (aem.effective_from is null or aem.effective_from<=current_date)
      and (aem.effective_until is null or aem.effective_until>=current_date)
  ) then
    raise exception 'POS_ACCOUNTING_MAPPING_NOT_READY' using errcode='22023';
  end if;

  if new.channel in ('QRIS','BANK_TRANSFER') then
    select * into v_provider
    from public.payment_provider_configs ppc
    where ppc.organization_id=v_sale.organization_id
      and ppc.organization_node_id=v_sale.organization_node_id
      and (ppc.organization_unit_id=v_sale.organization_unit_id or ppc.organization_unit_id is null)
      and ppc.status='ACTIVE'
      and ppc.config_status='VALIDATED'
      and new.channel=any(ppc.supported_channels)
      and (new.provider_code is null or ppc.code=new.provider_code)
    order by (ppc.organization_unit_id is not null) desc,ppc.updated_at desc
    limit 1;
    if v_provider.id is null then raise exception 'POS_PAYMENT_PROVIDER_NOT_READY' using errcode='22023'; end if;
    new.provider_code:=v_provider.code;
  elsif new.channel<>'CASH_POS' then
    raise exception 'POS_PAYMENT_CHANNEL_NOT_SUPPORTED' using errcode='22023';
  end if;

  v_intent_number:='POSPAY-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.payment_intents(organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,source_domain,source_entity_type,source_entity_id,source_reference,payer_member_id,amount,currency,status,idempotency_key,created_by)
  values(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_intent_number,'SALE','COMMERCIAL','SALES_TRANSACTION',v_sale.id,v_sale.sale_number,v_sale.customer_member_id,v_sale.total_amount,v_sale.currency,'CREATED','POSPAY:'||new.idempotency_key,v_profile.id)
  returning id into v_intent_id;

  insert into public.payment_attempts(payment_intent_id,organization_id,organization_node_id,organization_unit_id,provider_config_id,attempt_no,channel,amount,currency,status,merchant_reference)
  values(v_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_provider.id,1,new.channel,v_sale.total_amount,v_sale.currency,'CREATED',v_intent_number)
  returning id into v_attempt_id;

  update public.sales_transactions set payment_intent_id=v_intent_id,status='PAYMENT_PENDING',updated_at=now() where id=v_sale.id;
  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.result_payment_intent_id:=v_intent_id;
  new.result_payment_attempt_id:=v_attempt_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_sale.organization_id,v_profile.id,'POS_PAYMENT_STARTED','SALES_TRANSACTION',v_sale.id,jsonb_build_object('payment_intent_id',v_intent_id,'payment_attempt_id',v_attempt_id,'channel',new.channel,'provider_code',new.provider_code,'amount',v_sale.total_amount,'sale_status','PAYMENT_PENDING'),'POS payment initiated after stock, price, and accounting preflight');
  return new;
end;
$$;

create trigger trg_pos_shift_command_before_insert before insert on public.pos_shift_commands for each row execute function app_private.pos_shift_command_before_insert();
create trigger trg_pos_sale_command_before_insert before insert on public.pos_sale_commands for each row execute function app_private.pos_sale_command_before_insert();
create trigger trg_pos_sale_line_command_before_insert before insert on public.pos_sale_line_commands for each row execute function app_private.pos_sale_line_command_before_insert();
create trigger trg_pos_payment_command_before_insert before insert on public.pos_payment_commands for each row execute function app_private.pos_payment_command_before_insert();

revoke all on function app_private.pos_shift_command_before_insert() from public,anon,authenticated;
revoke all on function app_private.pos_sale_command_before_insert() from public,anon,authenticated;
revoke all on function app_private.pos_sale_line_command_before_insert() from public,anon,authenticated;
revoke all on function app_private.pos_payment_command_before_insert() from public,anon,authenticated;

create or replace function public.open_pos_shift(p_terminal_id uuid,p_opening_cash numeric default 0,p_idempotency_key text default null,p_notes text default null)
returns uuid
language plpgsql
set search_path to ''
as $$
declare v_result uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_shift_id into v_result from public.pos_shift_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;
  insert into public.pos_shift_commands(terminal_id,opening_cash,idempotency_key,notes) values(p_terminal_id,coalesce(p_opening_cash,0),v_key,p_notes) returning result_shift_id into v_result;
  if v_result is null then select result_shift_id into v_result from public.pos_shift_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
end;
$$;

create or replace function public.create_pos_sale(p_terminal_id uuid,p_pos_shift_id uuid,p_idempotency_key text,p_customer_member_id uuid default null,p_local_transaction_id text default null,p_device_id text default null,p_client_sequence bigint default null)
returns uuid
language plpgsql
set search_path to ''
as $$
declare v_result uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_sale_id into v_result from public.pos_sale_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;
  insert into public.pos_sale_commands(terminal_id,pos_shift_id,customer_member_id,local_transaction_id,device_id,client_sequence,idempotency_key)
  values(p_terminal_id,p_pos_shift_id,p_customer_member_id,p_local_transaction_id,p_device_id,p_client_sequence,v_key)
  returning result_sale_id into v_result;
  if v_result is null then select result_sale_id into v_result from public.pos_sale_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
end;
$$;

create or replace function public.add_pos_sale_line(p_sales_transaction_id uuid,p_inventory_item_id uuid,p_uom_id uuid,p_quantity numeric,p_idempotency_key text)
returns uuid
language plpgsql
set search_path to ''
as $$
declare v_result uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;
  insert into public.pos_sale_line_commands(action,sales_transaction_id,inventory_item_id,uom_id,quantity,idempotency_key)
  values('ADD',p_sales_transaction_id,p_inventory_item_id,p_uom_id,p_quantity,v_key) returning result_line_id into v_result;
  if v_result is null then select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
end;
$$;

create or replace function public.update_pos_sale_line_quantity(p_sales_transaction_id uuid,p_sales_transaction_line_id uuid,p_quantity numeric,p_idempotency_key text)
returns uuid
language plpgsql
set search_path to ''
as $$
declare v_result uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;
  insert into public.pos_sale_line_commands(action,sales_transaction_id,sales_transaction_line_id,quantity,idempotency_key)
  values('UPDATE_QTY',p_sales_transaction_id,p_sales_transaction_line_id,p_quantity,v_key) returning result_line_id into v_result;
  if v_result is null then select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
end;
$$;

create or replace function public.remove_pos_sale_line(p_sales_transaction_id uuid,p_sales_transaction_line_id uuid,p_idempotency_key text)
returns uuid
language plpgsql
set search_path to ''
as $$
declare v_result uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1;
  if v_result is not null then return v_result; end if;
  insert into public.pos_sale_line_commands(action,sales_transaction_id,sales_transaction_line_id,idempotency_key)
  values('REMOVE',p_sales_transaction_id,p_sales_transaction_line_id,v_key) returning result_line_id into v_result;
  if v_result is null then select result_line_id into v_result from public.pos_sale_line_commands where idempotency_key=v_key limit 1; end if;
  if v_result is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return v_result;
end;
$$;

create or replace function public.start_pos_payment(p_sales_transaction_id uuid,p_channel text,p_idempotency_key text,p_provider_code text default null)
returns table(payment_intent_id uuid,payment_attempt_id uuid)
language plpgsql
set search_path to ''
as $$
declare v_intent uuid; v_attempt uuid; v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  select result_payment_intent_id,result_payment_attempt_id into v_intent,v_attempt from public.pos_payment_commands where idempotency_key=v_key limit 1;
  if v_intent is null then
    insert into public.pos_payment_commands(sales_transaction_id,channel,provider_code,idempotency_key)
    values(p_sales_transaction_id,upper(trim(p_channel)),p_provider_code,v_key)
    returning result_payment_intent_id,result_payment_attempt_id into v_intent,v_attempt;
  end if;
  if v_intent is null then select result_payment_intent_id,result_payment_attempt_id into v_intent,v_attempt from public.pos_payment_commands where idempotency_key=v_key limit 1; end if;
  if v_intent is null or v_attempt is null then raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505'; end if;
  return query select v_intent,v_attempt;
end;
$$;

revoke all on function public.open_pos_shift(uuid,numeric,text,text) from public,anon;
revoke all on function public.create_pos_sale(uuid,uuid,text,uuid,text,text,bigint) from public,anon;
revoke all on function public.add_pos_sale_line(uuid,uuid,uuid,numeric,text) from public,anon;
revoke all on function public.update_pos_sale_line_quantity(uuid,uuid,numeric,text) from public,anon;
revoke all on function public.remove_pos_sale_line(uuid,uuid,text) from public,anon;
revoke all on function public.start_pos_payment(uuid,text,text,text) from public,anon;
grant execute on function public.open_pos_shift(uuid,numeric,text,text) to authenticated;
grant execute on function public.create_pos_sale(uuid,uuid,text,uuid,text,text,bigint) to authenticated;
grant execute on function public.add_pos_sale_line(uuid,uuid,uuid,numeric,text) to authenticated;
grant execute on function public.update_pos_sale_line_quantity(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.remove_pos_sale_line(uuid,uuid,text) to authenticated;
grant execute on function public.start_pos_payment(uuid,text,text,text) to authenticated;
