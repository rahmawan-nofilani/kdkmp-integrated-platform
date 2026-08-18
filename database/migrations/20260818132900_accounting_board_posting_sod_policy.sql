-- Controlled Accounting posting SoD for Release-1 DEVELOPMENT.
-- Maker = FINANCE_OFFICER, Checker = MANAGER, Poster/authorization actor = BOARD.
-- SUPERVISOR remains read/audit only. No production deployment is performed here.

-- 1) Baseline role policy: ACCOUNTING_POST belongs only to BOARD.
do $$
declare
  v_permission_id uuid;
  v_board_role_id uuid;
begin
  select id into v_permission_id
  from public.permissions
  where code='ACCOUNTING_POST' and is_privileged=true;
  if v_permission_id is null then
    raise exception 'ACCOUNTING_POST_PERMISSION_NOT_PRIVILEGED_OR_MISSING';
  end if;

  select id into v_board_role_id
  from public.roles
  where code='BOARD' and status='ACTIVE';
  if v_board_role_id is null then
    raise exception 'ACCOUNTING_BOARD_ROLE_MISSING';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_permission_id and r.code<>'BOARD'
  ) then
    raise exception 'ACCOUNTING_POST_NON_BOARD_MAPPING_PRESENT';
  end if;

  insert into public.role_permissions(role_id,permission_id)
  values(v_board_role_id,v_permission_id)
  on conflict do nothing;

  if (select count(*) from public.role_permissions where permission_id=v_permission_id)<>1 then
    raise exception 'ACCOUNTING_POST_BASELINE_MAPPING_COUNT_INVALID';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE') and r.code='BOARD'
  ) then
    raise exception 'ACCOUNTING_BOARD_MUST_NOT_BE_MAKER_OR_CHECKER';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE','ACCOUNTING_POST','ACCOUNTING_PERIOD_MANAGE','ACCOUNTING_RECONCILE')
      and r.code='SUPERVISOR'
  ) then
    raise exception 'ACCOUNTING_SUPERVISOR_MUST_REMAIN_READ_AUDIT_ONLY';
  end if;
end $$;

-- 2) Activate the existing JOURNAL_POST policy for the DEVELOPMENT cooperative.
-- The policy remains non-delegable and requires a conflict declaration.
do $$
declare
  v_org uuid;
  v_node uuid;
  v_policy uuid;
  v_version uuid;
begin
  select o.id,n.id into v_org,v_node
  from public.organizations o
  join public.organization_nodes n on n.organization_id=o.id
  where o.code='DEMO-KDKMP-DEV' and n.code='DEMO-KDKMP' and n.node_type='KDKMP'
  limit 1;
  if v_org is null or v_node is null then raise exception 'ACCOUNTING_DEVELOPMENT_SCOPE_NOT_FOUND'; end if;

  select id into v_policy
  from public.approval_policies
  where organization_id=v_org and organization_node_id=v_node
    and transaction_type='JOURNAL_POST' and code='DEMO-ACCOUNTING-POST'
  limit 1;
  if v_policy is null then raise exception 'ACCOUNTING_JOURNAL_POST_POLICY_MISSING'; end if;

  update public.approval_policies
  set status='ACTIVE',updated_at=now(),
      notes='Release-1 DEVELOPMENT: FINANCE_OFFICER maker -> MANAGER checker -> BOARD authorization/poster.'
  where id=v_policy;

  select id into v_version
  from public.approval_policy_versions
  where approval_policy_id=v_policy and version_no=1
  limit 1;
  if v_version is null then raise exception 'ACCOUNTING_JOURNAL_POST_POLICY_VERSION_MISSING'; end if;

  update public.approval_policy_versions
  set status='ACTIVE',effective_from=coalesce(effective_from,timestamptz '2026-08-18 00:00:00+00'),effective_until=null
  where id=v_version;

  update public.approval_policy_steps
  set step_name='BOARD Posting Authorization',
      required_permission_code='ACCOUNTING_POST',
      min_approvers=1,
      quorum_rule='ALL_REQUIRED',
      prohibit_requester_approval=true,
      prohibit_previous_step_actor=true,
      require_conflict_declaration=true,
      allow_delegation=false
  where approval_policy_version_id=v_version and step_no=1;

  if (select count(*) from public.approval_policy_steps where approval_policy_version_id=v_version)<>1 then
    raise exception 'ACCOUNTING_JOURNAL_POST_POLICY_STEP_COUNT_INVALID';
  end if;

  if not exists (
    select 1 from public.approval_policy_steps
    where approval_policy_version_id=v_version and step_no=1
      and required_permission_code='ACCOUNTING_POST'
      and min_approvers=1 and quorum_rule='ALL_REQUIRED'
      and prohibit_requester_approval=true
      and prohibit_previous_step_actor=true
      and require_conflict_declaration=true
      and allow_delegation=false
  ) then
    raise exception 'ACCOUNTING_JOURNAL_POST_POLICY_STEP_INVALID';
  end if;

  insert into public.sod_rules(
    organization_id,organization_node_id,code,name,domain,transaction_type,rule_type,
    subject_permission_code,conflicting_permission_code,status,effective_from,notes
  ) values
    (v_org,v_node,'ACCOUNTING-MAKER-CHECKER','Manual Journal Maker cannot be Checker','ACCOUNTING','JOURNAL_POST',
     'CREATOR_CANNOT_REVIEW','ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE','ACTIVE',timestamptz '2026-08-18 00:00:00+00',
     'Enforced by validate_manual_journal actor separation.'),
    (v_org,v_node,'ACCOUNTING-CHECKER-POSTER','Manual Journal Checker cannot be Poster','ACCOUNTING','JOURNAL_POST',
     'REVIEWER_CANNOT_APPROVE','ACCOUNTING_VALIDATE','ACCOUNTING_POST','ACTIVE',timestamptz '2026-08-18 00:00:00+00',
     'Enforced by authorize/post command actor separation.')
  on conflict (organization_node_id,code) do update
  set name=excluded.name,domain=excluded.domain,transaction_type=excluded.transaction_type,
      rule_type=excluded.rule_type,subject_permission_code=excluded.subject_permission_code,
      conflicting_permission_code=excluded.conflicting_permission_code,status='ACTIVE',
      effective_from=excluded.effective_from,effective_until=null,notes=excluded.notes;
end $$;

-- 3) Extend the accounting command ledger with explicit posting authorization.
alter table app_private.accounting_journal_commands
  drop constraint if exists accounting_journal_commands_command_type_check;
alter table app_private.accounting_journal_commands
  add constraint accounting_journal_commands_command_type_check
  check (command_type in ('CREATE_DRAFT','VALIDATE','AUTHORIZE_POST','POST'));

-- 4) Every newly VALIDATED manual journal receives exactly one approval request
-- using the ACTIVE JOURNAL_POST policy. The checker is the requester; BOARD cannot
-- be the checker under the baseline role matrix, so requester self-approval is impossible.
create or replace function app_private.create_manual_journal_post_approval()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_policy_version_id uuid;
  v_request_id uuid;
  v_step public.approval_policy_steps%rowtype;
begin
  if new.source_domain<>'MANUAL' or new.status<>'VALIDATED' or old.status is not distinct from new.status then
    return new;
  end if;
  if new.validated_by is null or new.created_by is null or new.validated_by=new.created_by then
    raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_VIOLATION';
  end if;

  select apv.id into v_policy_version_id
  from public.approval_policies ap
  join public.approval_policy_versions apv on apv.approval_policy_id=ap.id
  where ap.organization_id=new.organization_id
    and ap.organization_node_id=new.organization_node_id
    and ap.domain='ACCOUNTING'
    and ap.transaction_type='JOURNAL_POST'
    and ap.status='ACTIVE'
    and apv.status='ACTIVE'
    and (apv.effective_from is null or apv.effective_from<=now())
    and (apv.effective_until is null or apv.effective_until>now())
  order by apv.version_no desc
  limit 1;
  if v_policy_version_id is null then
    raise exception using errcode='42501',message='ACCOUNTING_POST_POLICY_NOT_ACTIVE';
  end if;

  select * into v_step
  from public.approval_policy_steps
  where approval_policy_version_id=v_policy_version_id and step_no=1;
  if not found
     or v_step.required_permission_code<>'ACCOUNTING_POST'
     or v_step.min_approvers<>1
     or v_step.prohibit_requester_approval is not true
     or v_step.require_conflict_declaration is not true
     or v_step.allow_delegation is not false then
    raise exception using errcode='42501',message='ACCOUNTING_POST_POLICY_INVALID';
  end if;

  insert into public.approval_requests(
    organization_id,organization_node_id,approval_policy_version_id,
    source_domain,source_entity_type,source_entity_id,source_reference,correlation_id,
    requested_by,request_snapshot,policy_snapshot,status,current_step_no
  ) values(
    new.organization_id,new.organization_node_id,v_policy_version_id,
    'ACCOUNTING','JOURNAL_ENTRY',new.id,new.journal_number,'ACCOUNTING:JOURNAL_POST:'||new.id::text,
    new.validated_by,
    jsonb_build_object('journal_entry_id',new.id,'journal_number',new.journal_number,'entry_date',new.entry_date,'description',new.description,'created_by',new.created_by,'validated_by',new.validated_by),
    jsonb_build_object('required_permission_code',v_step.required_permission_code,'prohibit_requester_approval',v_step.prohibit_requester_approval,'require_conflict_declaration',v_step.require_conflict_declaration,'allow_delegation',v_step.allow_delegation),
    'IN_REVIEW',1
  ) on conflict (organization_node_id,source_domain,source_entity_type,source_entity_id,correlation_id)
    do nothing;

  select id into v_request_id
  from public.approval_requests
  where organization_node_id=new.organization_node_id
    and source_domain='ACCOUNTING' and source_entity_type='JOURNAL_ENTRY'
    and source_entity_id=new.id and correlation_id='ACCOUNTING:JOURNAL_POST:'||new.id::text
  limit 1;
  if v_request_id is null then raise exception 'ACCOUNTING_POST_APPROVAL_REQUEST_CREATE_FAILED'; end if;

  insert into public.approval_request_steps(
    approval_request_id,organization_id,organization_node_id,step_no,step_name,
    required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,
    prohibit_previous_step_actor,require_conflict_declaration,allow_delegation,status,activated_at
  ) values(
    v_request_id,new.organization_id,new.organization_node_id,v_step.step_no,v_step.step_name,
    v_step.required_permission_code,v_step.min_approvers,v_step.quorum_rule,v_step.prohibit_requester_approval,
    v_step.prohibit_previous_step_actor,v_step.require_conflict_declaration,v_step.allow_delegation,'ACTIVE',now()
  ) on conflict (approval_request_id,step_no) do nothing;

  return new;
end;
$$;
revoke all on function app_private.create_manual_journal_post_approval() from public,anon,authenticated;

drop trigger if exists trg_create_manual_journal_post_approval on public.journal_entries;
create trigger trg_create_manual_journal_post_approval
after update of status on public.journal_entries
for each row
when (new.source_domain='MANUAL' and new.status='VALIDATED' and old.status is distinct from new.status)
execute function app_private.create_manual_journal_post_approval();

-- 5) BOARD authorization command. This records the approval decision separately
-- from posting and requires an explicit conflict declaration.
create or replace function app_private.authorize_manual_journal_post(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_conflict_declared boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid:=auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
  v_journal public.journal_entries%rowtype;
  v_request public.approval_requests%rowtype;
  v_step public.approval_request_steps%rowtype;
  v_request_hash text;
  v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id
  from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_POST') then raise exception using errcode='42501',message='ACCOUNTING_POST_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_conflict_declared is not true then raise exception using errcode='42501',message='ACCOUNTING_CONFLICT_DECLARATION_REQUIRED'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_POST_REASON_REQUIRED'; end if;

  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',btrim(p_reason),'conflict_declared',p_conflict_declared)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':AUTHORIZE_POST:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c
  where c.actor_profile_id=v_profile_id and c.command_type='AUTHORIZE_POST' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'approval_status','APPROVED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries je where je.id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL' or v_journal.status<>'VALIDATED' then raise exception using errcode='23514',message='ACCOUNTING_JOURNAL_NOT_VALIDATED'; end if;
  if v_journal.created_by is null or v_journal.validated_by is null or v_profile_id in (v_journal.created_by,v_journal.validated_by) then
    raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION';
  end if;

  select * into v_request
  from public.approval_requests ar
  where ar.organization_id=v_journal.organization_id
    and ar.organization_node_id=v_journal.organization_node_id
    and ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_ENTRY'
    and ar.source_entity_id=v_journal.id
    and ar.correlation_id='ACCOUNTING:JOURNAL_POST:'||v_journal.id::text
  for update;
  if not found then raise exception using errcode='42501',message='ACCOUNTING_POST_APPROVAL_REQUEST_MISSING'; end if;
  if v_request.requested_by=v_profile_id then raise exception using errcode='42501',message='ACCOUNTING_APPROVAL_REQUESTER_CANNOT_APPROVE'; end if;
  if v_request.status not in ('PENDING','IN_REVIEW') then raise exception using errcode='23514',message='ACCOUNTING_POST_APPROVAL_NOT_OPEN'; end if;

  select * into v_step from public.approval_request_steps s
  where s.approval_request_id=v_request.id and s.step_no=1 for update;
  if not found or v_step.status<>'ACTIVE' or v_step.required_permission_code<>'ACCOUNTING_POST' then
    raise exception using errcode='42501',message='ACCOUNTING_POST_APPROVAL_STEP_INVALID';
  end if;
  if v_step.prohibit_requester_approval and v_request.requested_by=v_profile_id then
    raise exception using errcode='42501',message='ACCOUNTING_APPROVAL_REQUESTER_CANNOT_APPROVE';
  end if;
  if v_step.require_conflict_declaration and p_conflict_declared is not true then
    raise exception using errcode='42501',message='ACCOUNTING_CONFLICT_DECLARATION_REQUIRED';
  end if;

  insert into public.approval_decisions(
    approval_request_id,approval_request_step_id,organization_id,organization_node_id,
    actor_profile_id,decision,conflict_declared,conflict_note,reason,evidence
  ) values(
    v_request.id,v_step.id,v_journal.organization_id,v_journal.organization_node_id,
    v_profile_id,'APPROVE',true,'No conflict declared for BOARD posting authorization.',btrim(p_reason),
    jsonb_build_object('journal_entry_id',v_journal.id,'journal_number',v_journal.journal_number,'validated_by',v_journal.validated_by)
  );

  update public.approval_request_steps set status='APPROVED',completed_at=now() where id=v_step.id;
  update public.approval_requests set status='APPROVED',completed_at=now() where id=v_request.id;

  insert into app_private.accounting_journal_commands(
    organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id
  ) values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'AUTHORIZE_POST',p_idempotency_key,v_request_hash,v_journal.id);

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id
  ) values(
    v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_POST_AUTHORIZED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('journal_status','VALIDATED','approval_status',v_request.status),
    jsonb_build_object('journal_status','VALIDATED','approval_status','APPROVED','approval_request_id',v_request.id),
    btrim(p_reason),p_idempotency_key
  );

  return jsonb_build_object('journal_entry_id',v_journal.id,'approval_request_id',v_request.id,'approval_status','APPROVED','idempotent_replay',false);
end;
$$;

create or replace function public.authorize_manual_journal_post(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_conflict_declared boolean
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.authorize_manual_journal_post(p_journal_entry_id,p_idempotency_key,p_reason,p_conflict_declared);
$$;

revoke all on function app_private.authorize_manual_journal_post(uuid,text,text,boolean) from public,anon;
grant execute on function app_private.authorize_manual_journal_post(uuid,text,text,boolean) to authenticated,service_role;
revoke all on function public.authorize_manual_journal_post(uuid,text,text,boolean) from public,anon;
grant execute on function public.authorize_manual_journal_post(uuid,text,text,boolean) to authenticated,service_role;

-- 6) Defense in depth: direct/service-role attempts to POST a manual journal must
-- have an APPROVED request and the posted_by actor must be the BOARD actor who
-- recorded the APPROVE decision.
create or replace function app_private.guard_manual_journal_poster_authorization()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.source_domain<>'MANUAL' or new.status<>'POSTED' or old.status is not distinct from new.status then return new; end if;
  if new.posted_by is null then raise exception using errcode='42501',message='ACCOUNTING_POSTER_REQUIRED'; end if;

  if not exists (
    select 1
    from public.approval_requests ar
    join public.approval_request_steps ars on ars.approval_request_id=ar.id and ars.step_no=1 and ars.status='APPROVED'
    join public.approval_decisions ad on ad.approval_request_id=ar.id and ad.approval_request_step_id=ars.id
    where ar.organization_id=new.organization_id
      and ar.organization_node_id=new.organization_node_id
      and ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_ENTRY'
      and ar.source_entity_id=new.id
      and ar.correlation_id='ACCOUNTING:JOURNAL_POST:'||new.id::text
      and ar.status='APPROVED'
      and ad.decision='APPROVE'
      and ad.actor_profile_id=new.posted_by
  ) then
    raise exception using errcode='42501',message='ACCOUNTING_POSTER_NOT_AUTHORIZING_BOARD_ACTOR';
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_manual_journal_poster_authorization() from public,anon,authenticated;

drop trigger if exists trg_guard_manual_journal_poster_authorization on public.journal_entries;
create trigger trg_guard_manual_journal_poster_authorization
before update of status on public.journal_entries
for each row
when (new.source_domain='MANUAL' and new.status='POSTED' and old.status is distinct from new.status)
execute function app_private.guard_manual_journal_poster_authorization();

comment on function public.authorize_manual_journal_post(uuid,text,text,boolean) is
'BOARD-only controlled authorization for a VALIDATED manual journal. Requires explicit conflict declaration; the same BOARD actor must execute the subsequent post command.';
