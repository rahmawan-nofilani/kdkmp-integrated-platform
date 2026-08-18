\set ON_ERROR_STOP on

begin;

-- Disposable identities used only inside this transaction.
insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,is_sso_user,is_anonymous
) values (
  '10700000-0000-4000-8000-000000000001','authenticated','authenticated',
  'pos-reversal-ci@example.invalid',now(),'{}'::jsonb,'{}'::jsonb,
  now(),now(),false,false
);

-- The auth profile trigger creates the profile. Activate and scope it for the test.
update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),
    full_name='POS Reversal CI',status='ACTIVE',updated_at=now()
where auth_user_id='10700000-0000-4000-8000-000000000001';

select id as profile_id from public.profiles
where auth_user_id='10700000-0000-4000-8000-000000000001'\gset

insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'profile_id'::uuid,p.id,'ALLOW','Disposable POS reversal CI permission'
from public.permissions p
where p.code in ('SALES_VOID','POS_SHIFT_MANAGE');

insert into public.data_scopes(
  organization_id,organization_node_id,organization_unit_id,scope_type,name
)
select o.id,n.id,u.id,'UNIT_SCOPE','POS Reversal CI unit scope'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code='DEMO-KDKMP'
join public.organization_units u on u.organization_node_id=n.id and u.code='DEMO-RETAIL'
where o.code='DEMO-KDKMP-DEV'
returning id as scope_id\gset

insert into public.user_scope_assignments(profile_id,data_scope_id)
values(:'profile_id'::uuid,:'scope_id'::uuid);

-- Resolve deterministic DEMO foundation rows created by the migration chain.
select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
select id as warehouse_id from public.warehouses where organization_unit_id=:'unit_id'::uuid and code='DEMO-RETAIL-WH' limit 1\gset
select id as warehouse_node_id from public.warehouse_nodes where warehouse_id=:'warehouse_id'::uuid and code='RETAIL-BIN-01' limit 1\gset
select id as terminal_id from public.pos_terminals where organization_unit_id=:'unit_id'::uuid and code='DEMO-POS-01' limit 1\gset
select id as item_id,base_uom_id as uom_id from public.inventory_items where sku='DEMO-GULA-1KG' limit 1\gset
select id as period_id from public.accounting_periods
where organization_node_id=:'node_id'::uuid and current_date between start_date and end_date and status='OPEN'
order by start_date desc limit 1\gset
select id as cash_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='110100' limit 1\gset
select id as sales_account_id from public.accounting_accounts where organization_node_id=:'node_id'::uuid and code='410100' limit 1\gset

-- Refund drawer must be the actor's own open shift and contain sufficient cash.
insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,
  cashier_profile_id,shift_number,status,opening_cash,reconciliation_status
) values (
  '10700000-0000-4000-8000-000000000010',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'profile_id'::uuid,'POSSHIFT-CI-REVERSAL','OPEN',500000,'PENDING'
);

-- Original settled cash payment.
insert into public.payment_intents(
  id,organization_id,organization_node_id,organization_unit_id,intent_number,
  business_purpose,source_domain,source_entity_type,source_reference,
  amount,currency,status,idempotency_key,confirmed_at,settled_at,created_by
) values (
  '10700000-0000-4000-8000-000000000020',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'PAY-CI-ORIGINAL',
  'SALE','COMMERCIAL','SALES_TRANSACTION','SALE-CI-REVERSAL',
  100000,'IDR','SETTLED','POS-CI-ORIGINAL-PAYMENT',now(),now(),:'profile_id'::uuid
);

insert into public.payment_attempts(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,
  attempt_no,channel,amount,currency,status,merchant_reference,confirmed_at,settled_at
) values (
  '10700000-0000-4000-8000-000000000021','10700000-0000-4000-8000-000000000020',
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,1,'CASH_POS',100000,'IDR','SETTLED','SALE-CI-REVERSAL',now(),now()
);

-- Original posted inventory issue.
insert into public.inventory_movements(
  id,organization_id,organization_node_id,organization_unit_id,warehouse_id,
  movement_number,movement_type,status,source_domain,source_entity_type,source_reference,
  idempotency_key,occurred_at,posted_at,created_by
) values (
  '10700000-0000-4000-8000-000000000030',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'warehouse_id'::uuid,
  'POSISS-CI-REVERSAL','SALE_ISSUE','POSTED','COMMERCIAL','SALES_TRANSACTION','SALE-CI-REVERSAL',
  'POS-CI-ORIGINAL-INVENTORY',now(),now(),:'profile_id'::uuid
);

insert into public.inventory_movement_lines(
  organization_id,organization_node_id,organization_unit_id,inventory_movement_id,
  line_no,inventory_item_id,uom_id,from_warehouse_node_id,from_stock_status,
  quantity,base_quantity,unit_cost,notes
) values (
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'10700000-0000-4000-8000-000000000030',
  1,:'item_id'::uuid,:'uom_id'::uuid,:'warehouse_node_id'::uuid,'AVAILABLE',1,1,60000,'POS reversal CI original issue'
);

-- Original posted balanced journal.
insert into public.journal_entries(
  id,organization_id,organization_node_id,accounting_period_id,journal_number,
  entry_date,description,source_domain,source_entity_type,source_reference,
  correlation_id,idempotency_key,status,created_by,validated_by,validated_at,posted_by,posted_at
) values (
  '10700000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,:'period_id'::uuid,'POSJ-CI-REVERSAL',
  current_date,'POS reversal CI original journal','COMMERCIAL','SALES_TRANSACTION','SALE-CI-REVERSAL',
  'pos-reversal-ci','POS-CI-ORIGINAL-JOURNAL','POSTED',:'profile_id'::uuid,:'profile_id'::uuid,now(),:'profile_id'::uuid,now()
);

insert into public.journal_lines(
  journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,memo,dimensions
) values
  ('10700000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,1,:'cash_account_id'::uuid,100000,0,'Original cash debit','{}'::jsonb),
  ('10700000-0000-4000-8000-000000000040',:'org_id'::uuid,:'node_id'::uuid,2,:'sales_account_id'::uuid,0,100000,'Original sales credit','{}'::jsonb);

-- Original completed sale links the three authoritative legs.
insert into public.sales_transactions(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,pos_shift_id,
  sale_number,sale_type,currency,subtotal,discount_amount,tax_amount,status,
  payment_intent_id,inventory_movement_id,journal_entry_id,receipt_reference,
  local_transaction_id,device_id,client_sequence,idempotency_key,sync_status,
  correlation_id,sold_at,completed_at,created_by
) values (
  '10700000-0000-4000-8000-000000000050',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  '10700000-0000-4000-8000-000000000010','SALE-CI-REVERSAL','POS','IDR',100000,0,0,'COMPLETED',
  '10700000-0000-4000-8000-000000000020','10700000-0000-4000-8000-000000000030','10700000-0000-4000-8000-000000000040',
  'RCP-CI-REVERSAL','LOCAL-CI-REVERSAL','CI-DEVICE',1,'POS-CI-ORIGINAL-SALE','SYNCED',
  '10700000-0000-4000-8000-000000000099',now(),now(),:'profile_id'::uuid
);

insert into public.payment_allocations(
  id,payment_intent_id,organization_id,organization_node_id,organization_unit_id,
  allocation_no,target_type,target_id,target_reference,amount,status,allocated_at
) values (
  '10700000-0000-4000-8000-000000000060','10700000-0000-4000-8000-000000000020',
  :'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,1,'SALE','10700000-0000-4000-8000-000000000050',
  'SALE-CI-REVERSAL',100000,'ALLOCATED',now()
);

insert into public.pos_cash_movements(
  id,organization_id,organization_node_id,organization_unit_id,pos_shift_id,
  sales_transaction_id,payment_intent_id,payment_attempt_id,movement_type,direction,
  amount,currency,status,reason,occurred_at,created_by
) values (
  '10700000-0000-4000-8000-000000000070',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  '10700000-0000-4000-8000-000000000010','10700000-0000-4000-8000-000000000050',
  '10700000-0000-4000-8000-000000000020','10700000-0000-4000-8000-000000000021',
  'CASH_SALE','IN',100000,'IDR','POSTED','POS reversal CI original cash',now(),:'profile_id'::uuid
);

insert into public.pos_receipts(
  id,organization_id,organization_node_id,organization_unit_id,sales_transaction_id,
  pos_shift_id,terminal_id,payment_intent_id,payment_attempt_id,receipt_number,currency,
  subtotal,discount_amount,tax_amount,total_amount,cash_received,payload,issued_at,created_by
) values (
  '10700000-0000-4000-8000-000000000080',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  '10700000-0000-4000-8000-000000000050','10700000-0000-4000-8000-000000000010',:'terminal_id'::uuid,
  '10700000-0000-4000-8000-000000000020','10700000-0000-4000-8000-000000000021','RCP-CI-REVERSAL','IDR',
  100000,0,0,100000,100000,'{"ci":true}'::jsonb,now(),:'profile_id'::uuid
);

-- Snapshot immutable originals before reversal.
create temporary table ci_pos_reversal_snapshot(kind text primary key,digest text) on commit drop;
insert into ci_pos_reversal_snapshot values
  ('receipt',(select md5(to_jsonb(r)::text) from public.pos_receipts r where id='10700000-0000-4000-8000-000000000080')),
  ('inventory',(select md5(to_jsonb(m)::text) from public.inventory_movements m where id='10700000-0000-4000-8000-000000000030')),
  ('journal',(select md5(to_jsonb(j)::text) from public.journal_entries j where id='10700000-0000-4000-8000-000000000040')),
  ('cash',(select md5(to_jsonb(c)::text) from public.pos_cash_movements c where id='10700000-0000-4000-8000-000000000070'));

-- Exercise the real authenticated/RLS/RPC path.
set local role authenticated;
select set_config('request.jwt.claim.sub','10700000-0000-4000-8000-000000000001',true);

select * from public.reverse_cash_pos_sale(
  '10700000-0000-4000-8000-000000000050',
  '10700000-0000-4000-8000-000000000010',
  'CI_VOID',
  'POS-REV-CI-IDEMPOTENT',
  'Disposable full cash reversal test'
)\gset rev1_

select * from public.reverse_cash_pos_sale(
  '10700000-0000-4000-8000-000000000050',
  '10700000-0000-4000-8000-000000000010',
  'CI_VOID',
  'POS-REV-CI-IDEMPOTENT',
  'Disposable full cash reversal test'
)\gset rev2_

reset role;

-- Positive result and idempotent retry must be identical.
do $$
begin
  if :'rev1_sales_return_id'::uuid is distinct from :'rev2_sales_return_id'::uuid
     or :'rev1_refund_payment_intent_id'::uuid is distinct from :'rev2_refund_payment_intent_id'::uuid
     or :'rev1_refund_payment_attempt_id'::uuid is distinct from :'rev2_refund_payment_attempt_id'::uuid
     or :'rev1_inventory_movement_id'::uuid is distinct from :'rev2_inventory_movement_id'::uuid
     or :'rev1_journal_entry_id'::uuid is distinct from :'rev2_journal_entry_id'::uuid
     or :'rev1_cash_movement_id'::uuid is distinct from :'rev2_cash_movement_id'::uuid
     or :'rev1_refund_receipt_id'::uuid is distinct from :'rev2_refund_receipt_id'::uuid then
    raise exception 'pos_reversal_retry_result_mismatch';
  end if;

  if (select count(*) from public.pos_cash_reversal_commands where idempotency_key='POS-REV-CI-IDEMPOTENT') <> 1 then
    raise exception 'pos_reversal_idempotency_command_count_invalid';
  end if;

  if (select status from public.sales_transactions where id='10700000-0000-4000-8000-000000000050') <> 'VOIDED' then
    raise exception 'pos_reversal_sale_not_voided';
  end if;
  if (select status from public.payment_intents where id='10700000-0000-4000-8000-000000000020') <> 'REFUNDED' then
    raise exception 'pos_reversal_original_intent_not_refunded';
  end if;
  if (select status from public.payment_attempts where id='10700000-0000-4000-8000-000000000021') <> 'REFUNDED' then
    raise exception 'pos_reversal_original_attempt_not_refunded';
  end if;
  if (select status from public.payment_allocations where id='10700000-0000-4000-8000-000000000060') <> 'REVERSED' then
    raise exception 'pos_reversal_original_allocation_not_reversed';
  end if;

  if not exists(
    select 1 from public.sales_returns
    where id=:'rev1_sales_return_id'::uuid
      and original_sale_id='10700000-0000-4000-8000-000000000050'
      and status='POSTED'
  ) then raise exception 'pos_reversal_sales_return_invalid'; end if;

  if not exists(
    select 1 from public.pos_cash_movements
    where id=:'rev1_cash_movement_id'::uuid
      and movement_type='CASH_REFUND' and direction='OUT' and amount=100000
      and reversal_of_movement_id='10700000-0000-4000-8000-000000000070'
      and status='POSTED'
  ) then raise exception 'pos_reversal_cash_refund_invalid'; end if;

  if not exists(
    select 1 from public.inventory_movements
    where id=:'rev1_inventory_movement_id'::uuid
      and movement_type='RETURN_IN' and status='POSTED'
      and reversal_of_movement_id='10700000-0000-4000-8000-000000000030'
  ) then raise exception 'pos_reversal_inventory_header_invalid'; end if;

  if not exists(
    select 1
    from public.inventory_movement_lines original_line
    join public.inventory_movement_lines reversal_line
      on reversal_line.inventory_movement_id=:'rev1_inventory_movement_id'::uuid
     and reversal_line.line_no=original_line.line_no
     and reversal_line.inventory_item_id=original_line.inventory_item_id
     and reversal_line.uom_id=original_line.uom_id
     and reversal_line.lot_id is not distinct from original_line.lot_id
     and reversal_line.to_warehouse_node_id=original_line.from_warehouse_node_id
     and reversal_line.base_quantity=original_line.base_quantity
     and reversal_line.unit_cost is not distinct from original_line.unit_cost
    where original_line.inventory_movement_id='10700000-0000-4000-8000-000000000030'
  ) then raise exception 'pos_reversal_inventory_lines_not_mirrored'; end if;

  if not exists(
    select 1 from public.journal_entries
    where id=:'rev1_journal_entry_id'::uuid and status='POSTED'
      and reversal_of_entry_id='10700000-0000-4000-8000-000000000040'
  ) then raise exception 'pos_reversal_journal_header_invalid'; end if;

  if exists(
    select 1
    from public.journal_lines original_line
    left join public.journal_lines reversal_line
      on reversal_line.journal_entry_id=:'rev1_journal_entry_id'::uuid
     and reversal_line.line_no=original_line.line_no
     and reversal_line.account_id=original_line.account_id
     and reversal_line.debit=original_line.credit
     and reversal_line.credit=original_line.debit
    where original_line.journal_entry_id='10700000-0000-4000-8000-000000000040'
      and reversal_line.id is null
  ) then raise exception 'pos_reversal_journal_lines_not_mirrored'; end if;

  if (select coalesce(sum(debit),0)-coalesce(sum(credit),0) from public.journal_lines where journal_entry_id=:'rev1_journal_entry_id'::uuid) <> 0 then
    raise exception 'pos_reversal_journal_not_balanced';
  end if;

  if not exists(
    select 1 from public.pos_refund_receipts
    where id=:'rev1_refund_receipt_id'::uuid
      and original_sales_transaction_id='10700000-0000-4000-8000-000000000050'
      and original_receipt_id='10700000-0000-4000-8000-000000000080'
      and refund_amount=100000
  ) then raise exception 'pos_reversal_refund_receipt_invalid'; end if;

  if (select md5(to_jsonb(r)::text) from public.pos_receipts r where id='10700000-0000-4000-8000-000000000080')
      <> (select digest from ci_pos_reversal_snapshot where kind='receipt') then
    raise exception 'pos_reversal_original_receipt_mutated';
  end if;
  if (select md5(to_jsonb(m)::text) from public.inventory_movements m where id='10700000-0000-4000-8000-000000000030')
      <> (select digest from ci_pos_reversal_snapshot where kind='inventory') then
    raise exception 'pos_reversal_original_inventory_mutated';
  end if;
  if (select md5(to_jsonb(j)::text) from public.journal_entries j where id='10700000-0000-4000-8000-000000000040')
      <> (select digest from ci_pos_reversal_snapshot where kind='journal') then
    raise exception 'pos_reversal_original_journal_mutated';
  end if;
  if (select md5(to_jsonb(c)::text) from public.pos_cash_movements c where id='10700000-0000-4000-8000-000000000070')
      <> (select digest from ci_pos_reversal_snapshot where kind='cash') then
    raise exception 'pos_reversal_original_cash_mutated';
  end if;
end $$;

rollback;
