create table public.pos_cash_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  sales_transaction_id uuid references public.sales_transactions(id) on delete restrict,
  payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  movement_type text not null check (movement_type in ('CASH_SALE','CASH_REFUND','CASH_IN','CASH_OUT','ADJUSTMENT')),
  direction text not null check (direction in ('IN','OUT')),
  amount numeric(20,2) not null check (amount > 0),
  currency text not null default 'IDR',
  status text not null default 'POSTED' check (status in ('POSTED','REVERSED')),
  reversal_of_movement_id uuid references public.pos_cash_movements(id) on delete restrict,
  reason text,
  occurred_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index idx_pos_cash_movements_scope on public.pos_cash_movements(organization_id,organization_node_id,organization_unit_id,pos_shift_id,occurred_at desc);
create index idx_pos_cash_movements_shift_status on public.pos_cash_movements(pos_shift_id,status,occurred_at desc);
create index idx_pos_cash_movements_sale on public.pos_cash_movements(sales_transaction_id);
create index idx_pos_cash_movements_payment_intent on public.pos_cash_movements(payment_intent_id);
create index idx_pos_cash_movements_payment_attempt on public.pos_cash_movements(payment_attempt_id);
create index idx_pos_cash_movements_reversal on public.pos_cash_movements(reversal_of_movement_id);
create index idx_pos_cash_movements_created_by on public.pos_cash_movements(created_by);
create index idx_pos_cash_movements_organization_node_id on public.pos_cash_movements(organization_node_id);
create index idx_pos_cash_movements_organization_unit_id on public.pos_cash_movements(organization_unit_id);

alter table public.pos_cash_movements enable row level security;
revoke all on public.pos_cash_movements from public,anon,authenticated;
grant select on public.pos_cash_movements to authenticated;
grant all on public.pos_cash_movements to service_role;

create policy pos_cash_movements_read on public.pos_cash_movements
for select to authenticated
using (
  public.has_permission('POS_SHIFT_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

alter table public.pos_shift_commands drop constraint if exists pos_shift_commands_action_check;
alter table public.pos_shift_commands add constraint pos_shift_commands_action_check check (action in ('OPEN','CLOSE'));
alter table public.pos_shift_commands add column target_shift_id uuid references public.pos_shifts(id) on delete restrict;
alter table public.pos_shift_commands add column counted_cash numeric(20,2) check (counted_cash is null or counted_cash >= 0);
create index idx_pos_shift_commands_target_shift on public.pos_shift_commands(target_shift_id);

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
  v_shift public.pos_shifts%rowtype;
  v_shift_id uuid;
  v_shift_number text;
  v_expected_cash numeric(20,2);
  v_reconciliation_status text;
  v_final_status text;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;

  if v_profile.id is null or v_profile.organization_id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;
  if not public.has_permission('POS_SHIFT_MANAGE') then
    raise exception 'POS_SHIFT_MANAGE_DENIED' using errcode='42501';
  end if;

  new.action:=upper(trim(coalesce(new.action,'OPEN')));
  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;

  select * into v_existing
  from public.pos_shift_commands
  where idempotency_key=new.idempotency_key
  limit 1;

  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.action=new.action
       and v_existing.terminal_id=new.terminal_id
       and v_existing.target_shift_id is not distinct from new.target_shift_id
       and v_existing.opening_cash is not distinct from new.opening_cash
       and v_existing.counted_cash is not distinct from new.counted_cash then
      return null;
    end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  if new.action='OPEN' then
    select * into v_terminal
    from public.pos_terminals
    where id=new.terminal_id and status='ACTIVE';

    if v_terminal.id is null or v_terminal.organization_id<>v_profile.organization_id then
      raise exception 'POS_TERMINAL_NOT_AVAILABLE' using errcode='22023';
    end if;
    if not public.has_data_scope(v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,null,null) then
      raise exception 'POS_TERMINAL_SCOPE_DENIED' using errcode='42501';
    end if;
    if v_terminal.default_warehouse_id is null then
      raise exception 'POS_TERMINAL_WAREHOUSE_REQUIRED' using errcode='22023';
    end if;

    select * into v_warehouse
    from public.warehouses
    where id=v_terminal.default_warehouse_id and status='ACTIVE';
    if v_warehouse.id is null then
      raise exception 'POS_TERMINAL_WAREHOUSE_NOT_ACTIVE' using errcode='22023';
    end if;

    if exists(select 1 from public.pos_shifts where terminal_id=v_terminal.id and status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION')) then
      raise exception 'POS_TERMINAL_SHIFT_ALREADY_OPEN' using errcode='23505';
    end if;
    if exists(select 1 from public.pos_shifts where cashier_profile_id=v_profile.id and status in ('OPEN','CLOSING','RECONCILIATION_EXCEPTION')) then
      raise exception 'POS_CASHIER_SHIFT_ALREADY_OPEN' using errcode='23505';
    end if;

    v_shift_number:='POSSHIFT-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
    insert into public.pos_shifts(
      organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
      shift_number,status,opening_cash,reconciliation_status,notes
    ) values(
      v_terminal.organization_id,v_terminal.organization_node_id,v_terminal.organization_unit_id,v_terminal.id,v_profile.id,
      v_shift_number,'OPEN',new.opening_cash,'PENDING',nullif(trim(new.notes),'')
    ) returning id into v_shift_id;

    new.organization_id:=v_terminal.organization_id;
    new.organization_node_id:=v_terminal.organization_node_id;
    new.organization_unit_id:=v_terminal.organization_unit_id;
    new.target_shift_id:=null;
    new.counted_cash:=null;
    new.result_shift_id:=v_shift_id;
    new.requested_by:=v_profile.id;
    new.notes:=nullif(trim(new.notes),'');
    new.created_at:=now();

    insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
    values(
      v_terminal.organization_id,v_profile.id,'POS_SHIFT_OPENED','POS_SHIFT',v_shift_id,
      jsonb_build_object('terminal_id',v_terminal.id,'shift_number',v_shift_number,'opening_cash',new.opening_cash),
      'POS shift opened through controlled command'
    );
    return new;
  end if;

  if new.action='CLOSE' then
    if new.target_shift_id is null or new.counted_cash is null then
      raise exception 'POS_SHIFT_AND_COUNTED_CASH_REQUIRED' using errcode='22023';
    end if;

    select * into v_shift
    from public.pos_shifts
    where id=new.target_shift_id
    for update;

    if v_shift.id is null then
      raise exception 'POS_SHIFT_NOT_FOUND' using errcode='P0002';
    end if;
    if v_shift.cashier_profile_id<>v_profile.id or v_shift.status<>'OPEN' then
      raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501';
    end if;
    if not public.has_data_scope(v_shift.organization_id,v_shift.organization_node_id,v_shift.organization_unit_id,null,null) then
      raise exception 'POS_SHIFT_SCOPE_DENIED' using errcode='42501';
    end if;

    if exists(
      select 1
      from public.sales_transactions st
      where st.pos_shift_id=v_shift.id
        and st.status not in ('COMPLETED','VOIDED','RETURNED','CANCELLED')
    ) then
      raise exception 'POS_SHIFT_HAS_UNFINISHED_SALES' using errcode='55000';
    end if;

    select v_shift.opening_cash
      + coalesce(sum(case when pcm.direction='IN' then pcm.amount else -pcm.amount end) filter (where pcm.status='POSTED'),0)
    into v_expected_cash
    from public.pos_cash_movements pcm
    where pcm.pos_shift_id=v_shift.id;

    if new.counted_cash=v_expected_cash then
      v_reconciliation_status:='MATCHED';
      v_final_status:='CLOSED';
    else
      v_reconciliation_status:='EXCEPTION';
      v_final_status:='RECONCILIATION_EXCEPTION';
    end if;

    update public.pos_shifts
    set status=v_final_status,
        closed_at=now(),
        expected_cash=v_expected_cash,
        counted_cash=new.counted_cash,
        reconciliation_status=v_reconciliation_status,
        notes=coalesce(nullif(trim(new.notes),''),notes)
    where id=v_shift.id;

    new.terminal_id:=v_shift.terminal_id;
    new.organization_id:=v_shift.organization_id;
    new.organization_node_id:=v_shift.organization_node_id;
    new.organization_unit_id:=v_shift.organization_unit_id;
    new.opening_cash:=v_shift.opening_cash;
    new.result_shift_id:=v_shift.id;
    new.requested_by:=v_profile.id;
    new.notes:=nullif(trim(new.notes),'');
    new.created_at:=now();

    insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
    values(
      v_shift.organization_id,v_profile.id,'POS_SHIFT_CLOSED','POS_SHIFT',v_shift.id,
      jsonb_build_object('status',v_shift.status,'opening_cash',v_shift.opening_cash),
      jsonb_build_object('status',v_final_status,'expected_cash',v_expected_cash,'counted_cash',new.counted_cash,'reconciliation_status',v_reconciliation_status),
      'POS shift closed through controlled command'
    );
    return new;
  end if;

  raise exception 'POS_SHIFT_ACTION_NOT_SUPPORTED' using errcode='22023';
end;
$$;

revoke all on function app_private.pos_shift_command_before_insert() from public,anon,authenticated;

create or replace function public.close_pos_shift(
  p_pos_shift_id uuid,
  p_counted_cash numeric,
  p_idempotency_key text,
  p_notes text default null
)
returns uuid
language plpgsql
set search_path to ''
as $$
declare
  v_result uuid;
  v_key text:=nullif(trim(p_idempotency_key),'');
  v_terminal_id uuid;
begin
  if v_key is null then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;
  if p_counted_cash is null or p_counted_cash<0 then
    raise exception 'POS_COUNTED_CASH_INVALID' using errcode='22023';
  end if;

  select result_shift_id into v_result
  from public.pos_shift_commands
  where idempotency_key=v_key
  limit 1;
  if v_result is not null then return v_result; end if;

  select terminal_id into v_terminal_id
  from public.pos_shifts
  where id=p_pos_shift_id;

  insert into public.pos_shift_commands(action,terminal_id,target_shift_id,counted_cash,idempotency_key,notes)
  values('CLOSE',v_terminal_id,p_pos_shift_id,p_counted_cash,v_key,p_notes)
  returning result_shift_id into v_result;

  if v_result is null then
    select result_shift_id into v_result
    from public.pos_shift_commands
    where idempotency_key=v_key
    limit 1;
  end if;
  if v_result is null then
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;
  return v_result;
end;
$$;

revoke all on function public.close_pos_shift(uuid,numeric,text,text) from public,anon;
grant execute on function public.close_pos_shift(uuid,numeric,text,text) to authenticated;
