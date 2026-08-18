-- POS CASH controlled partial return/refund foundation
--
-- Scope:
-- * repeated partial returns against one COMPLETED CASH_POS sale;
-- * cumulative quantity and monetary guards;
-- * append-only sales_return, refund payment, RETURN_IN inventory, reversing journal,
--   CASH_REFUND, refund receipt and audit evidence;
-- * the original sale remains COMPLETED while any quantity remains returnable and
--   becomes RETURNED only after every sale line has been fully returned;
-- * original payment/allocation remains settled/allocated during partial state and
--   becomes REFUNDED/REVERSED only when cumulative returns fully cover the sale;
-- * SALES_RETURN remains privileged and this migration grants it to no baseline role.

create table public.pos_partial_return_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  original_sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  refund_pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  requested_lines jsonb not null check (jsonb_typeof(requested_lines)='array'),
  reason_code text not null check (char_length(trim(reason_code)) between 3 and 80),
  reason_note text,
  idempotency_key text not null unique check (char_length(idempotency_key) between 8 and 200),
  refund_amount numeric(20,2) check (refund_amount is null or refund_amount > 0),
  sale_fully_returned boolean not null default false,
  original_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  original_payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  original_cash_movement_id uuid references public.pos_cash_movements(id) on delete restrict,
  original_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  original_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  result_sales_return_id uuid references public.sales_returns(id) on delete restrict,
  result_refund_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  result_refund_payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  result_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  result_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  result_cash_movement_id uuid references public.pos_cash_movements(id) on delete restrict,
  result_refund_receipt_id uuid references public.pos_refund_receipts(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (reason_note is null or char_length(reason_note) <= 500)
);

create table public.pos_partial_return_lines (
  id uuid primary key default gen_random_uuid(),
  command_id uuid not null references public.pos_partial_return_commands(id) on delete restrict deferrable initially deferred,
  sales_return_id uuid not null references public.sales_returns(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  original_sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  original_sales_transaction_line_id uuid not null references public.sales_transaction_lines(id) on delete restrict,
  quantity numeric(20,6) not null check (quantity > 0),
  base_quantity numeric(20,6) not null check (base_quantity > 0),
  gross_amount numeric(20,2) not null check (gross_amount >= 0),
  discount_amount numeric(20,2) not null check (discount_amount >= 0),
  tax_amount numeric(20,2) not null check (tax_amount >= 0),
  refund_amount numeric(20,2) not null check (refund_amount > 0),
  cost_amount numeric(20,2) not null check (cost_amount >= 0),
  created_at timestamptz not null default now(),
  unique (sales_return_id,original_sales_transaction_line_id)
);

create table public.pos_partial_return_inventory_links (
  id uuid primary key default gen_random_uuid(),
  partial_return_line_id uuid not null references public.pos_partial_return_lines(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  original_inventory_movement_line_id uuid not null references public.inventory_movement_lines(id) on delete restrict,
  return_inventory_movement_line_id uuid not null references public.inventory_movement_lines(id) on delete restrict,
  quantity numeric(20,6) not null check (quantity > 0),
  base_quantity numeric(20,6) not null check (base_quantity > 0),
  unit_cost numeric(20,6) not null check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  unique (return_inventory_movement_line_id)
);

create index idx_pos_partial_return_sale on public.pos_partial_return_commands(original_sales_transaction_id,created_at desc);
create index idx_pos_partial_return_shift on public.pos_partial_return_commands(refund_pos_shift_id,created_at desc);
create index idx_pos_partial_return_requested_by on public.pos_partial_return_commands(requested_by,created_at desc);
create index idx_pos_partial_return_result_return on public.pos_partial_return_commands(result_sales_return_id);
create index idx_pos_partial_return_lines_sale_line on public.pos_partial_return_lines(original_sales_transaction_line_id,created_at);
create index idx_pos_partial_return_lines_sale on public.pos_partial_return_lines(original_sales_transaction_id,created_at);
create index idx_pos_partial_return_inventory_source on public.pos_partial_return_inventory_links(original_inventory_movement_line_id,created_at);

alter table public.pos_partial_return_commands enable row level security;
alter table public.pos_partial_return_lines enable row level security;
alter table public.pos_partial_return_inventory_links enable row level security;

revoke all on public.pos_partial_return_commands,public.pos_partial_return_lines,public.pos_partial_return_inventory_links from public,anon,authenticated;
grant select,insert on public.pos_partial_return_commands to authenticated;
grant select on public.pos_partial_return_lines,public.pos_partial_return_inventory_links to authenticated;
grant all on public.pos_partial_return_commands,public.pos_partial_return_lines,public.pos_partial_return_inventory_links to service_role;

create policy pos_partial_return_command_read_own on public.pos_partial_return_commands
for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
  )
);

create policy pos_partial_return_command_insert on public.pos_partial_return_commands
for insert to authenticated
with check (
  public.has_permission('SALES_RETURN')
  and public.has_permission('POS_SHIFT_MANAGE')
  and exists (
    select 1 from public.profiles p
    where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
  )
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_partial_return_lines_read on public.pos_partial_return_lines
for select to authenticated
using (
  public.has_permission('SALES_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_partial_return_inventory_links_read on public.pos_partial_return_inventory_links
for select to authenticated
using (
  public.has_permission('SALES_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create or replace function app_private.pos_partial_return_before_insert()
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
  v_original_intent public.payment_intents%rowtype;
  v_original_attempt public.payment_attempts%rowtype;
  v_original_allocation public.payment_allocations%rowtype;
  v_original_cash public.pos_cash_movements%rowtype;
  v_original_inventory public.inventory_movements%rowtype;
  v_original_journal public.journal_entries%rowtype;
  v_original_receipt public.pos_receipts%rowtype;
  v_period public.accounting_periods%rowtype;
  v_existing public.pos_partial_return_commands%rowtype;
  v_requested jsonb;
  v_row record;
  v_line record;
  v_source record;
  v_return_id uuid;
  v_partial_line_id uuid;
  v_refund_intent_id uuid;
  v_refund_attempt_id uuid;
  v_inventory_id uuid;
  v_return_inventory_line_id uuid;
  v_journal_id uuid;
  v_cash_id uuid;
  v_refund_receipt_id uuid;
  v_return_number text;
  v_intent_number text;
  v_inventory_number text;
  v_journal_number text;
  v_refund_number text;
  v_reason text;
  v_factor numeric;
  v_requested_qty numeric;
  v_previous_qty numeric;
  v_remaining_qty numeric;
  v_previous_gross numeric;
  v_previous_discount numeric;
  v_previous_tax numeric;
  v_previous_refund numeric;
  v_line_gross numeric(20,2);
  v_line_discount numeric(20,2);
  v_line_tax numeric(20,2);
  v_line_refund numeric(20,2);
  v_line_cost numeric(20,2);
  v_required_base numeric;
  v_base_remaining numeric;
  v_source_returned numeric;
  v_source_available numeric;
  v_take numeric;
  v_return_inventory_line_no integer:=0;
  v_refund_total numeric(20,2):=0;
  v_net_revenue_total numeric(20,2):=0;
  v_tax_total numeric(20,2):=0;
  v_cost_total numeric(20,2):=0;
  v_drawer_available numeric(20,2);
  v_cash_account_id uuid;
  v_sales_account_id uuid;
  v_tax_account_id uuid;
  v_cogs_account_id uuid;
  v_inventory_account_id uuid;
  v_journal_line_no integer:=0;
  v_all_returned boolean:=false;
  v_payload_lines jsonb;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('SALES_RETURN') then raise exception 'SALES_RETURN_DENIED' using errcode='42501'; end if;
  if not public.has_permission('POS_SHIFT_MANAGE') then raise exception 'POS_SHIFT_MANAGE_DENIED' using errcode='42501'; end if;

  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  new.reason_code:=upper(nullif(trim(new.reason_code),''));
  new.reason_note:=nullif(trim(new.reason_note),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  if new.reason_code is null or char_length(new.reason_code)<3 then raise exception 'POS_RETURN_REASON_REQUIRED' using errcode='22023'; end if;
  if new.reason_note is not null and char_length(new.reason_note)>500 then raise exception 'POS_RETURN_NOTE_TOO_LONG' using errcode='22023'; end if;
  if jsonb_typeof(new.requested_lines)<>'array' or jsonb_array_length(new.requested_lines)=0 or jsonb_array_length(new.requested_lines)>100 then
    raise exception 'POS_RETURN_LINES_REQUIRED' using errcode='22023';
  end if;

  begin
    select jsonb_agg(
      jsonb_build_object('sales_transaction_line_id',x.line_id,'quantity',x.qty)
      order by x.line_id::text
    ) into v_requested
    from (
      select (e->>'sales_transaction_line_id')::uuid as line_id,(e->>'quantity')::numeric as qty
      from jsonb_array_elements(new.requested_lines) e
    ) x;
  exception when others then
    raise exception 'POS_RETURN_LINES_INVALID' using errcode='22023';
  end;

  if exists (
    select 1 from (
      select (e->>'sales_transaction_line_id')::uuid as line_id,count(*)
      from jsonb_array_elements(v_requested) e
      group by 1 having count(*)>1
    ) d
  ) then raise exception 'POS_RETURN_DUPLICATE_LINE' using errcode='22023'; end if;
  if exists (
    select 1 from jsonb_array_elements(v_requested) e
    where (e->>'quantity')::numeric<=0
  ) then raise exception 'POS_RETURN_QUANTITY_INVALID' using errcode='22023'; end if;
  new.requested_lines:=v_requested;

  select * into v_existing
  from public.pos_partial_return_commands
  where idempotency_key=new.idempotency_key
  limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.original_sales_transaction_id=new.original_sales_transaction_id
       and v_existing.refund_pos_shift_id=new.refund_pos_shift_id
       and v_existing.reason_code=new.reason_code
       and v_existing.reason_note is not distinct from new.reason_note
       and v_existing.requested_lines=v_requested then
      return null;
    end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_sale
  from public.sales_transactions
  where id=new.original_sales_transaction_id
  for update;
  if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
  if v_sale.status<>'COMPLETED' then raise exception 'POS_COMPLETED_SALE_REQUIRED' using errcode='22023'; end if;
  if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then
    raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501';
  end if;
  if v_sale.payment_intent_id is null or v_sale.inventory_movement_id is null or v_sale.journal_entry_id is null then
    raise exception 'POS_COMPLETION_LINKS_REQUIRED' using errcode='22023';
  end if;

  select * into v_shift from public.pos_shifts where id=new.refund_pos_shift_id for update;
  if v_shift.id is null or v_shift.status<>'OPEN' then raise exception 'POS_REFUND_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
  if v_shift.cashier_profile_id<>v_profile.id then raise exception 'POS_REFUND_OWN_SHIFT_REQUIRED' using errcode='42501'; end if;
  if v_shift.organization_id<>v_sale.organization_id or v_shift.organization_node_id<>v_sale.organization_node_id or v_shift.organization_unit_id<>v_sale.organization_unit_id then
    raise exception 'POS_REFUND_SHIFT_SCOPE_MISMATCH' using errcode='42501';
  end if;
  select * into v_terminal from public.pos_terminals where id=v_shift.terminal_id and status='ACTIVE';
  if v_terminal.id is null then raise exception 'POS_REFUND_TERMINAL_NOT_ACTIVE' using errcode='22023'; end if;

  select * into v_original_intent from public.payment_intents where id=v_sale.payment_intent_id and status='SETTLED';
  if v_original_intent.id is null then raise exception 'POS_ORIGINAL_SETTLED_PAYMENT_REQUIRED' using errcode='22023'; end if;
  select * into v_original_attempt
  from public.payment_attempts
  where payment_intent_id=v_original_intent.id and channel='CASH_POS' and status='SETTLED'
  order by attempt_no asc limit 1;
  if v_original_attempt.id is null then raise exception 'POS_ORIGINAL_SETTLED_CASH_ATTEMPT_REQUIRED' using errcode='22023'; end if;
  select * into v_original_allocation
  from public.payment_allocations
  where payment_intent_id=v_original_intent.id and target_type='SALE' and target_id=v_sale.id and status='ALLOCATED'
  order by allocation_no asc limit 1;
  if v_original_allocation.id is null or v_original_allocation.amount<>v_sale.total_amount then raise exception 'POS_ORIGINAL_PAYMENT_ALLOCATION_REQUIRED' using errcode='22023'; end if;
  select * into v_original_cash
  from public.pos_cash_movements
  where sales_transaction_id=v_sale.id and movement_type='CASH_SALE' and direction='IN' and status='POSTED'
  order by created_at asc limit 1;
  if v_original_cash.id is null or v_original_cash.amount<>v_sale.total_amount
     or v_original_cash.payment_intent_id is distinct from v_original_intent.id
     or v_original_cash.payment_attempt_id is distinct from v_original_attempt.id then
    raise exception 'POS_ORIGINAL_CASH_MOVEMENT_REQUIRED' using errcode='22023';
  end if;
  select * into v_original_inventory from public.inventory_movements where id=v_sale.inventory_movement_id and status='POSTED';
  if v_original_inventory.id is null or v_original_inventory.movement_type<>'SALE_ISSUE' then raise exception 'POS_ORIGINAL_INVENTORY_MOVEMENT_REQUIRED' using errcode='22023'; end if;
  select * into v_original_journal from public.journal_entries where id=v_sale.journal_entry_id and status='POSTED';
  if v_original_journal.id is null then raise exception 'POS_ORIGINAL_POSTED_JOURNAL_REQUIRED' using errcode='22023'; end if;
  select * into v_original_receipt
  from public.pos_receipts
  where sales_transaction_id=v_sale.id and payment_intent_id=v_original_intent.id and payment_attempt_id=v_original_attempt.id
  limit 1;
  if v_original_receipt.id is null or v_original_receipt.total_amount<>v_sale.total_amount then raise exception 'POS_ORIGINAL_RECEIPT_REQUIRED' using errcode='22023'; end if;

  select * into v_period
  from public.accounting_periods
  where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id
    and current_date between start_date and end_date and status='OPEN'
  order by start_date desc limit 1;
  if v_period.id is null then raise exception 'POS_ACCOUNTING_PERIOD_NOT_OPEN' using errcode='22023'; end if;

  select account_id into v_cash_account_id from public.journal_lines where journal_entry_id=v_original_journal.id and memo='Cash received at POS' limit 1;
  select account_id into v_sales_account_id from public.journal_lines where journal_entry_id=v_original_journal.id and memo='Retail sales revenue' limit 1;
  select account_id into v_tax_account_id from public.journal_lines where journal_entry_id=v_original_journal.id and memo='Sales tax payable' limit 1;
  select account_id into v_cogs_account_id from public.journal_lines where journal_entry_id=v_original_journal.id and memo='Cost of goods sold' limit 1;
  select account_id into v_inventory_account_id from public.journal_lines where journal_entry_id=v_original_journal.id and memo='Inventory issued for POS sale' limit 1;
  if v_cash_account_id is null or v_sales_account_id is null or v_cogs_account_id is null or v_inventory_account_id is null then
    raise exception 'POS_ORIGINAL_JOURNAL_ACCOUNTS_REQUIRED' using errcode='22023';
  end if;

  v_reason:=new.reason_code||case when new.reason_note is null then '' else ': '||new.reason_note end;
  v_return_number:='POSRET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_intent_number:='PAY-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_inventory_number:='INV-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_journal_number:='JRN-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_refund_number:='RFD-RET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.sales_returns(organization_id,organization_node_id,organization_unit_id,original_sale_id,return_number,reason_code,status,created_by)
  values(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.id,v_return_number,new.reason_code,'APPROVED',v_profile.id)
  returning id into v_return_id;

  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
    source_domain,source_entity_type,source_entity_id,source_reference,idempotency_key,correlation_id,occurred_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_original_inventory.warehouse_id,
    v_inventory_number,'RETURN_IN','DRAFT','COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    new.idempotency_key||':inventory',v_sale.correlation_id,now(),v_profile.id
  ) returning id into v_inventory_id;

  for v_row in
    select (e->>'sales_transaction_line_id')::uuid as line_id,(e->>'quantity')::numeric as qty
    from jsonb_array_elements(v_requested) e
    order by (e->>'sales_transaction_line_id')::uuid
  loop
    v_requested_qty:=v_row.qty;
    select stl.*,ii.base_uom_id into v_line
    from public.sales_transaction_lines stl
    join public.inventory_items ii on ii.id=stl.inventory_item_id
    where stl.id=v_row.line_id and stl.sales_transaction_id=v_sale.id;
    if v_line.id is null or v_line.inventory_item_id is null or v_line.uom_id is null then raise exception 'POS_RETURN_SALE_LINE_NOT_FOUND' using errcode='P0002'; end if;

    select coalesce(sum(prl.quantity),0),coalesce(sum(prl.gross_amount),0),coalesce(sum(prl.discount_amount),0),coalesce(sum(prl.tax_amount),0),coalesce(sum(prl.refund_amount),0)
    into v_previous_qty,v_previous_gross,v_previous_discount,v_previous_tax,v_previous_refund
    from public.pos_partial_return_lines prl
    join public.sales_returns sr on sr.id=prl.sales_return_id and sr.status='POSTED'
    where prl.original_sales_transaction_line_id=v_line.id;

    v_remaining_qty:=v_line.quantity-v_previous_qty;
    if v_remaining_qty<=0 then raise exception 'POS_RETURN_LINE_ALREADY_FULLY_RETURNED' using errcode='22023'; end if;
    if v_requested_qty>v_remaining_qty then raise exception 'POS_RETURN_QUANTITY_EXCEEDS_REMAINING' using errcode='22023'; end if;

    if v_line.uom_id=v_line.base_uom_id then v_factor:=1;
    else
      select factor_to_base into v_factor
      from public.inventory_item_uom_conversions
      where inventory_item_id=v_line.inventory_item_id and uom_id=v_line.uom_id and status='ACTIVE'
      limit 1;
    end if;
    if v_factor is null or v_factor<=0 then raise exception 'POS_ITEM_UOM_NOT_CONFIGURED' using errcode='22023'; end if;
    v_required_base:=v_requested_qty*v_factor;
    v_base_remaining:=v_required_base;
    v_line_cost:=0;

    if v_requested_qty=v_remaining_qty then
      v_line_gross:=round((v_line.quantity*v_line.unit_price)-v_previous_gross,2);
      v_line_discount:=round(v_line.discount_amount-v_previous_discount,2);
      v_line_tax:=round(v_line.tax_amount-v_previous_tax,2);
      v_line_refund:=round(coalesce(v_line.line_total,(v_line.quantity*v_line.unit_price-v_line.discount_amount+v_line.tax_amount))-v_previous_refund,2);
    else
      v_line_gross:=round(v_requested_qty*v_line.unit_price,2);
      v_line_discount:=round(v_line.discount_amount*(v_requested_qty/v_line.quantity),2);
      v_line_tax:=round(v_line.tax_amount*(v_requested_qty/v_line.quantity),2);
      v_line_refund:=round(v_line_gross-v_line_discount+v_line_tax,2);
    end if;
    if v_line_refund<=0 then raise exception 'POS_RETURN_REFUND_AMOUNT_INVALID' using errcode='22023'; end if;

    insert into public.pos_partial_return_lines(
      command_id,sales_return_id,organization_id,organization_node_id,organization_unit_id,
      original_sales_transaction_id,original_sales_transaction_line_id,quantity,base_quantity,
      gross_amount,discount_amount,tax_amount,refund_amount,cost_amount
    ) values(
      new.id,v_return_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
      v_sale.id,v_line.id,v_requested_qty,v_required_base,v_line_gross,v_line_discount,v_line_tax,v_line_refund,0
    ) returning id into v_partial_line_id;

    for v_source in
      select iml.*
      from public.inventory_movement_lines iml
      where iml.inventory_movement_id=v_original_inventory.id and iml.inventory_item_id=v_line.inventory_item_id
      order by iml.line_no
    loop
      exit when v_base_remaining<=0;
      select coalesce(sum(l.base_quantity),0) into v_source_returned
      from public.pos_partial_return_inventory_links l
      join public.pos_partial_return_lines prl on prl.id=l.partial_return_line_id
      join public.sales_returns sr on sr.id=prl.sales_return_id and sr.status='POSTED'
      where l.original_inventory_movement_line_id=v_source.id;
      v_source_available:=v_source.base_quantity-v_source_returned;
      if v_source_available<=0 then continue; end if;
      v_take:=least(v_base_remaining,v_source_available);
      if v_source.unit_cost is null then raise exception 'POS_RETURN_SOURCE_COST_REQUIRED' using errcode='22023'; end if;
      v_return_inventory_line_no:=v_return_inventory_line_no+1;
      insert into public.inventory_movement_lines(
        organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,
        inventory_item_id,uom_id,lot_id,to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes
      ) values(
        v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_inventory_id,v_return_inventory_line_no,
        v_source.inventory_item_id,v_source.uom_id,v_source.lot_id,v_source.from_warehouse_node_id,coalesce(v_source.from_stock_status,'AVAILABLE'),
        v_take,v_take,v_source.unit_cost,'Partial return of SALE_ISSUE line '||v_source.id::text
      ) returning id into v_return_inventory_line_id;
      insert into public.pos_partial_return_inventory_links(
        partial_return_line_id,organization_id,organization_node_id,organization_unit_id,
        original_inventory_movement_line_id,return_inventory_movement_line_id,quantity,base_quantity,unit_cost
      ) values(
        v_partial_line_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,
        v_source.id,v_return_inventory_line_id,v_take,v_take,v_source.unit_cost
      );
      v_line_cost:=v_line_cost+round(v_take*v_source.unit_cost,2);
      v_base_remaining:=v_base_remaining-v_take;
    end loop;
    if v_base_remaining>0 then raise exception 'POS_RETURN_SOURCE_INVENTORY_INSUFFICIENT' using errcode='22023'; end if;

    update public.pos_partial_return_lines set cost_amount=v_line_cost where id=v_partial_line_id;
    v_refund_total:=v_refund_total+v_line_refund;
    v_net_revenue_total:=v_net_revenue_total+(v_line_gross-v_line_discount);
    v_tax_total:=v_tax_total+v_line_tax;
    v_cost_total:=v_cost_total+v_line_cost;
  end loop;

  if v_refund_total<=0 or v_refund_total>v_sale.total_amount then raise exception 'POS_RETURN_TOTAL_INVALID' using errcode='22023'; end if;

  select round(v_shift.opening_cash+coalesce(sum(case when pcm.direction='IN' then pcm.amount else -pcm.amount end),0),2)
  into v_drawer_available
  from public.pos_cash_movements pcm
  where pcm.pos_shift_id=v_shift.id and pcm.status='POSTED';
  if v_drawer_available<v_refund_total then raise exception 'POS_REFUND_CASH_INSUFFICIENT' using errcode='22023'; end if;

  insert into public.payment_intents(
    organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,source_domain,
    source_entity_type,source_entity_id,source_reference,payee_member_id,amount,currency,status,idempotency_key,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_intent_number,'REFUND','COMMERCIAL',
    'SALES_RETURN',v_return_id,v_return_number,v_sale.customer_member_id,v_refund_total,v_sale.currency,'CREATED',
    new.idempotency_key||':refund-intent',v_profile.id
  ) returning id into v_refund_intent_id;

  insert into public.payment_attempts(
    payment_intent_id,organization_id,organization_node_id,organization_unit_id,attempt_no,channel,amount,currency,status,merchant_reference
  ) values(
    v_refund_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,1,'CASH_POS',v_refund_total,v_sale.currency,'CREATED',v_return_number
  ) returning id into v_refund_attempt_id;

  insert into public.journal_entries(
    organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,
    source_domain,source_entity_type,source_entity_id,source_reference,correlation_id,idempotency_key,status,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_period.id,v_journal_number,current_date,
    'POS partial return '||coalesce(v_sale.sale_number,v_sale.id::text),'COMMERCIAL','SALES_RETURN',v_return_id,v_return_number,
    coalesce(v_original_journal.correlation_id,v_sale.correlation_id::text),new.idempotency_key||':journal','DRAFT',v_profile.id
  ) returning id into v_journal_id;

  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_sales_account_id,v_net_revenue_total,0,'Partial return — reverse retail sales revenue',jsonb_build_object('sale_id',v_sale.id,'sales_return_id',v_return_id,'original_journal_entry_id',v_original_journal.id));
  if v_tax_total>0 then
    if v_tax_account_id is null then raise exception 'POS_ORIGINAL_TAX_JOURNAL_ACCOUNT_REQUIRED' using errcode='22023'; end if;
    v_journal_line_no:=v_journal_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_tax_account_id,v_tax_total,0,'Partial return — reverse sales tax payable',jsonb_build_object('sale_id',v_sale.id,'sales_return_id',v_return_id));
  end if;
  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_cash_account_id,0,v_refund_total,'Partial return — cash refund',jsonb_build_object('sale_id',v_sale.id,'sales_return_id',v_return_id,'pos_shift_id',v_shift.id));
  if v_cost_total>0 then
    v_journal_line_no:=v_journal_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_inventory_account_id,v_cost_total,0,'Partial return — inventory restored',jsonb_build_object('sale_id',v_sale.id,'sales_return_id',v_return_id,'inventory_movement_id',v_inventory_id));
    v_journal_line_no:=v_journal_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_cogs_account_id,0,v_cost_total,'Partial return — reverse cost of goods sold',jsonb_build_object('sale_id',v_sale.id,'sales_return_id',v_return_id));
  end if;

  update public.journal_entries set status='VALIDATED' where id=v_journal_id and status='DRAFT';
  if not found then raise exception 'POS_RETURN_JOURNAL_VALIDATE_FAILED' using errcode='55000'; end if;
  update public.journal_entries set status='POSTED',validated_by=v_profile.id,validated_at=now(),posted_by=v_profile.id,posted_at=now() where id=v_journal_id and status='VALIDATED';
  if not found then raise exception 'POS_RETURN_JOURNAL_POST_FAILED' using errcode='55000'; end if;
  update public.inventory_movements set journal_entry_id=v_journal_id,status='POSTED',posted_at=now() where id=v_inventory_id and status='DRAFT';
  if not found then raise exception 'POS_RETURN_INVENTORY_POST_FAILED' using errcode='55000'; end if;

  update public.payment_intents set status='SETTLED',confirmed_at=now(),settled_at=now(),updated_at=now() where id=v_refund_intent_id and status='CREATED';
  update public.payment_attempts set status='SETTLED',confirmed_at=now(),settled_at=now() where id=v_refund_attempt_id and status='CREATED';

  insert into public.payment_allocations(
    payment_intent_id,organization_id,organization_node_id,organization_unit_id,allocation_no,target_type,target_id,target_reference,amount,status,allocated_at
  ) values(
    v_refund_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,1,'SALE',v_sale.id,v_return_number,v_refund_total,'ALLOCATED',now()
  );

  insert into public.pos_cash_movements(
    organization_id,organization_node_id,organization_unit_id,pos_shift_id,sales_transaction_id,payment_intent_id,payment_attempt_id,
    movement_type,direction,amount,currency,status,reason,occurred_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_shift.id,v_sale.id,v_refund_intent_id,v_refund_attempt_id,
    'CASH_REFUND','OUT',v_refund_total,v_sale.currency,'POSTED',v_reason,now(),v_profile.id
  ) returning id into v_cash_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'sales_transaction_line_id',prl.original_sales_transaction_line_id,
    'quantity',prl.quantity,'refund_amount',prl.refund_amount,'cost_amount',prl.cost_amount
  ) order by prl.created_at),'[]'::jsonb) into v_payload_lines
  from public.pos_partial_return_lines prl where prl.sales_return_id=v_return_id;

  insert into public.pos_refund_receipts(
    organization_id,organization_node_id,organization_unit_id,sales_return_id,original_sales_transaction_id,original_receipt_id,
    refund_pos_shift_id,terminal_id,refund_payment_intent_id,refund_payment_attempt_id,cash_movement_id,
    refund_number,currency,refund_amount,reason_code,reason_note,payload,issued_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_return_id,v_sale.id,v_original_receipt.id,
    v_shift.id,v_terminal.id,v_refund_intent_id,v_refund_attempt_id,v_cash_id,v_refund_number,v_sale.currency,v_refund_total,
    new.reason_code,new.reason_note,jsonb_build_object('type','PARTIAL_RETURN','return_number',v_return_number,'original_sale_number',v_sale.sale_number,
    'original_receipt_number',v_original_receipt.receipt_number,'lines',v_payload_lines,'inventory_movement_id',v_inventory_id,'journal_entry_id',v_journal_id),
    now(),v_profile.id
  ) returning id into v_refund_receipt_id;

  update public.sales_returns
  set status='POSTED',inventory_movement_id=v_inventory_id,payment_intent_id=v_refund_intent_id,journal_entry_id=v_journal_id
  where id=v_return_id and status='APPROVED';
  if not found then raise exception 'POS_RETURN_POST_FAILED' using errcode='55000'; end if;

  select not exists(
    select 1
    from public.sales_transaction_lines stl
    where stl.sales_transaction_id=v_sale.id
      and coalesce((
        select sum(prl.quantity)
        from public.pos_partial_return_lines prl
        join public.sales_returns sr on sr.id=prl.sales_return_id and sr.status='POSTED'
        where prl.original_sales_transaction_line_id=stl.id
      ),0) < stl.quantity
  ) into v_all_returned;

  if v_all_returned then
    update public.payment_allocations set status='REVERSED' where id=v_original_allocation.id and status='ALLOCATED';
    if not found then raise exception 'POS_ORIGINAL_ALLOCATION_REVERSE_FAILED' using errcode='55000'; end if;
    update public.payment_attempts set status='REFUNDED' where id=v_original_attempt.id and status='SETTLED';
    if not found then raise exception 'POS_ORIGINAL_PAYMENT_ATTEMPT_REFUND_FAILED' using errcode='55000'; end if;
    update public.payment_intents set status='REFUNDED',updated_at=now() where id=v_original_intent.id and status='SETTLED';
    if not found then raise exception 'POS_ORIGINAL_PAYMENT_REFUND_FAILED' using errcode='55000'; end if;
    update public.sales_transactions set status='RETURNED',updated_at=now() where id=v_sale.id and status='COMPLETED';
    if not found then raise exception 'POS_RETURN_SALE_STATE_CHANGED' using errcode='40001'; end if;
  end if;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.refund_amount:=v_refund_total;
  new.sale_fully_returned:=v_all_returned;
  new.original_payment_intent_id:=v_original_intent.id;
  new.original_payment_attempt_id:=v_original_attempt.id;
  new.original_cash_movement_id:=v_original_cash.id;
  new.original_inventory_movement_id:=v_original_inventory.id;
  new.original_journal_entry_id:=v_original_journal.id;
  new.result_sales_return_id:=v_return_id;
  new.result_refund_payment_intent_id:=v_refund_intent_id;
  new.result_refund_payment_attempt_id:=v_refund_attempt_id;
  new.result_inventory_movement_id:=v_inventory_id;
  new.result_journal_entry_id:=v_journal_id;
  new.result_cash_movement_id:=v_cash_id;
  new.result_refund_receipt_id:=v_refund_receipt_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
  values(
    v_sale.organization_id,v_profile.id,'POS_CASH_PARTIAL_RETURN_POSTED','SALES_TRANSACTION',v_sale.id,
    jsonb_build_object('status','COMPLETED','sale_number',v_sale.sale_number,'total_amount',v_sale.total_amount),
    jsonb_build_object('status',case when v_all_returned then 'RETURNED' else 'COMPLETED' end,'sales_return_id',v_return_id,
      'refund_amount',v_refund_total,'refund_receipt_id',v_refund_receipt_id,'inventory_movement_id',v_inventory_id,
      'journal_entry_id',v_journal_id,'cash_movement_id',v_cash_id,'fully_returned',v_all_returned,'lines',v_payload_lines),
    v_reason
  );

  return new;
end;
$$;

revoke all on function app_private.pos_partial_return_before_insert() from public,anon,authenticated;

drop trigger if exists trg_pos_partial_return_before_insert on public.pos_partial_return_commands;
create trigger trg_pos_partial_return_before_insert
before insert on public.pos_partial_return_commands
for each row execute function app_private.pos_partial_return_before_insert();

create or replace function public.return_cash_pos_items(
  p_sales_transaction_id uuid,
  p_refund_pos_shift_id uuid,
  p_lines jsonb,
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
  cash_movement_id uuid,
  refund_receipt_id uuid,
  refund_amount numeric,
  sale_fully_returned boolean
)
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_command public.pos_partial_return_commands%rowtype;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;

  insert into public.pos_partial_return_commands(
    original_sales_transaction_id,refund_pos_shift_id,requested_lines,reason_code,reason_note,idempotency_key,requested_by
  ) values(
    p_sales_transaction_id,p_refund_pos_shift_id,p_lines,p_reason_code,p_reason_note,p_idempotency_key,v_profile.id
  ) returning * into v_command;

  if v_command.id is null then
    select * into v_command
    from public.pos_partial_return_commands
    where idempotency_key=p_idempotency_key and requested_by=v_profile.id and original_sales_transaction_id=p_sales_transaction_id
    limit 1;
  end if;

  if v_command.result_sales_return_id is null or v_command.result_refund_payment_intent_id is null
     or v_command.result_refund_payment_attempt_id is null or v_command.result_inventory_movement_id is null
     or v_command.result_journal_entry_id is null or v_command.result_cash_movement_id is null
     or v_command.result_refund_receipt_id is null or v_command.refund_amount is null then
    raise exception 'POS_PARTIAL_RETURN_NOT_COMPLETED' using errcode='P0001';
  end if;

  return query select
    v_command.result_sales_return_id,v_command.result_refund_payment_intent_id,v_command.result_refund_payment_attempt_id,
    v_command.result_inventory_movement_id,v_command.result_journal_entry_id,v_command.result_cash_movement_id,
    v_command.result_refund_receipt_id,v_command.refund_amount,v_command.sale_fully_returned;
end;
$$;

revoke all on function public.return_cash_pos_items(uuid,uuid,jsonb,text,text,text) from public,anon;
grant execute on function public.return_cash_pos_items(uuid,uuid,jsonb,text,text,text) to authenticated,service_role;
