-- REVIEW DRAFT ONLY / NOT A MIGRATION
-- POS CASH Reversal hardening layer.
-- Apply only in a disposable local Supabase replay together with
-- database/drafts/pos_cash_reversal_controlled_flow.sql.
-- Do not apply directly to DEVELOPMENT or production.

create table public.pos_refund_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  sales_return_id uuid not null unique references public.sales_returns(id) on delete restrict,
  original_sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  original_receipt_id uuid not null references public.pos_receipts(id) on delete restrict,
  refund_pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  refund_payment_intent_id uuid not null references public.payment_intents(id) on delete restrict,
  refund_payment_attempt_id uuid not null references public.payment_attempts(id) on delete restrict,
  cash_movement_id uuid not null references public.pos_cash_movements(id) on delete restrict,
  refund_number text not null,
  currency text not null default 'IDR',
  refund_amount numeric(20,2) not null check (refund_amount > 0),
  reason_code text not null,
  reason_note text,
  payload jsonb not null default '{}'::jsonb,
  issued_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_node_id,refund_number)
);

alter table public.pos_cash_reversal_commands
  add column result_refund_receipt_id uuid references public.pos_refund_receipts(id) on delete restrict;

create index idx_pos_refund_receipts_scope
  on public.pos_refund_receipts(organization_id,organization_node_id,organization_unit_id,issued_at desc);
create index idx_pos_refund_receipts_original_sale
  on public.pos_refund_receipts(original_sales_transaction_id);
create index idx_pos_refund_receipts_original_receipt
  on public.pos_refund_receipts(original_receipt_id);
create index idx_pos_refund_receipts_shift
  on public.pos_refund_receipts(refund_pos_shift_id,issued_at desc);
create index idx_pos_refund_receipts_terminal
  on public.pos_refund_receipts(terminal_id,issued_at desc);
create index idx_pos_refund_receipts_payment_intent
  on public.pos_refund_receipts(refund_payment_intent_id);
create index idx_pos_refund_receipts_payment_attempt
  on public.pos_refund_receipts(refund_payment_attempt_id);
create index idx_pos_refund_receipts_cash
  on public.pos_refund_receipts(cash_movement_id);
create index idx_pos_refund_receipts_created_by
  on public.pos_refund_receipts(created_by);
create index idx_pos_cash_reversal_refund_receipt
  on public.pos_cash_reversal_commands(result_refund_receipt_id);

alter table public.pos_refund_receipts enable row level security;
revoke all on public.pos_refund_receipts from public,anon,authenticated;
grant select on public.pos_refund_receipts to authenticated;
grant all on public.pos_refund_receipts to service_role;

create policy pos_refund_receipts_read on public.pos_refund_receipts
for select to authenticated
using (
  public.has_permission('SALES_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

drop policy if exists pos_cash_reversal_insert on public.pos_cash_reversal_commands;
create policy pos_cash_reversal_insert on public.pos_cash_reversal_commands
for insert to authenticated
with check (
  public.has_permission('SALES_VOID')
  and public.has_permission('POS_SHIFT_MANAGE')
  and exists (
    select 1
    from public.profiles p
    where p.id=requested_by
      and p.auth_user_id=(select auth.uid())
      and p.status='ACTIVE'
  )
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

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
  v_refund_terminal public.pos_terminals%rowtype;
  v_original_cash public.pos_cash_movements%rowtype;
  v_original_inventory public.inventory_movements%rowtype;
  v_original_journal public.journal_entries%rowtype;
  v_original_intent public.payment_intents%rowtype;
  v_original_attempt public.payment_attempts%rowtype;
  v_original_allocation public.payment_allocations%rowtype;
  v_original_receipt public.pos_receipts%rowtype;
  v_period public.accounting_periods%rowtype;
  v_existing public.pos_cash_reversal_commands%rowtype;
  v_return_id uuid;
  v_refund_intent_id uuid;
  v_refund_attempt_id uuid;
  v_inventory_id uuid;
  v_journal_id uuid;
  v_cash_id uuid;
  v_refund_receipt_id uuid;
  v_return_number text;
  v_intent_number text;
  v_inventory_number text;
  v_journal_number text;
  v_refund_number text;
  v_reason text;
  v_drawer_available numeric(20,2);
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
  if not public.has_permission('POS_SHIFT_MANAGE') then
    raise exception 'POS_SHIFT_MANAGE_DENIED' using errcode='42501';
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
  if new.reason_note is not null and char_length(new.reason_note)>500 then
    raise exception 'POS_REVERSAL_NOTE_TOO_LONG' using errcode='22023';
  end if;

  select * into v_existing
  from public.pos_cash_reversal_commands
  where idempotency_key=new.idempotency_key
  limit 1;

  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.original_sales_transaction_id=new.original_sales_transaction_id
       and v_existing.refund_pos_shift_id=new.refund_pos_shift_id
       and v_existing.reason_code=new.reason_code
       and v_existing.reason_note is not distinct from new.reason_note then
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
    select 1
    from public.sales_returns sr
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
  if v_refund_shift.cashier_profile_id<>v_profile.id then
    raise exception 'POS_REFUND_OWN_SHIFT_REQUIRED' using errcode='42501';
  end if;
  if v_refund_shift.organization_id<>v_sale.organization_id
     or v_refund_shift.organization_node_id<>v_sale.organization_node_id
     or v_refund_shift.organization_unit_id<>v_sale.organization_unit_id then
    raise exception 'POS_REFUND_SHIFT_SCOPE_MISMATCH' using errcode='42501';
  end if;

  select * into v_refund_terminal
  from public.pos_terminals
  where id=v_refund_shift.terminal_id and status='ACTIVE';
  if v_refund_terminal.id is null then
    raise exception 'POS_REFUND_TERMINAL_NOT_ACTIVE' using errcode='22023';
  end if;

  select round(
    v_refund_shift.opening_cash
    + coalesce(sum(case when pcm.direction='IN' then pcm.amount else -pcm.amount end),0),
    2
  ) into v_drawer_available
  from public.pos_cash_movements pcm
  where pcm.pos_shift_id=v_refund_shift.id and pcm.status='POSTED';

  if v_drawer_available<v_sale.total_amount then
    raise exception 'POS_REFUND_CASH_INSUFFICIENT' using errcode='22023';
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

  if v_original_cash.payment_intent_id is distinct from v_original_intent.id
     or v_original_cash.payment_attempt_id is distinct from v_original_attempt.id then
    raise exception 'POS_ORIGINAL_PAYMENT_CASH_LINK_MISMATCH' using errcode='22023';
  end if;

  select * into v_original_allocation
  from public.payment_allocations
  where payment_intent_id=v_original_intent.id
    and target_type='SALE'
    and target_id=v_sale.id
    and status='ALLOCATED'
  order by allocation_no asc
  limit 1;
  if v_original_allocation.id is null or v_original_allocation.amount<>v_sale.total_amount then
    raise exception 'POS_ORIGINAL_PAYMENT_ALLOCATION_REQUIRED' using errcode='22023';
  end if;

  select * into v_original_receipt
  from public.pos_receipts
  where sales_transaction_id=v_sale.id
    and payment_intent_id=v_original_intent.id
    and payment_attempt_id=v_original_attempt.id
  limit 1;
  if v_original_receipt.id is null or v_original_receipt.total_amount<>v_sale.total_amount then
    raise exception 'POS_ORIGINAL_RECEIPT_REQUIRED' using errcode='22023';
  end if;

  select * into v_period
  from public.accounting_periods
  where organization_id=v_sale.organization_id
    and organization_node_id=v_sale.organization_node_id
    and current_date between start_date and end_date
    and status='OPEN'
  order by start_date desc
  limit 1;
  if v_period.id is null then
    raise exception 'POS_ACCOUNTING_PERIOD_NOT_OPEN' using errcode='22023';
  end if;

  v_reason:=new.reason_code||case when new.reason_note is null then '' else ': '||new.reason_note end;
  v_return_number:='POSRET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_intent_number:='PAY-REF-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_inventory_number:='INV-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_journal_number:='JRN-REV-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_refund_number:='RFD-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

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
    source_reference,payee_member_id,amount,currency,status,idempotency_key,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_intent_number,'REFUND','COMMERCIAL','SALES_RETURN',v_return_id,
    v_return_number,v_sale.customer_member_id,v_sale.total_amount,v_sale.currency,
    'CREATED',new.idempotency_key||':refund-intent',v_profile.id
  ) returning id into v_refund_intent_id;

  insert into public.payment_attempts(
    payment_intent_id,organization_id,organization_node_id,organization_unit_id,
    attempt_no,channel,amount,currency,status,merchant_reference
  ) values (
    v_refund_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    1,'CASH_POS',v_sale.total_amount,v_sale.currency,'CREATED',v_return_number
  ) returning id into v_refund_attempt_id;

  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,
    movement_number,movement_type,status,source_domain,source_entity_type,
    source_entity_id,source_reference,idempotency_key,correlation_id,
    reversal_of_movement_id,occurred_at,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_original_inventory.warehouse_id,v_inventory_number,'RETURN_IN','DRAFT',
    'COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    new.idempotency_key||':inventory',v_sale.correlation_id,
    v_original_inventory.id,now(),v_profile.id
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
    'Exact reversal of SALE_ISSUE movement '||v_original_inventory.id::text
  from public.inventory_movement_lines l
  where l.inventory_movement_id=v_original_inventory.id
  order by l.line_no;

  if not exists(select 1 from public.inventory_movement_lines where inventory_movement_id=v_inventory_id) then
    raise exception 'POS_ORIGINAL_INVENTORY_LINES_REQUIRED' using errcode='22023';
  end if;

  insert into public.journal_entries(
    organization_id,organization_node_id,accounting_period_id,journal_number,
    entry_date,description,source_domain,source_entity_type,source_entity_id,
    source_reference,correlation_id,idempotency_key,reversal_of_entry_id,status,created_by
  ) values (
    v_original_journal.organization_id,v_original_journal.organization_node_id,
    v_period.id,v_journal_number,current_date,
    'POS cash sale reversal '||coalesce(v_sale.sale_number,v_sale.id::text),
    'COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    coalesce(v_original_journal.correlation_id,v_sale.correlation_id::text),
    new.idempotency_key||':journal',v_original_journal.id,'DRAFT',v_profile.id
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

  if not exists(select 1 from public.journal_lines where journal_entry_id=v_journal_id) then
    raise exception 'POS_ORIGINAL_JOURNAL_LINES_REQUIRED' using errcode='22023';
  end if;

  update public.journal_entries set status='VALIDATED' where id=v_journal_id and status='DRAFT';
  if not found then raise exception 'POS_REVERSAL_JOURNAL_VALIDATE_FAILED' using errcode='55000'; end if;
  update public.journal_entries set status='POSTED' where id=v_journal_id and status='VALIDATED';
  if not found then raise exception 'POS_REVERSAL_JOURNAL_POST_FAILED' using errcode='55000'; end if;

  update public.inventory_movements
  set journal_entry_id=v_journal_id,status='POSTED',posted_at=now()
  where id=v_inventory_id and status='DRAFT';
  if not found then raise exception 'POS_REVERSAL_INVENTORY_POST_FAILED' using errcode='55000'; end if;

  update public.payment_intents
  set status='SETTLED',confirmed_at=now(),settled_at=now(),updated_at=now()
  where id=v_refund_intent_id and status='CREATED';
  if not found then raise exception 'POS_REFUND_PAYMENT_SETTLE_FAILED' using errcode='55000'; end if;
  update public.payment_attempts
  set status='SETTLED',confirmed_at=now(),settled_at=now()
  where id=v_refund_attempt_id and status='CREATED';
  if not found then raise exception 'POS_REFUND_PAYMENT_ATTEMPT_SETTLE_FAILED' using errcode='55000'; end if;

  insert into public.payment_allocations(
    payment_intent_id,organization_id,organization_node_id,organization_unit_id,
    allocation_no,target_type,target_id,target_reference,amount,status,allocated_at
  ) values (
    v_refund_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    1,'SALE',v_sale.id,v_return_number,v_sale.total_amount,'ALLOCATED',now()
  );

  insert into public.pos_cash_movements(
    organization_id,organization_node_id,organization_unit_id,pos_shift_id,
    sales_transaction_id,payment_intent_id,payment_attempt_id,movement_type,
    direction,amount,currency,status,reversal_of_movement_id,reason,occurred_at,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_refund_shift.id,v_sale.id,v_refund_intent_id,v_refund_attempt_id,
    'CASH_REFUND','OUT',v_sale.total_amount,v_sale.currency,'POSTED',
    v_original_cash.id,v_reason,now(),v_profile.id
  ) returning id into v_cash_id;

  insert into public.pos_refund_receipts(
    organization_id,organization_node_id,organization_unit_id,
    sales_return_id,original_sales_transaction_id,original_receipt_id,
    refund_pos_shift_id,terminal_id,refund_payment_intent_id,refund_payment_attempt_id,
    cash_movement_id,refund_number,currency,refund_amount,reason_code,reason_note,
    payload,issued_at,created_by
  ) values (
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
    v_return_id,v_sale.id,v_original_receipt.id,
    v_refund_shift.id,v_refund_terminal.id,v_refund_intent_id,v_refund_attempt_id,
    v_cash_id,v_refund_number,v_sale.currency,v_sale.total_amount,new.reason_code,new.reason_note,
    jsonb_build_object(
      'refund_number',v_refund_number,
      'return_number',v_return_number,
      'original_sale_number',v_sale.sale_number,
      'original_receipt_number',v_original_receipt.receipt_number,
      'refund_amount',v_sale.total_amount,
      'currency',v_sale.currency,
      'inventory_reversal_id',v_inventory_id,
      'journal_reversal_id',v_journal_id,
      'cash_refund_id',v_cash_id,
      'issued_at',now()
    ),
    now(),v_profile.id
  ) returning id into v_refund_receipt_id;

  update public.sales_returns
  set status='POSTED',
      inventory_movement_id=v_inventory_id,
      payment_intent_id=v_refund_intent_id,
      journal_entry_id=v_journal_id
  where id=v_return_id and status='APPROVED';
  if not found then raise exception 'POS_SALES_RETURN_POST_FAILED' using errcode='55000'; end if;

  update public.payment_allocations
  set status='REVERSED'
  where id=v_original_allocation.id and status='ALLOCATED';
  if not found then raise exception 'POS_ORIGINAL_ALLOCATION_REVERSE_FAILED' using errcode='55000'; end if;

  update public.payment_attempts
  set status='REFUNDED'
  where id=v_original_attempt.id and status='SETTLED';
  if not found then raise exception 'POS_ORIGINAL_PAYMENT_ATTEMPT_REFUND_FAILED' using errcode='55000'; end if;

  update public.payment_intents
  set status='REFUNDED',updated_at=now()
  where id=v_original_intent.id and status='SETTLED';
  if not found then raise exception 'POS_ORIGINAL_PAYMENT_REFUND_FAILED' using errcode='55000'; end if;

  update public.sales_transactions
  set status='VOIDED',updated_at=now()
  where id=v_sale.id and status='COMPLETED';
  if not found then raise exception 'POS_SALE_REVERSAL_STATE_CHANGED' using errcode='40001'; end if;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.result_sales_return_id:=v_return_id;
  new.result_refund_payment_intent_id:=v_refund_intent_id;
  new.result_refund_payment_attempt_id:=v_refund_attempt_id;
  new.result_inventory_movement_id:=v_inventory_id;
  new.result_journal_entry_id:=v_journal_id;
  new.result_cash_movement_id:=v_cash_id;
  new.result_refund_receipt_id:=v_refund_receipt_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,
    before_data,after_data,reason
  ) values (
    v_sale.organization_id,v_profile.id,'POS_CASH_SALE_VOIDED','SALES_TRANSACTION',v_sale.id,
    jsonb_build_object(
      'status','COMPLETED',
      'sale_number',v_sale.sale_number,
      'total_amount',v_sale.total_amount,
      'payment_status','SETTLED'
    ),
    jsonb_build_object(
      'status','VOIDED',
      'sales_return_id',v_return_id,
      'refund_payment_intent_id',v_refund_intent_id,
      'inventory_reversal_id',v_inventory_id,
      'journal_reversal_id',v_journal_id,
      'cash_refund_id',v_cash_id,
      'refund_receipt_id',v_refund_receipt_id,
      'refund_number',v_refund_number
    ),
    v_reason
  );

  return new;
end;
$$;

revoke all on function app_private.pos_cash_reversal_before_insert() from public,anon,authenticated;

-- Hardening invariants added by this layer:
-- * actor must hold SALES_VOID + POS_SHIFT_MANAGE;
-- * refund cash must leave the actor's own OPEN shift;
-- * tracked drawer cash must cover the refund amount;
-- * active refund terminal is required;
-- * original payment allocation and receipt must match the sale;
-- * reversal posts into the current OPEN accounting period;
-- * inventory and journal are created DRAFT and use normal controlled transitions;
-- * original payment allocation is marked REVERSED only after all new reversal legs exist;
-- * an authoritative refund receipt is created;
-- * no role mapping is added here.
