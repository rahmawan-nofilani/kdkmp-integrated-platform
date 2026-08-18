-- REVIEW DRAFT ONLY / NOT A MIGRATION
-- POS CASH Reversal — controlled completed-sale void foundation
--
-- This file is intentionally stored under database/drafts/ until the pinned
-- Supabase CLI can generate the canonical migration basename. Do not apply
-- this file directly to DEVELOPMENT or production.
--
-- Design invariants:
-- 1. Original COMPLETED sale, receipt, SALE_ISSUE movement, POSTED journal,
--    and CASH_SALE movement remain historical records and are never edited.
-- 2. A void creates new linked reversal records atomically.
-- 3. Cash refund requires a target OPEN POS shift; no cash leaves an
--    untracked drawer/session.
-- 4. SALES_VOID remains privileged and is NOT mapped to any role here.
-- 5. Retry uses one idempotency key and must not duplicate money, stock,
--    journal, return, or audit records.
-- 6. Partial return is intentionally out of scope for this slice.

create table public.pos_cash_reversal_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  original_sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  refund_pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  reason_code text not null check (char_length(trim(reason_code)) between 3 and 80),
  reason_note text,
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  result_sales_return_id uuid references public.sales_returns(id) on delete restrict,
  result_refund_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  result_refund_payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  result_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  result_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  result_cash_movement_id uuid references public.pos_cash_movements(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create unique index ux_pos_cash_reversal_original_sale_once
  on public.pos_cash_reversal_commands(original_sales_transaction_id)
  where result_sales_return_id is not null;
create index idx_pos_cash_reversal_requested_by
  on public.pos_cash_reversal_commands(requested_by,created_at desc);
create index idx_pos_cash_reversal_refund_shift
  on public.pos_cash_reversal_commands(refund_pos_shift_id,created_at desc);
create index idx_pos_cash_reversal_org
  on public.pos_cash_reversal_commands(organization_id,organization_node_id,organization_unit_id,created_at desc);
create index idx_pos_cash_reversal_return
  on public.pos_cash_reversal_commands(result_sales_return_id);
create index idx_pos_cash_reversal_refund_intent
  on public.pos_cash_reversal_commands(result_refund_payment_intent_id);
create index idx_pos_cash_reversal_refund_attempt
  on public.pos_cash_reversal_commands(result_refund_payment_attempt_id);
create index idx_pos_cash_reversal_inventory
  on public.pos_cash_reversal_commands(result_inventory_movement_id);
create index idx_pos_cash_reversal_journal
  on public.pos_cash_reversal_commands(result_journal_entry_id);
create index idx_pos_cash_reversal_cash
  on public.pos_cash_reversal_commands(result_cash_movement_id);

alter table public.pos_cash_reversal_commands enable row level security;
revoke all on public.pos_cash_reversal_commands from public,anon,authenticated;
grant select,insert on public.pos_cash_reversal_commands to authenticated;
grant all on public.pos_cash_reversal_commands to service_role;

create policy pos_cash_reversal_read_own on public.pos_cash_reversal_commands
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

create policy pos_cash_reversal_insert on public.pos_cash_reversal_commands
for insert to authenticated
with check (
  public.has_permission('SALES_VOID')
  and exists (
    select 1
    from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create unique index ux_pos_cash_refund_reversal_once
  on public.pos_cash_movements(reversal_of_movement_id)
  where reversal_of_movement_id is not null
    and movement_type='CASH_REFUND'
    and status='POSTED';

create unique index ux_inventory_movement_reversal_once
  on public.inventory_movements(reversal_of_movement_id)
  where reversal_of_movement_id is not null
    and status='POSTED';

create unique index ux_journal_entry_reversal_once
  on public.journal_entries(reversal_of_entry_id)
  where reversal_of_entry_id is not null
    and status='POSTED';

create or replace function app_private.pos_cash_reversal_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_sale public.sales_transactions%rowtype;
  v_refund_shift public.pos_shifts%rowtype;
  v_original_cash public.pos_cash_movements%rowtype;
  v_original_inventory public.inventory_movements%rowtype;
  v_original_journal public.journal_entries%rowtype;
  v_original_intent public.payment_intents%rowtype;
  v_original_attempt public.payment_attempts%rowtype;
  v_existing public.pos_cash_reversal_commands%rowtype;
  v_return_id uuid;
  v_refund_intent_id uuid;
  v_refund_attempt_id uuid;
  v_inventory_id uuid;
  v_journal_id uuid;
  v_cash_id uuid;
  v_return_number text;
  v_intent_number text;
  v_inventory_number text;
  v_journal_number text;
  v_reason text;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;

  if v_profile.id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;
  if not public.has_permission('SALES_VOID') then
    raise exception 'SALES_VOID_DENIED' using errcode='42501';
  end if;

  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  new.reason_code:=upper(nullif(trim(new.reason_code),''));
  new.reason_note:=nullif(trim(new.reason_note),'');

  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then
    raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023';
  end if;
  if new.reason_code is null or char_length(new.reason_code)<3 then
    raise exception 'POS_REVERSAL_REASON_REQUIRED' using errcode='22023';
  end if;

  select * into v_existing
  from public.pos_cash_reversal_commands
  where idempotency_key=new.idempotency_key
  limit 1;

  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.original_sales_transaction_id=new.original_sales_transaction_id
       and v_existing.refund_pos_shift_id=new.refund_pos_shift_id
       and v_existing.reason_code=new.reason_code then
      return null;
    end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_sale
  from public.sales_transactions
  where id=new.original_sales_transaction_id
  for update;

  if v_sale.id is null or v_sale.sale_type<>'POS' then
    raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002';
  end if;
  if v_sale.status<>'COMPLETED' then
    raise exception 'POS_COMPLETED_SALE_REQUIRED' using errcode='22023';
  end if;
  if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then
    raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501';
  end if;
  if v_sale.payment_intent_id is null or v_sale.inventory_movement_id is null or v_sale.journal_entry_id is null then
    raise exception 'POS_COMPLETION_LINKS_REQUIRED' using errcode='22023';
  end if;

  if exists (
    select 1 from public.sales_returns sr
    where sr.original_sale_id=v_sale.id
      and sr.status in ('PENDING_APPROVAL','APPROVED','RECEIVING','POSTED')
  ) then
    raise exception 'POS_SALE_ALREADY_REVERSED_OR_RETURNING' using errcode='23505';
  end if;

  select * into v_refund_shift
  from public.pos_shifts
  where id=new.refund_pos_shift_id
  for update;

  if v_refund_shift.id is null or v_refund_shift.status<>'OPEN' then
    raise exception 'POS_REFUND_OPEN_SHIFT_REQUIRED' using errcode='42501';
  end if;
  if v_refund_shift.organization_id<>v_sale.organization_id
     or v_refund_shift.organization_node_id<>v_sale.organization_node_id
     or v_refund_shift.organization_unit_id<>v_sale.organization_unit_id then
    raise exception 'POS_REFUND_SHIFT_SCOPE_MISMATCH' using errcode='42501';
  end if;

  select * into v_original_cash
  from public.pos_cash_movements
  where sales_transaction_id=v_sale.id
    and movement_type='CASH_SALE'
    and direction='IN'
    and status='POSTED'
  order by created_at asc
  limit 1;

  if v_original_cash.id is null or v_original_cash.amount<>v_sale.total_amount then
    raise exception 'POS_ORIGINAL_CASH_MOVEMENT_REQUIRED' using errcode='22023';
  end if;

  select * into v_original_inventory
  from public.inventory_movements
  where id=v_sale.inventory_movement_id and status='POSTED';
  if v_original_inventory.id is null or v_original_inventory.movement_type<>'SALE_ISSUE' then
    raise exception 'POS_ORIGINAL_INVENTORY_MOVEMENT_REQUIRED' using errcode='22023';
  end if;

  select * into v_original_journal
  from public.journal_entries
  where id=v_sale.journal_entry_id and status='POSTED';
  if v_original_journal.id is null then
    raise exception 'POS_ORIGINAL_POSTED_JOURNAL_REQUIRED' using errcode='22023';
  end if;

  select * into v_original_intent
  from public.payment_intents
  where id=v_sale.payment_intent_id and status='SETTLED';
  if v_original_intent.id is null then
    raise exception 'POS_ORIGINAL_SETTLED_PAYMENT_REQUIRED' using errcode='22023';
  end if;

  select * into v_original_attempt
  from public.payment_attempts
  where payment_intent_id=v_original_intent.id
    and channel='CASH_POS'
    and status='SETTLED'
  order by attempt_no asc
  limit 1;
  if v_original_attempt.id is null then
    raise exception 'POS_ORIGINAL_SETTLED_CASH_ATTEMPT_REQUIRED' using errcode='22023';
  end if;

  v_reason:=new.reason_code||case when new.reason_note is null then '' else ': '||new.reason_note end;
  v_return_number:='POSRET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_intent_number:='PAY-REF-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_inventory_number:='INV-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_journal_number:='JRN-REV-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.sales_returns(
    organization_id,organization_node_id,organization_unit_id,
    original_sale_id,return_number,reason_code,status,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_sale.id,v_return_number,new.reason_code,'APPROVED',v_profile.id
  ) returning id into v_return_id;

  insert into public.payment_intents(
    organization_id,organization_node_id,organization_unit_id,
    intent_number,business_purpose,source_domain,source_entity_type,source_entity_id,
    source_reference,payee_member_id,amount,currency,status,idempotency_key,
    confirmed_at,settled_at,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_intent_number,'REFUND','COMMERCIAL','SALES_RETURN',v_return_id,
    v_return_number,v_sale.customer_member_id,v_sale.total_amount,v_sale.currency,
    'SETTLED',new.idempotency_key||':refund-intent',now(),now(),v_profile.id
  ) returning id into v_refund_intent_id;

  insert into public.payment_attempts(
    payment_intent_id,organization_id,organization_node_id,organization_unit_id,
    attempt_no,channel,amount,currency,status,merchant_reference,
    confirmed_at,settled_at
  ) values (
    v_refund_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    1,'CASH_POS',v_sale.total_amount,v_sale.currency,'SETTLED',v_return_number,
    now(),now()
  ) returning id into v_refund_attempt_id;

  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,
    movement_number,movement_type,status,source_domain,source_entity_type,
    source_entity_id,source_reference,idempotency_key,correlation_id,
    reversal_of_movement_id,occurred_at,posted_at,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_original_inventory.warehouse_id,v_inventory_number,'RETURN_IN','POSTED',
    'COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    new.idempotency_key||':inventory',v_sale.correlation_id,
    v_original_inventory.id,now(),now(),v_profile.id
  ) returning id into v_inventory_id;

  insert into public.inventory_movement_lines(
    organization_id,organization_node_id,organization_unit_id,
    inventory_movement_id,line_no,inventory_item_id,uom_id,lot_id,
    from_warehouse_node_id,to_warehouse_node_id,from_stock_status,to_stock_status,
    quantity,base_quantity,unit_cost,notes
  )
  select
    l.organization_id,l.organization_node_id,l.organization_unit_id,
    v_inventory_id,l.line_no,l.inventory_item_id,l.uom_id,l.lot_id,
    null,l.from_warehouse_node_id,null,coalesce(l.from_stock_status,'AVAILABLE'),
    l.quantity,l.base_quantity,l.unit_cost,
    'Reversal of SALE_ISSUE movement '||v_original_inventory.id::text
  from public.inventory_movement_lines l
  where l.inventory_movement_id=v_original_inventory.id
  order by l.line_no;

  insert into public.journal_entries(
    organization_id,organization_node_id,accounting_period_id,journal_number,
    entry_date,description,source_domain,source_entity_type,source_entity_id,
    source_reference,correlation_id,idempotency_key,reversal_of_entry_id,status,
    created_by,validated_by,validated_at,posted_by,posted_at
  ) values (
    v_original_journal.organization_id,v_original_journal.organization_node_id,
    v_original_journal.accounting_period_id,v_journal_number,current_date,
    'POS cash sale reversal '||coalesce(v_sale.sale_number,v_sale.id::text),
    'COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    coalesce(v_original_journal.correlation_id,v_sale.correlation_id::text),
    new.idempotency_key||':journal',v_original_journal.id,'POSTED',
    v_profile.id,v_profile.id,now(),v_profile.id,now()
  ) returning id into v_journal_id;

  insert into public.journal_lines(
    journal_entry_id,organization_id,organization_node_id,line_no,account_id,
    debit,credit,memo,subledger_type,subledger_id,dimensions
  )
  select
    v_journal_id,l.organization_id,l.organization_node_id,l.line_no,l.account_id,
    l.credit,l.debit,
    'Reversal: '||coalesce(l.memo,'POS sale journal line'),
    l.subledger_type,l.subledger_id,l.dimensions
  from public.journal_lines l
  where l.journal_entry_id=v_original_journal.id
  order by l.line_no;

  insert into public.pos_cash_movements(
    organization_id,organization_node_id,organization_unit_id,pos_shift_id,
    sales_transaction_id,payment_intent_id,payment_attempt_id,movement_type,
    direction,amount,currency,status,reversal_of_movement_id,reason,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_refund_shift.id,v_sale.id,v_refund_intent_id,v_refund_attempt_id,
    'CASH_REFUND','OUT',v_sale.total_amount,v_sale.currency,'POSTED',
    v_original_cash.id,v_reason,v_profile.id
  ) returning id into v_cash_id;

  update public.sales_returns
  set status='POSTED',
      inventory_movement_id=v_inventory_id,
      payment_intent_id=v_refund_intent_id,
      journal_entry_id=v_journal_id
  where id=v_return_id;

  update public.payment_attempts
  set status='REFUNDED'
  where id=v_original_attempt.id and status='SETTLED';

  update public.payment_intents
  set status='REFUNDED',updated_at=now()
  where id=v_original_intent.id and status='SETTLED';

  update public.sales_transactions
  set status='VOIDED',updated_at=now()
  where id=v_sale.id and status='COMPLETED';

  if not found then
    raise exception 'POS_SALE_REVERSAL_STATE_CHANGED' using errcode='40001';
  end if;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.result_sales_return_id:=v_return_id;
  new.result_refund_payment_intent_id:=v_refund_intent_id;
  new.result_refund_payment_attempt_id:=v_refund_attempt_id;
  new.result_inventory_movement_id:=v_inventory_id;
  new.result_journal_entry_id:=v_journal_id;
  new.result_cash_movement_id:=v_cash_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,
    before_data,after_data,reason
  ) values (
    v_sale.organization_id,v_profile.id,'POS_CASH_SALE_VOIDED','SALES_TRANSACTION',v_sale.id,
    jsonb_build_object('status','COMPLETED','sale_number',v_sale.sale_number,'total_amount',v_sale.total_amount),
    jsonb_build_object(
      'status','VOIDED',
      'sales_return_id',v_return_id,
      'refund_payment_intent_id',v_refund_intent_id,
      'inventory_reversal_id',v_inventory_id,
      'journal_reversal_id',v_journal_id,
      'cash_refund_id',v_cash_id
    ),
    v_reason
  );

  return new;
end;
$$;

revoke all on function app_private.pos_cash_reversal_before_insert() from public,anon,authenticated;

drop trigger if exists trg_pos_cash_reversal_before_insert on public.pos_cash_reversal_commands;
create trigger trg_pos_cash_reversal_before_insert
before insert on public.pos_cash_reversal_commands
for each row execute function app_private.pos_cash_reversal_before_insert();

create or replace function public.reverse_cash_pos_sale(
  p_sales_transaction_id uuid,
  p_refund_pos_shift_id uuid,
  p_reason_code text,
  p_idempotency_key text,
  p_reason_note text default null
)
returns table(
  sales_return_id uuid,
  refund_payment_intent_id uuid,
  refund_payment_attempt_id uuid,
  inventory_movement_id uuid,
  journal_entry_id uuid,
  cash_movement_id uuid
)
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_command public.pos_cash_reversal_commands%rowtype;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;

  if v_profile.id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;

  insert into public.pos_cash_reversal_commands(
    original_sales_transaction_id,refund_pos_shift_id,reason_code,reason_note,
    idempotency_key,requested_by
  ) values (
    p_sales_transaction_id,p_refund_pos_shift_id,p_reason_code,p_reason_note,
    p_idempotency_key,v_profile.id
  )
  returning * into v_command;

  if v_command.id is null then
    select * into v_command
    from public.pos_cash_reversal_commands
    where idempotency_key=p_idempotency_key
      and requested_by=v_profile.id
      and original_sales_transaction_id=p_sales_transaction_id
    limit 1;
  end if;

  if v_command.result_sales_return_id is null then
    raise exception 'POS_CASH_REVERSAL_NOT_COMPLETED' using errcode='P0001';
  end if;

  return query select
    v_command.result_sales_return_id,
    v_command.result_refund_payment_intent_id,
    v_command.result_refund_payment_attempt_id,
    v_command.result_inventory_movement_id,
    v_command.result_journal_entry_id,
    v_command.result_cash_movement_id;
end;
$$;

revoke all on function public.reverse_cash_pos_sale(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.reverse_cash_pos_sale(uuid,uuid,text,text,text) to authenticated,service_role;

-- Required validation before promotion to migration:
-- * clean replay in disposable Supabase
-- * positive full reversal with all records created exactly once
-- * retry with same idempotency key creates no duplicate
-- * second independent reversal key for same sale is rejected
-- * non-COMPLETED sale rejected
-- * non-CASH_POS sale/payment rejected
-- * missing/closed refund shift rejected
-- * wrong scope rejected
-- * missing SALES_VOID rejected
-- * original sale/lines/receipt/journal/inventory/cash rows remain byte-identical
-- * reversing journal is balanced and debit/credit are exact mirrors
-- * RETURN_IN lines exactly reverse the original SALE_ISSUE quantities/lots/costs
-- * refund cash movement is OUT for exact sale total and linked to original CASH_SALE
-- * original payment moves SETTLED -> REFUNDED only after all reversal legs succeed
-- * test transaction ROLLBACK leaves persistent business state unchanged
-- * Security Advisor adds no new finding
-- * every new FK has a covering index
