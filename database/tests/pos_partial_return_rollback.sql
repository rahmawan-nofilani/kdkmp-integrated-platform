\set ON_ERROR_STOP on

begin;

insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,is_sso_user,is_anonymous
) values (
  '10800000-0000-4000-8000-000000000001','authenticated','authenticated',
  'pos-partial-return-ci@example.invalid',now(),'{}'::jsonb,'{}'::jsonb,
  now(),now(),false,false
);

update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),
    full_name='POS Partial Return CI',status='ACTIVE',updated_at=now()
where auth_user_id='10800000-0000-4000-8000-000000000001';

select id as profile_id from public.profiles where auth_user_id='10800000-0000-4000-8000-000000000001'\gset
insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'profile_id'::uuid,p.id,'ALLOW','Disposable POS partial return CI permission'
from public.permissions p where p.code in ('SALES_RETURN','POS_SHIFT_MANAGE');

select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
select id as warehouse_id from public.warehouses where organization_unit_id=:'unit_id'::uuid and code='DEMO-RETAIL-WH' limit 1\gset
select id as warehouse_node_id from public.warehouse_nodes where warehouse_id=:'warehouse_id'::uuid and code='RETAIL-BIN-01' limit 1\gset
select id as terminal_id from public.pos_terminals where organization_unit_id=:'unit_id'::uuid and code='DEMO-POS-01' limit 1\gset
select id as item_id,base_uom_id as uom_id from public.inventory_items where sku='DEMO-GULA-1KG' limit 1\gset
select id as period_id from public.accounting_periods where organization_node_id=:'node_id'::uuid and current_date between start_date and end_date and status='OPEN' order by start_date desc limit 1\gset
select id as cash_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='110100' limit 1\gset
select id as sales_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='410100' limit 1\gset
select id as inventory_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='130100' limit 1\gset
select id as cogs_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='510100' limit 1\gset

insert into public.data_scopes(organization_id,organization_node_id,organization_unit_id,scope_type,name)
values(:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'UNIT_SCOPE','POS Partial Return CI scope')
returning id as scope_id\gset
insert into public.user_scope_assignments(profile_id,data_scope_id) values(:'profile_id'::uuid,:'scope_id'::uuid);

insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values(
  '10800000-0000-4000-8000-000000000010',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'profile_id'::uuid,'POSSHIFT-CI-PARTIAL-RETURN','OPEN',500000,'PENDING'
);

insert into public.payment_intents(
  id,organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,
  source_domain,source_entity_type,source_reference,amount,currency,status,idempotency_key,confirmed_at,settled_at,created_by
) values(
  '10800000-0000-4000-8000-000000000020',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'PAY-CI-PARTIAL-ORIGINAL',
  'SALE','COMMERCIAL','SALES_TRANSACTION','SALE-CI-PARTIAL',200000,'IDR','SETTLED','POS-CI-PARTIAL-PAYMENT',now(),now(),:'profile_id'::uuid
);
insert into public.payment_attempts(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,attempt_no,channel,amount,currency,status,merchant_reference,confirmed_at,settled_at
) values(
  '10800000-0000-4000-8000-000000000021','10800000-0000-4000-8000-000000000020',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  1,'CASH_POS',200000,'IDR','SETTLED','SALE-CI-PARTIAL',now(),now()
);

insert into public.inventory_movements(
  id,organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,
  source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at,created_by
) values(
  '10800000-0000-4000-8000-000000000030',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'warehouse_id'::uuid,
  'POSISS-CI-PARTIAL','SALE_ISSUE','POSTED','COMMERCIAL','SALES_TRANSACTION','SALE-CI-PARTIAL','POS-CI-PARTIAL-INVENTORY',now(),now(),:'profile_id'::uuid
);
insert into public.inventory_movement_lines(
  id,organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,
  from_warehouse_node_id,from_stock_status,quantity,base_quantity,unit_cost,notes
) values(
  '10800000-0000-4000-8000-000000000031',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10800000-0000-4000-8000-000000000030',1,
  :'item_id'::uuid,:'uom_id'::uuid,:'warehouse_node_id'::uuid,'AVAILABLE',2,2,60000,'POS partial return CI original issue'
);

insert into public.journal_entries(
  id,organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,
  source_domain,source_entity_type,source_reference,correlation_id,idempotency_key,status,
  created_by,validated_by,validated_at,posted_by,posted_at
) values(
  '10800000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'period_id'::uuid,'POSJ-CI-PARTIAL',current_date,
  'POS partial return CI original journal','COMMERCIAL','SALES_TRANSACTION','SALE-CI-PARTIAL','pos-partial-return-ci','POS-CI-PARTIAL-JOURNAL','POSTED',
  :'profile_id'::uuid,:'profile_id'::uuid,now(),:'profile_id'::uuid,now()
);
insert into public.journal_lines(journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions) values
('10800000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,1,:'cash_account_id'::uuid,200000,0,'Cash received at POS','{}'::jsonb),
('10800000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,2,:'sales_account_id'::uuid,0,200000,'Retail sales revenue','{}'::jsonb),
('10800000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,3,:'cogs_account_id'::uuid,120000,0,'Cost of goods sold','{}'::jsonb),
('10800000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,4,:'inventory_account_id'::uuid,0,120000,'Inventory issued for POS sale','{}'::jsonb);

insert into public.sales_transactions(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,sale_number,sale_type,currency,
  subtotal,discount_amount,tax_amount,status,payment_intent_id,inventory_movement_id,journal_entry_id,receipt_reference,
  local_transaction_id,device_id,client_sequence,idempotency_key,sync_status,correlation_id,sold_at,completed_at,created_by
) values(
  '10800000-0000-4000-8000-000000000050',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  '10800000-0000-4000-8000-000000000010','SALE-CI-PARTIAL','POS','IDR',200000,0,0,'COMPLETED',
  '10800000-0000-4000-8000-000000000020','10800000-0000-4000-8000-000000000030','10800000-0000-4000-8000-000000000040',
  'RCP-CI-PARTIAL','LOCAL-CI-PARTIAL','CI-DEVICE',1,'POS-CI-PARTIAL-SALE','SYNCED','10800000-0000-4000-8000-000000000099',now(),now(),:'profile_id'::uuid
);
insert into public.sales_transaction_lines(
  id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,line_no,inventory_item_id,item_snapshot,
  description,uom_id,quantity,unit_price,discount_amount,tax_amount
) values(
  '10800000-0000-4000-8000-000000000051',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10800000-0000-4000-8000-000000000050',1,
  :'item_id'::uuid,'{"ci":true}'::jsonb,'Gula CI Partial Return',:'uom_id'::uuid,2,100000,0,0
);
insert into public.payment_allocations(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,allocation_no,target_type,target_id,target_reference,amount,status,allocated_at
) values(
  '10800000-0000-4000-8000-000000000060','10800000-0000-4000-8000-000000000020',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,1,'SALE',
  '10800000-0000-4000-8000-000000000050','SALE-CI-PARTIAL',200000,'ALLOCATED',now()
);
insert into public.pos_cash_movements(
  id,organization_id,organization_node_id,organization_unit_id,pos_shift_id,sales_transaction_id,payment_intent_id,payment_attempt_id,
  movement_type,direction,amount,currency,status,reason,occurred_at,created_by
) values(
  '10800000-0000-4000-8000-000000000070',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10800000-0000-4000-8000-000000000010',
  '10800000-0000-4000-8000-000000000050','10800000-0000-4000-8000-000000000020','10800000-0000-4000-8000-000000000021',
  'CASH_SALE','IN',200000,'IDR','POSTED','POS partial return CI source cash',now(),:'profile_id'::uuid
);
insert into public.pos_receipts(
  id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,pos_shift_id,terminal_id,payment_intent_id,payment_attempt_id,
  receipt_number,currency,subtotal,discount_amount,tax_amount,total_amount,cash_received,payload,issued_at,created_by
) values(
  '10800000-0000-4000-8000-000000000080',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10800000-0000-4000-8000-000000000050',
  '10800000-0000-4000-8000-000000000010',:'terminal_id'::uuid,'10800000-0000-4000-8000-000000000020','10800000-0000-4000-8000-000000000021',
  'RCP-CI-PARTIAL','IDR',200000,0,0,200000,200000,'{"ci":true}'::jsonb,now(),:'profile_id'::uuid
);

create temporary table ci_partial_snapshot(kind text primary key,digest text) on commit drop;
insert into ci_partial_snapshot values
('receipt',(select md5(to_jsonb(r)::text) from public.pos_receipts r where id='10800000-0000-4000-8000-000000000080')),
('inventory',(select md5(to_jsonb(m)::text) from public.inventory_movements m where id='10800000-0000-4000-8000-000000000030')),
('journal',(select md5(to_jsonb(j)::text) from public.journal_entries j where id='10800000-0000-4000-8000-000000000040')),
('cash',(select md5(to_jsonb(c)::text) from public.pos_cash_movements c where id='10800000-0000-4000-8000-000000000070'));

set local role authenticated;
select set_config('request.jwt.claim.sub','10800000-0000-4000-8000-000000000001',true);
select * from public.return_cash_pos_items(
  '10800000-0000-4000-8000-000000000050','10800000-0000-4000-8000-000000000010',
  '[{"sales_transaction_line_id":"10800000-0000-4000-8000-000000000051","quantity":1}]'::jsonb,
  'CUSTOMER_REQUEST','POS-PARTIAL-CI-ONE','First half returned'
)\gset first_
select * from public.return_cash_pos_items(
  '10800000-0000-4000-8000-000000000050','10800000-0000-4000-8000-000000000010',
  '[{"quantity":1,"sales_transaction_line_id":"10800000-0000-4000-8000-000000000051"}]'::jsonb,
  'CUSTOMER_REQUEST','POS-PARTIAL-CI-ONE','First half returned'
)\gset retry_
reset role;

do $$
begin
  if :'first_sales_return_id'::uuid is distinct from :'retry_sales_return_id'::uuid then raise exception 'partial_return_idempotent_return_mismatch'; end if;
  if :'first_refund_receipt_id'::uuid is distinct from :'retry_refund_receipt_id'::uuid then raise exception 'partial_return_idempotent_receipt_mismatch'; end if;
  if :'first_refund_amount'::numeric<>100000 or :'first_sale_fully_returned'::boolean then raise exception 'partial_return_first_result_invalid'; end if;
  if (select status from public.sales_transactions where id='10800000-0000-4000-8000-000000000050')<>'COMPLETED' then raise exception 'partial_return_sale_should_remain_completed'; end if;
  if (select status from public.payment_intents where id='10800000-0000-4000-8000-000000000020')<>'SETTLED' then raise exception 'partial_return_original_payment_changed_too_early'; end if;
  if (select count(*) from public.pos_partial_return_commands where idempotency_key='POS-PARTIAL-CI-ONE')<>1 then raise exception 'partial_return_idempotency_command_count_invalid'; end if;
  if (select sum(quantity) from public.pos_partial_return_lines where original_sales_transaction_line_id='10800000-0000-4000-8000-000000000051')<>1 then raise exception 'partial_return_first_quantity_invalid'; end if;
  if (select sum(base_quantity) from public.inventory_movement_lines where inventory_movement_id=:'first_inventory_movement_id'::uuid)<>1 then raise exception 'partial_return_inventory_quantity_invalid'; end if;
  if (select coalesce(sum(debit),0)-coalesce(sum(credit),0) from public.journal_lines where journal_entry_id=:'first_journal_entry_id'::uuid)<>0 then raise exception 'partial_return_journal_unbalanced'; end if;
  if (select movement_type||':'||direction||':'||amount::text from public.pos_cash_movements where id=:'first_cash_movement_id'::uuid)<>'CASH_REFUND:OUT:100000.00' then raise exception 'partial_return_cash_refund_invalid'; end if;
  if (select refund_amount from public.pos_refund_receipts where id=:'first_refund_receipt_id'::uuid)<>100000 then raise exception 'partial_return_receipt_invalid'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','10800000-0000-4000-8000-000000000001',true);
select * from public.return_cash_pos_items(
  '10800000-0000-4000-8000-000000000050','10800000-0000-4000-8000-000000000010',
  '[{"sales_transaction_line_id":"10800000-0000-4000-8000-000000000051","quantity":1}]'::jsonb,
  'CUSTOMER_REQUEST','POS-PARTIAL-CI-TWO','Second half returned'
)\gset second_
reset role;

do $$
begin
  if :'second_refund_amount'::numeric<>100000 or not :'second_sale_fully_returned'::boolean then raise exception 'partial_return_second_result_invalid'; end if;
  if (select status from public.sales_transactions where id='10800000-0000-4000-8000-000000000050')<>'RETURNED' then raise exception 'partial_return_sale_not_returned'; end if;
  if (select status from public.payment_intents where id='10800000-0000-4000-8000-000000000020')<>'REFUNDED' then raise exception 'partial_return_original_intent_not_refunded'; end if;
  if (select status from public.payment_attempts where id='10800000-0000-4000-8000-000000000021')<>'REFUNDED' then raise exception 'partial_return_original_attempt_not_refunded'; end if;
  if (select status from public.payment_allocations where id='10800000-0000-4000-8000-000000000060')<>'REVERSED' then raise exception 'partial_return_original_allocation_not_reversed'; end if;
  if (select sum(quantity) from public.pos_partial_return_lines where original_sales_transaction_line_id='10800000-0000-4000-8000-000000000051')<>2 then raise exception 'partial_return_cumulative_quantity_invalid'; end if;
  if (select sum(refund_amount) from public.pos_partial_return_lines where original_sales_transaction_line_id='10800000-0000-4000-8000-000000000051')<>200000 then raise exception 'partial_return_cumulative_refund_invalid'; end if;
  if (select count(*) from public.sales_returns where original_sale_id='10800000-0000-4000-8000-000000000050' and status='POSTED')<>2 then raise exception 'partial_return_posted_return_count_invalid'; end if;
  if (select sum(amount) from public.pos_cash_movements where sales_transaction_id='10800000-0000-4000-8000-000000000050' and movement_type='CASH_REFUND' and status='POSTED')<>200000 then raise exception 'partial_return_cash_refund_total_invalid'; end if;
  if (select digest from ci_partial_snapshot where kind='receipt')<>(select md5(to_jsonb(r)::text) from public.pos_receipts r where id='10800000-0000-4000-8000-000000000080') then raise exception 'partial_return_mutated_original_receipt'; end if;
  if (select digest from ci_partial_snapshot where kind='inventory')<>(select md5(to_jsonb(m)::text) from public.inventory_movements m where id='10800000-0000-4000-8000-000000000030') then raise exception 'partial_return_mutated_original_inventory'; end if;
  if (select digest from ci_partial_snapshot where kind='journal')<>(select md5(to_jsonb(j)::text) from public.journal_entries j where id='10800000-0000-4000-8000-000000000040') then raise exception 'partial_return_mutated_original_journal'; end if;
  if (select digest from ci_partial_snapshot where kind='cash')<>(select md5(to_jsonb(c)::text) from public.pos_cash_movements c where id='10800000-0000-4000-8000-000000000070') then raise exception 'partial_return_mutated_original_cash'; end if;
end $$;

rollback;
