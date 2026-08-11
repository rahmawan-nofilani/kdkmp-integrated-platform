create or replace function app_private.recalculate_pos_sale_totals_after_command()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_gross numeric(20,2);
  v_discount numeric(20,2);
  v_tax numeric(20,2);
begin
  select
    coalesce(sum(quantity * unit_price),0),
    coalesce(sum(discount_amount),0),
    coalesce(sum(tax_amount),0)
  into v_gross,v_discount,v_tax
  from public.sales_transaction_lines
  where sales_transaction_id=new.sales_transaction_id;

  update public.sales_transactions
  set subtotal=v_gross,
      discount_amount=v_discount,
      tax_amount=v_tax,
      updated_at=now()
  where id=new.sales_transaction_id
    and sale_type='POS'
    and status='DRAFT';
  return new;
end;
$$;

revoke all on function app_private.recalculate_pos_sale_totals_after_command() from public,anon,authenticated;
drop trigger if exists trg_pos_sale_totals_after_command on public.pos_sale_line_commands;
create trigger trg_pos_sale_totals_after_command
after insert on public.pos_sale_line_commands
for each row execute function app_private.recalculate_pos_sale_totals_after_command();

create table public.pos_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  sales_transaction_id uuid not null unique references public.sales_transactions(id) on delete restrict,
  pos_shift_id uuid not null references public.pos_shifts(id) on delete restrict,
  terminal_id uuid not null references public.pos_terminals(id) on delete restrict,
  payment_intent_id uuid not null references public.payment_intents(id) on delete restrict,
  payment_attempt_id uuid not null references public.payment_attempts(id) on delete restrict,
  receipt_number text not null,
  currency text not null default 'IDR',
  subtotal numeric(20,2) not null check (subtotal >= 0),
  discount_amount numeric(20,2) not null default 0 check (discount_amount >= 0),
  tax_amount numeric(20,2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(20,2) not null check (total_amount > 0),
  cash_received numeric(20,2) not null check (cash_received > 0),
  change_amount numeric(20,2) generated always as (cash_received-total_amount) stored,
  payload jsonb not null default '{}'::jsonb,
  issued_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (organization_node_id,receipt_number),
  check (cash_received >= total_amount)
);

create table public.pos_cash_completion_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  sales_transaction_id uuid not null references public.sales_transactions(id) on delete restrict,
  cash_received numeric(20,2) not null check (cash_received > 0),
  idempotency_key text not null unique,
  result_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  result_payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  result_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  result_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  result_cash_movement_id uuid references public.pos_cash_movements(id) on delete restrict,
  result_receipt_id uuid references public.pos_receipts(id) on delete restrict,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create unique index ux_pos_cash_sale_posted_once
on public.pos_cash_movements(sales_transaction_id)
where sales_transaction_id is not null and movement_type='CASH_SALE' and status='POSTED';
create index idx_pos_receipts_scope on public.pos_receipts(organization_id,organization_node_id,organization_unit_id,issued_at desc);
create index idx_pos_receipts_shift on public.pos_receipts(pos_shift_id,issued_at desc);
create index idx_pos_receipts_terminal on public.pos_receipts(terminal_id,issued_at desc);
create index idx_pos_receipts_payment_intent on public.pos_receipts(payment_intent_id);
create index idx_pos_receipts_payment_attempt on public.pos_receipts(payment_attempt_id);
create index idx_pos_receipts_created_by on public.pos_receipts(created_by);
create index idx_pos_cash_completion_sale on public.pos_cash_completion_commands(sales_transaction_id,created_at desc);
create index idx_pos_cash_completion_requested_by on public.pos_cash_completion_commands(requested_by,created_at desc);
create index idx_pos_cash_completion_org on public.pos_cash_completion_commands(organization_id);
create index idx_pos_cash_completion_node on public.pos_cash_completion_commands(organization_node_id);
create index idx_pos_cash_completion_unit on public.pos_cash_completion_commands(organization_unit_id);
create index idx_pos_cash_completion_payment_intent on public.pos_cash_completion_commands(result_payment_intent_id);
create index idx_pos_cash_completion_payment_attempt on public.pos_cash_completion_commands(result_payment_attempt_id);
create index idx_pos_cash_completion_inventory on public.pos_cash_completion_commands(result_inventory_movement_id);
create index idx_pos_cash_completion_journal on public.pos_cash_completion_commands(result_journal_entry_id);
create index idx_pos_cash_completion_cash on public.pos_cash_completion_commands(result_cash_movement_id);
create index idx_pos_cash_completion_receipt on public.pos_cash_completion_commands(result_receipt_id);

alter table public.pos_receipts enable row level security;
alter table public.pos_cash_completion_commands enable row level security;
revoke all on public.pos_receipts,public.pos_cash_completion_commands from public,anon,authenticated;
grant select on public.pos_receipts to authenticated;
grant select,insert on public.pos_cash_completion_commands to authenticated;
grant all on public.pos_receipts,public.pos_cash_completion_commands to service_role;

create policy pos_receipts_read on public.pos_receipts
for select to authenticated
using (
  public.has_permission('SALES_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create policy pos_cash_completion_read_own on public.pos_cash_completion_commands
for select to authenticated
using (
  exists(
    select 1 from public.profiles p
    where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
  )
);

create policy pos_cash_completion_insert on public.pos_cash_completion_commands
for insert to authenticated
with check (
  public.has_permission('POS_PAYMENT_CAPTURE')
  and exists(
    select 1 from public.profiles p
    where p.id=requested_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
  )
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
);

create or replace function app_private.resolve_warehouse_weighted_average_cost(
  p_warehouse_id uuid,
  p_inventory_item_id uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_qty numeric;
  v_value numeric;
  v_missing integer;
begin
  with ledger as (
    select -ml.base_quantity as qty,
           case when ml.unit_cost is null then null else -(ml.base_quantity*ml.unit_cost) end as value,
           case when ml.unit_cost is null then 1 else 0 end as missing
    from public.inventory_movement_lines ml
    join public.inventory_movements m on m.id=ml.inventory_movement_id
    where m.status='POSTED' and m.warehouse_id=p_warehouse_id
      and ml.inventory_item_id=p_inventory_item_id and ml.from_warehouse_node_id is not null
    union all
    select ml.base_quantity,
           case when ml.unit_cost is null then null else ml.base_quantity*ml.unit_cost end,
           case when ml.unit_cost is null then 1 else 0 end
    from public.inventory_movement_lines ml
    join public.inventory_movements m on m.id=ml.inventory_movement_id
    where m.status='POSTED' and m.warehouse_id=p_warehouse_id
      and ml.inventory_item_id=p_inventory_item_id and ml.to_warehouse_node_id is not null
  )
  select coalesce(sum(qty),0),coalesce(sum(value),0),coalesce(sum(missing),0)
  into v_qty,v_value,v_missing
  from ledger;

  if v_missing>0 or v_qty<=0 or v_value<=0 then return null; end if;
  return round(v_value/v_qty,6);
end;
$$;
revoke all on function app_private.resolve_warehouse_weighted_average_cost(uuid,uuid) from public,anon,authenticated;

create or replace function app_private.pos_cash_completion_before_insert()
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
  v_existing public.pos_cash_completion_commands%rowtype;
  v_period public.accounting_periods%rowtype;
  v_mapping jsonb;
  v_cash_account public.accounting_accounts%rowtype;
  v_sales_account public.accounting_accounts%rowtype;
  v_inventory_account public.accounting_accounts%rowtype;
  v_cogs_account public.accounting_accounts%rowtype;
  v_tax_account public.accounting_accounts%rowtype;
  v_cash_code text;
  v_sales_code text;
  v_inventory_code text;
  v_cogs_code text;
  v_tax_code text;
  v_line record;
  v_pos record;
  v_price record;
  v_factor numeric;
  v_required_base numeric;
  v_remaining numeric;
  v_take numeric;
  v_available numeric;
  v_unit_cost numeric;
  v_total_cost numeric(20,6):=0;
  v_net_revenue numeric(20,2);
  v_gross numeric(20,2);
  v_discount numeric(20,2);
  v_tax numeric(20,2);
  v_total numeric(20,2);
  v_change numeric(20,2);
  v_movement_id uuid;
  v_movement_line_no integer:=0;
  v_payment_intent_id uuid;
  v_payment_attempt_id uuid;
  v_journal_id uuid;
  v_cash_movement_id uuid;
  v_receipt_id uuid;
  v_receipt_number text;
  v_movement_number text;
  v_journal_number text;
  v_journal_line_no integer:=0;
  v_receipt_lines jsonb;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('SALES_CREATE') then raise exception 'SALES_CREATE_DENIED' using errcode='42501'; end if;
  if not public.has_permission('POS_PAYMENT_CAPTURE') then raise exception 'POS_PAYMENT_CAPTURE_DENIED' using errcode='42501'; end if;

  new.idempotency_key:=nullif(trim(new.idempotency_key),'');
  if new.idempotency_key is null or char_length(new.idempotency_key)<8 then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  if new.cash_received is null or new.cash_received<=0 then raise exception 'POS_CASH_RECEIVED_INVALID' using errcode='22023'; end if;

  select * into v_existing from public.pos_cash_completion_commands where idempotency_key=new.idempotency_key limit 1;
  if v_existing.id is not null then
    if v_existing.requested_by=v_profile.id
       and v_existing.sales_transaction_id=new.sales_transaction_id
       and v_existing.cash_received is not distinct from new.cash_received then return null; end if;
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_sale from public.sales_transactions where id=new.sales_transaction_id for update;
  if v_sale.id is null or v_sale.sale_type<>'POS' then raise exception 'POS_SALE_NOT_FOUND' using errcode='P0002'; end if;
  if v_sale.created_by<>v_profile.id or v_sale.status<>'DRAFT' then raise exception 'POS_OWN_DRAFT_SALE_REQUIRED' using errcode='42501'; end if;
  if not public.has_data_scope(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,null,null) then raise exception 'POS_SALE_SCOPE_DENIED' using errcode='42501'; end if;

  select * into v_shift from public.pos_shifts where id=v_sale.pos_shift_id and cashier_profile_id=v_profile.id and status='OPEN';
  if v_shift.id is null then raise exception 'POS_OWN_OPEN_SHIFT_REQUIRED' using errcode='42501'; end if;
  select * into v_terminal from public.pos_terminals where id=v_sale.terminal_id and status='ACTIVE';
  if v_terminal.id is null or v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_NOT_READY' using errcode='22023'; end if;

  select coalesce(sum(quantity*unit_price),0),coalesce(sum(discount_amount),0),coalesce(sum(tax_amount),0)
  into v_gross,v_discount,v_tax
  from public.sales_transaction_lines where sales_transaction_id=v_sale.id;
  v_total:=v_gross-v_discount+v_tax;
  if v_total<=0 then raise exception 'POS_CART_EMPTY' using errcode='22023'; end if;
  if new.cash_received<v_total then raise exception 'POS_CASH_RECEIVED_INSUFFICIENT' using errcode='22023'; end if;
  v_change:=new.cash_received-v_total;
  if v_sale.subtotal is distinct from v_gross or v_sale.discount_amount is distinct from v_discount or v_sale.tax_amount is distinct from v_tax or v_sale.total_amount is distinct from v_total then
    raise exception 'POS_TOTALS_OUT_OF_SYNC' using errcode='22023';
  end if;
  v_net_revenue:=v_gross-v_discount;
  if v_net_revenue<=0 then raise exception 'POS_NET_REVENUE_INVALID' using errcode='22023'; end if;

  select aem.configuration into v_mapping
  from public.accounting_event_mappings aem
  join public.accounting_event_definitions aed on aed.id=aem.event_definition_id
  where aed.event_code='SALE_POST' and aed.status='ACTIVE'
    and aem.organization_id=v_sale.organization_id and aem.organization_node_id=v_sale.organization_node_id
    and aem.status='ACTIVE'
    and (aem.effective_from is null or aem.effective_from<=current_date)
    and (aem.effective_until is null or aem.effective_until>=current_date)
  order by aem.version_no desc limit 1;
  if v_mapping is null then raise exception 'POS_ACCOUNTING_MAPPING_NOT_READY' using errcode='22023'; end if;

  v_cash_code:=nullif(v_mapping->>'cash_account_code','');
  v_sales_code:=nullif(v_mapping->>'sales_revenue_account_code','');
  v_inventory_code:=nullif(v_mapping->>'inventory_account_code','');
  v_cogs_code:=nullif(v_mapping->>'cogs_account_code','');
  v_tax_code:=nullif(v_mapping->>'tax_payable_account_code','');
  if v_cash_code is null or v_sales_code is null or v_inventory_code is null or v_cogs_code is null then
    raise exception 'POS_ACCOUNTING_ACCOUNTS_NOT_CONFIGURED' using errcode='22023';
  end if;
  if v_tax>0 and v_tax_code is null then raise exception 'POS_TAX_ACCOUNT_NOT_CONFIGURED' using errcode='22023'; end if;

  select * into v_cash_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_cash_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_sales_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_sales_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_inventory_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_inventory_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_cogs_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_cogs_code and status='ACTIVE' and is_posting=true limit 1;
  if v_tax>0 then select * into v_tax_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_tax_code and status='ACTIVE' and is_posting=true limit 1; end if;
  if v_cash_account.id is null or v_cash_account.account_class<>'ASSET' or v_cash_account.normal_balance<>'DEBIT' then raise exception 'POS_CASH_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_sales_account.id is null or v_sales_account.account_class<>'REVENUE' or v_sales_account.normal_balance<>'CREDIT' then raise exception 'POS_SALES_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_inventory_account.id is null or v_inventory_account.account_class<>'ASSET' or v_inventory_account.normal_balance<>'DEBIT' then raise exception 'POS_INVENTORY_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_cogs_account.id is null or v_cogs_account.account_class<>'EXPENSE' or v_cogs_account.normal_balance<>'DEBIT' then raise exception 'POS_COGS_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_tax>0 and (v_tax_account.id is null or v_tax_account.account_class<>'LIABILITY' or v_tax_account.normal_balance<>'CREDIT') then raise exception 'POS_TAX_ACCOUNT_INVALID' using errcode='22023'; end if;

  select * into v_period from public.accounting_periods
  where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id
    and current_date between start_date and end_date and status='OPEN'
  order by start_date desc limit 1;
  if v_period.id is null then raise exception 'POS_ACCOUNTING_PERIOD_NOT_OPEN' using errcode='22023'; end if;

  v_movement_number:='POSISS-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
    source_domain,source_entity_type,source_entity_id,source_reference,idempotency_key,correlation_id,occurred_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_terminal.default_warehouse_id,
    v_movement_number,'SALE_ISSUE','DRAFT','COMMERCIAL','SALES_TRANSACTION',v_sale.id,v_sale.sale_number,
    'POS-ISSUE:'||new.idempotency_key,v_sale.correlation_id,now(),v_profile.id
  ) returning id into v_movement_id;

  for v_line in
    select stl.*,i.base_uom_id,i.tracking_type,i.costing_method,i.picking_policy
    from public.sales_transaction_lines stl
    join public.inventory_items i on i.id=stl.inventory_item_id
    where stl.sales_transaction_id=v_sale.id
    order by stl.line_no
  loop
    if v_line.inventory_item_id is null or v_line.uom_id is null then raise exception 'POS_LINE_ITEM_INVALID' using errcode='22023'; end if;
    if v_line.costing_method<>'WEIGHTED_AVERAGE' then raise exception 'POS_COSTING_METHOD_NOT_READY' using errcode='22023'; end if;
    if v_line.tracking_type='SERIAL' then raise exception 'POS_SERIAL_ITEM_REQUIRES_SERIAL_SELECTION' using errcode='22023'; end if;
    if v_line.picking_policy='MANUAL' then raise exception 'POS_MANUAL_PICK_ITEM_NOT_SUPPORTED' using errcode='22023'; end if;

    select * into v_price from app_private.resolve_pos_price(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_line.inventory_item_id,v_line.uom_id,v_line.quantity,now());
    if v_price.price_entry_id is null or (v_line.item_snapshot->>'price_entry_id') is distinct from v_price.price_entry_id::text or v_line.unit_price is distinct from v_price.unit_price then
      raise exception 'POS_PRICE_CHANGED_RELOAD_CART' using errcode='22023';
    end if;

    if v_line.uom_id=v_line.base_uom_id then v_factor:=1;
    else select factor_to_base into v_factor from public.inventory_item_uom_conversions where inventory_item_id=v_line.inventory_item_id and uom_id=v_line.uom_id and status='ACTIVE' limit 1;
    end if;
    if v_factor is null or v_factor<=0 then raise exception 'POS_ITEM_UOM_NOT_CONFIGURED' using errcode='22023'; end if;
    v_required_base:=v_line.quantity*v_factor;

    perform pg_advisory_xact_lock(hashtextextended(v_terminal.default_warehouse_id::text||':'||v_line.inventory_item_id::text,0));
    select coalesce(sum(available_to_allocate),0) into v_available
    from public.inventory_available_positions
    where warehouse_id=v_terminal.default_warehouse_id and inventory_item_id=v_line.inventory_item_id and stock_status='AVAILABLE';
    if v_available<v_required_base then raise exception 'POS_INSUFFICIENT_STOCK' using errcode='22023'; end if;

    v_unit_cost:=app_private.resolve_warehouse_weighted_average_cost(v_terminal.default_warehouse_id,v_line.inventory_item_id);
    if v_unit_cost is null or v_unit_cost<=0 then raise exception 'POS_INVENTORY_COST_NOT_READY' using errcode='22023'; end if;
    v_remaining:=v_required_base;

    for v_pos in
      select p.warehouse_node_id,p.lot_id,p.available_to_allocate,l.expiry_date,l.manufacture_date,l.created_at as lot_created_at
      from public.inventory_available_positions p
      left join public.inventory_lots l on l.id=p.lot_id
      where p.warehouse_id=v_terminal.default_warehouse_id and p.inventory_item_id=v_line.inventory_item_id
        and p.stock_status='AVAILABLE' and p.available_to_allocate>0
        and (v_line.tracking_type<>'LOT' or p.lot_id is not null)
      order by
        case when v_line.picking_policy='FEFO' then l.expiry_date end nulls last,
        case when v_line.picking_policy='FIFO' then coalesce(l.manufacture_date,l.created_at::date) end nulls last,
        p.warehouse_node_id
    loop
      exit when v_remaining<=0;
      v_take:=least(v_remaining,v_pos.available_to_allocate);
      if v_take<=0 then continue; end if;
      v_movement_line_no:=v_movement_line_no+1;
      insert into public.inventory_movement_lines(
        organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,lot_id,
        from_warehouse_node_id,from_stock_status,quantity,base_quantity,unit_cost,notes
      ) values(
        v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_movement_id,v_movement_line_no,
        v_line.inventory_item_id,v_line.base_uom_id,v_pos.lot_id,v_pos.warehouse_node_id,'AVAILABLE',v_take,v_take,v_unit_cost,
        'POS automatic issue from completed cash sale'
      );
      v_total_cost:=v_total_cost+(v_take*v_unit_cost);
      v_remaining:=v_remaining-v_take;
    end loop;
    if v_remaining>0 then raise exception 'POS_STOCK_PICK_FAILED' using errcode='22023'; end if;
  end loop;

  if v_movement_line_no=0 or v_total_cost<=0 then raise exception 'POS_INVENTORY_COST_NOT_READY' using errcode='22023'; end if;

  select payment_intent_id,payment_attempt_id into v_payment_intent_id,v_payment_attempt_id
  from public.start_pos_payment(v_sale.id,'CASH_POS','START:'||new.idempotency_key,null);
  if v_payment_intent_id is null or v_payment_attempt_id is null then raise exception 'POS_PAYMENT_START_FAILED' using errcode='55000'; end if;

  v_journal_number:='POSJ-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.journal_entries(
    organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,source_domain,
    source_entity_type,source_entity_id,source_reference,correlation_id,idempotency_key,status,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_period.id,v_journal_number,current_date,
    'POS cash sale '||coalesce(v_sale.sale_number,v_sale.id::text),'COMMERCIAL','SALES_TRANSACTION',v_sale.id,v_sale.sale_number,
    coalesce(v_sale.correlation_id::text,v_sale.id::text),'POS-JOURNAL:'||new.idempotency_key,'DRAFT',v_profile.id
  ) returning id into v_journal_id;

  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_cash_account.id,v_total,0,'Cash received at POS',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'terminal_id',v_sale.terminal_id,'pos_shift_id',v_sale.pos_shift_id,'sale_id',v_sale.id));
  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_sales_account.id,0,v_net_revenue,'Retail sales revenue',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'sale_id',v_sale.id));
  if v_tax>0 then
    v_journal_line_no:=v_journal_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_tax_account.id,0,v_tax,'Sales tax payable',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'sale_id',v_sale.id));
  end if;
  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_cogs_account.id,round(v_total_cost,2),0,'Cost of goods sold',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'sale_id',v_sale.id,'inventory_movement_id',v_movement_id));
  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_inventory_account.id,0,round(v_total_cost,2),'Inventory issued for POS sale',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'sale_id',v_sale.id,'inventory_movement_id',v_movement_id));

  update public.journal_entries set status='VALIDATED' where id=v_journal_id;
  update public.journal_entries set status='POSTED' where id=v_journal_id;
  update public.inventory_movements set journal_entry_id=v_journal_id,status='POSTED',posted_at=now() where id=v_movement_id;

  update public.payment_intents set status='SETTLED',confirmed_at=now(),settled_at=now(),updated_at=now() where id=v_payment_intent_id and status='CREATED';
  update public.payment_attempts set status='SETTLED',confirmed_at=now(),settled_at=now() where id=v_payment_attempt_id and status='CREATED';
  insert into public.payment_allocations(payment_intent_id,organization_id,organization_node_id,organization_unit_id,allocation_no,target_type,target_id,target_reference,amount,status,allocated_at)
  values(v_payment_intent_id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,1,'SALE',v_sale.id,v_sale.sale_number,v_total,'ALLOCATED',now());

  insert into public.pos_cash_movements(
    organization_id,organization_node_id,organization_unit_id,pos_shift_id,sales_transaction_id,payment_intent_id,payment_attempt_id,
    movement_type,direction,amount,currency,status,reason,occurred_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.pos_shift_id,v_sale.id,v_payment_intent_id,v_payment_attempt_id,
    'CASH_SALE','IN',v_total,v_sale.currency,'POSTED','Cash received for completed POS sale',now(),v_profile.id
  ) returning id into v_cash_movement_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'line_no',line_no,'description',description,'quantity',quantity,'uom_code',item_snapshot->>'uom_code',
    'unit_price',unit_price,'discount_amount',discount_amount,'tax_amount',tax_amount,'line_total',line_total
  ) order by line_no),'[]'::jsonb)
  into v_receipt_lines
  from public.sales_transaction_lines where sales_transaction_id=v_sale.id;

  v_receipt_number:='RCP-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.pos_receipts(
    organization_id,organization_node_id,organization_unit_id,sales_transaction_id,pos_shift_id,terminal_id,payment_intent_id,payment_attempt_id,
    receipt_number,currency,subtotal,discount_amount,tax_amount,total_amount,cash_received,payload,issued_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.id,v_sale.pos_shift_id,v_sale.terminal_id,v_payment_intent_id,v_payment_attempt_id,
    v_receipt_number,v_sale.currency,v_gross,v_discount,v_tax,v_total,new.cash_received,
    jsonb_build_object('sale_number',v_sale.sale_number,'receipt_number',v_receipt_number,'payment_channel','CASH_POS','cash_received',new.cash_received,'change_amount',v_change,'lines',v_receipt_lines,'total_cost',round(v_total_cost,2),'issued_at',now()),
    now(),v_profile.id
  ) returning id into v_receipt_id;

  update public.sales_transactions
  set status='COMPLETED',payment_intent_id=v_payment_intent_id,inventory_movement_id=v_movement_id,journal_entry_id=v_journal_id,
      receipt_reference=v_receipt_number,sold_at=coalesce(sold_at,now()),completed_at=now(),updated_at=now()
  where id=v_sale.id and status='PAYMENT_PENDING';
  if not found then raise exception 'POS_SALE_COMPLETION_STATE_INVALID' using errcode='55000'; end if;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.result_payment_intent_id:=v_payment_intent_id;
  new.result_payment_attempt_id:=v_payment_attempt_id;
  new.result_inventory_movement_id:=v_movement_id;
  new.result_journal_entry_id:=v_journal_id;
  new.result_cash_movement_id:=v_cash_movement_id;
  new.result_receipt_id:=v_receipt_id;
  new.requested_by:=v_profile.id;
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_sale.organization_id,v_profile.id,'POS_CASH_SALE_COMPLETED','SALES_TRANSACTION',v_sale.id,
    jsonb_build_object('payment_intent_id',v_payment_intent_id,'payment_attempt_id',v_payment_attempt_id,'inventory_movement_id',v_movement_id,'journal_entry_id',v_journal_id,'cash_movement_id',v_cash_movement_id,'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'total',v_total,'cash_received',new.cash_received,'change_amount',v_change,'cost',round(v_total_cost,2),'sale_status','COMPLETED'),
    'Atomic POS cash completion: payment, inventory, accounting, cash ledger and receipt');
  return new;
end;
$$;

revoke all on function app_private.pos_cash_completion_before_insert() from public,anon,authenticated;
create trigger trg_pos_cash_completion_before_insert
before insert on public.pos_cash_completion_commands
for each row execute function app_private.pos_cash_completion_before_insert();

create or replace function public.complete_cash_pos_sale(
  p_sales_transaction_id uuid,
  p_cash_received numeric,
  p_idempotency_key text
)
returns table(
  payment_intent_id uuid,
  payment_attempt_id uuid,
  inventory_movement_id uuid,
  journal_entry_id uuid,
  cash_movement_id uuid,
  receipt_id uuid
)
language plpgsql
set search_path to ''
as $$
declare
  v_key text:=nullif(trim(p_idempotency_key),'');
begin
  if v_key is null then raise exception 'POS_IDEMPOTENCY_KEY_REQUIRED' using errcode='22023'; end if;
  if p_cash_received is null or p_cash_received<=0 then raise exception 'POS_CASH_RECEIVED_INVALID' using errcode='22023'; end if;

  return query
  select c.result_payment_intent_id,c.result_payment_attempt_id,c.result_inventory_movement_id,c.result_journal_entry_id,c.result_cash_movement_id,c.result_receipt_id
  from public.pos_cash_completion_commands c
  where c.idempotency_key=v_key and c.cash_received=p_cash_received limit 1;
  if found then return; end if;

  if exists(select 1 from public.pos_cash_completion_commands c where c.idempotency_key=v_key) then
    raise exception 'POS_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  insert into public.pos_cash_completion_commands(sales_transaction_id,cash_received,idempotency_key)
  values(p_sales_transaction_id,p_cash_received,v_key)
  returning result_payment_intent_id,result_payment_attempt_id,result_inventory_movement_id,result_journal_entry_id,result_cash_movement_id,result_receipt_id
  into payment_intent_id,payment_attempt_id,inventory_movement_id,journal_entry_id,cash_movement_id,receipt_id;

  if payment_intent_id is null then
    select c.result_payment_intent_id,c.result_payment_attempt_id,c.result_inventory_movement_id,c.result_journal_entry_id,c.result_cash_movement_id,c.result_receipt_id
    into payment_intent_id,payment_attempt_id,inventory_movement_id,journal_entry_id,cash_movement_id,receipt_id
    from public.pos_cash_completion_commands c where c.idempotency_key=v_key limit 1;
  end if;
  if payment_intent_id is null or receipt_id is null then raise exception 'POS_CASH_COMPLETION_FAILED' using errcode='55000'; end if;
  return next;
end;
$$;

revoke all on function public.complete_cash_pos_sale(uuid,numeric,text) from public,anon;
grant execute on function public.complete_cash_pos_sale(uuid,numeric,text) to authenticated;
