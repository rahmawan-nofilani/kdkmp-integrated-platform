\set ON_ERROR_STOP on

begin;

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

insert into public.accounting_accounts(
  organization_id,organization_node_id,code,name,account_class,normal_balance,is_posting,is_control_account,status,effective_from,notes
)
select :'org_id'::uuid,:'node_id'::uuid,v.code,v.name,v.class,v.balance,true,false,'ACTIVE',current_date,'Disposable provider CI account'
from (values
  ('410100','CI Revenue','REVENUE','CREDIT'),
  ('130100','CI Inventory','ASSET','DEBIT'),
  ('510100','CI COGS','EXPENSE','DEBIT'),
  ('111100','CI QRIS Clearing','ASSET','DEBIT'),
  ('111200','CI Transfer Clearing','ASSET','DEBIT'),
  ('112100','CI Bank Settlement','ASSET','DEBIT'),
  ('610100','CI Provider Fee','EXPENSE','DEBIT')
) v(code,name,class,balance)
on conflict (organization_node_id,code) do nothing;

select id as sale_event_id from public.accounting_event_definitions where event_code='POS_PROVIDER_SALE_POST'\gset
select id as settlement_event_id from public.accounting_event_definitions where event_code='POS_PROVIDER_SETTLEMENT_POST'\gset
insert into public.accounting_event_mappings(
  organization_id,organization_node_id,event_definition_id,version_no,configuration,status,effective_from,created_by,approved_by,approved_at
) values
(:'org_id'::uuid,:'node_id'::uuid,:'sale_event_id'::uuid,1,
 jsonb_build_object('qris_clearing_account_code','111100','bank_transfer_clearing_account_code','111200','sales_revenue_account_code','410100','inventory_account_code','130100','cogs_account_code','510100'),
 'ACTIVE',current_date,:'profile_id'::uuid,:'profile_id'::uuid,now()),
(:'org_id'::uuid,:'node_id'::uuid,:'settlement_event_id'::uuid,1,
 jsonb_build_object('bank_account_code','112100','qris_clearing_account_code','111100','bank_transfer_clearing_account_code','111200','payment_fee_account_code','610100'),
 'ACTIVE',current_date,:'profile_id'::uuid,:'profile_id'::uuid,now());

insert into public.payment_provider_configs(
  id,organization_id,organization_node_id,organization_unit_id,code,provider_type,provider_name,supported_channels,config_status,status,secret_storage_reference,notes
) values(
  '10900000-0000-4000-8000-000000000010',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  'CI-QRIS-PROVIDER','PJP','CI QRIS Provider',array['QRIS'],'VALIDATED','ACTIVE','ci://no-secret','Rolled-back synthetic provider only'
);

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

select price_entry_id,unit_price
from app_private.resolve_pos_price(:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'item_id'::uuid,:'uom_id'::uuid,1,now())\gset

insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,shift_number,status,opening_cash,reconciliation_status
) values(
  '10900000-0000-4000-8000-000000000030',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'profile_id'::uuid,'POSSHIFT-CI-PROVIDER','OPEN',0,'PENDING'
);
insert into public.payment_intents(
  id,organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,source_domain,source_entity_type,
  source_entity_id,source_reference,amount,currency,status,idempotency_key,created_by
) values(
  '10900000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'POSPAY-CI-PROVIDER','SALE','COMMERCIAL','SALES_TRANSACTION',
  '10900000-0000-4000-8000-000000000050','SALE-CI-PROVIDER',:'unit_price'::numeric,'IDR','CREATED','POSPAY:CI-PROVIDER',:'profile_id'::uuid
);
insert into public.payment_attempts(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,provider_config_id,attempt_no,channel,amount,currency,status,merchant_reference
) values(
  '10900000-0000-4000-8000-000000000041','10900000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  '10900000-0000-4000-8000-000000000010',1,'QRIS',:'unit_price'::numeric,'IDR','CREATED','POSPAY-CI-PROVIDER'
);
insert into public.sales_transactions(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,sale_number,sale_type,currency,
  subtotal,discount_amount,tax_amount,status,payment_intent_id,local_transaction_id,device_id,client_sequence,idempotency_key,sync_status,correlation_id,created_by
) values(
  '10900000-0000-4000-8000-000000000050',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  '10900000-0000-4000-8000-000000000030','SALE-CI-PROVIDER','POS','IDR',:'unit_price'::numeric,0,0,'PAYMENT_PENDING',
  '10900000-0000-4000-8000-000000000040','LOCAL-CI-PROVIDER','CI-DEVICE',1,'POS-CI-PROVIDER-SALE','SYNCED','10900000-0000-4000-8000-000000000099',:'profile_id'::uuid
);
insert into public.sales_transaction_lines(
  id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,description,uom_id,quantity,unit_price,discount_amount,tax_amount
) values(
  '10900000-0000-4000-8000-000000000051',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10900000-0000-4000-8000-000000000050',1,
  :'item_id'::uuid,jsonb_build_object('price_entry_id',:'price_entry_id','factor_to_base',1,'uom_code','CI'),'CI Provider Sale Item',:'uom_id'::uuid,1,:'unit_price'::numeric,0,0
);

DO $$
BEGIN
  IF has_function_privilege('authenticated','public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_AUTHENTICATED_EXECUTE_FORBIDDEN';
  END IF;
  IF has_function_privilege('authenticated','public.reconcile_pos_provider_settlement(uuid,text,date,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_AUTHENTICATED_EXECUTE_FORBIDDEN';
  END IF;
  IF NOT has_function_privilege('service_role','public.confirm_pos_provider_payment(uuid,uuid,text,text,text,text,numeric,text,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_SERVICE_ROLE_REQUIRED';
  END IF;
END $$;

set local role service_role;
select * from public.confirm_pos_provider_payment(
  '10900000-0000-4000-8000-000000000010','10900000-0000-4000-8000-000000000041',
  'CI-EVENT-PAID-001','PAYMENT.PAID','PROVIDER-REF-CI-001','POSPAY-CI-PROVIDER',
  :'unit_price'::numeric,'IDR',repeat('a',64),'{"source":"ci","signature_verified":true}'::jsonb
);
reset role;

DO $$
DECLARE v_journal uuid; v_debit numeric; v_credit numeric;
BEGIN
  IF (SELECT status FROM public.sales_transactions WHERE id='10900000-0000-4000-8000-000000000050') <> 'COMPLETED' THEN RAISE EXCEPTION 'POS_PROVIDER_SALE_NOT_COMPLETED'; END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLEMENT_PENDING' THEN RAISE EXCEPTION 'POS_PROVIDER_ATTEMPT_NOT_PENDING_SETTLEMENT'; END IF;
  IF (SELECT status FROM public.payment_intents WHERE id='10900000-0000-4000-8000-000000000040') <> 'SETTLEMENT_PENDING' THEN RAISE EXCEPTION 'POS_PROVIDER_INTENT_NOT_PENDING_SETTLEMENT'; END IF;
  IF (SELECT count(*) FROM public.payment_external_events WHERE external_event_id='CI-EVENT-PAID-001' AND signature_validation_status='VALID' AND processing_status='PROCESSED') <> 1 THEN RAISE EXCEPTION 'POS_PROVIDER_EVENT_EVIDENCE_INVALID'; END IF;
  IF (SELECT count(*) FROM public.pos_receipts WHERE sales_transaction_id='10900000-0000-4000-8000-000000000050' AND payment_channel='QRIS' AND cash_received IS NULL AND change_amount IS NULL) <> 1 THEN RAISE EXCEPTION 'POS_PROVIDER_NONCASH_RECEIPT_INVALID'; END IF;
  IF (SELECT count(*) FROM public.pos_cash_movements WHERE sales_transaction_id='10900000-0000-4000-8000-000000000050') <> 0 THEN RAISE EXCEPTION 'POS_PROVIDER_CASH_MOVEMENT_FORBIDDEN'; END IF;
  IF (SELECT count(*) FROM public.inventory_movements WHERE source_entity_id='10900000-0000-4000-8000-000000000050' AND movement_type='SALE_ISSUE' AND status='POSTED') <> 1 THEN RAISE EXCEPTION 'POS_PROVIDER_INVENTORY_ISSUE_INVALID'; END IF;
  SELECT journal_entry_id INTO v_journal FROM public.sales_transactions WHERE id='10900000-0000-4000-8000-000000000050';
  IF v_journal IS NULL OR (SELECT status FROM public.journal_entries WHERE id=v_journal) <> 'POSTED' THEN RAISE EXCEPTION 'POS_PROVIDER_SALE_JOURNAL_INVALID'; END IF;
  SELECT sum(debit),sum(credit) INTO v_debit,v_credit FROM public.journal_lines WHERE journal_entry_id=v_journal;
  IF v_debit IS DISTINCT FROM v_credit THEN RAISE EXCEPTION 'POS_PROVIDER_SALE_JOURNAL_UNBALANCED'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.journal_lines jl JOIN public.accounting_accounts a ON a.id=jl.account_id
    WHERE jl.journal_entry_id=v_journal AND a.code='111100' AND jl.debit=(SELECT total_amount FROM public.sales_transactions WHERE id='10900000-0000-4000-8000-000000000050')
  ) THEN RAISE EXCEPTION 'POS_PROVIDER_CLEARING_DEBIT_MISSING'; END IF;
END $$;

-- Idempotent retry must not duplicate sale evidence.
set local role service_role;
select * from public.confirm_pos_provider_payment(
  '10900000-0000-4000-8000-000000000010','10900000-0000-4000-8000-000000000041',
  'CI-EVENT-PAID-001','PAYMENT.PAID','PROVIDER-REF-CI-001','POSPAY-CI-PROVIDER',
  :'unit_price'::numeric,'IDR',repeat('a',64),'{"source":"ci","signature_verified":true}'::jsonb
);
reset role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.pos_provider_confirmation_commands WHERE external_event_id='CI-EVENT-PAID-001') <> 1 THEN RAISE EXCEPTION 'POS_PROVIDER_CONFIRMATION_NOT_IDEMPOTENT'; END IF;
  IF (SELECT count(*) FROM public.pos_receipts WHERE sales_transaction_id='10900000-0000-4000-8000-000000000050') <> 1 THEN RAISE EXCEPTION 'POS_PROVIDER_RECEIPT_DUPLICATED'; END IF;
END $$;

-- Mismatch is recorded as EXCEPTION and must not settle payment or post settlement journal.
set local role service_role;
select * from public.reconcile_pos_provider_settlement(
  '10900000-0000-4000-8000-000000000010','CI-SETTLEMENT-BAD',current_date,'IDR',
  jsonb_build_array(jsonb_build_object('provider_reference','PROVIDER-REF-CI-001','gross_amount',:'unit_price'::numeric+1000,'fee_amount',0,'net_amount',:'unit_price'::numeric+1000))
);
reset role;
DO $$
BEGIN
  IF (SELECT status FROM public.payment_settlement_batches WHERE settlement_reference='CI-SETTLEMENT-BAD') <> 'EXCEPTION' THEN RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_NOT_EXCEPTION'; END IF;
  IF (SELECT journal_entry_id FROM public.payment_settlement_batches WHERE settlement_reference='CI-SETTLEMENT-BAD') IS NOT NULL THEN RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_POSTED_JOURNAL'; END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLEMENT_PENDING' THEN RAISE EXCEPTION 'POS_PROVIDER_BAD_SETTLEMENT_MUTATED_PAYMENT'; END IF;
END $$;

set local role service_role;
select * from public.reconcile_pos_provider_settlement(
  '10900000-0000-4000-8000-000000000010','CI-SETTLEMENT-GOOD',current_date,'IDR',
  jsonb_build_array(jsonb_build_object('provider_reference','PROVIDER-REF-CI-001','gross_amount',:'unit_price'::numeric,'fee_amount',1000,'net_amount',:'unit_price'::numeric-1000))
);
reset role;
DO $$
DECLARE v_batch uuid; v_journal uuid; v_debit numeric; v_credit numeric; v_total numeric;
BEGIN
  SELECT id,journal_entry_id INTO v_batch,v_journal FROM public.payment_settlement_batches WHERE settlement_reference='CI-SETTLEMENT-GOOD';
  SELECT total_amount INTO v_total FROM public.sales_transactions WHERE id='10900000-0000-4000-8000-000000000050';
  IF (SELECT status FROM public.payment_settlement_batches WHERE id=v_batch) <> 'RECONCILED' OR v_journal IS NULL THEN RAISE EXCEPTION 'POS_PROVIDER_GOOD_SETTLEMENT_NOT_RECONCILED'; END IF;
  IF (SELECT status FROM public.payment_attempts WHERE id='10900000-0000-4000-8000-000000000041') <> 'SETTLED' THEN RAISE EXCEPTION 'POS_PROVIDER_ATTEMPT_NOT_SETTLED'; END IF;
  IF (SELECT status FROM public.payment_intents WHERE id='10900000-0000-4000-8000-000000000040') <> 'SETTLED' THEN RAISE EXCEPTION 'POS_PROVIDER_INTENT_NOT_SETTLED'; END IF;
  IF (SELECT match_status FROM public.payment_settlement_items WHERE settlement_batch_id=v_batch LIMIT 1) <> 'MATCHED' THEN RAISE EXCEPTION 'POS_PROVIDER_ITEM_NOT_MATCHED'; END IF;
  SELECT sum(debit),sum(credit) INTO v_debit,v_credit FROM public.journal_lines WHERE journal_entry_id=v_journal;
  IF v_debit IS DISTINCT FROM v_credit THEN RAISE EXCEPTION 'POS_PROVIDER_SETTLEMENT_JOURNAL_UNBALANCED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journal_lines jl JOIN public.accounting_accounts a ON a.id=jl.account_id WHERE jl.journal_entry_id=v_journal AND a.code='112100' AND jl.debit=v_total-1000) THEN RAISE EXCEPTION 'POS_PROVIDER_BANK_DEBIT_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journal_lines jl JOIN public.accounting_accounts a ON a.id=jl.account_id WHERE jl.journal_entry_id=v_journal AND a.code='610100' AND jl.debit=1000) THEN RAISE EXCEPTION 'POS_PROVIDER_FEE_DEBIT_MISSING'; END IF;
END $$;

rollback;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.payment_provider_configs WHERE code='CI-QRIS-PROVIDER') THEN RAISE EXCEPTION 'POS_PROVIDER_CI_ROLLBACK_FAILED'; END IF;
  IF EXISTS (SELECT 1 FROM public.payment_external_events WHERE external_event_id='CI-EVENT-PAID-001') THEN RAISE EXCEPTION 'POS_PROVIDER_EVENT_ROLLBACK_FAILED'; END IF;
END $$;
