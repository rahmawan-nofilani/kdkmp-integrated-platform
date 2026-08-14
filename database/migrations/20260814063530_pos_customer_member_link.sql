create table public.pos_customer_lookup_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  customer_member_id uuid references public.members(id) on delete restrict,
  search_query text,
  result_limit integer not null default 10 check (result_limit between 1 and 20),
  result jsonb not null default '[]'::jsonb,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (
    (customer_member_id is not null and search_query is null)
    or (customer_member_id is null and search_query is not null)
  )
);

create index idx_pos_customer_lookup_requests_organization_id on public.pos_customer_lookup_requests(organization_id);
create index idx_pos_customer_lookup_requests_organization_node_id on public.pos_customer_lookup_requests(organization_node_id);
create index idx_pos_customer_lookup_requests_organization_unit_id on public.pos_customer_lookup_requests(organization_unit_id);
create index idx_pos_customer_lookup_requests_terminal_id on public.pos_customer_lookup_requests(terminal_id);
create index idx_pos_customer_lookup_requests_customer_member_id on public.pos_customer_lookup_requests(customer_member_id);
create index idx_pos_customer_lookup_requests_requested_by on public.pos_customer_lookup_requests(requested_by, created_at desc);

alter table public.pos_customer_lookup_requests enable row level security;
revoke all on public.pos_customer_lookup_requests from public, anon, authenticated;
grant insert(terminal_id, customer_member_id, search_query, result_limit) on public.pos_customer_lookup_requests to authenticated;
grant select on public.pos_customer_lookup_requests to authenticated;
grant all on public.pos_customer_lookup_requests to service_role;

create policy pos_customer_lookup_requests_insert on public.pos_customer_lookup_requests
for insert to authenticated
with check (
  public.has_permission('SALES_CREATE')
  and exists (
    select 1
    from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
  and public.has_data_scope(
    organization_id,
    organization_node_id,
    organization_unit_id,
    null,
    null
  )
);

create policy pos_customer_lookup_requests_read_own on public.pos_customer_lookup_requests
for select to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
);

create or replace function app_private.pos_customer_lookup_before_insert()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile public.profiles%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_shift public.pos_shifts%rowtype;
  v_query text;
begin
  select *
  into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid())
    and status='ACTIVE'
  limit 1;

  if v_profile.id is null or v_profile.organization_id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;
  if not public.has_permission('SALES_CREATE') then
    raise exception 'SALES_CREATE_DENIED' using errcode='42501';
  end if;

  select *
  into v_terminal
  from public.pos_terminals
  where id=new.terminal_id
    and status='ACTIVE';

  if v_terminal.id is null or v_terminal.organization_id<>v_profile.organization_id then
    raise exception 'POS_TERMINAL_NOT_AVAILABLE' using errcode='22023';
  end if;

  select *
  into v_shift
  from public.pos_shifts
  where terminal_id=v_terminal.id
    and cashier_profile_id=v_profile.id
    and status='OPEN'
  limit 1;

  if v_shift.id is null then
    raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501';
  end if;
  if not public.has_data_scope(
    v_terminal.organization_id,
    v_terminal.organization_node_id,
    v_terminal.organization_unit_id,
    null,
    null
  ) then
    raise exception 'POS_CUSTOMER_LOOKUP_SCOPE_DENIED' using errcode='42501';
  end if;

  new.result_limit:=least(greatest(coalesce(new.result_limit,10),1),20);

  if new.customer_member_id is not null then
    new.search_query:=null;
    new.result_limit:=1;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'member_id', safe_member.id,
          'member_number', safe_member.member_number,
          'full_name', safe_member.full_name
        )
        order by safe_member.full_name, safe_member.member_number
      ),
      '[]'::jsonb
    )
    into new.result
    from (
      select m.id, m.member_number, m.full_name
      from public.members m
      where m.id=new.customer_member_id
        and m.organization_id=v_terminal.organization_id
        and m.organization_node_id=v_terminal.organization_node_id
        and m.status='ACTIVE'
      limit 1
    ) safe_member;
  else
    v_query:=regexp_replace(trim(coalesce(new.search_query,'')),'[[:space:]]+',' ','g');
    if char_length(v_query)<2 or char_length(v_query)>80 then
      raise exception 'POS_CUSTOMER_SEARCH_QUERY_INVALID' using errcode='22023';
    end if;
    new.search_query:=v_query;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'member_id', safe_member.id,
          'member_number', safe_member.member_number,
          'full_name', safe_member.full_name
        )
        order by safe_member.rank_order, safe_member.full_name, safe_member.member_number
      ),
      '[]'::jsonb
    )
    into new.result
    from (
      select
        m.id,
        m.member_number,
        m.full_name,
        case
          when lower(coalesce(m.member_number,''))=lower(v_query) then 0
          when strpos(lower(coalesce(m.member_number,'')),lower(v_query))=1 then 1
          else 2
        end as rank_order
      from public.members m
      where m.organization_id=v_terminal.organization_id
        and m.organization_node_id=v_terminal.organization_node_id
        and m.status='ACTIVE'
        and (
          strpos(lower(m.full_name),lower(v_query))>0
          or strpos(lower(coalesce(m.member_number,'')),lower(v_query))>0
        )
      order by rank_order, m.full_name, m.member_number
      limit new.result_limit
    ) safe_member;
  end if;

  new.organization_id:=v_terminal.organization_id;
  new.organization_node_id:=v_terminal.organization_node_id;
  new.organization_unit_id:=v_terminal.organization_unit_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();
  return new;
end;
$$;

revoke all on function app_private.pos_customer_lookup_before_insert() from public, anon, authenticated;
create trigger trg_pos_customer_lookup_before_insert
before insert on public.pos_customer_lookup_requests
for each row execute function app_private.pos_customer_lookup_before_insert();

alter table public.pos_sale_commands
  drop constraint pos_sale_commands_action_check;
alter table public.pos_sale_commands
  add constraint pos_sale_commands_action_check
  check (action in ('CREATE_DRAFT','CANCEL_DRAFT','SET_CUSTOMER'));

create or replace function app_private.pos_sale_command_before_insert()
returns trigger
language plpgsql
security definer
set search_path=''
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
  if new.action not in ('CREATE_DRAFT','CANCEL_DRAFT','SET_CUSTOMER') then
    raise exception 'POS_SALE_COMMAND_ACTION_INVALID' using errcode='22023';
  end if;
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

  if new.action in ('CANCEL_DRAFT','SET_CUSTOMER') then
    if new.target_sale_id is null then raise exception 'POS_SALE_REQUIRED' using errcode='22023'; end if;
    select * into v_sale from public.sales_transactions where id=new.target_sale_id for update;
    if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
    if v_sale.created_by<>v_profile.id or v_sale.status<>'DRAFT' then raise exception 'POS_OWN_DRAFT_SALE_REQUIRED' using errcode='42501'; end if;
    select * into v_shift from public.pos_shifts where id=v_sale.pos_shift_id and cashier_profile_id=v_profile.id and status='OPEN';
    if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
    if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;

    new.organization_id:=v_sale.organization_id;
    new.organization_node_id:=v_sale.organization_node_id;
    new.organization_unit_id:=v_sale.organization_unit_id;
    new.terminal_id:=v_sale.terminal_id;
    new.pos_shift_id:=v_sale.pos_shift_id;
    new.result_sale_id:=v_sale.id;
    new.requested_by:=v_profile.id;
    new.local_transaction_id:=null;
    new.device_id:=null;
    new.client_sequence:=null;
    new.created_at:=now();

    if new.action='CANCEL_DRAFT' then
      new.customer_member_id:=v_sale.customer_member_id;
      update public.sales_transactions set status='CANCELLED',updated_at=now() where id=v_sale.id;

      insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
      values(v_sale.organization_id,v_profile.id,'POS_SALE_DRAFT_CANCELLED','SALES_TRANSACTION',v_sale.id,
        jsonb_build_object('status','DRAFT'),jsonb_build_object('status','CANCELLED'),'POS draft cancelled through controlled command');
      return new;
    end if;

    if new.customer_member_id is not null and not exists(
      select 1
      from public.members m
      where m.id=new.customer_member_id
        and m.organization_id=v_sale.organization_id
        and m.organization_node_id=v_sale.organization_node_id
        and m.status='ACTIVE'
    ) then
      raise exception 'POS_CUSTOMER_MEMBER_NOT_ACTIVE' using errcode='22023';
    end if;

    if v_sale.customer_member_id is distinct from new.customer_member_id then
      update public.sales_transactions
      set customer_member_id=new.customer_member_id,updated_at=now()
      where id=v_sale.id;

      insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
      values(v_sale.organization_id,v_profile.id,'POS_SALE_CUSTOMER_CHANGED','SALES_TRANSACTION',v_sale.id,
        jsonb_build_object('customer_member_id',v_sale.customer_member_id),
        jsonb_build_object('customer_member_id',new.customer_member_id),
        case when new.customer_member_id is null then 'Optional member link removed from POS draft' else 'Optional member linked to POS draft' end);
    end if;
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
  if new.customer_member_id is not null and not exists(
    select 1
    from public.members m
    where m.id=new.customer_member_id
      and m.organization_id=v_terminal.organization_id
      and m.organization_node_id=v_terminal.organization_node_id
      and m.status='ACTIVE'
  ) then raise exception 'POS_CUSTOMER_MEMBER_NOT_ACTIVE' using errcode='22023'; end if;

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

revoke all on function app_private.pos_sale_command_before_insert() from public, anon, authenticated;

create or replace function public.link_pos_sale_customer(
  p_sales_transaction_id uuid,
  p_customer_member_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_sale public.sales_transactions%rowtype;
  v_key text:=nullif(trim(p_idempotency_key),'');
  v_result uuid;
begin
  if p_sales_transaction_id is null then
    raise exception 'POS_SALE_REQUIRED' using errcode='22023';
  end if;
  if v_key is null or char_length(v_key)<8 then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;

  select result_sale_id
  into v_result
  from public.pos_sale_commands
  where idempotency_key=v_key
  limit 1;
  if found then return v_result; end if;

  select *
  into v_sale
  from public.sales_transactions
  where id=p_sales_transaction_id;

  if v_sale.id is null then
    raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002';
  end if;

  insert into public.pos_sale_commands(
    action,
    terminal_id,
    pos_shift_id,
    customer_member_id,
    idempotency_key,
    target_sale_id
  )
  values(
    'SET_CUSTOMER',
    v_sale.terminal_id,
    v_sale.pos_shift_id,
    p_customer_member_id,
    v_key,
    v_sale.id
  )
  returning result_sale_id into v_result;

  if v_result is null then
    select result_sale_id
    into v_result
    from public.pos_sale_commands
    where idempotency_key=v_key
    limit 1;
  end if;
  return v_result;
end;
$$;

revoke all on function public.link_pos_sale_customer(uuid,uuid,text) from public, anon;
grant execute on function public.link_pos_sale_customer(uuid,uuid,text) to authenticated;

comment on table public.pos_customer_lookup_requests is 'Cashier-safe ACTIVE member lookup. Results expose only member ID, member number and full name within the cashier own open-shift KDKMP scope.';
comment on function public.link_pos_sale_customer(uuid,uuid,text) is 'Idempotently links or clears an optional ACTIVE member on the cashier own DRAFT POS sale through the controlled command path.';
