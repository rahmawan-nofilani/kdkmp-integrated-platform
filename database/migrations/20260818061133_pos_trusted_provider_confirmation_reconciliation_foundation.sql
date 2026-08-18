-- POS trusted QRIS / BANK_TRANSFER confirmation and reconciliation foundation
--
-- Security and accounting invariants:
-- * cashier/authenticated clients may start a provider payment through start_pos_payment,
--   but cannot confirm it;
-- * only service_role may call the trusted confirmation / settlement RPCs;
-- * a provider confirmation must match the configured provider, payment attempt,
--   merchant reference, provider reference, amount and currency exactly;
-- * screenshots/manual cashier input are never authoritative payment evidence;
-- * confirmed provider payments debit a provider clearing asset and complete the sale
--   atomically with SALE_ISSUE, journal, allocation and receipt;
-- * provider payment remains SETTLEMENT_PENDING until a settlement batch fully matches;
-- * settlement reconciliation posts clearing -> bank/fee accounting only when every item
--   is matched and balanced; mismatches remain EXCEPTION and do not settle payment state;
-- * no provider credentials, secret keys or production provider configuration are added here.

alter table public.pos_receipts
  add column payment_channel text not null default 'CASH_POS';

alter table public.pos_receipts drop constraint pos_receipts_cash_received_check;
alter table public.pos_receipts drop constraint pos_receipts_check;
alter table public.pos_receipts alter column cash_received drop not null;

alter table public.pos_receipts
  add constraint pos_receipts_payment_channel_check
  check (payment_channel in ('CASH_POS','QRIS','BANK_TRANSFER'));

alter table public.pos_receipts
  add constraint pos_receipts_tender_semantics_check
  check (
    (payment_channel='CASH_POS' and cash_received is not null and cash_received>0 and cash_received>=total_amount)
    or
    (payment_channel in ('QRIS','BANK_TRANSFER') and cash_received is null and change_amount is null)
  );

alter table public.payment_external_events
  add column provider_reference text,
  add column merchant_reference text,
  add column event_amount numeric(20,2),
  add column event_currency text,
  add column event_status text;

alter table public.payment_external_events
  add constraint payment_external_events_amount_check
  check (event_amount is null or event_amount>0);

alter table public.payment_external_events
  add constraint payment_external_events_status_check
  check (event_status is null or event_status in ('PAID','FAILED','EXPIRED','REFUNDED','SETTLED','UNKNOWN'));

alter table public.payment_settlement_batches
  add column journal_entry_id uuid references public.journal_entries(id) on delete restrict;

create index idx_payment_events_provider_reference
  on public.payment_external_events(provider_config_id,provider_reference,received_at desc);
create index idx_payment_settlement_batches_journal
  on public.payment_settlement_batches(journal_entry_id);
create index idx_payment_settlement_items_attempt
  on public.payment_settlement_items(payment_attempt_id,created_at);

create table public.pos_provider_confirmation_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  provider_config_id uuid not null references public.payment_provider_configs(id) on delete restrict,
  payment_attempt_id uuid not null references public.payment_attempts(id) on delete restrict,
  external_event_id text not null,
  event_type text not null,
  event_status text not null check (event_status='PAID'),
  provider_reference text not null,
  merchant_reference text not null,
  amount numeric(20,2) not null check (amount>0),
  currency text not null,
  payload_hash text not null,
  sanitized_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(sanitized_metadata)='object'),
  result_payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  result_sales_transaction_id uuid references public.sales_transactions(id) on delete restrict,
  result_external_event_id uuid references public.payment_external_events(id) on delete restrict,
  result_inventory_movement_id uuid references public.inventory_movements(id) on delete restrict,
  result_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  result_receipt_id uuid references public.pos_receipts(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(provider_config_id,external_event_id)
);

create index idx_pos_provider_confirmation_attempt
  on public.pos_provider_confirmation_commands(payment_attempt_id,created_at desc);
create index idx_pos_provider_confirmation_sale
  on public.pos_provider_confirmation_commands(result_sales_transaction_id,created_at desc);

alter table public.pos_provider_confirmation_commands enable row level security;
revoke all on public.pos_provider_confirmation_commands from public,anon,authenticated;
grant all on public.pos_provider_confirmation_commands to service_role;

insert into public.accounting_event_definitions(event_code,domain,name,description,status)
values
  ('POS_PROVIDER_SALE_POST','COMMERCIAL','POS provider-confirmed sale','Post QRIS/BANK_TRANSFER POS sale to provider clearing after trusted backend confirmation','ACTIVE'),
  ('POS_PROVIDER_SETTLEMENT_POST','PAYMENT','POS provider settlement','Reconcile provider clearing to bank and payment fee after matched settlement','ACTIVE')
on conflict(event_code) do nothing;

create or replace function app_private.pos_provider_confirmation_before_insert()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_provider public.payment_provider_configs%rowtype;
  v_attempt public.payment_attempts%rowtype;
  v_intent public.payment_intents%rowtype;
  v_sale public.sales_transactions%rowtype;
  v_terminal public.pos_terminals%rowtype;
  v_period public.accounting_periods%rowtype;
  v_mapping jsonb;
  v_clearing_code text;
  v_sales_code text;
  v_inventory_code text;
  v_cogs_code text;
  v_tax_code text;
  v_clearing_account public.accounting_accounts%rowtype;
  v_sales_account public.accounting_accounts%rowtype;
  v_inventory_account public.accounting_accounts%rowtype;
  v_cogs_account public.accounting_accounts%rowtype;
  v_tax_account public.accounting_accounts%rowtype;
  v_existing public.pos_provider_confirmation_commands%rowtype;
  v_existing_event public.payment_external_events%rowtype;
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
  v_gross numeric(20,2);
  v_discount numeric(20,2);
  v_tax numeric(20,2);
  v_total numeric(20,2);
  v_net_revenue numeric(20,2);
  v_movement_id uuid;
  v_movement_line_no integer:=0;
  v_journal_id uuid;
  v_journal_line_no integer:=0;
  v_external_event_row_id uuid;
  v_receipt_id uuid;
  v_receipt_number text;
  v_movement_number text;
  v_journal_number text;
  v_receipt_lines jsonb;
begin
  new.external_event_id:=nullif(trim(new.external_event_id),'');
  new.event_type:=upper(nullif(trim(new.event_type),''));
  new.event_status:=upper(nullif(trim(new.event_status),''));
  new.provider_reference:=nullif(trim(new.provider_reference),'');
  new.merchant_reference:=nullif(trim(new.merchant_reference),'');
  new.currency:=upper(nullif(trim(new.currency),''));
  new.payload_hash:=lower(nullif(trim(new.payload_hash),''));
  new.sanitized_metadata:=coalesce(new.sanitized_metadata,'{}'::jsonb);

  if new.external_event_id is null or char_length(new.external_event_id)>200 then raise exception 'POS_PROVIDER_EVENT_ID_INVALID' using errcode='22023'; end if;
  if new.event_type is null or char_length(new.event_type)>100 then raise exception 'POS_PROVIDER_EVENT_TYPE_INVALID' using errcode='22023'; end if;
  if new.event_status<>'PAID' then raise exception 'POS_PROVIDER_EVENT_NOT_PAYMENT_CONFIRMED' using errcode='22023'; end if;
  if new.provider_reference is null or char_length(new.provider_reference)>200 then raise exception 'POS_PROVIDER_REFERENCE_REQUIRED' using errcode='22023'; end if;
  if new.merchant_reference is null or char_length(new.merchant_reference)>200 then raise exception 'POS_MERCHANT_REFERENCE_REQUIRED' using errcode='22023'; end if;
  if new.amount is null or new.amount<=0 then raise exception 'POS_PROVIDER_AMOUNT_INVALID' using errcode='22023'; end if;
  if new.currency is null or char_length(new.currency)<>3 then raise exception 'POS_PROVIDER_CURRENCY_INVALID' using errcode='22023'; end if;
  if new.payload_hash is null or new.payload_hash !~ '^[0-9a-f]{64}$' then raise exception 'POS_PROVIDER_PAYLOAD_HASH_INVALID' using errcode='22023'; end if;
  if jsonb_typeof(new.sanitized_metadata)<>'object' then raise exception 'POS_PROVIDER_METADATA_INVALID' using errcode='22023'; end if;

  select * into v_existing
  from public.pos_provider_confirmation_commands
  where provider_config_id=new.provider_config_id and external_event_id=new.external_event_id
  limit 1;
  if v_existing.id is not null then
    if v_existing.payment_attempt_id=new.payment_attempt_id
       and v_existing.event_type=new.event_type
       and v_existing.event_status=new.event_status
       and v_existing.provider_reference=new.provider_reference
       and v_existing.merchant_reference=new.merchant_reference
       and v_existing.amount=new.amount
       and v_existing.currency=new.currency
       and v_existing.payload_hash=new.payload_hash then
      return null;
    end if;
    raise exception 'POS_PROVIDER_EVENT_IDEMPOTENCY_CONFLICT' using errcode='23505';
  end if;

  select * into v_provider
  from public.payment_provider_configs
  where id=new.provider_config_id
    and status='ACTIVE'
    and config_status='VALIDATED'
  for update;
  if v_provider.id is null then raise exception 'POS_PAYMENT_PROVIDER_NOT_READY' using errcode='22023'; end if;

  select * into v_attempt from public.payment_attempts where id=new.payment_attempt_id for update;
  if v_attempt.id is null then raise exception 'POS_PAYMENT_ATTEMPT_NOT_FOUND' using errcode='P0002'; end if;
  if v_attempt.provider_config_id is distinct from v_provider.id then raise exception 'POS_PROVIDER_ATTEMPT_MISMATCH' using errcode='22023'; end if;
  if v_attempt.channel not in ('QRIS','BANK_TRANSFER') or not (v_attempt.channel=any(v_provider.supported_channels)) then raise exception 'POS_PROVIDER_CHANNEL_MISMATCH' using errcode='22023'; end if;
  if v_attempt.status not in ('CREATED','PENDING') then raise exception 'POS_PROVIDER_ATTEMPT_STATE_INVALID' using errcode='22023'; end if;
  if v_attempt.merchant_reference is null or v_attempt.merchant_reference<>new.merchant_reference then raise exception 'POS_PROVIDER_MERCHANT_REFERENCE_MISMATCH' using errcode='22023'; end if;
  if v_attempt.amount<>new.amount or v_attempt.currency<>new.currency then raise exception 'POS_PROVIDER_AMOUNT_CURRENCY_MISMATCH' using errcode='22023'; end if;

  select * into v_intent from public.payment_intents where id=v_attempt.payment_intent_id for update;
  if v_intent.id is null or v_intent.business_purpose<>'SALE' or v_intent.source_entity_type<>'SALES_TRANSACTION' then raise exception 'POS_PROVIDER_SALE_INTENT_REQUIRED' using errcode='22023'; end if;
  if v_intent.status not in ('CREATED','PENDING') then raise exception 'POS_PROVIDER_INTENT_STATE_INVALID' using errcode='22023'; end if;
  if v_intent.amount<>new.amount or v_intent.currency<>new.currency then raise exception 'POS_PROVIDER_INTENT_AMOUNT_MISMATCH' using errcode='22023'; end if;

  select * into v_sale from public.sales_transactions where id=v_intent.source_entity_id for update;
  if v_sale.id is null or v_sale.sale_type<>'POS' or v_sale.status<>'PAYMENT_PENDING' then raise exception 'POS_PROVIDER_PENDING_SALE_REQUIRED' using errcode='22023'; end if;
  if v_sale.payment_intent_id is distinct from v_intent.id then raise exception 'POS_PROVIDER_SALE_PAYMENT_LINK_MISMATCH' using errcode='22023'; end if;
  if v_sale.organization_id<>v_provider.organization_id or v_sale.organization_node_id<>v_provider.organization_node_id then raise exception 'POS_PROVIDER_SALE_SCOPE_MISMATCH' using errcode='22023'; end if;
  if v_provider.organization_unit_id is not null and v_sale.organization_unit_id is distinct from v_provider.organization_unit_id then raise exception 'POS_PROVIDER_SALE_UNIT_MISMATCH' using errcode='22023'; end if;

  select * into v_terminal from public.pos_terminals where id=v_sale.terminal_id;
  if v_terminal.id is null or v_terminal.default_warehouse_id is null then raise exception 'POS_TERMINAL_NOT_READY' using errcode='22023'; end if;

  select coalesce(sum(quantity*unit_price),0),coalesce(sum(discount_amount),0),coalesce(sum(tax_amount),0)
    into v_gross,v_discount,v_tax
  from public.sales_transaction_lines where sales_transaction_id=v_sale.id;
  v_total:=v_gross-v_discount+v_tax;
  if v_total<=0 or v_total<>v_sale.total_amount or v_total<>new.amount then raise exception 'POS_PROVIDER_SALE_TOTAL_MISMATCH' using errcode='22023'; end if;
  v_net_revenue:=v_gross-v_discount;
  if v_net_revenue<=0 then raise exception 'POS_NET_REVENUE_INVALID' using errcode='22023'; end if;

  select aem.configuration into v_mapping
  from public.accounting_event_mappings aem
  join public.accounting_event_definitions aed on aed.id=aem.event_definition_id
  where aed.event_code='POS_PROVIDER_SALE_POST' and aed.status='ACTIVE'
    and aem.organization_id=v_sale.organization_id
    and aem.organization_node_id=v_sale.organization_node_id
    and aem.status='ACTIVE'
    and (aem.effective_from is null or aem.effective_from<=current_date)
    and (aem.effective_until is null or aem.effective_until>=current_date)
  order by aem.version_no desc limit 1;
  if v_mapping is null then raise exception 'POS_PROVIDER_ACCOUNTING_MAPPING_NOT_READY' using errcode='22023'; end if;

  v_clearing_code:=case when v_attempt.channel='QRIS' then nullif(v_mapping->>'qris_clearing_account_code','') else nullif(v_mapping->>'bank_transfer_clearing_account_code','') end;
  v_sales_code:=nullif(v_mapping->>'sales_revenue_account_code','');
  v_inventory_code:=nullif(v_mapping->>'inventory_account_code','');
  v_cogs_code:=nullif(v_mapping->>'cogs_account_code','');
  v_tax_code:=nullif(v_mapping->>'tax_payable_account_code','');
  if v_clearing_code is null or v_sales_code is null or v_inventory_code is null or v_cogs_code is null then raise exception 'POS_PROVIDER_ACCOUNTING_ACCOUNTS_NOT_CONFIGURED' using errcode='22023'; end if;
  if v_tax>0 and v_tax_code is null then raise exception 'POS_TAX_ACCOUNT_NOT_CONFIGURED' using errcode='22023'; end if;

  select * into v_clearing_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_clearing_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_sales_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_sales_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_inventory_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_inventory_code and status='ACTIVE' and is_posting=true limit 1;
  select * into v_cogs_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_cogs_code and status='ACTIVE' and is_posting=true limit 1;
  if v_tax>0 then select * into v_tax_account from public.accounting_accounts where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id and code=v_tax_code and status='ACTIVE' and is_posting=true limit 1; end if;
  if v_clearing_account.id is null or v_clearing_account.account_class<>'ASSET' or v_clearing_account.normal_balance<>'DEBIT' then raise exception 'POS_PROVIDER_CLEARING_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_sales_account.id is null or v_sales_account.account_class<>'REVENUE' or v_sales_account.normal_balance<>'CREDIT' then raise exception 'POS_SALES_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_inventory_account.id is null or v_inventory_account.account_class<>'ASSET' or v_inventory_account.normal_balance<>'DEBIT' then raise exception 'POS_INVENTORY_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_cogs_account.id is null or v_cogs_account.account_class<>'EXPENSE' or v_cogs_account.normal_balance<>'DEBIT' then raise exception 'POS_COGS_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_tax>0 and (v_tax_account.id is null or v_tax_account.account_class<>'LIABILITY' or v_tax_account.normal_balance<>'CREDIT') then raise exception 'POS_TAX_ACCOUNT_INVALID' using errcode='22023'; end if;

  select * into v_period from public.accounting_periods
  where organization_id=v_sale.organization_id and organization_node_id=v_sale.organization_node_id
    and current_date between start_date and end_date and status='OPEN'
  order by start_date desc limit 1;
  if v_period.id is null then raise exception 'POS_ACCOUNTING_PERIOD_NOT_OPEN' using errcode='22023'; end if;

  v_movement_number:='POSPISS-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.inventory_movements(
    organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
    source_domain,source_entity_type,source_entity_id,source_reference,idempotency_key,correlation_id,occurred_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_terminal.default_warehouse_id,
    v_movement_number,'SALE_ISSUE','DRAFT','COMMERCIAL','SALES_TRANSACTION',v_sale.id,v_sale.sale_number,
    'POS-PROVIDER-ISSUE:'||new.external_event_id,v_sale.correlation_id,now(),v_sale.created_by
  ) returning id into v_movement_id;

  for v_line in
    select stl.*,i.base_uom_id,i.tracking_type,i.costing_method,i.picking_policy
    from public.sales_transaction_lines stl
    join public.inventory_items i on i.id=stl.inventory_item_id
    where stl.sales_transaction_id=v_sale.id
    order by stl.line_no
  loop
    if v_line.costing_method<>'WEIGHTED_AVERAGE' then raise exception 'POS_COSTING_METHOD_NOT_READY' using errcode='22023'; end if;
    if v_line.tracking_type='SERIAL' then raise exception 'POS_SERIAL_ITEM_REQUIRES_SERIAL_SELECTION' using errcode='22023'; end if;
    if v_line.picking_policy='MANUAL' then raise exception 'POS_MANUAL_PICK_ITEM_NOT_SUPPORTED' using errcode='22023'; end if;
    select * into v_price from app_private.resolve_pos_price(v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_line.inventory_item_id,v_line.uom_id,v_line.quantity,now());
    if v_price.price_entry_id is null or (v_line.item_snapshot->>'price_entry_id') is distinct from v_price.price_entry_id::text or v_line.unit_price is distinct from v_price.unit_price then raise exception 'POS_PRICE_CHANGED_RELOAD_CART' using errcode='22023'; end if;
    if v_line.uom_id=v_line.base_uom_id then v_factor:=1;
    else select factor_to_base into v_factor from public.inventory_item_uom_conversions where inventory_item_id=v_line.inventory_item_id and uom_id=v_line.uom_id and status='ACTIVE' limit 1;
    end if;
    if v_factor is null or v_factor<=0 then raise exception 'POS_ITEM_UOM_NOT_CONFIGURED' using errcode='22023'; end if;
    v_required_base:=v_line.quantity*v_factor;
    perform pg_advisory_xact_lock(hashtextextended(v_terminal.default_warehouse_id::text||':'||v_line.inventory_item_id::text,0));
    select coalesce(sum(available_to_allocate),0) into v_available from public.inventory_available_positions where warehouse_id=v_terminal.default_warehouse_id and inventory_item_id=v_line.inventory_item_id and stock_status='AVAILABLE';
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
      order by case when v_line.picking_policy='FEFO' then l.expiry_date end nulls last,
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
        'POS automatic issue from trusted provider-confirmed sale'
      );
      v_total_cost:=v_total_cost+(v_take*v_unit_cost);
      v_remaining:=v_remaining-v_take;
    end loop;
    if v_remaining>0 then raise exception 'POS_STOCK_PICK_FAILED' using errcode='22023'; end if;
  end loop;
  if v_movement_line_no=0 or v_total_cost<=0 then raise exception 'POS_INVENTORY_COST_NOT_READY' using errcode='22023'; end if;

  insert into public.payment_external_events(
    organization_id,organization_node_id,provider_config_id,payment_attempt_id,external_event_id,event_type,payload_hash,
    sanitized_metadata,signature_validation_status,processing_status,provider_reference,merchant_reference,event_amount,event_currency,event_status
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_provider.id,v_attempt.id,new.external_event_id,new.event_type,new.payload_hash,
    new.sanitized_metadata,'VALID','VALIDATED',new.provider_reference,new.merchant_reference,new.amount,new.currency,new.event_status
  ) returning id into v_external_event_row_id;

  v_journal_number:='POSPJ-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.journal_entries(
    organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,source_domain,
    source_entity_type,source_entity_id,source_reference,correlation_id,idempotency_key,status,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_period.id,v_journal_number,current_date,
    'POS '||v_attempt.channel||' provider-confirmed sale '||coalesce(v_sale.sale_number,v_sale.id::text),'COMMERCIAL','SALES_TRANSACTION',v_sale.id,v_sale.sale_number,
    coalesce(v_sale.correlation_id::text,v_sale.id::text),'POS-PROVIDER-JOURNAL:'||new.external_event_id,'DRAFT',v_sale.created_by
  ) returning id into v_journal_id;

  v_journal_line_no:=v_journal_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_sale.organization_id,v_sale.organization_node_id,v_journal_line_no,v_clearing_account.id,v_total,0,'Provider clearing receivable',jsonb_build_object('organization_unit_id',v_sale.organization_unit_id,'sale_id',v_sale.id,'payment_attempt_id',v_attempt.id,'provider_config_id',v_provider.id,'channel',v_attempt.channel));
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

  update public.payment_attempts
    set status='SETTLEMENT_PENDING',provider_reference=new.provider_reference,confirmed_at=now()
  where id=v_attempt.id and status in ('CREATED','PENDING');
  if not found then raise exception 'POS_PROVIDER_ATTEMPT_STATE_RACE' using errcode='55000'; end if;
  update public.payment_intents
    set status='SETTLEMENT_PENDING',confirmed_at=now(),updated_at=now()
  where id=v_intent.id and status in ('CREATED','PENDING');
  if not found then raise exception 'POS_PROVIDER_INTENT_STATE_RACE' using errcode='55000'; end if;

  insert into public.payment_allocations(payment_intent_id,organization_id,organization_node_id,organization_unit_id,allocation_no,target_type,target_id,target_reference,amount,status,allocated_at)
  values(v_intent.id,v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,1,'SALE',v_sale.id,v_sale.sale_number,v_total,'ALLOCATED',now());

  select coalesce(jsonb_agg(jsonb_build_object(
    'line_no',line_no,'description',description,'quantity',quantity,'uom_code',item_snapshot->>'uom_code',
    'unit_price',unit_price,'discount_amount',discount_amount,'tax_amount',tax_amount,'line_total',line_total
  ) order by line_no),'[]'::jsonb)
  into v_receipt_lines from public.sales_transaction_lines where sales_transaction_id=v_sale.id;

  v_receipt_number:='RCP-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.pos_receipts(
    organization_id,organization_node_id,organization_unit_id,sales_transaction_id,pos_shift_id,terminal_id,payment_intent_id,payment_attempt_id,
    receipt_number,currency,subtotal,discount_amount,tax_amount,total_amount,cash_received,change_amount,payment_channel,payload,issued_at,created_by
  ) values(
    v_sale.organization_id,v_sale.organization_node_id,v_sale.organization_unit_id,v_sale.id,v_sale.pos_shift_id,v_sale.terminal_id,v_intent.id,v_attempt.id,
    v_receipt_number,v_sale.currency,v_gross,v_discount,v_tax,v_total,null,null,v_attempt.channel,
    jsonb_build_object('sale_number',v_sale.sale_number,'receipt_number',v_receipt_number,'payment_channel',v_attempt.channel,'provider_code',v_provider.code,'provider_reference',new.provider_reference,'merchant_reference',new.merchant_reference,'lines',v_receipt_lines,'total_cost',round(v_total_cost,2),'issued_at',now()),
    now(),v_sale.created_by
  ) returning id into v_receipt_id;

  update public.sales_transactions
  set status='COMPLETED',inventory_movement_id=v_movement_id,journal_entry_id=v_journal_id,
      receipt_reference=v_receipt_number,sold_at=coalesce(sold_at,now()),completed_at=now(),updated_at=now()
  where id=v_sale.id and status='PAYMENT_PENDING' and payment_intent_id=v_intent.id;
  if not found then raise exception 'POS_PROVIDER_SALE_COMPLETION_STATE_INVALID' using errcode='55000'; end if;

  update public.payment_external_events
  set processing_status='PROCESSED',processed_at=now()
  where id=v_external_event_row_id;

  new.organization_id:=v_sale.organization_id;
  new.organization_node_id:=v_sale.organization_node_id;
  new.organization_unit_id:=v_sale.organization_unit_id;
  new.result_payment_intent_id:=v_intent.id;
  new.result_sales_transaction_id:=v_sale.id;
  new.result_external_event_id:=v_external_event_row_id;
  new.result_inventory_movement_id:=v_movement_id;
  new.result_journal_entry_id:=v_journal_id;
  new.result_receipt_id:=v_receipt_id;
  new.created_at:=now();

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_sale.organization_id,null,'POS_PROVIDER_PAYMENT_CONFIRMED','SALES_TRANSACTION',v_sale.id,
    jsonb_build_object('payment_intent_id',v_intent.id,'payment_attempt_id',v_attempt.id,'provider_config_id',v_provider.id,'provider_code',v_provider.code,'provider_reference',new.provider_reference,'external_event_id',new.external_event_id,'channel',v_attempt.channel,'amount',v_total,'inventory_movement_id',v_movement_id,'journal_entry_id',v_journal_id,'receipt_id',v_receipt_id,'sale_status','COMPLETED','payment_status','SETTLEMENT_PENDING'),
    'Trusted backend provider confirmation completed POS sale; settlement remains pending reconciliation');
  return new;
end;
$$;

create trigger trg_pos_provider_confirmation_before_insert
before insert on public.pos_provider_confirmation_commands
for each row execute function app_private.pos_provider_confirmation_before_insert();

create or replace function public.confirm_pos_provider_payment(
  p_provider_config_id uuid,
  p_payment_attempt_id uuid,
  p_external_event_id text,
  p_event_type text,
  p_provider_reference text,
  p_merchant_reference text,
  p_amount numeric,
  p_currency text,
  p_payload_hash text,
  p_sanitized_metadata jsonb default '{}'::jsonb
)
returns table(
  payment_intent_id uuid,
  sales_transaction_id uuid,
  external_event_row_id uuid,
  inventory_movement_id uuid,
  journal_entry_id uuid,
  receipt_id uuid
)
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_cmd public.pos_provider_confirmation_commands%rowtype;
begin
  select * into v_cmd
  from public.pos_provider_confirmation_commands
  where provider_config_id=p_provider_config_id and external_event_id=nullif(trim(p_external_event_id),'')
  limit 1;
  if v_cmd.id is null then
    insert into public.pos_provider_confirmation_commands(
      provider_config_id,payment_attempt_id,external_event_id,event_type,event_status,provider_reference,merchant_reference,amount,currency,payload_hash,sanitized_metadata
    ) values(
      p_provider_config_id,p_payment_attempt_id,p_external_event_id,p_event_type,'PAID',p_provider_reference,p_merchant_reference,p_amount,p_currency,p_payload_hash,coalesce(p_sanitized_metadata,'{}'::jsonb)
    );
    select * into v_cmd from public.pos_provider_confirmation_commands where provider_config_id=p_provider_config_id and external_event_id=nullif(trim(p_external_event_id),'') limit 1;
  end if;
  if v_cmd.id is null or v_cmd.result_receipt_id is null then raise exception 'POS_PROVIDER_CONFIRMATION_FAILED' using errcode='55000'; end if;
  return query select v_cmd.result_payment_intent_id,v_cmd.result_sales_transaction_id,v_cmd.result_external_event_id,v_cmd.result_inventory_movement_id,v_cmd.result_journal_entry_id,v_cmd.result_receipt_id;
end;
$$;

revoke execute on function public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb) to service_role;

create or replace function public.reconcile_pos_provider_settlement(
  p_provider_config_id uuid,
  p_settlement_reference text,
  p_settlement_date date,
  p_currency text,
  p_items jsonb
)
returns table(settlement_batch_id uuid,settlement_status text,journal_entry_id uuid)
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_provider public.payment_provider_configs%rowtype;
  v_batch public.payment_settlement_batches%rowtype;
  v_item jsonb;
  v_attempt public.payment_attempts%rowtype;
  v_intent public.payment_intents%rowtype;
  v_mapping jsonb;
  v_period public.accounting_periods%rowtype;
  v_bank_code text;
  v_qris_code text;
  v_transfer_code text;
  v_fee_code text;
  v_bank_account public.accounting_accounts%rowtype;
  v_qris_account public.accounting_accounts%rowtype;
  v_transfer_account public.accounting_accounts%rowtype;
  v_fee_account public.accounting_accounts%rowtype;
  v_provider_reference text;
  v_gross numeric(20,2);
  v_fee numeric(20,2);
  v_net numeric(20,2);
  v_total_gross numeric(20,2):=0;
  v_total_fee numeric(20,2):=0;
  v_total_net numeric(20,2):=0;
  v_qris_gross numeric(20,2):=0;
  v_transfer_gross numeric(20,2):=0;
  v_has_exception boolean:=false;
  v_journal_id uuid;
  v_journal_number text;
  v_line_no integer:=0;
  v_match_status text;
  v_currency text:=upper(nullif(trim(p_currency),''));
  v_reference text:=nullif(trim(p_settlement_reference),'');
begin
  if v_reference is null or char_length(v_reference)>200 then raise exception 'POS_SETTLEMENT_REFERENCE_INVALID' using errcode='22023'; end if;
  if p_settlement_date is null then raise exception 'POS_SETTLEMENT_DATE_REQUIRED' using errcode='22023'; end if;
  if v_currency is null or char_length(v_currency)<>3 then raise exception 'POS_SETTLEMENT_CURRENCY_INVALID' using errcode='22023'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>1000 then raise exception 'POS_SETTLEMENT_ITEMS_REQUIRED' using errcode='22023'; end if;

  select * into v_provider from public.payment_provider_configs where id=p_provider_config_id and status='ACTIVE' and config_status='VALIDATED' for update;
  if v_provider.id is null then raise exception 'POS_PAYMENT_PROVIDER_NOT_READY' using errcode='22023'; end if;

  select * into v_batch from public.payment_settlement_batches where organization_node_id=v_provider.organization_node_id and provider_config_id=v_provider.id and settlement_reference=v_reference limit 1;
  if v_batch.id is not null then return query select v_batch.id,v_batch.status,v_batch.journal_entry_id; return; end if;

  insert into public.payment_settlement_batches(organization_id,organization_node_id,provider_config_id,settlement_reference,settlement_date,currency,status,notes)
  values(v_provider.organization_id,v_provider.organization_node_id,v_provider.id,v_reference,p_settlement_date,v_currency,'MATCHING','Backend-ingested provider settlement; every item must match before accounting settlement')
  returning * into v_batch;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_provider_reference:=nullif(trim(v_item->>'provider_reference'),'');
    begin
      v_gross:=(v_item->>'gross_amount')::numeric;
      v_fee:=coalesce((v_item->>'fee_amount')::numeric,0);
      v_net:=(v_item->>'net_amount')::numeric;
    exception when others then
      raise exception 'POS_SETTLEMENT_ITEM_INVALID' using errcode='22023';
    end;
    if v_provider_reference is null or v_gross<=0 or v_fee<0 or v_net<0 or round(v_gross-v_fee-v_net,2)<>0 then raise exception 'POS_SETTLEMENT_ITEM_INVALID' using errcode='22023'; end if;
    v_total_gross:=v_total_gross+v_gross;
    v_total_fee:=v_total_fee+v_fee;
    v_total_net:=v_total_net+v_net;

    select * into v_attempt
    from public.payment_attempts
    where provider_config_id=v_provider.id and provider_reference=v_provider_reference and channel in ('QRIS','BANK_TRANSFER')
    order by confirmed_at desc nulls last,created_at desc limit 1
    for update;

    if v_attempt.id is null then
      v_match_status:='MISSING_INTERNAL';
      v_has_exception:=true;
    elsif v_attempt.status<>'SETTLEMENT_PENDING' then
      v_match_status:='REFERENCE_MISMATCH';
      v_has_exception:=true;
    elsif v_attempt.currency<>v_currency or v_attempt.amount<>v_gross then
      v_match_status:='AMOUNT_MISMATCH';
      v_has_exception:=true;
    else
      v_match_status:='MATCHED';
      if v_attempt.channel='QRIS' then v_qris_gross:=v_qris_gross+v_gross; else v_transfer_gross:=v_transfer_gross+v_gross; end if;
    end if;

    insert into public.payment_settlement_items(settlement_batch_id,organization_id,organization_node_id,payment_attempt_id,provider_reference,gross_amount,fee_amount,net_amount,match_status,notes)
    values(v_batch.id,v_provider.organization_id,v_provider.organization_node_id,v_attempt.id,v_provider_reference,v_gross,v_fee,v_net,v_match_status,case when v_match_status='MATCHED' then 'Exact provider reference / amount / currency match' else 'Fail-closed settlement mismatch' end);
  end loop;

  update public.payment_settlement_batches set gross_amount=v_total_gross,fee_amount=v_total_fee,net_amount=v_total_net where id=v_batch.id;

  if v_has_exception then
    update public.payment_settlement_batches set status='EXCEPTION' where id=v_batch.id returning * into v_batch;
    return query select v_batch.id,v_batch.status,v_batch.journal_entry_id;
    return;
  end if;

  select aem.configuration into v_mapping
  from public.accounting_event_mappings aem
  join public.accounting_event_definitions aed on aed.id=aem.event_definition_id
  where aed.event_code='POS_PROVIDER_SETTLEMENT_POST' and aed.status='ACTIVE'
    and aem.organization_id=v_provider.organization_id and aem.organization_node_id=v_provider.organization_node_id
    and aem.status='ACTIVE'
    and (aem.effective_from is null or aem.effective_from<=p_settlement_date)
    and (aem.effective_until is null or aem.effective_until>=p_settlement_date)
  order by aem.version_no desc limit 1;
  if v_mapping is null then raise exception 'POS_SETTLEMENT_ACCOUNTING_MAPPING_NOT_READY' using errcode='22023'; end if;

  v_bank_code:=nullif(v_mapping->>'bank_account_code','');
  v_qris_code:=nullif(v_mapping->>'qris_clearing_account_code','');
  v_transfer_code:=nullif(v_mapping->>'bank_transfer_clearing_account_code','');
  v_fee_code:=nullif(v_mapping->>'payment_fee_account_code','');
  if v_bank_code is null or (v_qris_gross>0 and v_qris_code is null) or (v_transfer_gross>0 and v_transfer_code is null) or (v_total_fee>0 and v_fee_code is null) then raise exception 'POS_SETTLEMENT_ACCOUNTS_NOT_CONFIGURED' using errcode='22023'; end if;

  select * into v_bank_account from public.accounting_accounts where organization_id=v_provider.organization_id and organization_node_id=v_provider.organization_node_id and code=v_bank_code and status='ACTIVE' and is_posting=true limit 1;
  if v_qris_gross>0 then select * into v_qris_account from public.accounting_accounts where organization_id=v_provider.organization_id and organization_node_id=v_provider.organization_node_id and code=v_qris_code and status='ACTIVE' and is_posting=true limit 1; end if;
  if v_transfer_gross>0 then select * into v_transfer_account from public.accounting_accounts where organization_id=v_provider.organization_id and organization_node_id=v_provider.organization_node_id and code=v_transfer_code and status='ACTIVE' and is_posting=true limit 1; end if;
  if v_total_fee>0 then select * into v_fee_account from public.accounting_accounts where organization_id=v_provider.organization_id and organization_node_id=v_provider.organization_node_id and code=v_fee_code and status='ACTIVE' and is_posting=true limit 1; end if;
  if v_bank_account.id is null or v_bank_account.account_class<>'ASSET' or v_bank_account.normal_balance<>'DEBIT' then raise exception 'POS_SETTLEMENT_BANK_ACCOUNT_INVALID' using errcode='22023'; end if;
  if v_qris_gross>0 and (v_qris_account.id is null or v_qris_account.account_class<>'ASSET' or v_qris_account.normal_balance<>'DEBIT') then raise exception 'POS_SETTLEMENT_QRIS_CLEARING_INVALID' using errcode='22023'; end if;
  if v_transfer_gross>0 and (v_transfer_account.id is null or v_transfer_account.account_class<>'ASSET' or v_transfer_account.normal_balance<>'DEBIT') then raise exception 'POS_SETTLEMENT_TRANSFER_CLEARING_INVALID' using errcode='22023'; end if;
  if v_total_fee>0 and (v_fee_account.id is null or v_fee_account.account_class<>'EXPENSE' or v_fee_account.normal_balance<>'DEBIT') then raise exception 'POS_SETTLEMENT_FEE_ACCOUNT_INVALID' using errcode='22023'; end if;

  select * into v_period from public.accounting_periods
  where organization_id=v_provider.organization_id and organization_node_id=v_provider.organization_node_id
    and p_settlement_date between start_date and end_date and status='OPEN'
  order by start_date desc limit 1;
  if v_period.id is null then raise exception 'POS_SETTLEMENT_ACCOUNTING_PERIOD_NOT_OPEN' using errcode='22023'; end if;

  v_journal_number:='POSSET-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISSMS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into public.journal_entries(organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,source_domain,source_entity_type,source_entity_id,source_reference,correlation_id,idempotency_key,status,created_by)
  values(v_provider.organization_id,v_provider.organization_node_id,v_period.id,v_journal_number,p_settlement_date,'Provider settlement '||v_reference,'PAYMENT','PAYMENT_SETTLEMENT_BATCH',v_batch.id,v_reference,v_batch.id::text,'POS-SETTLEMENT:'||v_provider.id::text||':'||v_reference,'DRAFT',null)
  returning id into v_journal_id;

  v_line_no:=v_line_no+1;
  insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
  values(v_journal_id,v_provider.organization_id,v_provider.organization_node_id,v_line_no,v_bank_account.id,v_total_net,0,'Provider settlement net received',jsonb_build_object('provider_config_id',v_provider.id,'settlement_batch_id',v_batch.id));
  if v_total_fee>0 then
    v_line_no:=v_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_provider.organization_id,v_provider.organization_node_id,v_line_no,v_fee_account.id,v_total_fee,0,'Provider processing fee',jsonb_build_object('provider_config_id',v_provider.id,'settlement_batch_id',v_batch.id));
  end if;
  if v_qris_gross>0 then
    v_line_no:=v_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_provider.organization_id,v_provider.organization_node_id,v_line_no,v_qris_account.id,0,v_qris_gross,'Clear QRIS provider receivable',jsonb_build_object('provider_config_id',v_provider.id,'settlement_batch_id',v_batch.id));
  end if;
  if v_transfer_gross>0 then
    v_line_no:=v_line_no+1;
    insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions)
    values(v_journal_id,v_provider.organization_id,v_provider.organization_node_id,v_line_no,v_transfer_account.id,0,v_transfer_gross,'Clear bank-transfer provider receivable',jsonb_build_object('provider_config_id',v_provider.id,'settlement_batch_id',v_batch.id));
  end if;

  update public.journal_entries set status='VALIDATED' where id=v_journal_id;
  update public.journal_entries set status='POSTED' where id=v_journal_id;

  for v_attempt in
    select pa.* from public.payment_attempts pa
    join public.payment_settlement_items psi on psi.payment_attempt_id=pa.id
    where psi.settlement_batch_id=v_batch.id and psi.match_status='MATCHED'
    for update
  loop
    update public.payment_attempts set status='SETTLED',settled_at=now() where id=v_attempt.id and status='SETTLEMENT_PENDING';
    update public.payment_intents set status='SETTLED',settled_at=now(),updated_at=now() where id=v_attempt.payment_intent_id and status='SETTLEMENT_PENDING';
  end loop;

  update public.payment_settlement_batches set status='RECONCILED',journal_entry_id=v_journal_id,reconciled_at=now() where id=v_batch.id returning * into v_batch;

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_provider.organization_id,null,'POS_PROVIDER_SETTLEMENT_RECONCILED','PAYMENT_SETTLEMENT_BATCH',v_batch.id,
    jsonb_build_object('provider_config_id',v_provider.id,'settlement_reference',v_reference,'gross_amount',v_total_gross,'fee_amount',v_total_fee,'net_amount',v_total_net,'journal_entry_id',v_journal_id,'status','RECONCILED'),
    'Trusted backend settlement reconciled only after every provider item matched internal payment state');

  return query select v_batch.id,v_batch.status,v_batch.journal_entry_id;
end;
$$;

revoke execute on function public.reconcile_pos_provider_settlement(uuid,text,date,text,jsonb) from public,anon,authenticated;
grant execute on function public.reconcile_pos_provider_settlement(uuid,text,date,text,jsonb) to service_role;

comment on function public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb)
is 'Backend-only trusted provider confirmation. Caller must verify provider signature before invoking; screenshots/manual cashier input are never accepted as provider evidence.';

comment on function public.reconcile_pos_provider_settlement(uuid,text,date,text,jsonb)
is 'Backend-only settlement reconciliation. Exact reference/amount/currency match and balanced accounting are required before payment moves from SETTLEMENT_PENDING to SETTLED.';
