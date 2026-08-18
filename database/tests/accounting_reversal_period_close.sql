\set ON_ERROR_STOP on

begin;

-- Release-1 role matrix must stay exact.
do $$
begin
  if (select count(*) from public.role_permissions rp join public.roles r on r.id=rp.role_id join public.permissions p on p.id=rp.permission_id where p.code='ACCOUNTING_POST' and r.code='BOARD')<>1 then
    raise exception 'ACCOUNTING_BOARD_POST_MAPPING_MISSING';
  end if;
  if exists(select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id join public.permissions p on p.id=rp.permission_id where p.code='ACCOUNTING_POST' and r.code<>'BOARD') then
    raise exception 'ACCOUNTING_NON_BOARD_POST_MAPPING_PRESENT';
  end if;
  if exists(select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id join public.permissions p on p.id=rp.permission_id where r.code='SUPERVISOR' and p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE','ACCOUNTING_POST','ACCOUNTING_PERIOD_MANAGE','ACCOUNTING_RECONCILE')) then
    raise exception 'ACCOUNTING_SUPERVISOR_WRITE_MAPPING_PRESENT';
  end if;
end $$;

-- Disposable Finance / Manager / BOARD actors.
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('12100000-0000-4000-8000-000000000001','authenticated','authenticated','accounting-rv-finance@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12100000-0000-4000-8000-000000000002','authenticated','authenticated','accounting-rv-manager@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12100000-0000-4000-8000-000000000003','authenticated','authenticated','accounting-rv-board@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),status='ACTIVE',updated_at=now()
where auth_user_id in ('12100000-0000-4000-8000-000000000001','12100000-0000-4000-8000-000000000002','12100000-0000-4000-8000-000000000003');

select id as finance_profile_id from public.profiles where auth_user_id='12100000-0000-4000-8000-000000000001'\gset
select id as manager_profile_id from public.profiles where auth_user_id='12100000-0000-4000-8000-000000000002'\gset
select id as board_profile_id from public.profiles where auth_user_id='12100000-0000-4000-8000-000000000003'\gset
select id as org_id from public.organizations where code='DEMO-KDKMP-DEV' limit 1\gset
select id as node_id from public.organization_nodes where organization_id=:'org_id'::uuid and code='DEMO-KDKMP' limit 1\gset
select id as cooperative_scope_id from public.data_scopes where organization_id=:'org_id'::uuid and scope_type='COOPERATIVE_SCOPE' limit 1\gset

insert into public.user_roles(profile_id,role_id) select :'finance_profile_id'::uuid,id from public.roles where code='FINANCE_OFFICER';
insert into public.user_roles(profile_id,role_id) select :'manager_profile_id'::uuid,id from public.roles where code='MANAGER';
insert into public.user_roles(profile_id,role_id) select :'board_profile_id'::uuid,id from public.roles where code='BOARD';
insert into public.user_scope_assignments(profile_id,data_scope_id)
values(:'finance_profile_id'::uuid,:'cooperative_scope_id'::uuid),(:'manager_profile_id'::uuid,:'cooperative_scope_id'::uuid),(:'board_profile_id'::uuid,:'cooperative_scope_id'::uuid);

select ap.id as period_id,ap.fiscal_year_id as fiscal_year_id
from public.accounting_periods ap
where ap.organization_node_id=:'node_id'::uuid and ap.status='OPEN' and current_date between ap.start_date and ap.end_date
order by ap.start_date desc limit 1\gset
select aa.id as debit_account_id from public.accounting_accounts aa where aa.organization_node_id=:'node_id'::uuid and aa.code='1110' and aa.status='ACTIVE' and aa.is_posting limit 1\gset
select aa.id as credit_account_id from public.accounting_accounts aa where aa.organization_node_id=:'node_id'::uuid and aa.code='4000' and aa.status='ACTIVE' and aa.is_posting limit 1\gset

-- Store psql-resolved values in transaction-local GUCs for PL/pgSQL assertions.
select set_config('accounting.rv.finance',:'finance_profile_id',true);
select set_config('accounting.rv.manager',:'manager_profile_id',true);
select set_config('accounting.rv.board',:'board_profile_id',true);
select set_config('accounting.rv.period',:'period_id',true);
select set_config('accounting.rv.fiscal',:'fiscal_year_id',true);
select set_config('accounting.rv.org',:'org_id',true);
select set_config('accounting.rv.node',:'node_id',true);
select set_config('accounting.rv.debit',:'debit_account_id',true);
select set_config('accounting.rv.credit',:'credit_account_id',true);

-- Build a controlled POSTED manual journal as the reversal source.
set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000001',true);
select public.create_manual_journal_draft(
  :'period_id'::uuid,current_date,'CI reversible manual journal',
  jsonb_build_array(
    jsonb_build_object('account_id',:'debit_account_id'::uuid,'debit',1250,'credit',0,'memo','Original debit'),
    jsonb_build_object('account_id',:'credit_account_id'::uuid,'debit',0,'credit',1250,'memo','Original credit')
  ),'ACC-RV-ORIG-CREATE','ACC-RV-ORIG-REF'
) as orig_create\gset
select set_config('accounting.rv.original',(:'orig_create'::jsonb->>'journal_entry_id'),true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000002',true);
select public.validate_manual_journal(current_setting('accounting.rv.original')::uuid,'ACC-RV-ORIG-VALIDATE','independent checker');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000003',true);
select public.authorize_manual_journal_post(current_setting('accounting.rv.original')::uuid,'ACC-RV-ORIG-AUTH','board original authorization',true);
select public.post_manual_journal(current_setting('accounting.rv.original')::uuid,'ACC-RV-ORIG-POST','board original post');
reset role;

-- Finance creates mirrored reversal DRAFT.
set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000001',true);
select public.create_manual_journal_reversal_draft(
  current_setting('accounting.rv.original')::uuid,:'period_id'::uuid,current_date,
  'CI correction requires full reversal','ACC-RV-CREATE-1'
) as rv_create\gset
select set_config('accounting.rv.reversal',(:'rv_create'::jsonb->>'journal_entry_id'),true);
reset role;

do $$
begin
  if not exists(select 1 from public.journal_entries where id=current_setting('accounting.rv.original')::uuid and status='POSTED') then raise exception 'ACCOUNTING_REVERSAL_MUTATED_ORIGINAL'; end if;
  if not exists(select 1 from public.journal_entries where id=current_setting('accounting.rv.reversal')::uuid and status='DRAFT' and source_domain='MANUAL_REVERSAL' and reversal_of_entry_id=current_setting('accounting.rv.original')::uuid) then raise exception 'ACCOUNTING_REVERSAL_DRAFT_INVALID'; end if;
  if exists(
    select 1 from public.journal_lines o
    join public.journal_lines r on r.journal_entry_id=current_setting('accounting.rv.reversal')::uuid and r.line_no=o.line_no
    where o.journal_entry_id=current_setting('accounting.rv.original')::uuid
      and (r.debit<>o.credit or r.credit<>o.debit or r.account_id<>o.account_id)
  ) then raise exception 'ACCOUNTING_REVERSAL_LINES_NOT_MIRRORED'; end if;
end $$;

-- Manager validates reversal; BOARD authorization becomes mandatory.
set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000002',true);
select public.validate_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-VALIDATE-1','reviewed reversal');
do $$ declare v_msg text; begin
  begin
    perform public.authorize_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-MANAGER-AUTH','must fail',true);
    raise exception 'expected_ACCOUNTING_POST_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_POST_DENIED' then raise exception 'expected ACCOUNTING_POST_DENIED, got %',v_msg; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform public.authorize_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-BOARD-NO-CONFLICT','must fail',false);
    raise exception 'expected_ACCOUNTING_CONFLICT_DECLARATION_REQUIRED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_CONFLICT_DECLARATION_REQUIRED' then raise exception 'expected ACCOUNTING_CONFLICT_DECLARATION_REQUIRED, got %',v_msg; end if; end;
end $$;
select public.authorize_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-BOARD-AUTH','board reversal authorization',true);
select public.post_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-BOARD-POST','board reversal post');
do $$ declare v_result jsonb; begin
  v_result:=public.post_manual_journal_reversal(current_setting('accounting.rv.reversal')::uuid,'ACC-RV-BOARD-POST','board reversal post');
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then raise exception 'ACCOUNTING_REVERSAL_POST_RETRY_NOT_IDEMPOTENT'; end if;
end $$;
reset role;

do $$
begin
  if (select status from public.journal_entries where id=current_setting('accounting.rv.reversal')::uuid)<>'POSTED' then raise exception 'ACCOUNTING_REVERSAL_NOT_POSTED'; end if;
  if (select created_by from public.journal_entries where id=current_setting('accounting.rv.reversal')::uuid)<>current_setting('accounting.rv.finance')::uuid then raise exception 'ACCOUNTING_REVERSAL_MAKER_INVALID'; end if;
  if (select validated_by from public.journal_entries where id=current_setting('accounting.rv.reversal')::uuid)<>current_setting('accounting.rv.manager')::uuid then raise exception 'ACCOUNTING_REVERSAL_CHECKER_INVALID'; end if;
  if (select posted_by from public.journal_entries where id=current_setting('accounting.rv.reversal')::uuid)<>current_setting('accounting.rv.board')::uuid then raise exception 'ACCOUNTING_REVERSAL_POSTER_INVALID'; end if;
  if not exists(select 1 from public.approval_requests where source_entity_type='JOURNAL_REVERSAL' and source_entity_id=current_setting('accounting.rv.reversal')::uuid and status='APPROVED') then raise exception 'ACCOUNTING_REVERSAL_APPROVAL_INVALID'; end if;
end $$;

-- Duplicate active reversal is denied.
set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000001',true);
do $$ declare v_msg text; begin
  begin
    perform public.create_manual_journal_reversal_draft(current_setting('accounting.rv.original')::uuid,current_setting('accounting.rv.period')::uuid,current_date,'duplicate reversal','ACC-RV-CREATE-2');
    raise exception 'expected_ACCOUNTING_REVERSAL_ALREADY_EXISTS';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_REVERSAL_ALREADY_EXISTS' then raise exception 'expected ACCOUNTING_REVERSAL_ALREADY_EXISTS, got %',v_msg; end if; end;
end $$;
reset role;

-- Ongoing period cannot close early.
set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000002',true);
do $$ declare v_msg text; begin
  begin
    perform public.soft_close_accounting_period(current_setting('accounting.rv.period')::uuid,'ACC-CLOSE-CURRENT','must fail current period');
    raise exception 'expected_ACCOUNTING_PERIOD_NOT_ENDED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_PERIOD_NOT_ENDED' then raise exception 'expected ACCOUNTING_PERIOD_NOT_ENDED, got %',v_msg; end if; end;
end $$;
reset role;

-- Clean ended period: MANAGER soft-close -> BOARD hard-close.
insert into public.accounting_periods(fiscal_year_id,organization_id,organization_node_id,period_code,period_name,start_date,end_date,status)
values(:'fiscal_year_id'::uuid,:'org_id'::uuid,:'node_id'::uuid,'CI-CLOSE-'||to_char(current_date,'YYYYMMDD'),'CI Controlled Close',current_date-10,current_date-1,'OPEN')
returning id as close_period_id\gset
select set_config('accounting.rv.close_period',:'close_period_id',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform public.soft_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-BOARD-SOFT','must fail');
    raise exception 'expected_ACCOUNTING_PERIOD_MANAGE_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_PERIOD_MANAGE_DENIED' then raise exception 'expected ACCOUNTING_PERIOD_MANAGE_DENIED, got %',v_msg; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000002',true);
select public.soft_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-SOFT-1','manager month-end review complete');
do $$ declare v_msg text; begin
  begin
    perform public.hard_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-MANAGER-HARD','must fail',true);
    raise exception 'expected_ACCOUNTING_POST_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_POST_DENIED' then raise exception 'expected ACCOUNTING_POST_DENIED, got %',v_msg; end if; end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12100000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform public.hard_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-BOARD-NO-CONFLICT','must fail',false);
    raise exception 'expected_ACCOUNTING_CONFLICT_DECLARATION_REQUIRED';
  exception when others then get stacked diagnostics v_msg=message_text; if v_msg<>'ACCOUNTING_CONFLICT_DECLARATION_REQUIRED' then raise exception 'expected ACCOUNTING_CONFLICT_DECLARATION_REQUIRED, got %',v_msg; end if; end;
end $$;
select public.hard_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-HARD-1','board final month-end close',true);
do $$ declare v_result jsonb; begin
  v_result:=public.hard_close_accounting_period(current_setting('accounting.rv.close_period')::uuid,'ACC-CLOSE-HARD-1','board final month-end close',true);
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then raise exception 'ACCOUNTING_HARD_CLOSE_RETRY_NOT_IDEMPOTENT'; end if;
end $$;
reset role;

do $$
begin
  if not exists(select 1 from public.accounting_periods where id=current_setting('accounting.rv.close_period')::uuid and status='HARD_CLOSED' and closed_by=current_setting('accounting.rv.board')::uuid and closed_at is not null) then raise exception 'ACCOUNTING_PERIOD_HARD_CLOSE_STATE_INVALID'; end if;
  if (select count(*) from public.audit_logs where entity_type='ACCOUNTING_PERIOD' and entity_id=current_setting('accounting.rv.close_period')::uuid and action_code in ('ACCOUNTING_PERIOD_SOFT_CLOSED','ACCOUNTING_PERIOD_HARD_CLOSED'))<>2 then raise exception 'ACCOUNTING_PERIOD_CLOSE_AUDIT_INCOMPLETE'; end if;
  if (select count(*) from public.audit_logs where entity_type='JOURNAL_ENTRY' and entity_id=current_setting('accounting.rv.reversal')::uuid and action_code in ('ACCOUNTING_MANUAL_JOURNAL_REVERSAL_DRAFT_CREATED','ACCOUNTING_MANUAL_JOURNAL_REVERSAL_VALIDATED','ACCOUNTING_MANUAL_JOURNAL_REVERSAL_AUTHORIZED','ACCOUNTING_MANUAL_JOURNAL_REVERSAL_POSTED'))<>4 then raise exception 'ACCOUNTING_REVERSAL_AUDIT_INCOMPLETE'; end if;
end $$;

rollback;
