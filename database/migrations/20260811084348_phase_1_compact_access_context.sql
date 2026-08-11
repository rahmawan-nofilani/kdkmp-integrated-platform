create or replace function public.get_my_access_context()
returns table (
  profile_id uuid,
  full_name text,
  profile_status text,
  organization_id uuid,
  roles jsonb,
  permission_codes text[],
  scopes jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  with current_profile as (
    select p.id, p.full_name, p.status, p.organization_id
    from public.profiles p
    where p.auth_user_id = (select auth.uid())
    limit 1
  ),
  active_roles as (
    select distinct r.id, r.code, r.name, r.is_privileged
    from public.user_roles ur
    join current_profile cp on cp.id = ur.profile_id
    join public.roles r on r.id = ur.role_id
    where r.status = 'ACTIVE'
      and ur.valid_from <= now()
      and (ur.valid_until is null or ur.valid_until > now())
  ),
  active_overrides as (
    select up.permission_id, up.effect
    from public.user_permissions up
    join current_profile cp on cp.id = up.profile_id
    where up.valid_from <= now()
      and (up.valid_until is null or up.valid_until > now())
  ),
  role_permissions_active as (
    select distinct rp.permission_id
    from public.role_permissions rp
    join active_roles ar on ar.id = rp.role_id
  ),
  effective_permissions as (
    select p.code
    from public.permissions p
    where not exists (
      select 1
      from active_overrides ao
      where ao.permission_id = p.id
        and ao.effect = 'DENY'
    )
    and (
      exists (
        select 1
        from active_overrides ao
        where ao.permission_id = p.id
          and ao.effect = 'ALLOW'
      )
      or exists (
        select 1
        from role_permissions_active rpa
        where rpa.permission_id = p.id
      )
    )
  ),
  active_scopes as (
    select distinct ds.id, ds.name, ds.scope_type,
      ds.organization_id, ds.organization_node_id, ds.organization_unit_id
    from public.user_scope_assignments usa
    join current_profile cp on cp.id = usa.profile_id
    join public.data_scopes ds on ds.id = usa.data_scope_id
    where usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
  )
  select
    cp.id,
    cp.full_name,
    cp.status,
    cp.organization_id,
    coalesce(
      (select jsonb_agg(jsonb_build_object(
        'id', ar.id,
        'code', ar.code,
        'name', ar.name,
        'is_privileged', ar.is_privileged
      ) order by ar.name) from active_roles ar),
      '[]'::jsonb
    ),
    coalesce(
      (select array_agg(ep.code order by ep.code) from effective_permissions ep),
      array[]::text[]
    ),
    coalesce(
      (select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'scope_type', s.scope_type,
        'organization_id', s.organization_id,
        'organization_node_id', s.organization_node_id,
        'organization_unit_id', s.organization_unit_id
      ) order by s.name) from active_scopes s),
      '[]'::jsonb
    )
  from current_profile cp;
$$;

revoke all on function public.get_my_access_context() from public;
revoke all on function public.get_my_access_context() from anon;
grant execute on function public.get_my_access_context() to authenticated;

comment on function public.get_my_access_context() is
'Compact authenticated access context for one request: active profile, active roles, effective permissions with DENY precedence, and active data scopes. SECURITY INVOKER; RLS remains enforced.';
