\set ON_ERROR_STOP on

begin;

-- Baseline SoD must be exact after the BOARD posting policy migration.
do $$
begin
  if (select count(*)
      from public.role_permissions rp
      join public.permissions p on p.id=rp.permission_id
      where p.code='ACCOUNTING_POST')<>1 then
    raise exception 'ACCOUNTING_POST_MAPPING_COUNT_MUST_BE_ONE';
  end if;
  if not exists(
      select 1 from public.role_permissions rp
      join public.permissions p on p.id=rp.permission_id
      join public.roles r on r.id=rp.role_id
      where p.code='ACCOUNTING_POST' and r.code='BOARD') then
    raise exception 'ACCOUNTING_POST_BOARD_MAPPING_MISSING';
  end if;
  if exists(
      select 1 from public.role_permissions rp
      join public.permissions p on p.id=rp.permission_id
      join public.roles r on r.id=rp.role_id
      where p.code='ACCOUNTING_POST' and r.code<>'BOARD') then
    raise exception 'ACCOUNTING_POST_NON_BOARD_MAPPING_PRESENT';
  end if;
  if exists(
      select 1 from public.role_permissions rp
      join public.permissions p on p.id=rp.permission_id
      join public.roles r on r.id=rp.role_id
      where r.code='BOARD' and p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE')) then
    raise exception 'BOARD_MUST_NOT_BE_MAKER_OR_CHECKER';
  end if;
  if exists(
      select 1 from public.role_permissions rp
      join public.permissions p on p.id=rp.permission_id
      join public.roles r on r.id=rp.role_id
      where r.code='SUPERVISOR' and p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE','ACCOUNTING_POST','ACCOUNTING_PERIOD_MANAGE','ACCOUNTING_RECONCILE')) then
    raise exception 'SUPERVISOR_MUST_REMAIN_READ_AUDIT_ONLY';
  end if;
end $$;

-- Active JOURNAL_POST policy must be the controlled single-step BOARD authorization gate.
do $$
begin
  if not exists(
    select 1
    from public.approval_policies ap
    join public.approval_policy_versions apv on apv.approval_policy_id=ap.id
    join public.approval_policy_steps aps on aps.approval_policy_version_id=apv.id
    where ap.code='DEMO-ACCOUNTING-POST'
      and ap.domain='ACCOUNTING' and ap.transaction_type='JOURNAL_POST' and ap.status='ACTIVE'
      and apv.version_no=1 and apv.status='ACTIVE'
      and aps.step_no=1 and aps.required_permission_code='ACCOUNTING_POST'
      and aps.min_approvers=1 and aps.quorum_rule='ALL_REQUIRED'
      and aps.prohibit_requester_approval=true
      and aps.prohibit_previous_step_actor=true
      and aps.require_conflict_declaration=true
      and aps.allow_delegation=false
  ) then raise exception 'ACCOUNTING_JOURNAL_POST_POLICY_NOT_CONTROLLED_ACTIVE'; end if;
end $$;

-- Synthetic actors for disposable local CI only.
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('12000000-0000-4000-8000-000000000001','authenticated','authenticated','accounting-finance@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12000000-0000-4000-8000-000000000002','authenticated','authenticated','accounting-manager@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12000000-0000-4000-8000-000000000003','authenticated','authenticated','accounting-board-a@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12000000-0000-4000-8000-000000000004','authenticated','authenticated','accounting-board-b@example.invalid',now(),'{}','{}',now(),now(),false,false),
('12000000-0000-4000-8000-000000000005','authenticated','authenticated','accounting-supervisor@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),status='ACTIVE',updated_at=now()
where auth_user_id in (
 '12000000-0000-4000-8000-000000000001','12000000-0000-4000-8000-000000000002',
 '12000000-0000-4000-8000-000000000003','12000000-0000-4000-8000-000000000004',
 '12000000-0000-4000-8000-000000000005'
);

select id as finance_profile_id from public.profiles where auth_user_id='12000000-0000-4000-8000-000000000001'\gset
select id as manager_profile_id from public.profiles where auth_user_id='12000000-0000-4000-8000-000000000002'\gset
select id as board_a_profile_id from public.profiles where auth_user_id='12000000-0000-4000-8000-000000000003'\gset
select id as board_b_profile_id from public.profiles where auth_user_id='12000000-0000-4000-8000-000000000004'\gset
select id as supervisor_profile_id from public.profiles where auth_user_id='12000000-0000-4000-8000-000000000005'\gset
select id as cooperative_scope_id from public.data_scopes
where organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1)
  and scope_type='COOPERATIVE_SCOPE' limit 1\gset

insert into public.user_roles(profile_id,role_id)
select :'finance_profile_id'::uuid,r.id from public.roles r where r.code='FINANCE_OFFICER'
union all select :'manager_profile_id'::uuid,r.id from public.roles r where r.code='MANAGER'
union all select :'board_a_profile_id'::uuid,r.id from public.roles r where r.code='BOARD'
union all select :'board_b_profile_id'::uuid,r.id from public.roles r where r.code='BOARD'
union all select :'supervisor_profile_id'::uuid,r.id from public.roles r where r.code='SUPERVISOR';

insert into public.user_scope_assignments(profile_id,data_scope_id)
values
(:'finance_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'manager_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'board_a_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'board_b_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'supervisor_profile_id'::uuid,:'cooperative_scope_id'::uuid);

-- Test-only extra maker permission for Manager to prove self-validation rejection.
insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'manager_profile_id'::uuid,p.id,'ALLOW','Disposable maker-checker negative test'
from public.permissions p where p.code='ACCOUNTING_DRAFT_CREATE';

select ap.id as period_id
from public.accounting_periods ap
join public.organization_nodes n on n.id=ap.organization_node_id and n.code='DEMO-KDKMP'
where ap.status='OPEN' and current_date between ap.start_date and ap.end_date
order by ap.start_date desc limit 1\gset
select aa.id as debit_account_id
from public.accounting_accounts aa
join public.organization_nodes n on n.id=aa.organization_node_id and n.code='DEMO-KDKMP'
where aa.code='1110' and aa.status='ACTIVE' and aa.is_posting limit 1\gset
select aa.id as credit_account_id
from public.accounting_accounts aa
join public.organization_nodes n on n.id=aa.organization_node_id and n.code='DEMO-KDKMP'
where aa.code='4000' and aa.status='ACTIVE' and aa.is_posting limit 1\gset

select set_config('accounting.ci.finance_profile_id',:'finance_profile_id',true);
select set_config('accounting.ci.manager_profile_id',:'manager_profile_id',true);
select set_config('accounting.ci.board_a_profile_id',:'board_a_profile_id',true);
select set_config('accounting.ci.board_b_profile_id',:'board_b_profile_id',true);
select set_config('accounting.ci.period_id',:'period_id',true);
select set_config('accounting.ci.debit_account_id',:'debit_account_id',true);
select set_config('accounting.ci.credit_account_id',:'credit_account_id',true);

-- 1) FINANCE_OFFICER creates a balanced DRAFT.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000001',true);
select public.create_manual_journal_draft(
  :'period_id'::uuid,current_date,'CI BOARD posting journal',
  jsonb_build_array(
    jsonb_build_object('account_id',:'debit_account_id'::uuid,'debit',1000,'credit',0,'memo','Debit'),
    jsonb_build_object('account_id',:'credit_account_id'::uuid,'debit',0,'credit',1000,'memo','Credit')
  ),'ACC-BOARD-CREATE-1','ACC-BOARD-REF-1'
) as finance_create_result\gset
select set_config('accounting.ci.finance_journal_id',(:'finance_create_result'::jsonb->>'journal_entry_id'),true);
reset role;

-- 2) Manager's own draft cannot be self-validated even with test-only maker permission.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000002',true);
select public.create_manual_journal_draft(
  :'period_id'::uuid,current_date,'CI self validation rejection',
  jsonb_build_array(
    jsonb_build_object('account_id',:'debit_account_id'::uuid,'debit',500,'credit',0),
    jsonb_build_object('account_id',:'credit_account_id'::uuid,'debit',0,'credit',500)
  ),'ACC-BOARD-CREATE-SELF','ACC-BOARD-REF-SELF'
) as manager_create_result\gset
select set_config('accounting.ci.manager_journal_id',(:'manager_create_result'::jsonb->>'journal_entry_id'),true);
do $$ declare v_msg text; begin
  begin
    perform public.validate_manual_journal(current_setting('accounting.ci.manager_journal_id')::uuid,'ACC-BOARD-VALIDATE-SELF','must fail');
    raise exception 'expected_ACCOUNTING_MAKER_CHECKER_VIOLATION';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_MAKER_CHECKER_VIOLATION' then raise exception 'expected ACCOUNTING_MAKER_CHECKER_VIOLATION, got %',v_msg; end if;
  end;
end $$;

-- 3) MANAGER validates Finance journal. Trigger must create an IN_REVIEW approval request.
select public.validate_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-VALIDATE-1','independent checker');
reset role;

do $$
declare v_request_id uuid;
begin
  if not exists(
    select 1 from public.journal_entries je
    where je.id=current_setting('accounting.ci.finance_journal_id')::uuid
      and je.status='VALIDATED'
      and je.created_by=current_setting('accounting.ci.finance_profile_id')::uuid
      and je.validated_by=current_setting('accounting.ci.manager_profile_id')::uuid
      and je.created_by<>je.validated_by
  ) then raise exception 'ACCOUNTING_VALIDATE_STATE_INVALID'; end if;

  select ar.id into v_request_id
  from public.approval_requests ar
  where ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_ENTRY'
    and ar.source_entity_id=current_setting('accounting.ci.finance_journal_id')::uuid
    and ar.status='IN_REVIEW'
    and ar.requested_by=current_setting('accounting.ci.manager_profile_id')::uuid;
  if v_request_id is null then raise exception 'ACCOUNTING_APPROVAL_REQUEST_NOT_AUTO_CREATED'; end if;
  if not exists(select 1 from public.approval_request_steps where approval_request_id=v_request_id and step_no=1 and status='ACTIVE' and required_permission_code='ACCOUNTING_POST') then
    raise exception 'ACCOUNTING_APPROVAL_ACTIVE_STEP_MISSING';
  end if;
end $$;

-- 4) MANAGER and SUPERVISOR cannot authorize/post.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000002',true);
do $$ declare v_msg text; begin
  begin
    perform public.authorize_manual_journal_post(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-AUTH-MANAGER','must fail',true);
    raise exception 'expected_ACCOUNTING_POST_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_POST_DENIED' then raise exception 'expected ACCOUNTING_POST_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000005',true);
do $$ declare v_msg text; begin
  begin
    perform public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-POST-SUPERVISOR','must fail');
    raise exception 'expected_ACCOUNTING_POST_DENIED';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_POST_DENIED' then raise exception 'expected ACCOUNTING_POST_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 5) BOARD authorization requires an explicit conflict declaration.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform public.authorize_manual_journal_post(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-AUTH-NO-CONFLICT','BOARD authorization',false);
    raise exception 'expected_ACCOUNTING_CONFLICT_DECLARATION_REQUIRED';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_CONFLICT_DECLARATION_REQUIRED' then raise exception 'expected ACCOUNTING_CONFLICT_DECLARATION_REQUIRED, got %',v_msg; end if;
  end;
end $$;

select public.authorize_manual_journal_post(
  current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-AUTH-1','BOARD reviewed and authorizes posting',true
) as authorize_result\gset

do $$ declare v_result jsonb; begin
  v_result:=public.authorize_manual_journal_post(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-AUTH-1','BOARD reviewed and authorizes posting',true);
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then raise exception 'ACCOUNTING_AUTHORIZE_IDEMPOTENT_RETRY_FAILED'; end if;
end $$;
reset role;

-- 6) A different BOARD actor cannot execute another BOARD actor's approval.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000004',true);
do $$ declare v_msg text; begin
  begin
    perform public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-POST-WRONG-BOARD','must fail');
    raise exception 'expected_ACCOUNTING_POSTER_NOT_AUTHORIZING_BOARD_ACTOR';
  exception when others then get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_POSTER_NOT_AUTHORIZING_BOARD_ACTOR' then raise exception 'expected ACCOUNTING_POSTER_NOT_AUTHORIZING_BOARD_ACTOR, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 7) The same BOARD actor that authorized may POST.
set local role authenticated;
select set_config('request.jwt.claim.sub','12000000-0000-4000-8000-000000000003',true);
select public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-POST-1','authorized BOARD posting') as post_result\gset

do $$ declare v_result jsonb; begin
  v_result:=public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-BOARD-POST-1','authorized BOARD posting');
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then raise exception 'ACCOUNTING_POST_IDEMPOTENT_RETRY_FAILED'; end if;
end $$;
reset role;

-- Final evidence: exact three-actor business separation, approval evidence, balance and audit trail.
do $$
declare v_request_id uuid;
begin
  if not exists(
    select 1 from public.journal_entries je
    where je.id=current_setting('accounting.ci.finance_journal_id')::uuid
      and je.status='POSTED'
      and je.created_by=current_setting('accounting.ci.finance_profile_id')::uuid
      and je.validated_by=current_setting('accounting.ci.manager_profile_id')::uuid
      and je.posted_by=current_setting('accounting.ci.board_a_profile_id')::uuid
      and je.created_by<>je.validated_by
      and je.created_by<>je.posted_by
      and je.validated_by<>je.posted_by
  ) then raise exception 'ACCOUNTING_POST_ACTOR_SEPARATION_INVALID'; end if;

  select id into v_request_id from public.approval_requests
  where source_domain='ACCOUNTING' and source_entity_type='JOURNAL_ENTRY'
    and source_entity_id=current_setting('accounting.ci.finance_journal_id')::uuid
    and status='APPROVED';
  if v_request_id is null then raise exception 'ACCOUNTING_APPROVED_REQUEST_MISSING'; end if;
  if not exists(
    select 1 from public.approval_decisions ad
    where ad.approval_request_id=v_request_id
      and ad.actor_profile_id=current_setting('accounting.ci.board_a_profile_id')::uuid
      and ad.decision='APPROVE' and ad.conflict_declared=true
  ) then raise exception 'ACCOUNTING_BOARD_APPROVAL_DECISION_MISSING'; end if;

  if (select coalesce(sum(debit),0) from public.journal_lines where journal_entry_id=current_setting('accounting.ci.finance_journal_id')::uuid)
     <> (select coalesce(sum(credit),0) from public.journal_lines where journal_entry_id=current_setting('accounting.ci.finance_journal_id')::uuid) then
    raise exception 'ACCOUNTING_POSTED_JOURNAL_NOT_BALANCED';
  end if;

  if (select count(*) from public.audit_logs
      where entity_id=current_setting('accounting.ci.finance_journal_id')::uuid
        and action_code in ('ACCOUNTING_MANUAL_JOURNAL_DRAFT_CREATED','ACCOUNTING_MANUAL_JOURNAL_VALIDATED','ACCOUNTING_MANUAL_JOURNAL_POST_AUTHORIZED','ACCOUNTING_MANUAL_JOURNAL_POSTED'))<>4 then
    raise exception 'ACCOUNTING_JOURNAL_AUDIT_TRAIL_INCOMPLETE';
  end if;
end $$;

rollback;
