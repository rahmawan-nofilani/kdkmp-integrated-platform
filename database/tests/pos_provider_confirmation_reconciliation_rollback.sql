\set ON_ERROR_STOP on

begin;

-- Disposable CI identities / scope.
insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,is_sso_user,is_anonymous
) values (
  '10900000-0000-4000-8000-000000000001','authenticated','authenticated',
  'pos-provider-ci@example.invalid',now(),'{}'::jsonb,'{}'::jsonb,
  now(),now(),false,false
);
update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),
    full_name='POS Provider CI',status='ACTIVE',updated_at=now()
where auth_user_id='10900000-0000-4000-8000-000000000001';
select id as profile_id from public.profiles where auth_user_id='10900000-0000-4000-8000-000000000001'\gset
select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
select id as warehouse_id from public.warehouses where organization_unit_id=:'unit_id'::uuid and code='DEMO-RETAIL-WH' limit 1\gset
select id as warehouse_node_id from public.warehouse_nodes where warehouse_id=:'warehouse_id'::uuid and code='RETAIL-BIN-01' limit 1\gset
select id as terminal_id from public.pos_terminals where organization_unit_id=:'unit_id'::uuid and code='DEMO-POS-01' limit 1\gset
select id as item_id,base_uom_id as uom_id from public.inventory_items where sku='DEMO-GULA-1KG' limit 1\gset
select id as period_id from public.accounting_periods where organization_node_id=:'node_id'::uuid and current_date between start_date and end_date and status='OPEN' order by start_date desc limit 1\gset

-- Ensure deterministic posting accounts for provider clearing / settlement.
insert into public.accounting_accounts(
  organization_id,organization_node_id,code,name,account_class,normal_balance,
  is_posting,is_control_account,status,effective_from,notes
)
select :'org_id'::uuid,:'node_id'::uuid,v.code,v.name,v.account_class,v.normal_balance,
       true,false,'ACTIVE',current_date,'Disposable trusted provider CI account'
from (values
  ('410100','CI — Pendapatan POS','REVENUE','CREDIT'),
  ('130100','CI — Persediaan POS','ASSET','DEBIT'),
  ('510100','CI — HPP POS','EXPENSE','DEBIT'),
  ('111100','CI — QRIS Clearing','ASSET','DEBIT'),
  ('111200','CI — Transfer Clearing','ASSET','DEBIT'),
  ('112100','CI — Bank Settlement','ASSET','DEBIT'),
  ('610100','CI — Provider Fee','EXPENSE','DEBIT')
) as v(code,name,account_class,normal_balance)
on conflict (organization_node_id,code) do nothing;

select id as sales_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='410100' limit 1\gset
select id as inventory_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='130100' limit 1\gset
select id as cogs_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='510100' limit 1\gset
select id as qris_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='111100' limit 1\gset
select id as bank_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='112100' limit 1\gset
select id as fee_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='610100' limit 1\gset

select id as sale_event_id from public.accounting_event_definitions where event_code='POS_PROVIDER_SALE_POST'\gset
select id as settlement_event_id from public.accounting_event_definitions where event_code='POS_PROVIDER_SETTLEMENT_POST'\gset
insert into public.accounting_event_mappings(
  organization_id,organization_node_id,event_definition_id,version_no,configuration,status,effective_from,created_by,approved_by,approved_at
) values
(:'org_id'::uuid,:'node_id'::uuid,:'sale_event_id'::uuid,1,
 jsonb_build_object(
  'qris_clearing_account_code','111100','bank_transfer_clearing_account_code','111200',
  'sales_revenue_account_code','410100','inventory_account_code','130100','cogs_account_code','510100'
 ),'ACTIVE',current_date,:'profile_id'::uuid,:'profile_id'::uuid,now()),
(:'org_id'::uuid,:'node_id'::uuid,:'settlement_event_id'::uuid,1,
 jsonb_build_object(
  'bank_account_code','112100','qris_clearing_account_code','111100',
  'bank_transfer_clearing_account_code','111200','payment_fee_account_code','610100'
 ),'ACTIVE',current_date,:'profile_id'::uuid,:'profile_id'::uuid,now());

-- Provider is synthetic and exists only inside this rolled-back transaction.
insert into public.payment_provider_configs(
  id,organization_id,organization_node_id,organization_unit_id,code,provider_type,provider_name,
  supported_channels,config_status,status,secret_storage_reference,notes
) values(
  '10900000-0000-4000-8000-000000000010',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  'CI-QRIS-PROVIDER','PJP','CI QRIS Provider',array['QRIS'],'VALIDATED','ACTIVE',
  'ci://no-secret','Disposable provider; no real credential'
);

-- Ensure stock exists and weighted-average cost is resolvable.
insert into public.inventory_movements(
  id,organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
  source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at,created_by
) values(
  '10900000-0000-4000-8000-000000000020',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'warehouse_id'::uuid,
  'CI-PROVIDER-STOCK','ADJUSTMENT_IN','POSTED','INVENTORY','CI_PROVIDER_FIXTURE','CI-PROVIDER-STOCK','CI-PROVIDER-STOCK',now(),now(),:'profile_id'::uuid
);
insert into public.inventory_movement_lines(
  organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,
  to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes
) values(
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10900000-0000-4000-8000-000000000020',1,:'item_id'::uuid,:'uom_id'::uuid,
  :'warehouse_node_id'::uuid,'AVAILABLE',10,10,60000,'Disposable provider confirmation stock'
);

select price_entry_id as price_entry_id,unit_price as unit_price
from app_private.resolve_pos_price(:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'item_id'::uuid,:'uom_id'::uuid,1,now())\gset

DO $$
BEGIN
  IF :'price_entry_id' = '' OR :'unit_price' = '' THEN
    RAISE EXCEPTION 'POS_PROVIDER_CI_PRICE_NOT_READY';
  END IF;
END $$;

insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values(
  '10900000-0000-4000-8000-000000000030',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'profile_id'::uuid,'POSSHIFT-CI-PROVIDER','OPEN',0,'PENDING'
);

insert into public.payment_intents(
  id,organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,
  source_domain,source_entity_type,source_entity_id,source_reference,amount,currency,status,idempotency_key,created_by
) values(
  '10900000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'POSPAY-CI-PROVIDER',
  'SALE','COMMERCIAL','SALES_TRANSACTION','10900000-0000-4000-8000-000000000050','SALE-CI-PROVIDER',:'unit_price'::numeric,'IDR','CREATED','POSPAY:CI-PROVIDER',:'profile_id'::uuid
);
insert into public.payment_attempts(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,provider_config_id,
  attempt_no,channel,amount,currency,status,merchant_reference
) values(
  '10900000-0000-4000-8000-000000000041','10900000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  '10900000-0000-4000-8000-000000000010',1,'QRIS',:'unit_price'::numeric,'IDR','CREATED','POSPAY-CI-PROVIDER'
);

insert into public.sales_transactions(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,sale_number,sale_type,currency,
  subtotal,discount_amount,tax_amount,status,payment_intent_id,local_transaction_id,device_id,client_sequence,
  idempotency_key,sync_status,correlation_id,created_by
) values(
  '10900000-0000-4000-8000-000000000050',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  '10900000-0000-4000-8000-000000000030','SALE-CI-PROVIDER','POS','IDR',:'unit_price'::numeric,0,0,'PAYMENT_PENDING',
  '10900000-0000-4000-8000-000000000040','LOCAL-CI-PROVIDER','CI-DEVICE',1,'POS-CI-PROVIDER-SALE','SYNCED',
  '10900000-0000-4000-8000-000000000099',:'profile_id'::uuid
);
insert into public.sales_transaction_lines(
  id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,
  description,uom_id,quantity,unit_price,discount_amount,tax_amount
) values(
  '10900000-0000-4000-8000-000000000051',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10900000-0000-4000-8000-000000000050',1,
  :'item_id'::uuid,jsonb_build_object('price_entry_id',:'price_entry_id','factor_to_base',1,'uom_code','CI'),
  'CI Provider Sale Item',:'uom_id'::uuid,1,:'unit_price'::numeric,0,0
);

-- API boundary: browser/authenticated roles must not be able to call trusted backend RPCs.
DO $$
BEGIN
  IF has_function_privilege('authenticated','public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_MUST_NOT_BE_AUTHENTICATED_EXECUTABLE';
  END IF;
  IF has_function_privilege('authenticated','public.reconcile_pos_provider_settlement(uuid,text,date,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_MUST_NOT_BE_AUTHENTICATED_EXECUTABLE';
  END IF;
  IF NOT has_function_privilege('service_role','public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_SERVICE_ROLE_EXECUTE_REQUIRED';
  END IF;
END $$;

create temporary table ci_provider_confirmation_result(
  payment_intent_id uuid,sales_transaction_id uuid,external_event_row_id uuid,
  inventory_movement_id uuid,journal_entry_id uuid,receipt_id uuid
) on commit drop;

set local role service_role;
insert into ci_provider_confirmation_result
select * from public.confirm_pos_provider_payment(
  '10900000-0000-4000-8000-000000000010','10900000-0000-4000-8000-000000000041',
  'CI-EVENT-PAID-001','PAYMENT.PAID','PROVIDER-REF-CI-001','POSPAY-CI-PROVIDER',
  :'unit_price'::numeric,'IDR',repeat('a',64),'{"source":"ci","signature_verified":true}'::jsonb
);
reset role;

DO $$
DECLARE
  v_result ci_provider_confirmation_result%rowtype;
  v_debit numeric; v_credit numeric;
BEGIN
  SELECT * INTO v_result FROM ci_provider_confirmation_result LIMIT 1;
  IF v_result.receipt_id IS NULL OR v_result.journal_entry_id IS NULL OR v_result.inventory_movement_id IS NULL THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_RESULT_INCOMPLETE';
  END IF;
  IF (SELECT status FROM public.sales_transactions WHERE id='10900000-0000-4000-8000-000000000050') <> 'COMPLETED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_SALE_NOT_COMPLETED';
  END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLEMENT_PENDING' THEN
    RAISE EXCEPTION 'POS_PROVIDER_ATTEMPT_NOT_SETTLEMENT_PENDING';
  END IF;
  IF (SELECT status FROM public.payment_intents WHERE id='10900000-0000-4000-8000-000000000040') <> 'SETTLEMENT_PENDING' THEN
    RAISE EXCEPTION 'POS_PROVIDER_INTENT_NOT_SETTLEMENT_PENDING';
  END IF;
  IF (SELECT payment_channel FROM public.pos_receipts WHERE id=v_result.receipt_id) <> 'QRIS' THEN
    RAISE EXCEPTION 'POS_PROVIDER_RECEIPT_CHANNEL_INVALID';
  END IF;
  IF (SELECT cash_received IS NOT NULL FROM public.pos_receipts WHERE id=v_result.receipt_id) THEN
    RAISE EXCEPTION 'POS_PROVIDER_RECEIPT_MUST_NOT_RECORD_CASH';
  END IF;
  IF (SELECT count(*) FROM public.pos_cash_movements WHERE sales_transaction_id='10900000-0000-4000-8000-000000000050') <> 0 THEN
    RAISE EXCEPTION 'POS_PROVIDER_SALE_MUST_NOT_CREATE_CASH_MOVEMENT';
  END IF;
  IF (SELECT count(*) FROM public.payment_external_events WHERE external_event_id='CI-EVENT-PAID-001' AND signature_validation_status='VALID' AND processing_status='PROCESSED') <> 1 THEN
    RAISE EXCEPTION 'POS_PROVIDER_EXTERNAL_EVENT_EVIDENCE_INVALID';
  END IF;
  IF (SELECT movement_type||':'||status FROM public.inventory_movements WHERE id=v_result.inventory_movement_id) <> 'SALE_ISSUE:POSTED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_INVENTORY_NOT_POSTED';
  END IF;
  IF (SELECT status FROM public.journal_entries WHERE id=v_result.journal_entry_id) <> 'POSTED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_SALE_JOURNAL_NOT_POSTED';
  END IF;
  SELECT sum(debit),sum(credit) INTO v_debit,v_credit FROM public.journal_lines WHERE journal_entry_id=v_result.journal_entry_id;
  IF v_debit IS DISTINCT FROM v_credit THEN RAISE EXCEPTION 'POS_PROVIDER_SALE_JOURNAL_UNBALANCED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journal_lines WHERE journal_entry_id=v_result.journal_entry_id AND account_id=:'qris_account_id'::uuid AND debit=:'unit_price'::numeric) THEN
    RAISE EXCEPTION 'POS_PROVIDER_CLEARING_DEBIT_MISSING';
  END IF;
END $$;

-- Same trusted event is idempotent and must not duplicate authoritative artifacts.
set local role service_role;
select * from public.confirm_pos_provider_payment(
  '10900000-0000-4000-8000-000000000010','10900000-0000-4000-8000-000000000041',
  'CI-EVENT-PAID-001','PAYMENT.PAID','PROVIDER-REF-CI-001','POSPAY-CI-PROVIDER',
  :'unit_price'::numeric,'IDR',repeat('a',64),'{"source":"ci","signature_verified":true}'::jsonb
)\gset retry_
reset role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.pos_provider_confirmation_commands WHERE external_event_id='CI-EVENT-PAID-001') <> 1 THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_NOT_IDEMPOTENT';
  END IF;
  IF (SELECT count(*) FROM public.pos_receipts WHERE sales_transaction_id='10900000-0000-4000-8000-000000000050') <> 1 THEN
    RAISE EXCEPTION 'POS_PROVIDER_RECEIPT_DUPLICATED';
  END IF;
END $$;

-- Mismatched settlement must fail closed: batch EXCEPTION, no journal, payment unchanged.
set local role service_role;
select * from public.reconcile_pos_provider_settlement(
  '10900000-0000-4000-8000-000000000010','CI-SETTLEMENT-BAD',current_date,'IDR',
  jsonb_build_array(jsonb_build_object('provider_reference','PROVIDER-REF-CI-001','gross_amount',:'unit_price'::numeric+1000,'fee_amount',0,'net_amount',:'unit_price'::numeric+1000))
)\gset bad_
reset role;
DO $$
BEGIN
  IF :'bad_settlement_status' <> 'EXCEPTION' THEN RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_NOT_EXCEPTION'; END IF;
  IF :'bad_journal_entry_id' <> '' THEN RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_MUST_NOT_POST_JOURNAL'; END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLEMENT_PENDING' THEN
    RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_MUTATED_PAYMENT';
  END IF;
END $$;

-- Exact settlement posts clearing -> bank/fee and settles payment state.
set local role service_role;
select * from public.reconcile_pos_provider_settlement(
  '10900000-0000-4000-8000-000000000010','CI-SETTLEMENT-GOOD',current_date,'IDR',
  jsonb_build_array(jsonb_build_object('provider_reference','PROVIDER-REF-CI-001','gross_amount',:'unit_price'::numeric,'fee_amount',1000,'net_amount',:'unit_price'::numeric-1000))
)\gset good_
reset role;
DO $$
DECLARE v_debit numeric; v_credit numeric;
BEGIN
  IF :'good_settlement_status' <> 'RECONCILED' OR :'good_journal_entry_id' = '' THEN
    RAISE EXCEPTION 'POS_PROVIDER_GOOD_SETTLEMENT_NOT_RECONCILED';
  END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_ATTEMPT_NOT_SETTLED';
  END IF;
  IF (SELECT status FROM public.payment_intents WHERE id='10900000-0000-4000-8000-000000000040') <> 'SETTLED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_INTENT_NOT_SETTLED';
  END IF;
  IF (SELECT match_status FROM public.payment_settlement_items WHERE settlement_batch_id=:'good_settlement_batch_id'::uuid LIMIT 1) <> 'MATCHED' THEN
    RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_ITEM_NOT_MATCHED';
  END IF;
  SELECT sum(debit),sum(credit) INTO v_debit,v_credit FROM public.journal_lines WHERE journal_entry_id=:'good_journal_entry_id'::uuid;
  IF v_debit IS DISTINCT FROM v_credit THEN RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_JOURNAL_UNBALANCED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journal_lines WHERE journal_entry_id=:'good_journal_entry_id'::uuid AND account_id=:'bank_account_id'::uuid AND debit=:'unit_price'::numeric-1000) THEN
    RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_BANK_DEBIT_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journal_lines WHERE journal_entry_id=:'good_journal_entry_id'::uuid AND account_id=:'fee_account_id'::uuid AND debit=1000) THEN
    RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_FEE_DEBIT_MISSING';
  END IF;
END $$;

rollback;

-- Rollback guard: test leaves no synthetic provider evidence behind.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.payment_provider_configs WHERE code='CI-QRIS-PROVIDER') THEN
    RAISE EXCEPTION 'POS_PROVIDER_CI_ROLLBACK_FAILED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.payment_external_events WHERE external_event_id='CI-EVENT-PAID-001') THEN
    RAISE EXCEPTION 'POS_PROVIDER_EVENT_ROLLBACK_FAILED';
  END IF;
END $$;
