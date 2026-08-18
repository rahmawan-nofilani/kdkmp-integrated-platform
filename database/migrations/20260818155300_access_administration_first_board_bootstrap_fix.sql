-- Pre-apply refinement of the first BOARD DEVELOPMENT/UAT bootstrap.
-- Keeps the one-time policy from the preceding migration while using an explicit actor lookup.

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
  v_now timestamptz:=now();
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if v_reason is null or length(v_reason)>500 then raise exception 'ACCESS_ADMIN_REASON_REQUIRED'; end if;
  if v_key is null or length(v_key)>160 then raise exception 'ACCESS_ADMIN_IDEMPOTENCY_REQUIRED'; end if;
  if nullif(btrim(coalesce(p_full_name,'')),'') is null then raise exception 'ACCESS_ADMIN_FULL_NAME_REQUIRED'; end if;

  select * into v_actor
  from public.profiles p
  where p.id=p_actor_profile_id and p.status='ACTIVE';
  if v_actor.id is null or v_actor.organization_id is null then raise exception 'ACCESS_ADMIN_ACTOR_INVALID'; end if;

  select o.code into v_org_code
  from public.organizations o
  where o.id=v_actor.organization_id and o.status='ACTIVE';
  if v_org_code is distinct from 'DEMO-KDKMP-DEV' then raise exception 'ACCESS_ADMIN_UAT_DEVELOPMENT_ONLY'; end if;

  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.profile_id=v_actor.id and r.code='MANAGER' and r.status='ACTIVE'
      and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now)
  ) then raise exception 'ACCESS_ADMIN_MANAGER_REQUIRED'; end if;
  if not app_private.profile_has_permission(v_actor.id,'USER_CREATE')
     or not app_private.profile_has_permission(v_actor.id,'ROLE_ASSIGN')
     or not app_private.profile_has_permission(v_actor.id,'SCOPE_ASSIGN') then
    raise exception 'ACCESS_ADMIN_PERMISSION_DENIED';
  end if;

  if p_target_auth_user_id is null or not exists(select 1 from auth.users u where u.id=p_target_auth_user_id) then
    raise exception 'ACCESS_ADMIN_AUTH_USER_NOT_FOUND';
  end if;
  select * into v_target from public.profiles p where p.auth_user_id=p_target_auth_user_id;
  if v_target.id is null then raise exception 'ACCESS_ADMIN_PROFILE_TRIGGER_MISSING'; end if;
  if v_target.id=v_actor.id then raise exception 'ACCESS_ADMIN_SELF_ADMIN_DENIED'; end if;
  if v_target.organization_id is not null and v_target.organization_id<>v_actor.organization_id then raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED'; end if;
  if app_private.profile_has_protected_role_history(v_target.id) then raise exception 'ACCESS_ADMIN_PROTECTED_ROLE_DENIED'; end if;
  if v_target.status not in ('PENDING','INACTIVE') then raise exception 'ACCESS_ADMIN_TARGET_NOT_PROVISIONABLE'; end if;

  select * into v_scope from public.data_scopes ds where ds.id=p_data_scope_id;
  if v_scope.id is null then raise exception 'ACCESS_ADMIN_SCOPE_NOT_FOUND'; end if;
  if v_scope.organization_id is distinct from v_actor.organization_id then raise exception 'ACCESS_ADMIN_CROSS_ORGANIZATION_DENIED'; end if;
  if not app_private.profile_scope_covers(v_actor.id,v_scope.id) then raise exception 'ACCESS_ADMIN_SCOPE_ESCALATION_DENIED'; end if;

  select * into v_board_role from public.roles r where r.code='BOARD' and r.status='ACTIVE';
  if v_board_role.id is null then raise exception 'ACCESS_ADMIN_BOARD_ROLE_NOT_FOUND'; end if;

  v_payload:=jsonb_strip_nulls(jsonb_build_object(
    'command_type','BOOTSTRAP_FIRST_BOARD_UAT','target_auth_user_id',p_target_auth_user_id,'target_profile_id',v_target.id,
    'full_name',btrim(p_full_name),'phone',case when p_phone is null then null else nullif(btrim(p_phone),'') end,
    'data_scope_id',p_data_scope_id,'reason',v_reason
  ));

  select * into v_existing from app_private.access_admin_commands c
  where c.organization_id=v_actor.organization_id and c.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.command_type<>'BOOTSTRAP_FIRST_BOARD_UAT' or v_existing.request_payload<>v_payload then
      raise exception 'ACCESS_ADMIN_IDEMPOTENCY_CONFLICT';
    end if;
    if v_existing.status<>'COMPLETED' or v_existing.result_payload is null then raise exception 'ACCESS_ADMIN_COMMAND_IN_PROGRESS'; end if;
    return v_existing.result_payload || jsonb_build_object('command_id',v_existing.id,'idempotent_replay',true);
  end if;

  if exists(select 1 from public.audit_logs al where al.organization_id=v_actor.organization_id and al.action_code='BOOTSTRAP_FIRST_BOARD_UAT') then
    raise exception 'ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED';
  end if;
  if exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id join public.profiles p on p.id=ur.profile_id
    where r.code='BOARD' and p.organization_id=v_actor.organization_id and p.status='ACTIVE'
      and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now)
  ) then raise exception 'ACCESS_ADMIN_ACTIVE_BOARD_ALREADY_EXISTS'; end if;

  insert into app_private.access_admin_commands(
    organization_id,actor_profile_id,command_type,target_auth_user_id,target_profile_id,idempotency_key,request_payload
  ) values(v_actor.organization_id,v_actor.id,'BOOTSTRAP_FIRST_BOARD_UAT',p_target_auth_user_id,v_target.id,v_key,v_payload)
  returning id into v_command_id;

  update public.user_roles ur set valid_until=v_now
  where ur.profile_id=v_target.id and ur.valid_from<=v_now and (ur.valid_until is null or ur.valid_until>v_now);
  update public.user_scope_assignments usa set valid_until=v_now
  where usa.profile_id=v_target.id and usa.valid_from<=v_now and (usa.valid_until is null or usa.valid_until>v_now);
  update public.profiles set organization_id=v_actor.organization_id,full_name=btrim(p_full_name),
    phone=case when p_phone is null then phone else nullif(btrim(p_phone),'') end,status='ACTIVE',updated_at=v_now
  where id=v_target.id;
  insert into public.user_roles(profile_id,role_id,valid_from,assigned_by)
  values(v_target.id,v_board_role.id,v_now,v_actor.id);
  insert into public.user_scope_assignments(profile_id,data_scope_id,valid_from,assigned_by)
  values(v_target.id,v_scope.id,v_now,v_actor.id);

  v_result:=jsonb_build_object('profile_id',v_target.id,'status','ACTIVE','role_code','BOARD','data_scope_id',v_scope.id,'environment','DEVELOPMENT');
  insert into public.audit_logs(actor_profile_id,organization_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_actor.id,v_actor.organization_id,'BOOTSTRAP_FIRST_BOARD_UAT','PROFILE',v_target.id,
    jsonb_build_object('status',v_target.status,'organization_id',v_target.organization_id),v_result,v_reason,v_key);
  update app_private.access_admin_commands set status='COMPLETED',result_payload=v_result,completed_at=now() where id=v_command_id;
  return v_result || jsonb_build_object('command_id',v_command_id,'idempotent_replay',false);
end;
$$;

revoke all on function public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text) from public, anon, authenticated;
grant execute on function public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text) to service_role;
