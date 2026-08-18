-- Controlled Access Administration for DEVELOPMENT / Release-1.
-- General Manager commands are limited to operational roles. MANAGER and BOARD are
-- protected from the general path. First BOARD UAT bootstrap is a distinct one-time path.

create table if not exists app_private.access_admin_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  command_type text not null check (command_type in (
    'PROVISION_USER','UPDATE_USER','SUSPEND_USER','ARCHIVE_USER','ASSIGN_ROLE','ASSIGN_SCOPE','BOOTSTRAP_FIRST_BOARD_UAT'
  )),
  target_auth_user_id uuid references auth.users(id) on delete restrict,
  target_profile_id uuid references public.profiles(id) on delete restrict,
  idempotency_key text not null,
  request_payload jsonb not null default '{}'::jsonb,
  result_payload jsonb,
  status text not null default 'STARTED' check (status in ('STARTED','COMPLETED')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (organization_id, idempotency_key)
);

create index if not exists access_admin_commands_actor_created_idx
  on app_private.access_admin_commands(actor_profile_id, created_at desc);
create index if not exists access_admin_commands_target_profile_idx
  on app_private.access_admin_commands(target_profile_id, created_at desc);

revoke all on app_private.access_admin_commands from public, anon, authenticated;

create or replace function app_private.profile_has_permission(
  p_profile_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with current_profile as (
    select p.id
    from public.profiles p
    where p.id = p_profile_id
      and p.status = 'ACTIVE'
    limit 1
  ),
  target_permission as (
    select p.id
    from public.permissions p
    where p.code = p_permission_code
    limit 1
  ),
  explicit_deny as (
    select 1
    from public.user_permissions up
    join current_profile cp on cp.id = up.profile_id
    join target_permission tp on tp.id = up.permission_id
    where up.effect = 'DENY'
      and up.valid_from <= now()
      and (up.valid_until is null or up.valid_until > now())
    limit 1
  ),
  explicit_allow as (
    select 1
    from public.user_permissions up
    join current_profile cp on cp.id = up.profile_id
    join target_permission tp on tp.id = up.permission_id
    where up.effect = 'ALLOW'
      and up.valid_from <= now()
      and (up.valid_until is null or up.valid_until > now())
    limit 1
  ),
  role_allow as (
    select 1
    from public.user_roles ur
    join current_profile cp on cp.id = ur.profile_id
    join public.roles r on r.id = ur.role_id and r.status = 'ACTIVE'
    join public.role_permissions rp on rp.role_id = ur.role_id
    join target_permission tp on tp.id = rp.permission_id
    where ur.valid_from <= now()
      and (ur.valid_until is null or ur.valid_until > now())
    limit 1
  )
  select case
    when not exists (select 1 from current_profile) then false
    when not exists (select 1 from target_permission) then false
    when exists (select 1 from explicit_deny) then false
    when exists (select 1 from explicit_allow) then true
    when exists (select 1 from role_allow) then true
    else false
  end;
$$;

revoke all on function app_private.profile_has_permission(uuid, text) from public, anon, authenticated;

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

  if v_requested.id is null then
    return false;
  end if;

  -- These scopes are contextual per-record and cannot be delegated as an administrative scope.
  if v_requested.scope_type in ('OWN_DATA_ONLY','ASSIGNED_RECORDS_ONLY') then
    return false;
  end if;

  v_target_node_id := v_requested.organization_node_id;
  if v_requested.organization_unit_id is not null then
    select ou.organization_node_id into v_target_node_id
    from public.organization_units ou
    where ou.id = v_requested.organization_unit_id
      and ou.organization_id is not distinct from v_requested.organization_id
    limit 1;
  end if;

  return exists (
    select 1
    from public.user_scope_assignments usa
    join public.data_scopes actor_scope on actor_scope.id = usa.data_scope_id
    where usa.profile_id = p_actor_profile_id
      and usa.valid_from <= now()
      and (usa.valid_until is null or usa.valid_until > now())
      and (
        actor_scope.scope_type = 'PLATFORM_SCOPE'
        or (
          actor_scope.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
          and actor_scope.organization_id is not distinct from v_requested.organization_id
          and actor_scope.organization_node_id is not null
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
            select 1 from ancestry a where a.id = actor_scope.organization_node_id
          )
        )
        or (
          actor_scope.scope_type = 'UNIT_SCOPE'
          and v_requested.scope_type = 'UNIT_SCOPE'
          and actor_scope.organization_id is not distinct from v_requested.organization_id
          and actor_scope.organization_unit_id is not null
          and actor_scope.organization_unit_id = v_requested.organization_unit_id
        )
      )
  );
end;
$$;

revoke all on function app_private.profile_scope_covers(uuid, uuid) from public, anon, authenticated;

create or replace function app_private.profile_has_protected_role_history(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.profile_id = p_profile_id
      and r.code in ('MANAGER','BOARD')
  );
$$;

revoke all on function app_private.profile_has_protected_role_history(uuid) from public, anon, authenticated;

create or replace function public.execute_access_admin_command(
  p_actor_profile_id uuid,
  p_command_type text,
  p_target_auth_user_id uuid default null,
  p_target_profile_id uuid default null,
  p_full_name text default null,
  p_phone text default null,
  p_role_code text default null,
  p_data_scope_id uuid default null,
  p_reason text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_scope public.data_scopes%rowtype;
  v_role public.roles%rowtype;
  v_command_id uuid;
  v_existing app_private.access_admin_commands%rowtype;
  v_payload jsonb;
  v_result jsonb;
  v_before jsonb;
  v_after jsonb;
  v_now timestamptz := now();
  v_command text := upper(btrim(coalesce(p_command_type,'')));
  v_reason text := nullif(btrim(coalesce(p_reason,'')), '');
  v_key text := nullif(btrim(coalesce(p_idempotency_key,'')), '');
begin
  if v_command not in ('PROVISION_USER','UPDATE_USER','SUSPEND_USER','ARCHIVE_USER','ASSIGN_ROLE','ASSIGN_SCOPE') then
    raise exception 'ACCESS_ADMIN_COMMAND_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 500 then
    raise exception 'ACCESS_ADMIN_REASON_REQUIRED';
  end if;
  if v_key is null or length(v_key) > 160 then
    raise exception 'ACCESS_ADMIN_IDEMPOTENCY_REQUIRED';
  end if;

  select * into v_actor
  from public.profiles p
  where p.id = p_actor_profile_id
    and p.status = 'ACTIVE';
  if v_actor.id is null or v_actor.organization_id is null then
    raise exception 'ACCESS_ADMIN_ACTOR_INVALID';
  end if;
  if not exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.profile_id = v_actor.id
      and r.code = 'MANAGER'
      and r.status = 'ACTIVE'
      and ur.valid_from <= v_now
      and (ur.valid_until is null or ur.valid_until > v_now)
  ) then
    raise exception 'ACCESS_ADMIN_MANAGER_REQUIRED';
  end if;

  if v_command = 'PROVISION_USER' then
    if not app_private.profile_has_permission(v_actor.id,'USER_CREATE')
       or not app_private.profile_has_permission(v_actor.id,'ROLE_ASSIGN')
       or not app_private.profile_has_permission(v_actor.id,'SCOPE_ASSIGN') then
      raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
    end if;
  elsif v_command = 'UPDATE_USER' and not app_private.profile_has_permission(v_actor.id,'USER_UPDATE') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  elsif v_command = 'SUSPEND_USER' and not app_private.profile_has_permission(v_actor.id,'USER_SUSPEND') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  elsif v_command = 'ARCHIVE_USER' and not app_private.profile_has_permission(v_actor.id,'USER_ARCHIVE') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  elsif v_command = 'ASSIGN_ROLE' and not app_private.profile_has_permission(v_actor.id,'ROLE_ASSIGN') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  elsif v_command = 'ASSIGN_SCOPE' and not app_private.profile_has_permission(v_actor.id,'SCOPE_ASSIGN') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  end if;

  if v_command = 'PROVISION_USER' then
    if p_target_auth_user_id is null
       or not exists(select 1 from auth.users u where u.id = p_target_auth_user_id) then
      raise exception 'ACCESS_ADMIN_AUTH_USER_NOT_FOUND';
    end if;
    select * into v_target
    from public.profiles p
    where p.auth_user_id = p_target_auth_user_id;
    if v_target.id is null then raise exception 'ACCESS_ADMIN_PROFILE_TRIGGER_MISSING'; end if;
  else
    if p_target_profile_id is null then raise exception 'ACCESS_ADMIN_TARGET_REQUIRED'; end if;
    select * into v_target
    from public.profiles p
    where p.id = p_target_profile_id;
    if v_target.id is null then raise exception 'ACCESS_ADMIN_TARGET_NOT_FOUND'; end if;
  end if;

  if v_target.id = v_actor.id then raise exception 'ACCESS_ADMIN_SELF_ADMIN_DENIED'; end if;
  if v_target.organization_id is not null
     and v_target.organization_id <> v_actor.organization_id then
    raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED';
  end if;
  if app_private.profile_has_protected_role_history(v_target.id) then
    raise exception 'ACCESS_ADMIN_PROTECTED_ROLE_DENIED';
  end if;

  if v_command in ('PROVISION_USER','ASSIGN_ROLE') then
    if upper(btrim(coalesce(p_role_code,''))) not in ('CASHIER','TELLER','FINANCE_OFFICER','SUPERVISOR') then
      raise exception 'ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE';
    end if;
    select * into v_role
    from public.roles r
    where r.code = upper(btrim(p_role_code))
      and r.status = 'ACTIVE';
    if v_role.id is null then raise exception 'ACCESS_ADMIN_ROLE_NOT_FOUND'; end if;
  end if;

  if v_command in ('PROVISION_USER','ASSIGN_SCOPE') then
    if p_data_scope_id is null then raise exception 'ACCESS_ADMIN_SCOPE_REQUIRED'; end if;
    select * into v_scope
    from public.data_scopes ds
    where ds.id = p_data_scope_id;
    if v_scope.id is null then raise exception 'ACCESS_ADMIN_SCOPE_NOT_FOUND'; end if;
    if v_scope.organization_id is distinct from v_actor.organization_id then
      raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED';
    end if;
    if not app_private.profile_scope_covers(v_actor.id,v_scope.id) then
      raise exception 'ACCESS_ADMIN_SCOPE_ESCALATION_DENIED';
    end if;
  end if;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'command_type',v_command,
    'target_auth_user_id',p_target_auth_user_id,
    'target_profile_id',v_target.id,
    'full_name',nullif(btrim(coalesce(p_full_name,'')),''),
    'phone',case when p_phone is null then null else nullif(btrim(p_phone),'') end,
    'role_code',case when p_role_code is null then null else upper(btrim(p_role_code)) end,
    'data_scope_id',p_data_scope_id,
    'reason',v_reason
  ));

  select * into v_existing
  from app_private.access_admin_commands c
  where c.organization_id = v_actor.organization_id
    and c.idempotency_key = v_key;
  if v_existing.id is not null then
    if v_existing.command_type <> v_command or v_existing.request_payload <> v_payload then
      raise exception 'ACCESS_ADMIN_IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.status <> 'COMPLETED' or v_existing.result_payload is null then
      raise exception 'ACCESS_ADMIN_COMMAND_IN_PROGRESS';
    end if;
    return v_existing.result_payload || jsonb_build_object('command_id',v_existing.id,'idempotent_replay',true);
  end if;

  insert into app_private.access_admin_commands(
    organization_id,actor_profile_id,command_type,target_auth_user_id,target_profile_id,idempotency_key,request_payload
  ) values (
    v_actor.organization_id,v_actor.id,v_command,p_target_auth_user_id,v_target.id,v_key,v_payload
  ) on conflict (organization_id,idempotency_key) do nothing
  returning id into v_command_id;

  if v_command_id is null then
    select * into v_existing
    from app_private.access_admin_commands c
    where c.organization_id = v_actor.organization_id
      and c.idempotency_key = v_key;
    if v_existing.command_type <> v_command or v_existing.request_payload <> v_payload then
      raise exception 'ACCESS_ADMIN_IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.status <> 'COMPLETED' or v_existing.result_payload is null then
      raise exception 'ACCESS_ADMIN_COMMAND_IN_PROGRESS';
    end if;
    return v_existing.result_payload || jsonb_build_object('command_id',v_existing.id,'idempotent_replay',true);
  end if;

  v_before := jsonb_build_object(
    'status',v_target.status,
    'full_name',v_target.full_name,
    'phone',v_target.phone
  );

  if v_command = 'PROVISION_USER' then
    if v_target.status not in ('PENDING','INACTIVE') then
      raise exception 'ACCESS_ADMIN_TARGET_NOT_PROVISIONABLE';
    end if;
    if nullif(btrim(coalesce(p_full_name,'')),'') is null then
      raise exception 'ACCESS_ADMIN_FULL_NAME_REQUIRED';
    end if;

    update public.user_roles ur
    set valid_until = v_now
    where ur.profile_id = v_target.id
      and ur.valid_from <= v_now
      and (ur.valid_until is null or ur.valid_until > v_now);
    update public.user_scope_assignments usa
    set valid_until = v_now
    where usa.profile_id = v_target.id
      and usa.valid_from <= v_now
      and (usa.valid_until is null or usa.valid_until > v_now);

    update public.profiles
    set organization_id = v_actor.organization_id,
        full_name = btrim(p_full_name),
        phone = case when p_phone is null then phone else nullif(btrim(p_phone),'') end,
        status = 'ACTIVE',
        updated_at = v_now
    where id = v_target.id;

    insert into public.user_roles(profile_id,role_id,valid_from,assigned_by)
    values(v_target.id,v_role.id,v_now,v_actor.id);
    insert into public.user_scope_assignments(profile_id,data_scope_id,valid_from,assigned_by)
    values(v_target.id,v_scope.id,v_now,v_actor.id);

    v_result := jsonb_build_object(
      'profile_id',v_target.id,'status','ACTIVE','role_code',v_role.code,'data_scope_id',v_scope.id
    );

  elsif v_command = 'UPDATE_USER' then
    if v_target.status = 'ARCHIVED' then raise exception 'ACCESS_ADMIN_ARCHIVED_IMMUTABLE'; end if;
    if nullif(btrim(coalesce(p_full_name,'')),'') is null then raise exception 'ACCESS_ADMIN_FULL_NAME_REQUIRED'; end if;
    update public.profiles
    set full_name = btrim(p_full_name),
        phone = case when p_phone is null then phone else nullif(btrim(p_phone),'') end,
        updated_at = v_now
    where id = v_target.id;
    v_result := jsonb_build_object('profile_id',v_target.id,'status',v_target.status);

  elsif v_command = 'SUSPEND_USER' then
    if v_target.status <> 'ACTIVE' then raise exception 'ACCESS_ADMIN_TARGET_NOT_ACTIVE'; end if;
    update public.profiles set status='SUSPENDED',updated_at=v_now where id=v_target.id;
    update public.user_roles ur set valid_until=v_now
    where ur.profile_id=v_target.id and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now);
    update public.user_scope_assignments usa set valid_until=v_now
    where usa.profile_id=v_target.id and usa.valid_from<=v_now and (usa.valid_until is null or usa.valid_until>v_now);
    v_result := jsonb_build_object('profile_id',v_target.id,'status','SUSPENDED');

  elsif v_command = 'ARCHIVE_USER' then
    if v_target.status = 'ACTIVE' then raise exception 'ACCESS_ADMIN_SUSPEND_BEFORE_ARCHIVE_REQUIRED'; end if;
    if v_target.status = 'ARCHIVED' then raise exception 'ACCESS_ADMIN_ARCHIVED_IMMUTABLE'; end if;
    update public.profiles set status='ARCHIVED',updated_at=v_now where id=v_target.id;
    update public.user_roles ur set valid_until=v_now
    where ur.profile_id=v_target.id and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now);
    update public.user_scope_assignments usa set valid_until=v_now
    where usa.profile_id=v_target.id and usa.valid_from<=v_now and (usa.valid_until is null or usa.valid_until>v_now);
    v_result := jsonb_build_object('profile_id',v_target.id,'status','ARCHIVED');

  elsif v_command = 'ASSIGN_ROLE' then
    if v_target.status <> 'ACTIVE' then raise exception 'ACCESS_ADMIN_TARGET_NOT_ACTIVE'; end if;
    update public.user_roles ur set valid_until=v_now
    where ur.profile_id=v_target.id and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now);
    insert into public.user_roles(profile_id,role_id,valid_from,assigned_by)
    values(v_target.id,v_role.id,v_now,v_actor.id);
    v_result := jsonb_build_object('profile_id',v_target.id,'status','ACTIVE','role_code',v_role.code);

  elsif v_command = 'ASSIGN_SCOPE' then
    if v_target.status <> 'ACTIVE' then raise exception 'ACCESS_ADMIN_TARGET_NOT_ACTIVE'; end if;
    update public.user_scope_assignments usa set valid_until=v_now
    where usa.profile_id=v_target.id and usa.valid_from<=v_now and (usa.valid_until is null or usa.valid_until>v_now);
    insert into public.user_scope_assignments(profile_id,data_scope_id,valid_from,assigned_by)
    values(v_target.id,v_scope.id,v_now,v_actor.id);
    v_result := jsonb_build_object('profile_id',v_target.id,'status','ACTIVE','data_scope_id',v_scope.id);
  end if;

  select jsonb_build_object('status',p.status,'full_name',p.full_name,'phone',p.phone)
    into v_after
  from public.profiles p
  where p.id = v_target.id;

  insert into public.audit_logs(
    actor_profile_id,organization_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id
  ) values (
    v_actor.id,v_actor.organization_id,'ACCESS_ADMIN_'||v_command,'PROFILE',v_target.id,v_before,v_after,v_reason,v_key
  );

  update app_private.access_admin_commands
  set status='COMPLETED',result_payload=v_result,completed_at=now()
  where id=v_command_id;

  return v_result || jsonb_build_object('command_id',v_command_id,'idempotent_replay',false);
end;
$$;

revoke all on function public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)
  to service_role;

create or replace function public.bootstrap_first_board_uat(
  p_actor_profile_id uuid,
  p_target_auth_user_id uuid,
  p_full_name text,
  p_phone text default null,
  p_data_scope_id uuid default null,
  p_reason text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_scope public.data_scopes%rowtype;
  v_board_role public.roles%rowtype;
  v_org_code text;
  v_command_id uuid;
  v_existing app_private.access_admin_commands%rowtype;
  v_payload jsonb;
  v_result jsonb;
  v_now timestamptz := now();
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_key text := nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if v_reason is null or length(v_reason) > 500 then raise exception 'ACCESS_ADMIN_REASON_REQUIRED'; end if;
  if v_key is null or length(v_key) > 160 then raise exception 'ACCESS_ADMIN_IDEMPOTENCY_REQUIRED'; end if;
  if nullif(btrim(coalesce(p_full_name,'')),'') is null then raise exception 'ACCESS_ADMIN_FULL_NAME_REQUIRED'; end if;

  select * into v_actor
  from public.profiles p
  where p.id = p_actor_profile_id
    and p.status = 'ACTIVE';
  if v_actor.id is null or v_actor.organization_id is null then raise exception 'ACCESS_ADMIN_ACTOR_INVALID'; end if;

  select o.code into v_org_code
  from public.organizations o
  where o.id = v_actor.organization_id
    and o.status = 'ACTIVE';
  if v_org_code is distinct from 'DEMO-KDKMP-DEV' then raise exception 'ACCESS_ADMIN_UAT_DEVELOPMENT_ONLY'; end if;

  if not exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.profile_id=v_actor.id
      and r.code='MANAGER'
      and r.status='ACTIVE'
      and ur.valid_from<=v_now
      and (ur.valid_until is null or ur.valid_until>v_now)
  ) then raise exception 'ACCESS_ADMIN_MANAGER_REQUIRED'; end if;

  if not app_private.profile_has_permission(v_actor.id,'USER_CREATE')
     or not app_private.profile_has_permission(v_actor.id,'ROLE_ASSIGN')
     or not app_private.profile_has_permission(v_actor.id,'SCOPE_ASSIGN') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  end if;

  if p_target_auth_user_id is null
     or not exists(select 1 from auth.users u where u.id=p_target_auth_user_id) then
    raise exception 'ACCESS_ADMIN_AUTH_USER_NOT_FOUND';
  end if;

  select * into v_target
  from public.profiles p
  where p.auth_user_id=p_target_auth_user_id;
  if v_target.id is null then raise exception 'ACCESS_ADMIN_PROFILE_TRIGGER_MISSING'; end if;
  if v_target.id=v_actor.id then raise exception 'ACCESS_ADMIN_SELF_ADMIN_DENIED'; end if;
  if v_target.organization_id is not null and v_target.organization_id<>v_actor.organization_id then
    raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED';
  end if;
  if app_private.profile_has_protected_role_history(v_target.id) then raise exception 'ACCESS_ADMIN_PROTECTED_ROLE_DENIED'; end if;
  if v_target.status not in ('PENDING','INACTIVE') then raise exception 'ACCESS_ADMIN_TARGET_NOT_PROVISIONABLE'; end if;

  select * into v_scope
  from public.data_scopes ds
  where ds.id=p_data_scope_id;
  if v_scope.id is null then raise exception 'ACCESS_ADMIN_SCOPE_NOT_FOUND'; end if;
  if v_scope.organization_id is distinct from v_actor.organization_id then raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED'; end if;
  if not app_private.profile_scope_covers(v_actor.id,v_scope.id) then raise exception 'ACCESS_ADMIN_SCOPE_ESCALATION_DENIED'; end if;

  select * into v_board_role
  from public.roles r
  where r.code='BOARD' and r.status='ACTIVE';
  if v_board_role.id is null then raise exception 'ACCESS_ADMIN_BOARD_ROLE_NOT_FOUND'; end if;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'command_type','BOOTSTRAP_FIRST_BOARD_UAT',
    'target_auth_user_id',p_target_auth_user_id,
    'target_profile_id',v_target.id,
    'full_name',btrim(p_full_name),
    'phone',case when p_phone is null then null else nullif(btrim(p_phone),'') end,
    'data_scope_id',p_data_scope_id,
    'reason',v_reason
  ));

  -- Exact retries return the original result before the one-time gate is evaluated.
  select * into v_existing
  from app_private.access_admin_commands c
  where c.organization_id=v_actor.organization_id
    and c.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.command_type<>'BOOTSTRAP_FIRST_BOARD_UAT' or v_existing.request_payload<>v_payload then
      raise exception 'ACCESS_ADMIN_IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.status<>'COMPLETED' or v_existing.result_payload is null then
      raise exception 'ACCESS_ADMIN_COMMAND_IN_PROGRESS';
    end if;
    return v_existing.result_payload || jsonb_build_object('command_id',v_existing.id,'idempotent_replay',true);
  end if;

  -- Serialize first-BOARD creation per organization so concurrent requests cannot both pass.
  perform pg_advisory_xact_lock(hashtextextended('ACCESS_ADMIN_FIRST_BOARD_UAT:' || v_actor.organization_id::text, 0));

  if exists (
    select 1
    from public.audit_logs al
    where al.organization_id=v_actor.organization_id
      and al.action_code='BOOTSTRAP_FIRST_BOARD_UAT'
  ) then raise exception 'ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED'; end if;

  if exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    join public.profiles p on p.id=ur.profile_id
    where r.code='BOARD'
      and p.organization_id=v_actor.organization_id
      and p.status='ACTIVE'
      and ur.valid_from<=v_now
      and (ur.valid_until is null or ur.valid_until>v_now)
  ) then raise exception 'ACCESS_ADMIN_ACTIVE_BOARD_ALREADY_EXISTS'; end if;

  insert into app_private.access_admin_commands(
    organization_id,actor_profile_id,command_type,target_auth_user_id,target_profile_id,idempotency_key,request_payload
  ) values (
    v_actor.organization_id,v_actor.id,'BOOTSTRAP_FIRST_BOARD_UAT',p_target_auth_user_id,v_target.id,v_key,v_payload
  ) returning id into v_command_id;

  update public.user_roles ur set valid_until=v_now
  where ur.profile_id=v_target.id and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now);
  update public.user_scope_assignments usa set valid_until=v_now
  where usa.profile_id=v_target.id and usa.valid_from<=v_now and (usa.valid_until is null or usa.valid_until>v_now);

  update public.profiles
  set organization_id=v_actor.organization_id,
      full_name=btrim(p_full_name),
      phone=case when p_phone is null then phone else nullif(btrim(p_phone),'') end,
      status='ACTIVE',
      updated_at=v_now
  where id=v_target.id;

  insert into public.user_roles(profile_id,role_id,valid_from,assigned_by)
  values(v_target.id,v_board_role.id,v_now,v_actor.id);
  insert into public.user_scope_assignments(profile_id,data_scope_id,valid_from,assigned_by)
  values(v_target.id,v_scope.id,v_now,v_actor.id);

  v_result := jsonb_build_object(
    'profile_id',v_target.id,
    'status','ACTIVE',
    'role_code','BOARD',
    'data_scope_id',v_scope.id,
    'environment','DEVELOPMENT'
  );

  insert into public.audit_logs(
    actor_profile_id,organization_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id
  ) values (
    v_actor.id,v_actor.organization_id,'BOOTSTRAP_FIRST_BOARD_UAT','PROFILE',v_target.id,
    jsonb_build_object('status',v_target.status,'organization_id',v_target.organization_id),v_result,v_reason,v_key
  );

  update app_private.access_admin_commands
  set status='COMPLETED',result_payload=v_result,completed_at=now()
  where id=v_command_id;

  return v_result || jsonb_build_object('command_id',v_command_id,'idempotent_replay',false);
end;
$$;

revoke all on function public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)
  to service_role;

-- Guardrail assertions: access administration stays Manager-only; direct permission grant stays unmapped.
do $$
begin
  if exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where p.code in ('USER_CREATE','USER_UPDATE','USER_SUSPEND','USER_ARCHIVE','ROLE_ASSIGN','SCOPE_ASSIGN')
      and r.code<>'MANAGER'
  ) then raise exception 'ACCESS_ADMIN_NON_MANAGER_BASELINE_MAPPING_PRESENT'; end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    where p.code='PERMISSION_GRANT'
  ) then raise exception 'ACCESS_ADMIN_DIRECT_PERMISSION_GRANT_MUST_REMAIN_UNMAPPED'; end if;
end $$;
