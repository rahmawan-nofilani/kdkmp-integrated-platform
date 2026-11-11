-- KopdesKu M1 / SECURITY HARDENING / STAGING FIRST
-- Business records belong to ONE cooperative; PLATFORM_SCOPE never grants business access.
-- Additive migration: do not rewrite already-applied historical migrations.
-- Review + replay ALL migrations + tenant-negative tests before promotion.

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
  v_profile_organization_id uuid;
  v_target_node_id uuid := p_organization_node_id;
  v_node_organization_id uuid;
begin
  -- Never resolve business-data scope for unbound/central platform users.
  if v_auth_user_id is null or p_organization_id is null then
    return false;
  end if;

  select p.id, p.organization_id
    into v_profile_id, v_profile_organization_id
  from public.profiles p
  where p.auth_user_id = v_auth_user_id
    and p.status = 'ACTIVE'
  limit 1;

  if v_profile_id is null
     or v_profile_organization_id is distinct from p_organization_id then
    return false;
  end if;

  -- Pending/suspended organizations cannot operate or view business records.
  if not exists (
    select 1 from public.organizations o
    where o.id = p_organization_id and o.status = 'ACTIVE'
  ) then
    return false;
  end if;

  -- A platform-scope account must use a SEPARATE cooperative identity to run
  -- business operations, even if granted an accidental business permission/scope.
  if exists (
    select 1
    from public.user_scope_assignments usa
    join public.data_scopes ds on ds.id = usa.data_scope_id
    where usa.profile_id = v_profile_id
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
      and ds.scope_type = 'PLATFORM_SCOPE'
  ) then
    return false;
  end if;

  -- Reject forged or inconsistent node/unit identifiers before ancestry checks.
  if p_organization_node_id is not null then
    select n.organization_id into v_node_organization_id
    from public.organization_nodes n
    where n.id = p_organization_node_id;
    if v_node_organization_id is distinct from p_organization_id then
      return false;
    end if;
  end if;

  if p_organization_unit_id is not null then
    select ou.organization_node_id into v_target_node_id
    from public.organization_units ou
    where ou.id = p_organization_unit_id
      and ou.organization_id = p_organization_id;
    if v_target_node_id is null then
      return false;
    end if;
    if p_organization_node_id is not null
       and p_organization_node_id <> v_target_node_id then
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
      and ds.organization_id = p_organization_id
      and (
        (
          ds.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
          and ds.organization_node_id is not null
          and (
            (ds.scope_type = 'COOPERATIVE_SCOPE' and v_target_node_id is null)
            or (v_target_node_id is not null and exists (
            with recursive ancestry as (
              select n.id, n.parent_id from public.organization_nodes n
              where n.id = v_target_node_id
                and n.organization_id = p_organization_id
              union
              select parent.id, parent.parent_id
              from public.organization_nodes parent
              join ancestry child on child.parent_id = parent.id
              where parent.organization_id = p_organization_id
            )
            select 1 from ancestry a where a.id = ds.organization_node_id
            ))
          )
        )
        or (
          ds.scope_type = 'UNIT_SCOPE'
          and ds.organization_unit_id = p_organization_unit_id
          and ds.organization_unit_id is not null
        )
        or (
          ds.scope_type = 'OWN_DATA_ONLY'
          and p_owner_auth_user_id = v_auth_user_id
        )
        or (
          ds.scope_type = 'ASSIGNED_RECORDS_ONLY'
          and p_assigned_profile_id = v_profile_id
        )
      )
  );
end;
$$;

-- Metadata helpers also must never treat PLATFORM_SCOPE as access to a
-- cooperative's organization metadata or operational units.
create or replace function app_private.can_access_organization(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_organization_id is not null
    and p_organization_id = app_private.current_organization_id()
    and not exists (
      select 1 from public.user_scope_assignments usa
      join public.data_scopes s on s.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and s.scope_type = 'PLATFORM_SCOPE'
        and usa.valid_from <= now()
        and (usa.valid_until is null or usa.valid_until > now())
    )
    and exists (
      select 1 from public.user_scope_assignments usa
      join public.data_scopes s on s.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and usa.valid_from <= now()
        and (usa.valid_until is null or usa.valid_until > now())
        and s.organization_id = p_organization_id
        and s.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE','UNIT_SCOPE')
    );
$$;

create or replace function app_private.can_access_unit(
  p_organization_id uuid,
  p_unit_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive unit_ancestry as (
    select n.id, n.parent_id
    from public.organization_units u
    join public.organization_nodes n
      on n.id = u.organization_node_id
     and n.organization_id = u.organization_id
    where u.id = p_unit_id
      and u.organization_id = p_organization_id
    union
    select parent.id, parent.parent_id
    from public.organization_nodes parent
    join unit_ancestry child on child.parent_id = parent.id
    where parent.organization_id = p_organization_id
  )
  select app_private.can_access_organization(p_organization_id)
    and exists (select 1 from unit_ancestry)
    and exists (
      select 1
      from public.user_scope_assignments usa
      join public.data_scopes s on s.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and usa.valid_from <= now()
        and (usa.valid_until is null or usa.valid_until > now())
        and s.organization_id = p_organization_id
        and (
          (s.scope_type = 'UNIT_SCOPE' and s.organization_unit_id = p_unit_id)
          or (s.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
              and s.organization_node_id in (select id from unit_ancestry))
        )
    );
$$;

-- Separate archive metadata read from platform-scope identity as well.
create or replace function app_private.can_access_archive_node(
  p_organization_id uuid,
  p_organization_node_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive target_lineage as (
    select n.id, n.parent_id
    from public.organization_nodes n
    where n.id = p_organization_node_id
      and n.organization_id = p_organization_id
    union
    select parent.id, parent.parent_id
    from public.organization_nodes parent
    join target_lineage child on child.parent_id = parent.id
    where parent.organization_id = p_organization_id
  )
  select app_private.can_access_organization(p_organization_id)
    and exists (select 1 from target_lineage)
    and exists (
      select 1 from public.user_scope_assignments usa
      join public.data_scopes s on s.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and usa.valid_from <= now()
        and (usa.valid_until is null or usa.valid_until > now())
        and s.organization_id = p_organization_id
        and s.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
        and s.organization_node_id in (select id from target_lineage)
    );
$$;

-- Delegation must also exclude PLATFORM_SCOPE, even within an otherwise
-- operationally-bound account. This function is trusted-server only.
create or replace function app_private.profile_scope_covers(
  p_actor_profile_id uuid,
  p_data_scope_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_requested public.data_scopes%rowtype;
  v_target_node_id uuid;
begin
  select * into v_requested
  from public.data_scopes ds
  where ds.id = p_data_scope_id;

  if v_requested.id is null or v_requested.organization_id is null
     or v_requested.scope_type in ('PLATFORM_SCOPE','OWN_DATA_ONLY','ASSIGNED_RECORDS_ONLY') then
    return false;
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = p_actor_profile_id
      and p.status = 'ACTIVE'
      and p.organization_id = v_requested.organization_id
  ) then
    return false;
  end if;

  if exists (
    select 1 from public.user_scope_assignments usa
    join public.data_scopes s on s.id = usa.data_scope_id
    where usa.profile_id = p_actor_profile_id
      and s.scope_type = 'PLATFORM_SCOPE'
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
  ) then
    return false;
  end if;

  v_target_node_id := v_requested.organization_node_id;
  if v_requested.organization_unit_id is not null then
    select ou.organization_node_id into v_target_node_id
    from public.organization_units ou
    where ou.id = v_requested.organization_unit_id
      and ou.organization_id = v_requested.organization_id;
    if v_target_node_id is null then
      return false;
    end if;
  end if;

  return exists (
    select 1
    from public.user_scope_assignments usa
    join public.data_scopes actor_scope on actor_scope.id = usa.data_scope_id
    where usa.profile_id = p_actor_profile_id
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
      and actor_scope.organization_id = v_requested.organization_id
      and (
        (
          actor_scope.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
          and actor_scope.organization_node_id is not null
          and v_target_node_id is not null
          and exists (
            with recursive ancestry as (
              select n.id, n.parent_id
              from public.organization_nodes n
              where n.id = v_target_node_id
                and n.organization_id = v_requested.organization_id
              union
              select parent.id, parent.parent_id
              from public.organization_nodes parent
              join ancestry child on child.parent_id = parent.id
              where parent.organization_id = v_requested.organization_id
            )
            select 1 from ancestry a where a.id = actor_scope.organization_node_id
          )
        )
        or (
          actor_scope.scope_type = 'UNIT_SCOPE'
          and v_requested.scope_type = 'UNIT_SCOPE'
          and actor_scope.organization_unit_id = v_requested.organization_unit_id
          and actor_scope.organization_unit_id is not null
        )
      )
  );
end;
$$;

-- Preserve the historical function ACLs: public API for authorized users,
-- app_private delegation RPC only for trusted server execution.
revoke all on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) from public, anon;
grant execute on function app_private.has_data_scope(uuid,uuid,uuid,uuid,uuid) to authenticated;
revoke all on function app_private.can_access_organization(uuid) from public, anon;
revoke all on function app_private.can_access_unit(uuid,uuid) from public, anon;
revoke all on function app_private.can_access_archive_node(uuid,uuid) from public, anon;
revoke all on function app_private.profile_scope_covers(uuid,uuid) from public, anon, authenticated;

comment on function public.has_data_scope(uuid,uuid,uuid,uuid,uuid) is
  'KopdesKu M1: BUSINESS scope is tenant-locked. PLATFORM_SCOPE never grants access, including to the platform actor holding business grants.';
