-- ZC access-context RLS short-circuit hardening
--
-- get_my_access_context() has no caller-controlled arguments and resolves its
-- profile exclusively from auth.uid(). Running the internal role / permission /
-- scope reads as SECURITY INVOKER causes those reads to traverse the same RLS
-- graph again, adding avoidable database work on every authenticated request.
--
-- SECURITY DEFINER is safe here because:
-- * the function owner is postgres;
-- * all referenced objects are schema-qualified;
-- * search_path remains empty;
-- * there are no caller-controlled identifiers or SQL fragments;
-- * the only identity selector is auth.uid();
-- * anon/PUBLIC execute remains revoked;
-- * authenticated/service_role execute contract is preserved.
--
-- This migration changes execution context only. It does not change the
-- returned shape, role mappings, permission mappings, data scopes, or RLS
-- policies on any table.

do $$
begin
  if to_regprocedure('public.get_my_access_context()') is null then
    raise exception 'get_my_access_context_missing';
  end if;

  if (select pg_get_userbyid(proowner)
      from pg_proc
      where oid='public.get_my_access_context()'::regprocedure) <> 'postgres' then
    raise exception 'get_my_access_context_owner_must_be_postgres';
  end if;
end $$;

alter function public.get_my_access_context() security definer;
alter function public.get_my_access_context() set search_path = '';

revoke all on function public.get_my_access_context() from public;
revoke all on function public.get_my_access_context() from anon;
grant execute on function public.get_my_access_context() to authenticated;
grant execute on function public.get_my_access_context() to service_role;

comment on function public.get_my_access_context() is
  'Current-user access context. SECURITY DEFINER avoids recursive RLS overhead; identity remains bound to auth.uid(); search_path is empty.';

do $$
declare
  v_proc pg_proc%rowtype;
begin
  select * into v_proc
  from pg_proc
  where oid='public.get_my_access_context()'::regprocedure;

  if not v_proc.prosecdef then
    raise exception 'get_my_access_context_must_be_security_definer';
  end if;

  if not exists (
    select 1
    from unnest(coalesce(v_proc.proconfig, array[]::text[])) setting
    where setting like 'search_path=%'
      and replace(setting, 'search_path=', '') in ('', '""')
  ) then
    raise exception 'get_my_access_context_search_path_must_be_empty';
  end if;

  if has_function_privilege('anon', 'public.get_my_access_context()', 'EXECUTE') then
    raise exception 'anon_must_not_execute_get_my_access_context';
  end if;

  if exists (
    select 1
    from aclexplode(coalesce(v_proc.proacl, acldefault('f', v_proc.proowner))) acl
    where acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'public_must_not_execute_get_my_access_context';
  end if;

  if not has_function_privilege('authenticated', 'public.get_my_access_context()', 'EXECUTE') then
    raise exception 'authenticated_execute_get_my_access_context_missing';
  end if;

  if not has_function_privilege('service_role', 'public.get_my_access_context()', 'EXECUTE') then
    raise exception 'service_role_execute_get_my_access_context_missing';
  end if;
end $$;
