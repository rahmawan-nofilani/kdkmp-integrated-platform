-- Accounting manual journal command engine.
--
-- DEVELOPMENT-safe foundation for maker -> checker -> poster workflow.
-- This migration DOES NOT map ACCOUNTING_POST to any baseline role and DOES NOT
-- activate the draft JOURNAL_POST approval policy. Posting therefore remains
-- fail-closed until a separate owner-approved SoD policy is codified.

create table if not exists app_private.accounting_journal_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  command_type text not null check (command_type in ('CREATE_DRAFT','VALIDATE','POST')),
  idempotency_key text not null,
  request_hash text not null,
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (actor_profile_id, command_type, idempotency_key)
);

create index if not exists idx_accounting_journal_commands_journal
  on app_private.accounting_journal_commands(journal_entry_id, created_at desc);

revoke all on table app_private.accounting_journal_commands from public, anon, authenticated;
grant select on table app_private.accounting_journal_commands to service_role;

create or replace function app_private.create_manual_journal_draft(
  p_accounting_period_id uuid,
  p_entry_date date,
  p_description text,
  p_lines jsonb,
  p_idempotency_key text,
  p_source_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
  v_period public.accounting_periods%rowtype;
  v_journal_id uuid := gen_random_uuid();
  v_journal_number text;
  v_line_count integer;
  v_debit numeric(20,2);
  v_credit numeric(20,2);
  v_invalid_lines integer;
  v_invalid_accounts integer;
  v_request_hash text;
  v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then
    raise exception using errcode='42501', message='AUTH_REQUIRED';
  end if;

  select p.id, p.organization_id
    into v_profile_id, v_organization_id
  from public.profiles p
  where p.auth_user_id=v_auth_user_id and p.status='ACTIVE'
  limit 1;

  if v_profile_id is null or v_organization_id is null then
    raise exception using errcode='42501', message='ACCOUNTING_CONTEXT_UNAVAILABLE';
  end if;
  if not app_private.has_permission('ACCOUNTING_DRAFT_CREATE') then
    raise exception using errcode='42501', message='ACCOUNTING_DRAFT_CREATE_DENIED';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then
    raise exception using errcode='22023', message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID';
  end if;
  if p_description is null or btrim(p_description)='' or length(p_description)>500 then
    raise exception using errcode='22023', message='ACCOUNTING_DESCRIPTION_INVALID';
  end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 or jsonb_array_length(p_lines)>200 then
    raise exception using errcode='22023', message='ACCOUNTING_LINES_INVALID';
  end if;

  v_request_hash := md5(jsonb_build_object(
    'period',p_accounting_period_id,
    'entry_date',p_entry_date,
    'description',btrim(p_description),
    'source_reference',nullif(btrim(coalesce(p_source_reference,'')),''),
    'lines',p_lines
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':CREATE_DRAFT:'||p_idempotency_key,0));

  select * into v_existing
  from app_private.accounting_journal_commands c
  where c.actor_profile_id=v_profile_id
    and c.command_type='CREATE_DRAFT'
    and c.idempotency_key=p_idempotency_key;

  if found then
    if v_existing.request_hash<>v_request_hash then
      raise exception using errcode='23505', message='ACCOUNTING_IDEMPOTENCY_CONFLICT';
    end if;
    return jsonb_build_object(
      'journal_entry_id',v_existing.journal_entry_id,
      'status',(select je.status from public.journal_entries je where je.id=v_existing.journal_entry_id),
      'idempotent_replay',true
    );
  end if;

  select * into v_period
  from public.accounting_periods ap
  where ap.id=p_accounting_period_id
  for share;

  if not found or v_period.organization_id<>v_organization_id then
    raise exception using errcode='42501', message='ACCOUNTING_PERIOD_NOT_ACCESSIBLE';
  end if;
  if not app_private.has_data_scope(v_period.organization_id,v_period.organization_node_id,null,null,null) then
    raise exception using errcode='42501', message='ACCOUNTING_SCOPE_DENIED';
  end if;
  if v_period.status<>'OPEN' then
    raise exception using errcode='23514', message='ACCOUNTING_PERIOD_NOT_OPEN';
  end if;
  if p_entry_date is null or p_entry_date<v_period.start_date or p_entry_date>v_period.end_date then
    raise exception using errcode='23514', message='ACCOUNTING_ENTRY_DATE_OUTSIDE_PERIOD';
  end if;

  select count(*),coalesce(sum(x.debit),0),coalesce(sum(x.credit),0),
         count(*) filter (where x.account_id is null
                          or coalesce(x.debit,0)<0 or coalesce(x.credit,0)<0
                          or not ((coalesce(x.debit,0)>0 and coalesce(x.credit,0)=0)
                               or (coalesce(x.credit,0)>0 and coalesce(x.debit,0)=0)))
    into v_line_count,v_debit,v_credit,v_invalid_lines
  from jsonb_to_recordset(p_lines) as x(
    account_id uuid,
    debit numeric(20,2),
    credit numeric(20,2),
    memo text,
    subledger_type text,
    subledger_id uuid,
    dimensions jsonb
  );

  if v_line_count<2 or v_invalid_lines>0 then
    raise exception using errcode='23514', message='ACCOUNTING_JOURNAL_LINES_INVALID';
  end if;
  if v_debit<=0 or v_debit<>v_credit then
    raise exception using errcode='23514', message='ACCOUNTING_JOURNAL_NOT_BALANCED';
  end if;

  select count(*) into v_invalid_accounts
  from jsonb_to_recordset(p_lines) as x(account_id uuid,debit numeric,credit numeric,memo text,subledger_type text,subledger_id uuid,dimensions jsonb)
  left join public.accounting_accounts aa on aa.id=x.account_id
  where aa.id is null
     or aa.organization_id<>v_period.organization_id
     or aa.organization_node_id<>v_period.organization_node_id
     or aa.status<>'ACTIVE'
     or aa.is_posting=false;

  if v_invalid_accounts>0 then
    raise exception using errcode='23514', message='ACCOUNTING_JOURNAL_ACCOUNT_INVALID';
  end if;

  v_journal_number := 'MJ-'||to_char(p_entry_date,'YYYYMMDD')||'-'||upper(substr(replace(v_journal_id::text,'-',''),1,8));

  insert into public.journal_entries(
    id,organization_id,organization_node_id,accounting_period_id,journal_number,
    entry_date,description,source_domain,source_reference,idempotency_key,status,created_by
  ) values (
    v_journal_id,v_period.organization_id,v_period.organization_node_id,v_period.id,v_journal_number,
    p_entry_date,btrim(p_description),'MANUAL',nullif(btrim(coalesce(p_source_reference,'')),''),
    p_idempotency_key,'DRAFT',v_profile_id
  );

  insert into public.journal_lines(
    journal_entry_id,organization_id,organization_node_id,line_no,account_id,debit,credit,
    memo,subledger_type,subledger_id,dimensions
  )
  select v_journal_id,v_period.organization_id,v_period.organization_node_id,e.ord::integer,
         (e.value->>'account_id')::uuid,
         coalesce((e.value->>'debit')::numeric,0),coalesce((e.value->>'credit')::numeric,0),
         nullif(btrim(coalesce(e.value->>'memo','')),''),
         nullif(btrim(coalesce(e.value->>'subledger_type','')),''),
         nullif(e.value->>'subledger_id','')::uuid,
         coalesce(e.value->'dimensions','{}'::jsonb)
  from jsonb_array_elements(p_lines) with ordinality as e(value,ord);

  insert into app_private.accounting_journal_commands(
    organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id
  ) values (
    v_period.organization_id,v_period.organization_node_id,v_profile_id,'CREATE_DRAFT',p_idempotency_key,v_request_hash,v_journal_id
  );

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id
  ) values (
    v_period.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_DRAFT_CREATED','JOURNAL_ENTRY',v_journal_id,
    jsonb_build_object('status','DRAFT','journal_number',v_journal_number,'debit',v_debit,'credit',v_credit,'line_count',v_line_count),
    'Manual journal draft created through controlled command',p_idempotency_key
  );

  return jsonb_build_object(
    'journal_entry_id',v_journal_id,
    'journal_number',v_journal_number,
    'status','DRAFT',
    'idempotent_replay',false
  );
end;
$$;

create or replace function app_private.validate_manual_journal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
  v_journal public.journal_entries%rowtype;
  v_request_hash text;
  v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id
  from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_VALIDATE') then raise exception using errcode='42501',message='ACCOUNTING_VALIDATE_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if length(coalesce(p_reason,''))>500 then raise exception using errcode='22023',message='ACCOUNTING_REASON_INVALID'; end if;

  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':VALIDATE:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c
  where c.actor_profile_id=v_profile_id and c.command_type='VALIDATE' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'status','VALIDATED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries je where je.id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL' then raise exception using errcode='23514',message='ACCOUNTING_MANUAL_JOURNAL_REQUIRED'; end if;
  if v_journal.status<>'DRAFT' then raise exception using errcode='23514',message='ACCOUNTING_JOURNAL_NOT_DRAFT'; end if;
  if v_journal.created_by is null or v_journal.created_by=v_profile_id then raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_VIOLATION'; end if;

  update public.journal_entries
  set status='VALIDATED',validated_by=v_profile_id,validated_at=now()
  where id=v_journal.id;

  insert into app_private.accounting_journal_commands(
    organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id
  ) values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'VALIDATE',p_idempotency_key,v_request_hash,v_journal.id);

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id
  ) values(
    v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_VALIDATED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('status','DRAFT','created_by',v_journal.created_by),
    jsonb_build_object('status','VALIDATED','validated_by',v_profile_id),
    nullif(btrim(coalesce(p_reason,'')),''),p_idempotency_key
  );

  return jsonb_build_object('journal_entry_id',v_journal.id,'status','VALIDATED','idempotent_replay',false);
end;
$$;

create or replace function app_private.post_manual_journal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
  v_journal public.journal_entries%rowtype;
  v_policy_version_id uuid;
  v_approval_request_id uuid;
  v_request_hash text;
  v_existing app_private.accounting_journal_commands%rowtype;
begin
  if v_auth_user_id is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id,p.organization_id into v_profile_id,v_organization_id
  from public.profiles p where p.auth_user_id=v_auth_user_id and p.status='ACTIVE' limit 1;
  if v_profile_id is null then raise exception using errcode='42501',message='ACCOUNTING_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission('ACCOUNTING_POST') then raise exception using errcode='42501',message='ACCOUNTING_POST_DENIED'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='ACCOUNTING_IDEMPOTENCY_KEY_INVALID'; end if;
  if length(coalesce(p_reason,''))>500 then raise exception using errcode='22023',message='ACCOUNTING_REASON_INVALID'; end if;

  v_request_hash:=md5(jsonb_build_object('journal',p_journal_entry_id,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile_id::text||':POST:'||p_idempotency_key,0));
  select * into v_existing from app_private.accounting_journal_commands c
  where c.actor_profile_id=v_profile_id and c.command_type='POST' and c.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_request_hash then raise exception using errcode='23505',message='ACCOUNTING_IDEMPOTENCY_CONFLICT'; end if;
    return jsonb_build_object('journal_entry_id',v_existing.journal_entry_id,'status','POSTED','idempotent_replay',true);
  end if;

  select * into v_journal from public.journal_entries je where je.id=p_journal_entry_id for update;
  if not found or v_journal.organization_id<>v_organization_id then raise exception using errcode='42501',message='ACCOUNTING_JOURNAL_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_journal.organization_id,v_journal.organization_node_id,null,null,null) then raise exception using errcode='42501',message='ACCOUNTING_SCOPE_DENIED'; end if;
  if v_journal.source_domain<>'MANUAL' then raise exception using errcode='23514',message='ACCOUNTING_MANUAL_JOURNAL_REQUIRED'; end if;
  if v_journal.status<>'VALIDATED' then raise exception using errcode='23514',message='ACCOUNTING_JOURNAL_NOT_VALIDATED'; end if;
  if v_journal.created_by is null or v_journal.validated_by is null
     or v_profile_id=v_journal.created_by or v_profile_id=v_journal.validated_by
     or v_journal.created_by=v_journal.validated_by then
    raise exception using errcode='42501',message='ACCOUNTING_MAKER_CHECKER_POSTER_VIOLATION';
  end if;

  select apv.id into v_policy_version_id
  from public.approval_policies ap
  join public.approval_policy_versions apv on apv.approval_policy_id=ap.id
  where ap.organization_id=v_journal.organization_id
    and ap.organization_node_id=v_journal.organization_node_id
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

  select ar.id into v_approval_request_id
  from public.approval_requests ar
  where ar.approval_policy_version_id=v_policy_version_id
    and ar.organization_id=v_journal.organization_id
    and ar.organization_node_id=v_journal.organization_node_id
    and ar.source_domain='ACCOUNTING'
    and ar.source_entity_type='JOURNAL_ENTRY'
    and ar.source_entity_id=v_journal.id
    and ar.status='APPROVED'
  order by ar.completed_at desc nulls last, ar.requested_at desc
  limit 1;

  if v_approval_request_id is null then
    raise exception using errcode='42501',message='ACCOUNTING_POST_APPROVAL_REQUIRED';
  end if;

  update public.journal_entries
  set status='POSTED',posted_by=v_profile_id,posted_at=now()
  where id=v_journal.id;

  insert into app_private.accounting_journal_commands(
    organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,journal_entry_id
  ) values(v_journal.organization_id,v_journal.organization_node_id,v_profile_id,'POST',p_idempotency_key,v_request_hash,v_journal.id);

  insert into public.audit_logs(
    organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id
  ) values(
    v_journal.organization_id,v_profile_id,'ACCOUNTING_MANUAL_JOURNAL_POSTED','JOURNAL_ENTRY',v_journal.id,
    jsonb_build_object('status','VALIDATED','validated_by',v_journal.validated_by),
    jsonb_build_object('status','POSTED','posted_by',v_profile_id,'approval_request_id',v_approval_request_id),
    nullif(btrim(coalesce(p_reason,'')),''),p_idempotency_key
  );

  return jsonb_build_object('journal_entry_id',v_journal.id,'status','POSTED','approval_request_id',v_approval_request_id,'idempotent_replay',false);
end;
$$;

create or replace function public.create_manual_journal_draft(
  p_accounting_period_id uuid,
  p_entry_date date,
  p_description text,
  p_lines jsonb,
  p_idempotency_key text,
  p_source_reference text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.create_manual_journal_draft(p_accounting_period_id,p_entry_date,p_description,p_lines,p_idempotency_key,p_source_reference);
$$;

create or replace function public.validate_manual_journal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.validate_manual_journal(p_journal_entry_id,p_idempotency_key,p_reason);
$$;

create or replace function public.post_manual_journal(
  p_journal_entry_id uuid,
  p_idempotency_key text,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.post_manual_journal(p_journal_entry_id,p_idempotency_key,p_reason);
$$;

revoke all on function app_private.create_manual_journal_draft(uuid,date,text,jsonb,text,text) from public,anon;
revoke all on function app_private.validate_manual_journal(uuid,text,text) from public,anon;
revoke all on function app_private.post_manual_journal(uuid,text,text) from public,anon;
grant execute on function app_private.create_manual_journal_draft(uuid,date,text,jsonb,text,text) to authenticated,service_role;
grant execute on function app_private.validate_manual_journal(uuid,text,text) to authenticated,service_role;
grant execute on function app_private.post_manual_journal(uuid,text,text) to authenticated,service_role;

revoke all on function public.create_manual_journal_draft(uuid,date,text,jsonb,text,text) from public,anon;
revoke all on function public.validate_manual_journal(uuid,text,text) from public,anon;
revoke all on function public.post_manual_journal(uuid,text,text) from public,anon;
grant execute on function public.create_manual_journal_draft(uuid,date,text,jsonb,text,text) to authenticated,service_role;
grant execute on function public.validate_manual_journal(uuid,text,text) to authenticated,service_role;
grant execute on function public.post_manual_journal(uuid,text,text) to authenticated,service_role;

comment on function public.create_manual_journal_draft(uuid,date,text,jsonb,text,text) is
  'Controlled manual journal draft command. Requires ACCOUNTING_DRAFT_CREATE and scope; validates balanced active posting accounts server-side.';
comment on function public.validate_manual_journal(uuid,text,text) is
  'Controlled manual journal validation command. Requires ACCOUNTING_VALIDATE and enforces creator != validator.';
comment on function public.post_manual_journal(uuid,text,text) is
  'Controlled manual journal posting command. Requires ACCOUNTING_POST, distinct maker/checker/poster, ACTIVE JOURNAL_POST policy and APPROVED request.';

do $$
declare
  v_post_permission uuid;
begin
  select id into v_post_permission from public.permissions where code='ACCOUNTING_POST';
  if v_post_permission is null then raise exception 'ACCOUNTING_POST_PERMISSION_MISSING'; end if;

  if exists(select 1 from public.role_permissions rp where rp.permission_id=v_post_permission) then
    raise exception 'ACCOUNTING_POST_BASELINE_ROLE_MAPPING_MUST_REMAIN_EMPTY';
  end if;

  if has_function_privilege('anon','public.create_manual_journal_draft(uuid,date,text,jsonb,text,text)','EXECUTE')
     or has_function_privilege('anon','public.validate_manual_journal(uuid,text,text)','EXECUTE')
     or has_function_privilege('anon','public.post_manual_journal(uuid,text,text)','EXECUTE') then
    raise exception 'ANON_MUST_NOT_EXECUTE_ACCOUNTING_COMMANDS';
  end if;

  if not has_function_privilege('authenticated','public.create_manual_journal_draft(uuid,date,text,jsonb,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.validate_manual_journal(uuid,text,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.post_manual_journal(uuid,text,text)','EXECUTE') then
    raise exception 'AUTHENTICATED_ACCOUNTING_COMMAND_GRANT_MISSING';
  end if;
end $$;
