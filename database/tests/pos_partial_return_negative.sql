\set ON_ERROR_STOP on

begin;

-- SALES_RETURN remains owner-policy gated: this implementation must not map it to a baseline role.
do $$
begin
  if exists(
    select 1 from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    where p.code='SALES_RETURN'
  ) then raise exception 'pos_partial_return_sales_return_role_mapping_must_remain_empty'; end if;
end $$;

insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('10810000-0000-4000-8000-000000000001','authenticated','authenticated','partial-return-none@example.invalid',now(),'{}','{}',now(),now(),false,false),
('10810000-0000-4000-8000-000000000002','authenticated','authenticated','partial-return-only@example.invalid',now(),'{}','{}',now(),now(),false,false),
('10810000-0000-4000-8000-000000000003','authenticated','authenticated','partial-return-full@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),status='ACTIVE',updated_at=now()
where auth_user_id in (
  '10810000-0000-4000-8000-000000000001','10810000-0000-4000-8000-000000000002','10810000-0000-4000-8000-000000000003'
);
select id as none_profile_id from public.profiles where auth_user_id='10810000-0000-4000-8000-000000000001'\gset
select id as return_profile_id from public.profiles where auth_user_id='10810000-0000-4000-8000-000000000002'\gset
select id as full_profile_id from public.profiles where auth_user_id='10810000-0000-4000-8000-000000000003'\gset

insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'return_profile_id'::uuid,p.id,'ALLOW','Disposable partial-return negative test' from public.permissions p where p.code='SALES_RETURN';
insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'full_profile_id'::uuid,p.id,'ALLOW','Disposable partial-return negative test' from public.permissions p where p.code in ('SALES_RETURN','POS_SHIFT_MANAGE');

-- 1. Missing SALES_RETURN.
set local role authenticated;
select set_config('request.jwt.claim.sub','10810000-0000-4000-8000-000000000001',true);
do $$ declare v_msg text; begin
  begin
    perform 1 from public.return_cash_pos_items(
      '10810000-0000-4000-8000-000000000050','10810000-0000-4000-8000-000000000010',
      '[{"sales_transaction_line_id":"10810000-0000-4000-8000-000000000051","quantity":1}]'::jsonb,
      'NEG_TEST','PARTIAL-NEG-NO-RETURN',null);
    raise exception 'expected_SALES_RETURN_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'SALES_RETURN_DENIED' then raise exception 'expected SALES_RETURN_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 2. SALES_RETURN exists but POS_SHIFT_MANAGE is missing.
set local role authenticated;
select set_config('request.jwt.claim.sub','10810000-0000-4000-8000-000000000002',true);
do $$ declare v_msg text; begin
  begin
    perform 1 from public.return_cash_pos_items(
      '10810000-0000-4000-8000-000000000050','10810000-0000-4000-8000-000000000010',
      '[{"sales_transaction_line_id":"10810000-0000-4000-8000-000000000051","quantity":1}]'::jsonb,
      'NEG_TEST','PARTIAL-NEG-NO-SHIFT',null);
    raise exception 'expected_POS_SHIFT_MANAGE_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_SHIFT_MANAGE_DENIED' then raise exception 'expected POS_SHIFT_MANAGE_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 3. Duplicate requested sale line is rejected before business state is touched.
set local role authenticated;
select set_config('request.jwt.claim.sub','10810000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform 1 from public.return_cash_pos_items(
      '10810000-0000-4000-8000-000000000050','10810000-0000-4000-8000-000000000010',
      '[{"sales_transaction_line_id":"10810000-0000-4000-8000-000000000051","quantity":1},{"sales_transaction_line_id":"10810000-0000-4000-8000-000000000051","quantity":1}]'::jsonb,
      'NEG_TEST','PARTIAL-NEG-DUP-LINE',null);
    raise exception 'expected_POS_RETURN_DUPLICATE_LINE';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_RETURN_DUPLICATE_LINE' then raise exception 'expected POS_RETURN_DUPLICATE_LINE, got %',v_msg; end if;
  end;
end $$;

-- 4. Non-positive quantity is rejected before business state is touched.
do $$ declare v_msg text; begin
  begin
    perform 1 from public.return_cash_pos_items(
      '10810000-0000-4000-8000-000000000050','10810000-0000-4000-8000-000000000010',
      '[{"sales_transaction_line_id":"10810000-0000-4000-8000-000000000051","quantity":0}]'::jsonb,
      'NEG_TEST','PARTIAL-NEG-ZERO-QTY',null);
    raise exception 'expected_POS_RETURN_QUANTITY_INVALID';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'POS_RETURN_QUANTITY_INVALID' then raise exception 'expected POS_RETURN_QUANTITY_INVALID, got %',v_msg; end if;
  end;
end $$;
reset role;

-- No expected failure may leave partial-return artifacts.
do $$
begin
  if exists(select 1 from public.pos_partial_return_commands where idempotency_key like 'PARTIAL-NEG-%') then
    raise exception 'partial_return_negative_left_command';
  end if;
  if exists(select 1 from public.pos_refund_receipts where refund_number like 'RFD-RET-%' and created_by in (:'none_profile_id'::uuid,:'return_profile_id'::uuid,:'full_profile_id'::uuid)) then
    raise exception 'partial_return_negative_left_refund_receipt';
  end if;
end $$;

rollback;
