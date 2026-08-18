\set ON_ERROR_STOP on

begin;

-- Baseline access-administration permissions remain Manager-only; direct permission grant stays unmapped.
do $$
begin
  if exists(
    select 1 from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where p.code in ('USER_CREATE','USER_UPDATE','USER_SUSPEND','USER_ARCHIVE','ROLE_ASSIGN','SCOPE_ASSIGN')
      and r.code<>'MANAGER'
  ) then raise exception 'CI_ACCESS_ADMIN_NON_MANAGER_MAPPING'; end if;
  if exists(
    select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id
    where p.code='PERMISSION_GRANT'
  ) then raise exception 'CI_ACCESS_ADMIN_PERMISSION_GRANT_MAPPED'; end if;
end $$;

-- Public RPCs must be callable only through the trusted server/service-role boundary.
do $$
begin
  if has_function_privilege('authenticated','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE') then
    raise exception 'CI_ACCESS_ADMIN_AUTHENTICATED_RPC_EXPOSED';
  end if;
  if has_function_privilege('anon','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE') then
    raise exception 'CI_ACCESS_ADMIN_ANON_RPC_EXPOSED';
  end if;
  if not has_function_privilege('service_role','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE') then
    raise exception 'CI_ACCESS_ADMIN_SERVICE_ROLE_RPC_MISSING';
  end if;
  if has_function_privilege('authenticated','public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)','EXECUTE') then
    raise exception 'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_AUTHENTICATED_EXPOSED';
  end if;
  if not has_function_privilege('service_role','public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)','EXECUTE') then
    raise exception 'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_SERVICE_ROLE_MISSING';
  end if;
end $$;

-- Synthetic DEVELOPMENT/UAT actors; disposable transaction only.
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous)
values
('13000000-0000-4000-8000-000000000001','authenticated','authenticated','access-manager@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000002','authenticated','authenticated','access-operational@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000003','authenticated','authenticated','access-board-first@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000004','authenticated','authenticated','access-board-second@example.invalid',now(),'{}','{}',now(),now(),false,false);

select id as organization_id from public.organizations where code='DEMO-KDKMP-DEV' and status='ACTIVE' limit 1\gset
select id as cooperative_scope_id from public.data_scopes
where organization_id=:'organization_id'::uuid and scope_type='COOPERATIVE_SCOPE' order by created_at asc limit 1\gset

update public.profiles set organization_id=:'organization_id'::uuid,full_name='CI Access Manager',status='ACTIVE',updated_at=now()
where auth_user_id='13000000-0000-4000-8000-000000000001';
select id as manager_profile_id from public.profiles where auth_user_id='13000000-0000-4000-8000-000000000001'\gset
select id as operational_profile_id from public.profiles where auth_user_id='13000000-0000-4000-8000-000000000002'\gset
select id as board_first_profile_id from public.profiles where auth_user_id='13000000-0000-4000-8000-000000000003'\gset
select id as board_second_profile_id from public.profiles where auth_user_id='13000000-0000-4000-8000-000000000004'\gset

insert into public.user_roles(profile_id,role_id,assigned_by)
select :'manager_profile_id'::uuid,r.id,:'manager_profile_id'::uuid from public.roles r where r.code='MANAGER';
insert into public.user_scope_assignments(profile_id,data_scope_id,assigned_by)
values(:'manager_profile_id'::uuid,:'cooperative_scope_id'::uuid,:'manager_profile_id'::uuid);

-- 1) Manager provisions an operational CASHIER inside own scope.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'PROVISION_USER','13000000-0000-4000-8000-000000000002'::uuid,null,
  'CI Operational User','081200000001','CASHIER',:'cooperative_scope_id'::uuid,
  'CI provision operational cashier','ACCESS-CI-PROVISION-1'
) as provision_result\gset

do $$
begin
  if not exists(select 1 from public.profiles p where p.id=:'operational_profile_id'::uuid and p.status='ACTIVE' and p.organization_id=:'organization_id'::uuid) then
    raise exception 'CI_ACCESS_ADMIN_PROVISION_PROFILE_INVALID';
  end if;
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.profile_id=:'operational_profile_id'::uuid and r.code='CASHIER'
      and ur.assigned_by=:'manager_profile_id'::uuid and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())
  ) then raise exception 'CI_ACCESS_ADMIN_CASHIER_ROLE_MISSING'; end if;
  if not exists(
    select 1 from public.user_scope_assignments usa
    where usa.profile_id=:'operational_profile_id'::uuid and usa.data_scope_id=:'cooperative_scope_id'::uuid
      and usa.assigned_by=:'manager_profile_id'::uuid and usa.valid_from<=now() and (usa.valid_until is null or usa.valid_until>now())
  ) then raise exception 'CI_ACCESS_ADMIN_SCOPE_MISSING'; end if;
end $$;

-- Exact retry is idempotent.
do $$ declare v_result jsonb; begin
  v_result:=public.execute_access_admin_command(
    :'manager_profile_id'::uuid,'PROVISION_USER','13000000-0000-4000-8000-000000000002'::uuid,null,
    'CI Operational User','081200000001','CASHIER',:'cooperative_scope_id'::uuid,
    'CI provision operational cashier','ACCESS-CI-PROVISION-1'
  );
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then
    raise exception 'CI_ACCESS_ADMIN_IDEMPOTENT_REPLAY_FAILED';
  end if;
end $$;

-- 2) Manager cannot assign MANAGER or BOARD through the normal command path.
do $$ declare v_msg text; begin
  begin
    perform public.execute_access_admin_command(
      :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'MANAGER',null,
      'must reject manager role','ACCESS-CI-ROLE-MANAGER'
    );
    raise exception 'expected_ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE' then raise exception 'expected ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE, got %',v_msg; end if;
  end;

  begin
    perform public.execute_access_admin_command(
      :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'BOARD',null,
      'must reject board role','ACCESS-CI-ROLE-BOARD'
    );
    raise exception 'expected_ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE' then raise exception 'expected ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE, got %',v_msg; end if;
  end;
end $$;

-- 3) Manager cannot administer itself.
do $$ declare v_msg text; begin
  begin
    perform public.execute_access_admin_command(
      :'manager_profile_id'::uuid,'SUSPEND_USER',null,:'manager_profile_id'::uuid,null,null,null,null,
      'must reject self administration','ACCESS-CI-SELF-SUSPEND'
    );
    raise exception 'expected_ACCESS_ADMIN_SELF_ADMIN_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_SELF_ADMIN_DENIED' then raise exception 'expected ACCESS_ADMIN_SELF_ADMIN_DENIED, got %',v_msg; end if;
  end;
end $$;

-- 4) Manager may switch among the approved operational roles; old role is closed.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'TELLER',null,
  'CI switch operational role','ACCESS-CI-ROLE-TELLER'
);

do $$
begin
  if (select count(*) from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.profile_id=:'operational_profile_id'::uuid and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now()))<>1 then
    raise exception 'CI_ACCESS_ADMIN_ACTIVE_ROLE_COUNT_INVALID';
  end if;
  if not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.profile_id=:'operational_profile_id'::uuid and r.code='TELLER' and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())) then
    raise exception 'CI_ACCESS_ADMIN_TELLER_ROLE_MISSING';
  end if;
end $$;

-- 5) A scope outside the Manager's organizational scope is rejected.
insert into public.data_scopes(organization_id,scope_type,name)
values(:'organization_id'::uuid,'OWN_DATA_ONLY','CI non-assignable own-data scope') returning id as non_assignable_scope_id\gset

do $$ declare v_msg text; begin
  begin
    perform public.execute_access_admin_command(
      :'manager_profile_id'::uuid,'ASSIGN_SCOPE',null,:'operational_profile_id'::uuid,null,null,null,:'non_assignable_scope_id'::uuid,
      'must reject scope escalation','ACCESS-CI-SCOPE-ESCALATION'
    );
    raise exception 'expected_ACCESS_ADMIN_SCOPE_ESCALATION_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_SCOPE_ESCALATION_DENIED' then raise exception 'expected ACCESS_ADMIN_SCOPE_ESCALATION_DENIED, got %',v_msg; end if;
  end;
end $$;

-- 6) Suspend immediately removes active role/scope; archive requires prior non-active state.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'SUSPEND_USER',null,:'operational_profile_id'::uuid,null,null,null,null,
  'CI suspend operational user','ACCESS-CI-SUSPEND-1'
);

do $$
begin
  if not exists(select 1 from public.profiles where id=:'operational_profile_id'::uuid and status='SUSPENDED') then
    raise exception 'CI_ACCESS_ADMIN_SUSPEND_STATUS_INVALID';
  end if;
  if exists(select 1 from public.user_roles where profile_id=:'operational_profile_id'::uuid and valid_from<=now() and (valid_until is null or valid_until>now())) then
    raise exception 'CI_ACCESS_ADMIN_SUSPEND_ROLE_NOT_REVOKED';
  end if;
  if exists(select 1 from public.user_scope_assignments where profile_id=:'operational_profile_id'::uuid and valid_from<=now() and (valid_until is null or valid_until>now())) then
    raise exception 'CI_ACCESS_ADMIN_SUSPEND_SCOPE_NOT_REVOKED';
  end if;
end $$;

select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'ARCHIVE_USER',null,:'operational_profile_id'::uuid,null,null,null,null,
  'CI archive suspended user','ACCESS-CI-ARCHIVE-1'
);

-- 7) Controlled one-time first BOARD bootstrap works only through its dedicated path.
select public.bootstrap_first_board_uat(
  :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000003'::uuid,'CI First Board',null,
  :'cooperative_scope_id'::uuid,'CI one-time DEVELOPMENT first BOARD','ACCESS-CI-BOARD-FIRST'
) as board_result\gset

do $$
begin
  if not exists(
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.profile_id=:'board_first_profile_id'::uuid and r.code='BOARD'
      and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())
  ) then raise exception 'CI_ACCESS_ADMIN_BOARD_ROLE_MISSING'; end if;
  if not exists(select 1 from public.audit_logs al where al.entity_id=:'board_first_profile_id'::uuid and al.action_code='BOOTSTRAP_FIRST_BOARD_UAT') then
    raise exception 'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_AUDIT_MISSING';
  end if;
end $$;

-- Exact bootstrap retry is idempotent even after the one-time marker exists.
do $$ declare v_result jsonb; begin
  v_result:=public.bootstrap_first_board_uat(
    :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000003'::uuid,'CI First Board',null,
    :'cooperative_scope_id'::uuid,'CI one-time DEVELOPMENT first BOARD','ACCESS-CI-BOARD-FIRST'
  );
  if coalesce((v_result->>'idempotent_replay')::boolean,false) is not true then
    raise exception 'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_REPLAY_FAILED';
  end if;
end $$;

-- General Manager commands can no longer touch the BOARD account.
do $$ declare v_msg text; begin
  begin
    perform public.execute_access_admin_command(
      :'manager_profile_id'::uuid,'UPDATE_USER',null,:'board_first_profile_id'::uuid,'Changed Board',null,null,null,
      'must reject protected board','ACCESS-CI-BOARD-UPDATE'
    );
    raise exception 'expected_ACCESS_ADMIN_PROTECTED_ROLE_DENIED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_PROTECTED_ROLE_DENIED' then raise exception 'expected ACCESS_ADMIN_PROTECTED_ROLE_DENIED, got %',v_msg; end if;
  end;
end $$;

-- A different user cannot become another "first" BOARD after the marker is written.
do $$ declare v_msg text; begin
  begin
    perform public.bootstrap_first_board_uat(
      :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000004'::uuid,'CI Second Board',null,
      :'cooperative_scope_id'::uuid,'must reject second bootstrap','ACCESS-CI-BOARD-SECOND'
    );
    raise exception 'expected_ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED';
  exception when others then
    get stacked diagnostics v_msg=message_text;
    if v_msg<>'ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED' then
      raise exception 'expected ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED, got %',v_msg;
    end if;
  end;
end $$;

-- Audit evidence exists for all successful command families.
do $$
begin
  if not exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_PROVISION_USER') then
    raise exception 'CI_ACCESS_ADMIN_PROVISION_AUDIT_MISSING';
  end if;
  if not exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_ASSIGN_ROLE') then
    raise exception 'CI_ACCESS_ADMIN_ROLE_AUDIT_MISSING';
  end if;
  if not exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_SUSPEND_USER') then
    raise exception 'CI_ACCESS_ADMIN_SUSPEND_AUDIT_MISSING';
  end if;
  if not exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_ARCHIVE_USER') then
    raise exception 'CI_ACCESS_ADMIN_ARCHIVE_AUDIT_MISSING';
  end if;
end $$;

rollback;
