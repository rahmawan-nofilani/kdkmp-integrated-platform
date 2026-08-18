-- ZC accounting dashboard snapshot
-- Collapse seven read requests from /dashboard/accounting into one scoped RPC.

create or replace function app_private.get_accounting_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
begin
  if v_auth_user_id is null then
    raise exception using errcode='42501', message='AUTH_REQUIRED';
  end if;

  select p.id, p.organization_id into v_profile_id, v_organization_id
  from public.profiles p
  where p.auth_user_id=v_auth_user_id and p.status='ACTIVE'
  limit 1;

  if v_profile_id is null or v_organization_id is null then
    raise exception using errcode='42501', message='ACCOUNTING_CONTEXT_UNAVAILABLE';
  end if;

  if not app_private.has_permission('ACCOUNTING_VIEW') then
    raise exception using errcode='42501', message='ACCOUNTING_VIEW_DENIED';
  end if;

  return jsonb_build_object(
    'accounts', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select a.id,a.code,a.name,a.account_class,a.normal_balance,a.is_posting,a.is_control_account,a.control_purpose,a.status,a.notes
      from public.accounting_accounts a
      where a.organization_id=v_organization_id
        and public.has_data_scope(a.organization_id,a.organization_node_id,null,null,null)
      order by a.code
    ) x),'[]'::jsonb),
    'periods', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select p.id,p.period_code,p.period_name,p.start_date,p.end_date,p.status
      from public.accounting_periods p
      where p.organization_id=v_organization_id
        and public.has_data_scope(p.organization_id,p.organization_node_id,null,null,null)
      order by p.start_date desc limit 24
    ) x),'[]'::jsonb),
    'journals', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select j.id,j.journal_number,j.entry_date,j.description,j.source_domain,j.status,j.posted_at
      from public.journal_entries j
      where j.organization_id=v_organization_id
        and public.has_data_scope(j.organization_id,j.organization_node_id,null,null,null)
      order by j.entry_date desc limit 20
    ) x),'[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select e.id,e.event_code,e.domain,e.name,e.status
      from public.accounting_event_definitions e
      order by e.domain,e.event_code
    ) x),'[]'::jsonb),
    'mappings', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select m.id,m.event_definition_id,m.version_no,m.status,m.effective_from,m.effective_until
      from public.accounting_event_mappings m
      where m.organization_id=v_organization_id
        and public.has_data_scope(m.organization_id,m.organization_node_id,null,null,null)
      order by m.id
    ) x),'[]'::jsonb),
    'reconciliations', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select r.id,r.reconciliation_type,r.as_of_date,r.subledger_amount,r.gl_amount,r.difference_amount,r.status,r.generated_at
      from public.reconciliation_runs r
      where r.organization_id=v_organization_id
        and public.has_data_scope(r.organization_id,r.organization_node_id,null,null,null)
      order by r.generated_at desc limit 20
    ) x),'[]'::jsonb),
    'control_mappings', coalesce((select jsonb_agg(to_jsonb(x)) from (
      select c.id,c.subledger_code,c.control_account_id,c.status,c.effective_from
      from public.subledger_control_accounts c
      where c.organization_id=v_organization_id
        and public.has_data_scope(c.organization_id,c.organization_node_id,null,null,null)
      order by c.id
    ) x),'[]'::jsonb)
  );
end;
$$;

create or replace function public.get_accounting_dashboard_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select app_private.get_accounting_dashboard_snapshot(); $$;

revoke all on function app_private.get_accounting_dashboard_snapshot() from public;
revoke all on function app_private.get_accounting_dashboard_snapshot() from anon;
grant execute on function app_private.get_accounting_dashboard_snapshot() to authenticated, service_role;
revoke all on function public.get_accounting_dashboard_snapshot() from public;
revoke all on function public.get_accounting_dashboard_snapshot() from anon;
grant execute on function public.get_accounting_dashboard_snapshot() to authenticated, service_role;

comment on function app_private.get_accounting_dashboard_snapshot() is 'Private scoped Accounting dashboard snapshot bounded by auth.uid(), ACCOUNTING_VIEW and explicit data-scope checks.';
comment on function public.get_accounting_dashboard_snapshot() is 'Authenticated SECURITY INVOKER wrapper for scoped Accounting dashboard reads.';

do $$
declare v_private pg_proc%rowtype; v_public pg_proc%rowtype;
begin
  select * into v_private from pg_proc where oid='app_private.get_accounting_dashboard_snapshot()'::regprocedure;
  select * into v_public from pg_proc where oid='public.get_accounting_dashboard_snapshot()'::regprocedure;
  if not v_private.prosecdef then raise exception 'accounting_snapshot_private_must_be_security_definer'; end if;
  if v_public.prosecdef then raise exception 'accounting_snapshot_public_must_be_security_invoker'; end if;
  if not exists(select 1 from unnest(coalesce(v_private.proconfig,array[]::text[])) s where s in ('search_path=','search_path=""')) then raise exception 'accounting_snapshot_private_search_path_must_be_empty'; end if;
  if not exists(select 1 from unnest(coalesce(v_public.proconfig,array[]::text[])) s where s in ('search_path=','search_path=""')) then raise exception 'accounting_snapshot_public_search_path_must_be_empty'; end if;
  if has_function_privilege('anon','public.get_accounting_dashboard_snapshot()','EXECUTE') then raise exception 'anon_must_not_execute_accounting_dashboard_snapshot'; end if;
  if exists(select 1 from aclexplode(coalesce(v_public.proacl,acldefault('f',v_public.proowner))) acl where acl.grantee=0 and acl.privilege_type='EXECUTE') then raise exception 'public_must_not_execute_accounting_dashboard_snapshot'; end if;
  if not has_function_privilege('authenticated','public.get_accounting_dashboard_snapshot()','EXECUTE') then raise exception 'authenticated_accounting_snapshot_execute_missing'; end if;
end $$;
