\set ON_ERROR_STOP on

begin;

-- The operational boundary remains locked: no baseline role may own ACCOUNTING_POST.
do $$
begin
  if exists(
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    where p.code='ACCOUNTING_POST'
  ) then
    raise exception 'ACCOUNTING_POST_BASELINE_MAPPING_MUST_REMAIN_EMPTY';
  end if;
end $$;

-- Synthetic actors for disposable local CI only.
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('11900000-0000-4000-8000-000000000001','authenticated','authenticated','accounting-finance@example.invalid',now(),'{}','{}',now(),now(),false,false),
('11900000-0000-4000-8000-000000000002','authenticated','authenticated','accounting-manager@example.invalid',now(),'{}','{}',now(),now(),false,false),
('11900000-0000-4000-8000-000000000003','authenticated','authenticated','accounting-poster@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles
set organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1),
    status='ACTIVE',updated_at=now()
where auth_user_id in (
  '11900000-0000-4000-8000-000000000001',
  '11900000-0000-4000-8000-000000000002',
  '11900000-0000-4000-8000-000000000003'
);

select id as finance_profile_id from public.profiles where auth_user_id='11900000-0000-4000-8000-000000000001'\gset
select id as manager_profile_id from public.profiles where auth_user_id='11900000-0000-4000-8000-000000000002'\gset
select id as poster_profile_id from public.profiles where auth_user_id='11900000-0000-4000-8000-000000000003'\gset
select id as cooperative_scope_id from public.data_scopes
where organization_id=(select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1)
  and scope_type='COOPERATIVE_SCOPE' limit 1\gset

insert into public.user_roles(profile_id,role_id)
select :'finance_profile_id'::uuid,r.id from public.roles r where r.code='FINANCE_OFFICER';
insert into public.user_roles(profile_id,role_id)
select :'manager_profile_id'::uuid,r.id from public.roles r where r.code='MANAGER';

insert into public.user_scope_assignments(profile_id,data_scope_id)
values
(:'finance_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'manager_profile_id'::uuid,:'cooperative_scope_id'::uuid),
(:'poster_profile_id'::uuid,:'cooperative_scope_id'::uuid);

-- Give Manager DRAFT_CREATE only inside this rolled-back test to prove maker-checker denial.
insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'manager_profile_id'::uuid,p.id,'ALLOW','Disposable accounting command maker-checker test'
from public.permissions p where p.code='ACCOUNTING_DRAFT_CREATE';

-- Give the third actor ACCOUNTING_POST only inside this rolled-back test.
insert into public.user_permissions(profile_id,permission_id,effect,reason)
select :'poster_profile_id'::uuid,p.id,'ALLOW','Disposable accounting command posting boundary test'
from public.permissions p where p.code='ACCOUNTING_POST';

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

-- Store psql-resolved identifiers in transaction-local GUCs so PL/pgSQL blocks never depend on psql interpolation.
select set_config('accounting.ci.finance_profile_id',:'finance_profile_id',true);
select set_config('accounting.ci.manager_profile_id',:'manager_profile_id',true);
select set_config('accounting.ci.poster_profile_id',:'poster_profile_id',true);
select set_config('accounting.ci.period_id',:'period_id',true);
select set_config('accounting.ci.debit_account_id',:'debit_account_id',true);
select set_config('accounting.ci.credit_account_id',:'credit_account_id',true);

-- 1) Finance Officer creates a balanced DRAFT.
set local role authenticated;
select set_config('request.jwt.claim.sub','11900000-0000-4000-8000-000000000001',true);
select public.create_manual_journal_draft(
  :'period_id'::uuid,
  current_date,
  'CI maker-checker journal',
  jsonb_build_array(
    jsonb_build_object('account_id',:'debit_account_id'::uuid,'debit',1000,'credit',0,'memo','Debit'),
    jsonb_build_object('account_id',:'credit_account_id'::uuid,'debit',0,'credit',1000,'memo','Credit')
  ),
  'ACC-CI-CREATE-1',
  'ACC-CI-REF-1'
) as finance_create_result\gset
select set_config('accounting.ci.finance_journal_id',(:'finance_create_result'::jsonb->>'journal_entry_id'),true);

-- Retry is idempotent and does not create another journal.
do $$
declare
  v_result jsonb;
  v_period uuid:=current_setting('accounting.ci.period_id')::uuid;
  v_debit uuid:=current_setting('accounting.ci.debit_account_id')::uuid;
  v_credit uuid:=current_setting('accounting.ci.credit_account_id')::uuid;
begin
  v_result:=public.create_manual_journal_draft(
    v_period,current_date,'CI maker-checker journal',
    jsonb_build_array(
      jsonb_build_object('account_id',v_debit,'debit',1000,'credit',0,'memo','Debit'),
      jsonb_build_object('account_id',v_credit,'debit',0,'credit',1000,'memo','Credit')
    ),'ACC-CI-CREATE-1','ACC-CI-REF-1');
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then
    raise exception 'ACCOUNTING_CREATE_IDEMPOTENT_RETRY_FAILED';
  end if;
end $$;
reset role;

-- 2) Manager creates own draft (test-only permission) then cannot self-validate it.
set local role authenticated;
select set_config('request.jwt.claim.sub','11900000-0000-4000-8000-000000000002',true);
select public.create_manual_journal_draft(
  :'period_id'::uuid,current_date,'CI self-validation rejection',
  jsonb_build_array(
    jsonb_build_object('account_id',:'debit_account_id'::uuid,'debit',500,'credit',0),
    jsonb_build_object('account_id',:'credit_account_id'::uuid,'debit',0,'credit',500)
  ),'ACC-CI-CREATE-SELF','ACC-CI-REF-SELF'
) as manager_create_result\gset
select set_config('accounting.ci.manager_journal_id',(:'manager_create_result'::jsonb->>'journal_entry_id'),true);

do $$ declare v_msg text; begin
  begin
    perform public.validate_manual_journal(current_setting('accounting.ci.manager_journal_id')::uuid,'ACC-CI-VALIDATE-SELF','must fail');
    raise exception 'expected_ACCOUNTING_MAKER_CHECKER_VIOLATION';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_MAKER_CHECKER_VIOLATION' then
      raise exception 'expected ACCOUNTING_MAKER_CHECKER_VIOLATION, got %',v_msg;
    end if;
  end;
end $$;

-- 3) Manager validates Finance draft successfully.
select public.validate_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-CI-VALIDATE-1','independent checker') as validate_result\gset
reset role;

do $$
begin
  if not exists(
    select 1 from public.journal_entries je
    where je.id=current_setting('accounting.ci.finance_journal_id')::uuid
      and je.status='VALIDATED'
      and je.created_by=current_setting('accounting.ci.finance_profile_id')::uuid
      and je.validated_by=current_setting('accounting.ci.manager_profile_id')::uuid
      and je.created_by<>je.validated_by
  ) then raise exception 'ACCOUNTING_VALIDATE_STATE_INVALID'; end if;
end $$;

-- 4) Manager still cannot post because ACCOUNTING_POST is intentionally unmapped.
set local role authenticated;
select set_config('request.jwt.claim.sub','11900000-0000-4000-8000-000000000002',true);
do $$ declare v_msg text; begin
  begin
    perform public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-CI-POST-MANAGER','must fail');
    raise exception 'expected_ACCOUNTING_POST_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_POST_DENIED' then raise exception 'expected ACCOUNTING_POST_DENIED, got %',v_msg; end if;
  end;
end $$;
reset role;

-- 5) Even a test actor with explicit ACCOUNTING_POST remains blocked while JOURNAL_POST policy is DRAFT.
set local role authenticated;
select set_config('request.jwt.claim.sub','11900000-0000-4000-8000-000000000003',true);
do $$ declare v_msg text; begin
  begin
    perform public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-CI-POST-POLICY-DENIED','must fail');
    raise exception 'expected_ACCOUNTING_POST_POLICY_NOT_ACTIVE';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCOUNTING_POST_POLICY_NOT_ACTIVE' then raise exception 'expected ACCOUNTING_POST_POLICY_NOT_ACTIVE, got %',v_msg; end if;
  end;
end $$;
reset role;

-- Activate the existing demo policy/version only inside this rolled-back transaction.
update public.approval_policies
set status='ACTIVE',updated_at=now()
where code='DEMO-ACCOUNTING-POST';
update public.approval_policy_versions apv
set status='ACTIVE',effective_from=now()-interval '1 minute'
where apv.approval_policy_id=(select id from public.approval_policies where code='DEMO-ACCOUNTING-POST' limit 1)
  and apv.version_no=1;
select apv.id as policy_version_id
from public.approval_policy_versions apv
join public.approval_policies ap on ap.id=apv.approval_policy_id
where ap.code='DEMO-ACCOUNTING-POST' and apv.version_no=1\gset

insert into public.approval_requests(
  organization_id,organization_node_id,approval_policy_version_id,source_domain,source_entity_type,
  source_entity_id,source_reference,correlation_id,requested_by,request_snapshot,policy_snapshot,
  status,current_step_no,completed_at
)
select je.organization_id,je.organization_node_id,:'policy_version_id'::uuid,'ACCOUNTING','JOURNAL_ENTRY',
       je.id,je.journal_number,'ACC-CI-APPROVAL-1',current_setting('accounting.ci.finance_profile_id')::uuid,'{}'::jsonb,'{}'::jsonb,
       'APPROVED',1,now()
from public.journal_entries je where je.id=current_setting('accounting.ci.finance_journal_id')::uuid;

-- 6) A third, distinct actor with explicit test-only ACCOUNTING_POST can now post.
set local role authenticated;
select set_config('request.jwt.claim.sub','11900000-0000-4000-8000-000000000003',true);
select public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-CI-POST-1','approved third-actor post') as post_result\gset

do $$ declare v_result jsonb; begin
  v_result:=public.post_manual_journal(current_setting('accounting.ci.finance_journal_id')::uuid,'ACC-CI-POST-1','approved third-actor post');
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then
    raise exception 'ACCOUNTING_POST_IDEMPOTENT_RETRY_FAILED';
  end if;
end $$;
reset role;

-- Final evidence: three distinct actors, balanced immutable POSTED journal, audit trail.
do $$
begin
  if not exists(
    select 1 from public.journal_entries je
    where je.id=current_setting('accounting.ci.finance_journal_id')::uuid
      and je.status='POSTED'
      and je.created_by=current_setting('accounting.ci.finance_profile_id')::uuid
      and je.validated_by=current_setting('accounting.ci.manager_profile_id')::uuid
      and je.posted_by=current_setting('accounting.ci.poster_profile_id')::uuid
      and je.created_by<>je.validated_by
      and je.created_by<>je.posted_by
      and je.validated_by<>je.posted_by
  ) then raise exception 'ACCOUNTING_POST_ACTOR_SEPARATION_INVALID'; end if;

  if (select coalesce(sum(debit),0) from public.journal_lines where journal_entry_id=current_setting('accounting.ci.finance_journal_id')::uuid)
     <> (select coalesce(sum(credit),0) from public.journal_lines where journal_entry_id=current_setting('accounting.ci.finance_journal_id')::uuid) then
    raise exception 'ACCOUNTING_POSTED_JOURNAL_NOT_BALANCED';
  end if;

  if (select count(*) from public.audit_logs where entity_id=current_setting('accounting.ci.finance_journal_id')::uuid
      and action_code in ('ACCOUNTING_MANUAL_JOURNAL_DRAFT_CREATED','ACCOUNTING_MANUAL_JOURNAL_VALIDATED','ACCOUNTING_MANUAL_JOURNAL_POSTED'))<>3 then
    raise exception 'ACCOUNTING_JOURNAL_AUDIT_TRAIL_INCOMPLETE';
  end if;
end $$;

rollback;
