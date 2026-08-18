\set ON_ERROR_STOP on

begin;

-- Baseline scope and references reconstructed by migrations/local CI fixture.
select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as unit_id from public.organization_units where organization_node_id=:'node_id'::uuid and code='DEMO-RETAIL' limit 1\gset
select id as warehouse_id from public.pos_terminals where organization_unit_id=:'unit_id'::uuid and code='DEMO-POS-01' limit 1\gset
select id as terminal_id,default_warehouse_id as default_warehouse_id
from public.pos_terminals where organization_unit_id=:'unit_id'::uuid and code='DEMO-POS-01' limit 1\gset
select id as period_id from public.accounting_periods
where organization_node_id=:'node_id'::uuid and current_date between start_date and end_date and status='OPEN'
order by start_date desc limit 1\gset

-- The migration must not silently grant SALES_VOID to any baseline role.
do $$
begin
  if exists(
    select 1 from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    where p.code='SALES_VOID'
  ) then raise exception 'pos_reversal_sales_void_role_mapping_must_remain_empty'; end if;
end $$;

-- Three disposable actors: no permissions, SALES_VOID only, and full reversal permissions.
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('10710000-0000-4000-8000-000000000001','authenticated','authenticated','pos-rev-neg-none@example.invalid',now(),'{}','{}',now(),now(),false,false),
('10710000-0000-4000-8000-000000000002','authenticated','authenticated','pos-rev-neg-void@example.invalid',now(),'{}','{}',now(),now(),false,false),
('10710000-0000-4000-8000-000000000003','authenticated','authenticated','pos-rev-neg-full@example.invalid',now(),'{}','{}',now(),now(),false,false),
('10710000-0000-4000-8000-000000000004','authenticated','authenticated','pos-rev-neg-foreign@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles
set organization_id=:'org_id'::uuid,status='ACTIVE',updated_at=now(),
    full_name=case auth_user_id
      when '10710000-0000-4000-8000-000000000001' then 'POS Reversal No Perm CI'
      when '10710000-0000-4000-8000-000000000002' then 'POS Reversal Void Only CI'
      when '10710000-0000-4000-8000-000000000003' then 'POS Reversal Full CI'
      else 'POS Reversal Foreign Cashier CI' end
where auth_user_id in (
  '10710000-0000-4000-8000-000000000001',
  '10710000-0000-4000-8000-000000000002',
  '10710000-0000-4000-8000-000000000003',
  '10710000-0000-4000-8000-000000000004'
);

select id as none_profile_id from public.profiles where auth_user_id='10710000-0000-4000-8000-000000000001'\gset
select id as void_profile_id from public.profiles where auth_user_id='10710000-0000-4000-8000-000000000002'\gset
select id as full_profile_id from public.profiles where auth_user_id='10710000-0000-4000-8000-000000000003'\gset
select id as foreign_profile_id from public.profiles where auth_user_id='10710000-0000-4000-8000-000000000004'\gset

insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'void_profile_id'::uuid,p.id,'ALLOW','Disposable fail-closed CI permission'
from public.permissions p where p.code='SALES_VOID';

insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'full_profile_id'::uuid,p.id,'ALLOW','Disposable fail-closed CI permission'
from public.permissions p where p.code in ('SALES_VOID','POS_SHIFT_MANAGE');

insert into public.data_scopes(organization_id,organization_node_id,organization_unit_id,scope_type,name)
values(:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,'UNIT_SCOPE','POS Reversal Negative CI Scope')
returning id as full_scope_id\gset
insert into public.user_scope_assignments(profile_id,data_scope_id)
values(:'full_profile_id'::uuid,:'full_scope_id'::uuid);

-- Source rows sufficient to reach shift/cash validation branches.
insert into public.payment_intents(
  id,organization_id,organization_node_id,organization_unit_id,intent_number,business_purpose,
  source_domain,source_entity_type,source_reference,amount,currency,status,idempotency_key,confirmed_at,settled_at,created_by
) values (
  '10710000-0000-4000-8000-000000000100',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  'PAY-NEG-ORIGINAL','SALE','COMMERCIAL','SALES_TRANSACTION','SALE-NEG-COMPLETED',100000,'IDR','SETTLED',
  'POS-REV-NEG-PAYMENT',now(),now(),:'full_profile_id'::uuid
);

insert into public.inventory_movements(
  id,organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,
  movement_type,status,source_domain,source_entity_type,source_reference,idempotency_key,occurred_at,posted_at,created_by
) values (
  '10710000-0000-4000-8000-000000000110',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'default_warehouse_id'::uuid,
  'INV-NEG-ORIGINAL','SALE_ISSUE','POSTED','COMMERCIAL','SALES_TRANSACTION','SALE-NEG-COMPLETED',
  'POS-REV-NEG-INVENTORY',now(),now(),:'full_profile_id'::uuid
);

insert into public.journal_entries(
  id,organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,description,
  source_domain,source_entity_type,source_reference,correlation_id,idempotency_key,status,
  created_by,validated_by,validated_at,posted_by,posted_at
) values (
  '10710000-0000-4000-8000-000000000120',:'org_id'::uuid,:'node_id'::uuid,:'period_id'::uuid,
  'JRN-NEG-ORIGINAL',current_date,'POS reversal negative source journal','COMMERCIAL','SALES_TRANSACTION',
  'SALE-NEG-COMPLETED','pos-reversal-negative','POS-REV-NEG-JOURNAL','POSTED',
  :'full_profile_id'::uuid,:'full_profile_id'::uuid,now(),:'full_profile_id'::uuid,now()
);

insert into public.sales_transactions(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,
  sale_number,sale_type,currency,subtotal,discount_amount,tax_amount,status,
  payment_intent_id,inventory_movement_id,journal_entry_id,idempotency_key,sync_status,created_by
) values
(
  '10710000-0000-4000-8000-000000000130',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  'SALE-NEG-DRAFT','POS','IDR',100000,0,0,'DRAFT',null,null,null,'POS-REV-NEG-DRAFT','SYNCED',:'full_profile_id'::uuid
),
(
  '10710000-0000-4000-8000-000000000131',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  'SALE-NEG-COMPLETED','POS','IDR',100000,0,0,'COMPLETED',
  '10710000-0000-4000-8000-000000000100','10710000-0000-4000-8000-000000000110','10710000-0000-4000-8000-000000000120',
  'POS-REV-NEG-COMPLETED','SYNCED',:'full_profile_id'::uuid
);

-- Closed shift for full actor.
insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values (
  '10710000-0000-4000-8000-000000000200',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'full_profile_id'::uuid,'SHIFT-NEG-CLOSED','CLOSED',500000,'MATCHED'
);

-- 1. Missing SALES_VOID.
set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000001',true);
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000200',
      'NEG_TEST','NEG-NO-SALES-VOID',null);
    raise exception 'expected_SALES_VOID_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'SALES_VOID_DENIED' then raise exception 'expected SALES_VOID_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 2. SALES_VOID exists but POS_SHIFT_MANAGE is missing.
set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000002',true);
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000200',
      'NEG_TEST','NEG-NO-SHIFT-MANAGE',null);
    raise exception 'expected_POS_SHIFT_MANAGE_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_SHIFT_MANAGE_DENIED' then raise exception 'expected POS_SHIFT_MANAGE_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- Remaining cases use the fully authorized disposable actor.
set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000003',true);

-- 3. Non-completed sale.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000130','10710000-0000-4000-8000-000000000200',
      'NEG_TEST','NEG-NOT-COMPLETED',null);
    raise exception 'expected_POS_COMPLETED_SALE_REQUIRED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_COMPLETED_SALE_REQUIRED' then raise exception 'expected POS_COMPLETED_SALE_REQUIRED, got %',v_msg; end if;
  end;
end $$;

-- 4. Invalid reason is rejected before any business mutation.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000200',
      'X','NEG-BAD-REASON',null);
    raise exception 'expected_POS_REVERSAL_REASON_REQUIRED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_REVERSAL_REASON_REQUIRED' then raise exception 'expected POS_REVERSAL_REASON_REQUIRED, got %',v_msg; end if;
  end;
end $$;

-- 5. Closed refund shift.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000200',
      'NEG_TEST','NEG-CLOSED-SHIFT',null);
    raise exception 'expected_POS_REFUND_OPEN_SHIFT_REQUIRED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_REFUND_OPEN_SHIFT_REQUIRED' then raise exception 'expected POS_REFUND_OPEN_SHIFT_REQUIRED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- Foreign cashier owns an OPEN shift on the real active terminal.
insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values (
  '10710000-0000-4000-8000-000000000201',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'foreign_profile_id'::uuid,'SHIFT-NEG-FOREIGN','OPEN',500000,'PENDING'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000003',true);
-- 6. Refund shift belongs to another cashier.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000201',
      'NEG_TEST','NEG-FOREIGN-SHIFT',null);
    raise exception 'expected_POS_REFUND_OWN_SHIFT_REQUIRED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_REFUND_OWN_SHIFT_REQUIRED' then raise exception 'expected POS_REFUND_OWN_SHIFT_REQUIRED, got %',v_msg; end if;
  end;
end $$;
reset role;

update public.pos_shifts set status='CLOSED',closed_at=now() where id='10710000-0000-4000-8000-000000000201';

-- Inactive terminal with the full actor's own OPEN shift.
insert into public.pos_terminals(
  id,organization_id,organization_node_id,organization_unit_id,code,name,default_warehouse_id,status
) values (
  '10710000-0000-4000-8000-000000000210',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  'CI-NEG-INACTIVE','CI Negative Inactive Terminal',:'default_warehouse_id'::uuid,'INACTIVE'
);
insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values (
  '10710000-0000-4000-8000-000000000211',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,
  '10710000-0000-4000-8000-000000000210',:'full_profile_id'::uuid,'SHIFT-NEG-INACTIVE','OPEN',500000,'PENDING'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000003',true);
-- 7. Inactive refund terminal.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000211',
      'NEG_TEST','NEG-INACTIVE-TERMINAL',null);
    raise exception 'expected_POS_REFUND_TERMINAL_NOT_ACTIVE';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_REFUND_TERMINAL_NOT_ACTIVE' then raise exception 'expected POS_REFUND_TERMINAL_NOT_ACTIVE, got %',v_msg; end if;
  end;
end $$;
reset role;

update public.pos_shifts set status='CLOSED',closed_at=now() where id='10710000-0000-4000-8000-000000000211';

-- Own OPEN shift on active terminal with no tracked cash.
insert into public.pos_shifts(
  id,organization_id,organization_node_id,organization_unit_id,terminal_id,cashier_profile_id,
  shift_number,status,opening_cash,reconciliation_status
) values (
  '10710000-0000-4000-8000-000000000220',:'org_id'::uuid,:'node_id'::uuid,:'unit_id'::uuid,:'terminal_id'::uuid,
  :'full_profile_id'::uuid,'SHIFT-NEG-NO-CASH','OPEN',0,'PENDING'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000003',true);
-- 8. Tracked drawer cash is insufficient.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000220',
      'NEG_TEST','NEG-INSUFFICIENT-CASH',null);
    raise exception 'expected_POS_REFUND_CASH_INSUFFICIENT';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_REFUND_CASH_INSUFFICIENT' then raise exception 'expected POS_REFUND_CASH_INSUFFICIENT, got %',v_msg; end if;
  end;
end $$;
reset role;

-- Increase tracked opening cash; source still has no original CASH_SALE movement.
update public.pos_shifts set opening_cash=500000 where id='10710000-0000-4000-8000-000000000220';
set local role authenticated;
select set_config('request.jwt.claim.sub','10710000-0000-4000-8000-000000000003',true);
-- 9. Missing original cash movement is fail-closed.
do $$
declare v_msg text; begin
  begin
    perform 1 from public.reverse_cash_pos_sale(
      '10710000-0000-4000-8000-000000000131','10710000-0000-4000-8000-000000000220',
      'NEG_TEST','NEG-MISSING-CASH-MOVEMENT',null);
    raise exception 'expected_POS_ORIGINAL_CASH_MOVEMENT_REQUIRED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_ORIGINAL_CASH_MOVEMENT_REQUIRED' then raise exception 'expected POS_ORIGINAL_CASH_MOVEMENT_REQUIRED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- Every expected failure must have left zero reversal artifacts.
do $$
begin
  if exists(select 1 from public.pos_cash_reversal_commands where idempotency_key like 'NEG-%') then
    raise exception 'negative_tests_left_reversal_command';
  end if;
  if exists(select 1 from public.sales_returns where original_sale_id='10710000-0000-4000-8000-000000000131') then
    raise exception 'negative_tests_left_sales_return';
  end if;
  if exists(select 1 from public.pos_cash_movements where movement_type='CASH_REFUND' and sales_transaction_id='10710000-0000-4000-8000-000000000131') then
    raise exception 'negative_tests_left_cash_refund';
  end if;
  if (select status from public.sales_transactions where id='10710000-0000-4000-8000-000000000131') <> 'COMPLETED' then
    raise exception 'negative_tests_mutated_source_sale';
  end if;
end $$;

rollback;
