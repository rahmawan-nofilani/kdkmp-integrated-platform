-- Release-1 controlled manual-journal reversal + accounting period close.
--
-- Existing SoD is preserved:
--   FINANCE_OFFICER = maker (ACCOUNTING_DRAFT_CREATE)
--   MANAGER         = checker + soft-close operator (ACCOUNTING_VALIDATE / ACCOUNTING_PERIOD_MANAGE)
--   BOARD           = posting authority + hard-close governance actor (ACCOUNTING_POST)
--   SUPERVISOR      = read/audit only
--
-- No new privileged permission or role mapping is introduced here.
-- Manual reversal is deliberately limited to source_domain = MANUAL so POS/payment/
-- inventory journals remain reversible only through their authoritative domain engines.

do $$
begin
  if not exists (
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
    where r.code='FINANCE_OFFICER' and p.code='ACCOUNTING_DRAFT_CREATE'
  ) then raise exception 'ACCOUNTING_FINANCE_MAKER_POLICY_MISSING'; end if;

  if not exists (
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
    where r.code='MANAGER' and p.code='ACCOUNTING_VALIDATE'
  ) or not exists (
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
    where r.code='MANAGER' and p.code='ACCOUNTING_PERIOD_MANAGE'
  ) then raise exception 'ACCOUNTING_MANAGER_CHECKER_PERIOD_POLICY_MISSING'; end if;

  if not exists (
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
    where r.code='BOARD' and p.code='ACCOUNTING_POST'
  ) then raise exception 'ACCOUNTING_BOARD_POST_POLICY_MISSING'; end if;

  if exists (
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    join public.permissions p on p.id=rp.permission_id
    where r.code='SUPERVISOR'
      and p.code in ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING_VALIDATE','ACCOUNTING_POST','ACCOUNTING_PERIOD_MANAGE','ACCOUNTING_RECONCILE')
  ) then raise exception 'ACCOUNTING_SUPERVISOR_WRITE_POLICY_PRESENT'; end if;
end $$;

-- Extend the append-only command evidence ledger for reversal operations.
alter table app_private.accounting_journal_commands
  drop constraint if exists accounting_journal_commands_command_type_check;
alter table app_private.accounting_journal_commands
  add constraint accounting_journal_commands_command_type_check
  check (command_type in (
    'CREATE_DRAFT','VALIDATE','AUTHORIZE_POST','POST',
    'CREATE_REVERSAL','VALIDATE_REVERSAL','AUTHORIZE_REVERSAL','POST_REVERSAL'
  ));

-- One active reversal at a time for a manual source journal. A CANCELLED reversal may
-- be replaced; POSTED reversal evidence remains unique and immutable.
create unique index if not exists uq_manual_reversal_active_source
  on public.journal_entries(reversal_of_entry_id)
  where source_domain='MANUAL_REVERSAL'
    and reversal_of_entry_id is not null
    and status in ('DRAFT','VALIDATED','POSTED');

create or replace function app_private.create_manual_journal_reversal_draft(
  p_original_journal_entry_id uuid,
  p_accounting_period_id uuid,
  p_entry_date date,
  p_reason text,
  p_idempotency_key text
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
  v_original public.journal_entries%rowtype;
  v_period public.accounting_periods%rowtype;
  v_reversal_id uuid:=gen_random_uuid();
  v_journal_number text;
  v_request_hash text;
  v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id
  from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_DRAFT_CREATE') then raise exception using errcode='42501',message='ACCOUNTING_DRAFT_CREATE_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_REVERSAL_REASON_REQUIRED'; end if;

  v_request_hash:=md5(jsonb_build_object(
    'original',p_original_journal_entry_id,'period',p_accounting_period_id,
    'entry_date',p_entry_date,'reason',btrim(p_reason)
  )::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':CREATE_REVERSAL:'||p_idempotency_key,0));

  select * into v_existing from app_private.accounting_journal_commands c
  where c.actor_profile_id=v_profile_id and c.command_type='CREATE_REVERSAL' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'status',(select status from public.journal_entries where id=v_existing.journal_entry_id),'idempotent_replay',true);
  end if;

  select * into v_original from public.journal_entries je where je.id=p_original_journal_entry_id for share;
  if not found or v_original.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_original.organization_id,v_original.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_original.status<>'POSTED' then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_SOURCE_NOT_POSTED'; end if;
  if v_original.source_domain<>'MANUAL' or v_original.reversal_of_entry_id is not null then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_MANUAL_SOURCE_REQUIRED'; end if;
  if exists (
    select 1 from public.journal_entries r
    where r.reversal_of_entry_id=v_original.id and r.source_domain='MANUAL_REVERSAL'
      and r.status in ('DRAFT','VALIDATED','POSTED')
  ) then raise exception using errcode='23505',message='ACCOUNTING_REVERSAL_ALREADY_EXISTS'; end if;

  select * into v_period from public.accounting_periods ap where ap.id=p_accounting_period_id for share;
  if not found or v_period.organization_id<>v_original.organization_id or v_period.organization_node_id<>v_original.organization_node_id then
    raise exception using errcode='42501',message='ACCOUNTING_PERIOD_NOT_ACCESSIBLE';
  end if;
  if not app_private.has_data_scope(v_period.organization_id,v_period.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_period.status<>'OPEN' then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_OPEN'; end if;
  if p_entry_date is null or p_entry_date<v_period.start_date or p_entry_date>v_period.end_date then raise exception using errcode='23514',message='ACCOUNTING_ENTRY_DATE_OUTSIDE_PERIOD'; end if;
  if p_entry_date<v_original.entry_date then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_DATE_BEFORE_SOURCE'; end if;

  v_journal_number:='RV-'||to_char(p_entry_date,'YYYYMMDD')||'-'||upper(substr(replace(v_reversal_id::text,'-',''),1,8));
  insert into public.journal_entries(
    id,organization_id,organization_node_id,accounting_period_id,journal_number,entry_date,
    description,source_domain,source_entity_type,source_entity_id,source_reference,correlation_id,
    idempotency_key,reversal_of_entry_id,status,created_by
  ) values(
    v_reversal_id,v_original.organization_id,v_original.organization_node_id,v_period.id,v_journal_number,p_entry_date,
    'Reversal of '||v_original.journal_number||': '||btrim(p_reason),'MANUAL_REVERSAL','JOURNAL_ENTRY',v_original.id,
    v_original.journal_number,'ACCOUNTING:REVERSAL:'||v_original.id::text,p_idempotency_key,v_original.id,'DRAFT',v_profile_id
  );

  insert into public.journal_lines(
    journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,
    memo,subledger_type,subledger_id,dimensions
  )
  select v_reversal_id,jl.organization_id,jl.organization_node_id,jl.line_no,jl.account_id,
         jl.credit,jl.debit,
         coalesce('Reversal: '||nullif(jl.memo,''),'Reversal of '||v_original.journal_number),
         jl.subledger_type,jl.subledger_id,jl.dimensions
  from public.journal_lines jl where jl.journal_entry_id=v_original.id order by jl.line_no;

  insert into app_private.accounting_journal_commands(
    organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id
  ) values(v_original.organization_id,v_original.organization_node_id,v_profile_id,'CREATE_REVERSAL',p_idempotency_key,v_request_hash,v_reversal_id);

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id)
  values(v_original.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_REVERSAL_DRAFT_CREATED','JOURNAL_ENTRY',v_reversal_id,
    jsonb_build_object('status','DRAFT','reversal_of_entry_id',v_original.id,'source_journal_number',v_original.journal_number),
    btrim(p_reason),p_idempotency_key);

  return jsonb_build_object('journal_entry_id',v_reversal_id,'journal_number',v_journal_number,'status','DRAFT','reversal_of_entry_id',v_original.id,'idempotent_replay',false);
end;
$$;

create or replace function app_private.validate_manual_journal_reversal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid:=auth.uid(); v_profile_id uuid; v_organization_id uuid;
  v_journal public.journal_entries%rowtype; v_period public.accounting_periods%rowtype;
  v_policy_version_id uuid; v_request_id uuid; v_step public.approval_policy_steps%rowtype;
  v_request_hash text; v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_VALIDATE') then raise exception using errcode='42501',message='ACCOUNTING_VALIDATE_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if length(coalesce(p_reason,''))>500 then raise exception using errcode='22023',message='ACCOUNTING_REASON_INVALID'; end if;
  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':VALIDATE_REVERSAL:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c where c.actor_profile_id=v_profile_id and c.command_type='VALIDATE_REVERSAL' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'status','VALIDATED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries je where je.id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL_REVERSAL' or v_journal.reversal_of_entry_id is null then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_JOURNAL_REQUIRED'; end if;
  if v_journal.status<>'DRAFT' then raise exception using errcode='23514',message='ACCOUNTING_JOURNAL_NOT_DRAFT'; end if;
  if v_journal.created_by is null or v_journal.created_by=v_profile_id then raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_VIOLATION'; end if;
  select * into v_period from public.accounting_periods where id=v_journal.accounting_period_id;
  if not found or v_period.status<>'OPEN' then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_OPEN'; end if;

  select apv.id into v_policy_version_id
  from public.approval_policies ap join public.approval_policy_versions apv on apv.approval_policy_id=ap.id
  where ap.organization_id=v_journal.organization_id and ap.organization_node_id=v_journal.organization_node_id
    and ap.domain='ACCOUNTING' and ap.transaction_type='JOURNAL_POST' and ap.status='ACTIVE' and apv.status='ACTIVE'
    and (apv.effective_from is null or apv.effective_from<=now()) and (apv.effective_until is null or apv.effective_until>now())
  order by apv.version_no desc limit 1;
  if v_policy_version_id is null then raise exception using errcode='42501',message='ACCOUNTING_POST_POLICY_NOT_ACTIVE'; end if;
  select * into v_step from public.approval_policy_steps where approval_policy_version_id=v_policy_version_id and step_no=1;
  if not found or v_step.required_permission_code<>'ACCOUNTING_POST' or v_step.min_approvers<>1
     or v_step.prohibit_requester_approval is not true or v_step.require_conflict_declaration is not true or v_step.allow_delegation is not false then
    raise exception using errcode='42501',message='ACCOUNTING_POST_POLICY_INVALID';
  end if;

  update public.journal_entries set status='VALIDATED',validated_by=v_profile_id,validated_at=now() where id=v_journal.id;

  insert into public.approval_requests(
    organization_id,organization_node_id,approval_policy_version_id,source_domain,source_entity_type,
    source_entity_id,source_reference,correlation_id,requested_by,request_snapshot,policy_snapshot,status,current_step_no
  ) values(
    v_journal.organization_id,v_journal.organization_node_id,v_policy_version_id,'ACCOUNTING','JOURNAL_REVERSAL',
    v_journal.id,v_journal.journal_number,'ACCOUNTING:JOURNAL_REVERSAL:'||v_journal.id::text,v_profile_id,
    jsonb_build_object('journal_entry_id',v_journal.id,'reversal_of_entry_id',v_journal.reversal_of_entry_id,'created_by',v_journal.created_by,'validated_by',v_profile_id),
    jsonb_build_object('required_permission_code',v_step.required_permission_code,'require_conflict_declaration',v_step.require_conflict_declaration,'allow_delegation',v_step.allow_delegation),
    'IN_REVIEW',1
  ) on conflict (organization_node_id,source_domain,source_entity_type,source_entity_id,correlation_id) do nothing;

  select id into v_request_id from public.approval_requests
  where organization_node_id=v_journal.organization_node_id and source_domain='ACCOUNTING' and source_entity_type='JOURNAL_REVERSAL'
    and source_entity_id=v_journal.id and correlation_id='ACCOUNTING:JOURNAL_REVERSAL:'||v_journal.id::text limit 1;
  if v_request_id is null then raise exception 'ACCOUNTING_REVERSAL_APPROVAL_CREATE_FAILED'; end if;

  insert into public.approval_request_steps(
    approval_request_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,
    min_approvers,quorum_rule,prohibit_requester_approval,prohibit_previous_step_actor,
    require_conflict_declaration,allow_delegation,status,activated_at
  ) values(
    v_request_id,v_journal.organization_id,v_journal.organization_node_id,v_step.step_no,'BOARD Reversal Authorization',v_step.required_permission_code,
    v_step.min_approvers,v_step.quorum_rule,true,true,true,false,'ACTIVE',now()
  ) on conflict (approval_request_id,step_no) do nothing;

  insert into app_private.accounting_journal_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id)
  values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'VALIDATE_REVERSAL',p_idempotency_key,v_request_hash,v_journal.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_REVERSAL_VALIDATED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('status','DRAFT','created_by',v_journal.created_by),
    jsonb_build_object('status','VALIDATED','validated_by',v_profile_id,'approval_request_id',v_request_id),
    nullif(btrim(coalesce(p_reason,'')),''),p_idempotency_key);
  return jsonb_build_object('journal_entry_id',v_journal.id,'status','VALIDATED','approval_request_id',v_request_id,'idempotent_replay',false);
end;
$$;

create or replace function app_private.authorize_manual_journal_reversal(
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
  v_auth_user_id uuid:=auth.uid(); v_profile_id uuid; v_organization_id uuid;
  v_journal public.journal_entries%rowtype; v_request public.approval_requests%rowtype; v_step public.approval_request_steps%rowtype;
  v_request_hash text; v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_POST') then raise exception using errcode='42501',message='ACCOUNTING_POST_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_conflict_declared is not true then raise exception using errcode='42501',message='ACCOUNTING_CONFLICT_DECLARATION_REQUIRED'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_REVERSAL_REASON_REQUIRED'; end if;
  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',btrim(p_reason),'conflict_declared',true)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':AUTHORIZE_REVERSAL:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c where c.actor_profile_id=v_profile_id and c.command_type='AUTHORIZE_REVERSAL' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'approval_status','APPROVED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries where id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL_REVERSAL' or v_journal.status<>'VALIDATED' then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_NOT_VALIDATED'; end if;
  if v_profile_id in (v_journal.created_by,v_journal.validated_by) or v_journal.created_by=v_journal.validated_by then raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION'; end if;

  select * into v_request from public.approval_requests ar
  where ar.organization_id=v_journal.organization_id and ar.organization_node_id=v_journal.organization_node_id
    and ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_REVERSAL' and ar.source_entity_id=v_journal.id
    and ar.correlation_id='ACCOUNTING:JOURNAL_REVERSAL:'||v_journal.id::text for update;
  if not found then raise exception using errcode='42501',message='ACCOUNTING_REVERSAL_APPROVAL_MISSING'; end if;
  if v_request.requested_by=v_profile_id then raise exception using errcode='42501',message='ACCOUNTING_APPROVAL_REQUESTER_CANNOT_APPROVE'; end if;
  if v_request.status not in ('PENDING','IN_REVIEW') then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_APPROVAL_NOT_OPEN'; end if;
  select * into v_step from public.approval_request_steps where approval_request_id=v_request.id and step_no=1 for update;
  if not found or v_step.status<>'ACTIVE' or v_step.required_permission_code<>'ACCOUNTING_POST' then raise exception using errcode='42501',message='ACCOUNTING_REVERSAL_APPROVAL_STEP_INVALID'; end if;

  insert into public.approval_decisions(
    approval_request_id,approval_request_step_id,organization_id,organization_node_id,actor_profile_id,
    decision,conflict_declared,conflict_note,reason,evidence
  ) values(
    v_request.id,v_step.id,v_journal.organization_id,v_journal.organization_node_id,v_profile_id,
    'APPROVE',true,'No conflict declared for BOARD reversal authorization.',btrim(p_reason),
    jsonb_build_object('journal_entry_id',v_journal.id,'reversal_of_entry_id',v_journal.reversal_of_entry_id,'validated_by',v_journal.validated_by)
  );
  update public.approval_request_steps set status='APPROVED',completed_at=now() where id=v_step.id;
  update public.approval_requests set status='APPROVED',completed_at=now() where id=v_request.id;
  insert into app_private.accounting_journal_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id)
  values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'AUTHORIZE_REVERSAL',p_idempotency_key,v_request_hash,v_journal.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_REVERSAL_AUTHORIZED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('approval_status',v_request.status),jsonb_build_object('approval_status','APPROVED','approval_request_id',v_request.id),btrim(p_reason),p_idempotency_key);
  return jsonb_build_object('journal_entry_id',v_journal.id,'approval_request_id',v_request.id,'approval_status','APPROVED','idempotent_replay',false);
end;
$$;

create or replace function app_private.post_manual_journal_reversal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid:=auth.uid(); v_profile_id uuid; v_organization_id uuid;
  v_journal public.journal_entries%rowtype; v_period public.accounting_periods%rowtype; v_approval_request_id uuid;
  v_request_hash text; v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_POST') then raise exception using errcode='42501',message='ACCOUNTING_POST_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_REVERSAL_REASON_REQUIRED'; end if;
  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':POST_REVERSAL:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c where c.actor_profile_id=v_profile_id and c.command_type='POST_REVERSAL' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'status','POSTED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries where id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL_REVERSAL' or v_journal.status<>'VALIDATED' then raise exception using errcode='23514',message='ACCOUNTING_REVERSAL_NOT_VALIDATED'; end if;
  if v_profile_id in (v_journal.created_by,v_journal.validated_by) or v_journal.created_by=v_journal.validated_by then raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION'; end if;
  select * into v_period from public.accounting_periods where id=v_journal.accounting_period_id;
  if not found or v_period.status<>'OPEN' then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_OPEN'; end if;

  select ar.id into v_approval_request_id
  from public.approval_requests ar
  join public.approval_request_steps ars on ars.approval_request_id=ar.id and ars.step_no=1 and ars.status='APPROVED'
  join public.approval_decisions ad on ad.approval_request_id=ar.id and ad.approval_request_step_id=ars.id
  where ar.organization_id=v_journal.organization_id and ar.organization_node_id=v_journal.organization_node_id
    and ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_REVERSAL' and ar.source_entity_id=v_journal.id
    and ar.status='APPROVED' and ad.decision='APPROVE' and ad.actor_profile_id=v_profile_id
  order by ar.completed_at desc nulls last limit 1;
  if v_approval_request_id is null then raise exception using errcode='42501',message='ACCOUNTING_REVERSAL_BOARD_AUTHORIZATION_REQUIRED'; end if;

  update public.journal_entries set status='POSTED',posted_by=v_profile_id,posted_at=now() where id=v_journal.id;
  insert into app_private.accounting_journal_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id)
  values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'POST_REVERSAL',p_idempotency_key,v_request_hash,v_journal.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_REVERSAL_POSTED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('status','VALIDATED','validated_by',v_journal.validated_by),
    jsonb_build_object('status','POSTED','posted_by',v_profile_id,'reversal_of_entry_id',v_journal.reversal_of_entry_id,'approval_request_id',v_approval_request_id),
    btrim(p_reason),p_idempotency_key);
  return jsonb_build_object('journal_entry_id',v_journal.id,'status','POSTED','reversal_of_entry_id',v_journal.reversal_of_entry_id,'approval_request_id',v_approval_request_id,'idempotent_replay',false);
end;
$$;

create or replace function app_private.guard_manual_reversal_poster_authorization()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.source_domain<>'MANUAL_REVERSAL' or new.status<>'POSTED' or old.status is not distinct from new.status then return new; end if;
  if new.posted_by is null then raise exception using errcode='42501',message='ACCOUNTING_POSTER_REQUIRED'; end if;
  if not exists (
    select 1 from public.approval_requests ar
    join public.approval_request_steps ars on ars.approval_request_id=ar.id and ars.step_no=1 and ars.status='APPROVED'
    join public.approval_decisions ad on ad.approval_request_id=ar.id and ad.approval_request_step_id=ars.id
    where ar.organization_id=new.organization_id and ar.organization_node_id=new.organization_node_id
      and ar.source_domain='ACCOUNTING' and ar.source_entity_type='JOURNAL_REVERSAL' and ar.source_entity_id=new.id
      and ar.status='APPROVED' and ad.decision='APPROVE' and ad.actor_profile_id=new.posted_by
  ) then raise exception using errcode='42501',message='ACCOUNTING_REVERSAL_POSTER_NOT_AUTHORIZING_BOARD_ACTOR'; end if;
  return new;
end;
$$;
revoke all on function app_private.guard_manual_reversal_poster_authorization() from public,anon,authenticated;

drop trigger if exists trg_guard_manual_reversal_poster_authorization on public.journal_entries;
create trigger trg_guard_manual_reversal_poster_authorization
before update of status on public.journal_entries
for each row
when (new.source_domain='MANUAL_REVERSAL' and new.status='POSTED' and old.status is distinct from new.status)
execute function app_private.guard_manual_reversal_poster_authorization();

-- Period-close evidence is append-only and private. It is separate from journal commands.
create table if not exists app_private.accounting_period_commands(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  command_type text not null check (command_type in ('SOFT_CLOSE','HARD_CLOSE')),
  idempotency_key text not null,
  request_hash text not null,
  accounting_period_id uuid not null references public.accounting_periods(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(actor_profile_id,command_type,idempotency_key)
);
create index if not exists idx_accounting_period_commands_period on app_private.accounting_period_commands(accounting_period_id,created_at desc);
revoke all on table app_private.accounting_period_commands from public,anon,authenticated;
grant select on table app_private.accounting_period_commands to service_role;

create or replace function app_private.assert_accounting_period_close_ready(p_period_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(select 1 from public.journal_entries where accounting_period_id=p_period_id and status in ('DRAFT','VALIDATED')) then
    raise exception using errcode='23514',message='ACCOUNTING_PERIOD_HAS_UNPOSTED_JOURNALS';
  end if;
  if exists(
    select 1 from public.approval_requests ar
    join public.journal_entries je on je.id=ar.source_entity_id
    where je.accounting_period_id=p_period_id and ar.source_domain='ACCOUNTING'
      and ar.source_entity_type in ('JOURNAL_ENTRY','JOURNAL_REVERSAL') and ar.status in ('PENDING','IN_REVIEW')
  ) then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_HAS_OPEN_APPROVALS'; end if;
  if exists(select 1 from public.reconciliation_runs where period_id=p_period_id and status in ('PENDING','EXCEPTION')) then
    raise exception using errcode='23514',message='ACCOUNTING_PERIOD_HAS_UNRESOLVED_RECONCILIATION';
  end if;
  if exists(
    select 1 from public.journal_entries je
    left join public.journal_lines jl on jl.journal_entry_id=je.id
    where je.accounting_period_id=p_period_id and je.status='POSTED'
    group by je.id having coalesce(sum(jl.debit),0)<>coalesce(sum(jl.credit),0)
  ) then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_HAS_UNBALANCED_POSTED_JOURNAL'; end if;
end;
$$;
revoke all on function app_private.assert_accounting_period_close_ready(uuid) from public,anon,authenticated;

create or replace function app_private.soft_close_accounting_period(
  p_accounting_period_id uuid,
  p_idempotency_key text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid:=auth.uid(); v_profile_id uuid; v_organization_id uuid;
  v_period public.accounting_periods%rowtype; v_request_hash text; v_existing app_private.accounting_period_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_PERIOD_MANAGE') then raise exception using errcode='42501',message='ACCOUNTING_PERIOD_MANAGE_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_PERIOD_CLOSE_REASON_REQUIRED'; end if;
  v_request_hash:=md5(jsonb_build_object('period',p_accounting_period_id,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':SOFT_CLOSE:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_period_commands c where c.actor_profile_id=v_profile_id and c.command_type='SOFT_CLOSE' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('accounting_period_id',v_existing.accounting_period_id,'status','SOFT_CLOSED','idempotent_replay',true);
  end if;
  select * into v_period from public.accounting_periods where id=p_accounting_period_id for update;
  if not found or v_period.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_PERIOD_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_period.organization_id,v_period.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_period.status<>'OPEN' then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_OPEN'; end if;
  if v_period.end_date>=current_date then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_ENDED'; end if;
  perform app_private.assert_accounting_period_close_ready(v_period.id);
  update public.accounting_periods set status='SOFT_CLOSED',updated_at=now() where id=v_period.id;
  insert into app_private.accounting_period_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,accounting_period_id)
  values(v_period.organization_id,v_period.organization_node_id,v_profile_id,'SOFT_CLOSE',p_idempotency_key,v_request_hash,v_period.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_period.organization_id,v_profile_id,'ACCOUNTING_PERIOD_SOFT_CLOSED','ACCOUNTING_PERIOD',v_period.id,
    jsonb_build_object('status','OPEN'),jsonb_build_object('status','SOFT_CLOSED'),btrim(p_reason),p_idempotency_key);
  return jsonb_build_object('accounting_period_id',v_period.id,'status','SOFT_CLOSED','idempotent_replay',false);
end;
$$;

create or replace function app_private.hard_close_accounting_period(
  p_accounting_period_id uuid,
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
  v_auth_user_id uuid:=auth.uid(); v_profile_id uuid; v_organization_id uuid; v_soft_closer uuid;
  v_period public.accounting_periods%rowtype; v_request_hash text; v_existing app_private.accounting_period_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_POST') then raise exception using errcode='42501',message='ACCOUNTING_POST_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='ACCOUNTING_PERIOD_CLOSE_REASON_REQUIRED'; end if;
  if p_conflict_declared is not true then raise exception using errcode='42501',message='ACCOUNTING_CONFLICT_DECLARATION_REQUIRED'; end if;
  v_request_hash:=md5(jsonb_build_object('period',p_accounting_period_id,'reason',btrim(p_reason),'conflict_declared',true)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':HARD_CLOSE:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_period_commands c where c.actor_profile_id=v_profile_id and c.command_type='HARD_CLOSE' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('accounting_period_id',v_existing.accounting_period_id,'status','HARD_CLOSED','idempotent_replay',true);
  end if;
  select * into v_period from public.accounting_periods where id=p_accounting_period_id for update;
  if not found or v_period.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_PERIOD_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_period.organization_id,v_period.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_period.status<>'SOFT_CLOSED' then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_SOFT_CLOSED'; end if;
  if v_period.end_date>=current_date then raise exception using errcode='23514',message='ACCOUNTING_PERIOD_NOT_ENDED'; end if;
  perform app_private.assert_accounting_period_close_ready(v_period.id);
  select al.actor_profile_id into v_soft_closer from public.audit_logs al
  where al.entity_type='ACCOUNTING_PERIOD' and al.entity_id=v_period.id and al.action_code='ACCOUNTING_PERIOD_SOFT_CLOSED'
  order by al.created_at desc limit 1;
  if v_soft_closer is null then raise exception using errcode='42501',message='ACCOUNTING_PERIOD_SOFT_CLOSE_EVIDENCE_MISSING'; end if;
  if v_soft_closer=v_profile_id then raise exception using errcode='42501',message='ACCOUNTING_PERIOD_CLOSE_ACTOR_SEPARATION_REQUIRED'; end if;
  update public.accounting_periods set status='HARD_CLOSED',closed_by=v_profile_id,closed_at=now(),updated_at=now() where id=v_period.id;
  insert into app_private.accounting_period_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,accounting_period_id)
  values(v_period.organization_id,v_period.organization_node_id,v_profile_id,'HARD_CLOSE',p_idempotency_key,v_request_hash,v_period.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_period.organization_id,v_profile_id,'ACCOUNTING_PERIOD_HARD_CLOSED','ACCOUNTING_PERIOD',v_period.id,
    jsonb_build_object('status','SOFT_CLOSED','soft_closed_by',v_soft_closer),
    jsonb_build_object('status','HARD_CLOSED','closed_by',v_profile_id,'conflict_declared',true),btrim(p_reason),p_idempotency_key);
  return jsonb_build_object('accounting_period_id',v_period.id,'status','HARD_CLOSED','closed_by',v_profile_id,'idempotent_replay',false);
end;
$$;

-- Public RPC wrappers remain SECURITY INVOKER. Only bounded private helpers write.
create or replace function public.create_manual_journal_reversal_draft(uuid,uuid,date,text,text)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.create_manual_journal_reversal_draft($1,$2,$3,$4,$5)
$$;
create or replace function public.validate_manual_journal_reversal(uuid,text,text)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.validate_manual_journal_reversal($1,$2,$3)
$$;
create or replace function public.authorize_manual_journal_reversal(uuid,text,text,boolean)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.authorize_manual_journal_reversal($1,$2,$3,$4)
$$;
create or replace function public.post_manual_journal_reversal(uuid,text,text)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.post_manual_journal_reversal($1,$2,$3)
$$;
create or replace function public.soft_close_accounting_period(uuid,text,text)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.soft_close_accounting_period($1,$2,$3)
$$;
create or replace function public.hard_close_accounting_period(uuid,text,text,boolean)
returns jsonb language sql security invoker set search_path='' as $$
  select app_private.hard_close_accounting_period($1,$2,$3,$4)
$$;

revoke all on function public.create_manual_journal_reversal_draft(uuid,uuid,date,text,text) from public,anon;
revoke all on function public.validate_manual_journal_reversal(uuid,text,text) from public,anon;
revoke all on function public.authorize_manual_journal_reversal(uuid,text,text,boolean) from public,anon;
revoke all on function public.post_manual_journal_reversal(uuid,text,text) from public,anon;
revoke all on function public.soft_close_accounting_period(uuid,text,text) from public,anon;
revoke all on function public.hard_close_accounting_period(uuid,text,text,boolean) from public,anon;
grant execute on function public.create_manual_journal_reversal_draft(uuid,uuid,date,text,text) to authenticated,service_role;
grant execute on function public.validate_manual_journal_reversal(uuid,text,text) to authenticated,service_role;
grant execute on function public.authorize_manual_journal_reversal(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function public.post_manual_journal_reversal(uuid,text,text) to authenticated,service_role;
grant execute on function public.soft_close_accounting_period(uuid,text,text) to authenticated,service_role;
grant execute on function public.hard_close_accounting_period(uuid,text,text,boolean) to authenticated,service_role;
