create or replace function app_private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (auth_user_id, full_name, status)
  values (
    new.id,
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    'PENDING'
  )
  on conflict (auth_user_id) do nothing;

  return new;
end;
$$;

revoke all on function app_private.handle_new_auth_user() from public;

drop trigger if exists on_auth_user_created_kdkmp on auth.users;
create trigger on_auth_user_created_kdkmp
after insert on auth.users
for each row execute function app_private.handle_new_auth_user();

create or replace function app_private.bootstrap_first_manager(
  p_auth_user_id uuid,
  p_full_name text default null
)
returns table (
  profile_id uuid,
  organization_id uuid,
  role_id uuid,
  data_scope_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_organization_id uuid;
  v_role_id uuid;
  v_scope_id uuid;
  v_existing_manager uuid;
begin
  if not exists (select 1 from auth.users u where u.id = p_auth_user_id) then
    raise exception 'AUTH_USER_NOT_FOUND';
  end if;

  select o.id
    into v_organization_id
  from public.organizations o
  where o.code = 'DEMO-KDKMP-001'
  limit 1;

  if v_organization_id is null then
    raise exception 'DEMO_ORGANIZATION_NOT_FOUND';
  end if;

  select r.id
    into v_role_id
  from public.roles r
  where r.code = 'MANAGER'
    and r.status = 'ACTIVE'
  limit 1;

  if v_role_id is null then
    raise exception 'MANAGER_ROLE_NOT_FOUND';
  end if;

  select ds.id
    into v_scope_id
  from public.data_scopes ds
  where ds.organization_id = v_organization_id
    and ds.scope_type = 'COOPERATIVE_SCOPE'
  order by ds.created_at asc
  limit 1;

  if v_scope_id is null then
    raise exception 'COOPERATIVE_SCOPE_NOT_FOUND';
  end if;

  select p.id
    into v_existing_manager
  from public.profiles p
  join public.user_roles ur on ur.profile_id = p.id
  where ur.role_id = v_role_id
    and p.status = 'ACTIVE'
    and ur.valid_from <= now()
    and (ur.valid_until is null or ur.valid_until > now())
  order by ur.created_at asc
  limit 1;

  insert into public.profiles (
    auth_user_id,
    full_name,
    organization_id,
    status
  )
  values (
    p_auth_user_id,
    nullif(btrim(coalesce(p_full_name, '')), ''),
    v_organization_id,
    'ACTIVE'
  )
  on conflict (auth_user_id) do update
  set full_name = coalesce(nullif(btrim(coalesce(excluded.full_name, '')), ''), public.profiles.full_name),
      organization_id = excluded.organization_id,
      status = 'ACTIVE',
      updated_at = now()
  returning id into v_profile_id;

  if v_existing_manager is not null and v_existing_manager <> v_profile_id then
    raise exception 'ACTIVE_MANAGER_ALREADY_EXISTS';
  end if;

  if not exists (
    select 1
    from public.user_roles ur
    where ur.profile_id = v_profile_id
      and ur.role_id = v_role_id
      and ur.valid_from <= now()
      and (ur.valid_until is null or ur.valid_until > now())
  ) then
    insert into public.user_roles (profile_id, role_id, valid_from)
    values (v_profile_id, v_role_id, now());
  end if;

  if not exists (
    select 1
    from public.user_scope_assignments usa
    where usa.profile_id = v_profile_id
      and usa.data_scope_id = v_scope_id
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
  ) then
    insert into public.user_scope_assignments (profile_id, data_scope_id, valid_from)
    values (v_profile_id, v_scope_id, now());
  end if;

  insert into public.audit_logs (
    actor_profile_id,
    organization_id,
    action_code,
    entity_type,
    entity_id,
    before_data,
    after_data,
    reason
  )
  values (
    null,
    v_organization_id,
    'BOOTSTRAP_FIRST_MANAGER',
    'PROFILE',
    v_profile_id,
    null,
    jsonb_build_object(
      'profile_status', 'ACTIVE',
      'role', 'MANAGER',
      'scope_type', 'COOPERATIVE_SCOPE',
      'environment', 'DEVELOPMENT'
    ),
    'Controlled DEVELOPMENT bootstrap of the first KDKMP Manager account.'
  );

  return query
  select v_profile_id, v_organization_id, v_role_id, v_scope_id;
end;
$$;

revoke all on function app_private.bootstrap_first_manager(uuid, text) from public, anon, authenticated;
grant execute on function app_private.bootstrap_first_manager(uuid, text) to postgres, service_role;
