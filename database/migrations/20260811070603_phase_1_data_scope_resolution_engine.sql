create schema if not exists app_private;
revoke all on schema app_private from public;
revoke all on schema app_private from anon;
revoke all on schema app_private from authenticated;

grant select on table public.user_scope_assignments to authenticated;
grant select on table public.data_scopes to authenticated;

create policy "user_scope_assignments_select_own"
on public.user_scope_assignments
for select
to authenticated
using (
  profile_id in (
    select p.id
    from public.profiles p
    where p.auth_user_id = (select auth.uid())
  )
);

create policy "data_scopes_select_assigned"
on public.data_scopes
for select
to authenticated
using (
  id in (
    select usa.data_scope_id
    from public.user_scope_assignments usa
    join public.profiles p on p.id = usa.profile_id
    where p.auth_user_id = (select auth.uid())
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
  )
);

create or replace function app_private.has_data_scope(
  p_organization_id uuid default null,
  p_organization_node_id uuid default null,
  p_organization_unit_id uuid default null,
  p_owner_auth_user_id uuid default null,
  p_assigned_profile_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_target_node_id uuid := p_organization_node_id;
begin
  if v_auth_user_id is null then
    return false;
  end if;

  select p.id into v_profile_id
  from public.profiles p
  where p.auth_user_id = v_auth_user_id
    and p.status = 'ACTIVE'
  limit 1;

  if v_profile_id is null then
    return false;
  end if;

  if p_organization_unit_id is not null then
    select ou.organization_node_id into v_target_node_id
    from public.organization_units ou
    where ou.id = p_organization_unit_id
      and (p_organization_id is null or ou.organization_id = p_organization_id)
    limit 1;

    if v_target_node_id is null then
      return false;
    end if;
  end if;

  return exists (
    select 1
    from public.user_scope_assignments usa
    join public.data_scopes ds on ds.id = usa.data_scope_id
    where usa.profile_id = v_profile_id
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
      and (
        ds.scope_type = 'PLATFORM_SCOPE'
        or (
          ds.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
          and ds.organization_id is not distinct from p_organization_id
          and ds.organization_node_id is not null
          and v_target_node_id is not null
          and exists (
            with recursive ancestry as (
              select n.id, n.parent_id
              from public.organization_nodes n
              where n.id = v_target_node_id
              union all
              select parent.id, parent.parent_id
              from public.organization_nodes parent
              join ancestry child on child.parent_id = parent.id
            )
            select 1 from ancestry a where a.id = ds.organization_node_id
          )
        )
        or (
          ds.scope_type = 'UNIT_SCOPE'
          and ds.organization_id is not distinct from p_organization_id
          and ds.organization_unit_id is not null
          and ds.organization_unit_id = p_organization_unit_id
        )
        or (
          ds.scope_type = 'OWN_DATA_ONLY'
          and p_owner_auth_user_id is not null
          and p_owner_auth_user_id = v_auth_user_id
        )
        or (
          ds.scope_type = 'ASSIGNED_RECORDS_ONLY'
          and p_assigned_profile_id is not null
          and p_assigned_profile_id = v_profile_id
        )
      )
  );
end;
$$;

revoke all on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) from anon;
revoke all on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) from authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) to authenticated;

create or replace function public.has_data_scope(
  p_organization_id uuid default null,
  p_organization_node_id uuid default null,
  p_organization_unit_id uuid default null,
  p_owner_auth_user_id uuid default null,
  p_assigned_profile_id uuid default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.has_data_scope(
    p_organization_id,
    p_organization_node_id,
    p_organization_unit_id,
    p_owner_auth_user_id,
    p_assigned_profile_id
  );
$$;

revoke all on function public.has_data_scope(uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function public.has_data_scope(uuid,uuid,uuid,uuid,uuid) from anon;
grant execute on function public.has_data_scope(uuid,uuid,uuid,uuid,uuid) to authenticated;

comment on function public.has_data_scope(uuid,uuid,uuid,uuid,uuid) is
'Data-scope resolution for the current authenticated ACTIVE profile. Supports platform, hierarchical region/cooperative, unit, own-data and assigned-record scopes.';
