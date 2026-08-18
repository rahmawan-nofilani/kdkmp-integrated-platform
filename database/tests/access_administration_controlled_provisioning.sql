\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
as $$
begin
  if coalesce(p_condition,false) is not true then
    raise exception '%', p_message;
  end if;
end;
$$;

create or replace function pg_temp.expect_access_error(
  p_actor uuid,
  p_command text,
  p_target_auth uuid,
  p_target_profile uuid,
  p_full_name text,
  p_phone text,
  p_role text,
  p_scope uuid,
  p_reason text,
  p_key text,
  p_expected text
)
returns void
language plpgsql
as $$
declare
  v_message text;
begin
  begin
    perform public.execute_access_admin_command(
      p_actor,p_command,p_target_auth,p_target_profile,p_full_name,p_phone,p_role,p_scope,p_reason,p_key
    );
    raise exception 'CI_EXPECTED_ERROR_MISSING:%',p_expected;
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message <> p_expected then
      raise exception 'CI_EXPECTED_%,GOT_%',p_expected,v_message;
    end if;
  end;
end;
$$;

create or replace function pg_temp.expect_board_error(
  p_actor uuid,
  p_target_auth uuid,
  p_full_name text,
  p_scope uuid,
  p_reason text,
  p_key text,
  p_expected text
)
returns void
language plpgsql
as $$
declare
  v_message text;
begin
  begin
    perform public.bootstrap_first_board_uat(
      p_actor,p_target_auth,p_full_name,null,p_scope,p_reason,p_key
    );
    raise exception 'CI_EXPECTED_ERROR_MISSING:%',p_expected;
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message <> p_expected then
      raise exception 'CI_EXPECTED_%,GOT_%',p_expected,v_message;
    end if;
  end;
end;
$$;

-- Baseline access-admin permissions stay Manager-only and direct permission grant stays unmapped.
select pg_temp.assert_true(
  not exists(
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where p.code in ('USER_CREATE','USER_UPDATE','USER_SUSPEND','USER_ARCHIVE','ROLE_ASSIGN','SCOPE_ASSIGN')
      and r.code<>'MANAGER'
  ),
  'CI_ACCESS_ADMIN_NON_MANAGER_MAPPING'
);

select pg_temp.assert_true(
  not exists(
    select 1
    from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    where p.code='PERMISSION_GRANT'
  ),
  'CI_ACCESS_ADMIN_PERMISSION_GRANT_MAPPED'
);

-- Privileged RPCs are trusted-server/service-role only.
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE'),
  'CI_ACCESS_ADMIN_AUTHENTICATED_RPC_EXPOSED'
);
select pg_temp.assert_true(
  not has_function_privilege('anon','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE'),
  'CI_ACCESS_ADMIN_ANON_RPC_EXPOSED'
);
select pg_temp.assert_true(
  has_function_privilege('service_role','public.execute_access_admin_command(uuid,text,uuid,uuid,text,text,text,uuid,text,text)','EXECUTE'),
  'CI_ACCESS_ADMIN_SERVICE_ROLE_RPC_MISSING'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated','public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)','EXECUTE'),
  'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_AUTHENTICATED_EXPOSED'
);
select pg_temp.assert_true(
  has_function_privilege('service_role','public.bootstrap_first_board_uat(uuid,uuid,text,text,uuid,text,text)','EXECUTE'),
  'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_SERVICE_ROLE_MISSING'
);

-- Disposable Auth users. The existing auth trigger creates fail-closed PENDING profiles.
insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_sso_user,is_anonymous
) values
('13000000-0000-4000-8000-000000000001','authenticated','authenticated','access-manager@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000002','authenticated','authenticated','access-operational@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000003','authenticated','authenticated','access-board-first@example.invalid',now(),'{}','{}',now(),now(),false,false),
('13000000-0000-4000-8000-000000000004','authenticated','authenticated','access-board-second@example.invalid',now(),'{}','{}',now(),now(),false,false);

select id as organization_id
from public.organizations
where code='DEMO-KDKMP-DEV' and status='ACTIVE'
limit 1\gset

select id as cooperative_scope_id
from public.data_scopes
where organization_id=:'organization_id'::uuid
  and scope_type='COOPERATIVE_SCOPE'
order by created_at asc
limit 1\gset

update public.profiles
set organization_id=:'organization_id'::uuid,
    full_name='CI Access Manager',
    status='ACTIVE',
    updated_at=now()
where auth_user_id='13000000-0000-4000-8000-000000000001';

select id as manager_profile_id
from public.profiles
where auth_user_id='13000000-0000-4000-8000-000000000001'\gset
select id as operational_profile_id
from public.profiles
where auth_user_id='13000000-0000-4000-8000-000000000002'\gset
select id as board_first_profile_id
from public.profiles
where auth_user_id='13000000-0000-4000-8000-000000000003'\gset

insert into public.user_roles(profile_id,role_id,assigned_by)
select :'manager_profile_id'::uuid,r.id,:'manager_profile_id'::uuid
from public.roles r
where r.code='MANAGER';
insert into public.user_scope_assignments(profile_id,data_scope_id,assigned_by)
values(:'manager_profile_id'::uuid,:'cooperative_scope_id'::uuid,:'manager_profile_id'::uuid);

-- Manager provisions CASHIER in its own scope.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'PROVISION_USER','13000000-0000-4000-8000-000000000002'::uuid,null,
  'CI Operational User','081200000001','CASHIER',:'cooperative_scope_id'::uuid,
  'CI provision operational cashier','ACCESS-CI-PROVISION-1'
);

select pg_temp.assert_true(
  exists(
    select 1 from public.profiles p
    where p.id=:'operational_profile_id'::uuid
      and p.status='ACTIVE'
      and p.organization_id=:'organization_id'::uuid
  ),
  'CI_ACCESS_ADMIN_PROVISION_PROFILE_INVALID'
);
select pg_temp.assert_true(
  exists(
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.profile_id=:'operational_profile_id'::uuid
      and r.code='CASHIER'
      and ur.assigned_by=:'manager_profile_id'::uuid
      and ur.valid_from<=now()
      and (ur.valid_until is null or ur.valid_until>now())
  ),
  'CI_ACCESS_ADMIN_CASHIER_ROLE_MISSING'
);
select pg_temp.assert_true(
  exists(
    select 1
    from public.user_scope_assignments usa
    where usa.profile_id=:'operational_profile_id'::uuid
      and usa.data_scope_id=:'cooperative_scope_id'::uuid
      and usa.assigned_by=:'manager_profile_id'::uuid
      and usa.valid_from<=now()
      and (usa.valid_until is null or usa.valid_until>now())
  ),
  'CI_ACCESS_ADMIN_SCOPE_MISSING'
);

-- Exact retry is idempotent.
select pg_temp.assert_true(
  coalesce((public.execute_access_admin_command(
    :'manager_profile_id'::uuid,'PROVISION_USER','13000000-0000-4000-8000-000000000002'::uuid,null,
    'CI Operational User','081200000001','CASHIER',:'cooperative_scope_id'::uuid,
    'CI provision operational cashier','ACCESS-CI-PROVISION-1'
  )->>'idempotent_replay')::boolean,false),
  'CI_ACCESS_ADMIN_IDEMPOTENT_REPLAY_FAILED'
);

-- MANAGER/BOARD are never assignable from the normal Manager path.
select pg_temp.expect_access_error(
  :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'MANAGER',null,
  'must reject manager role','ACCESS-CI-ROLE-MANAGER','ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE'
);
select pg_temp.expect_access_error(
  :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'BOARD',null,
  'must reject board role','ACCESS-CI-ROLE-BOARD','ACCESS_ADMIN_ROLE_NOT_ASSIGNABLE'
);

-- Self administration is denied.
select pg_temp.expect_access_error(
  :'manager_profile_id'::uuid,'SUSPEND_USER',null,:'manager_profile_id'::uuid,null,null,null,null,
  'must reject self administration','ACCESS-CI-SELF-SUSPEND','ACCESS_ADMIN_SELF_ADMIN_DENIED'
);

-- Manager may switch between approved operational roles; the previous active role is closed.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'ASSIGN_ROLE',null,:'operational_profile_id'::uuid,null,null,'TELLER',null,
  'CI switch operational role','ACCESS-CI-ROLE-TELLER'
);
select pg_temp.assert_true(
  (select count(*)=1
   from public.user_roles ur
   where ur.profile_id=:'operational_profile_id'::uuid
     and ur.valid_from<=now()
     and (ur.valid_until is null or ur.valid_until>now())),
  'CI_ACCESS_ADMIN_ACTIVE_ROLE_COUNT_INVALID'
);
select pg_temp.assert_true(
  exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.profile_id=:'operational_profile_id'::uuid
      and r.code='TELLER'
      and ur.valid_from<=now()
      and (ur.valid_until is null or ur.valid_until>now())
  ),
  'CI_ACCESS_ADMIN_TELLER_ROLE_MISSING'
);

-- Contextual own-data scope is intentionally non-delegable.
insert into public.data_scopes(organization_id,scope_type,name)
values(:'organization_id'::uuid,'OWN_DATA_ONLY','CI non-assignable own-data scope')
returning id as non_assignable_scope_id\gset

select pg_temp.expect_access_error(
  :'manager_profile_id'::uuid,'ASSIGN_SCOPE',null,:'operational_profile_id'::uuid,null,null,null,:'non_assignable_scope_id'::uuid,
  'must reject scope escalation','ACCESS-CI-SCOPE-ESCALATION','ACCESS_ADMIN_SCOPE_ESCALATION_DENIED'
);

-- Suspend immediately revokes active role/scope; archive requires prior non-active state.
select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'SUSPEND_USER',null,:'operational_profile_id'::uuid,null,null,null,null,
  'CI suspend operational user','ACCESS-CI-SUSPEND-1'
);
select pg_temp.assert_true(
  exists(select 1 from public.profiles where id=:'operational_profile_id'::uuid and status='SUSPENDED'),
  'CI_ACCESS_ADMIN_SUSPEND_STATUS_INVALID'
);
select pg_temp.assert_true(
  not exists(
    select 1 from public.user_roles
    where profile_id=:'operational_profile_id'::uuid
      and valid_from<=now() and (valid_until is null or valid_until>now())
  ),
  'CI_ACCESS_ADMIN_SUSPEND_ROLE_NOT_REVOKED'
);
select pg_temp.assert_true(
  not exists(
    select 1 from public.user_scope_assignments
    where profile_id=:'operational_profile_id'::uuid
      and valid_from<=now() and (valid_until is null or valid_until>now())
  ),
  'CI_ACCESS_ADMIN_SUSPEND_SCOPE_NOT_REVOKED'
);

select public.execute_access_admin_command(
  :'manager_profile_id'::uuid,'ARCHIVE_USER',null,:'operational_profile_id'::uuid,null,null,null,null,
  'CI archive suspended user','ACCESS-CI-ARCHIVE-1'
);
select pg_temp.assert_true(
  exists(select 1 from public.profiles where id=:'operational_profile_id'::uuid and status='ARCHIVED'),
  'CI_ACCESS_ADMIN_ARCHIVE_STATUS_INVALID'
);

-- First BOARD bootstrap is separate and one-time.
select public.bootstrap_first_board_uat(
  :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000003'::uuid,'CI First Board',null,
  :'cooperative_scope_id'::uuid,'CI one-time DEVELOPMENT first BOARD','ACCESS-CI-BOARD-FIRST'
);
select pg_temp.assert_true(
  exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.profile_id=:'board_first_profile_id'::uuid
      and r.code='BOARD'
      and ur.valid_from<=now()
      and (ur.valid_until is null or ur.valid_until>now())
  ),
  'CI_ACCESS_ADMIN_BOARD_ROLE_MISSING'
);
select pg_temp.assert_true(
  exists(
    select 1 from public.audit_logs al
    where al.entity_id=:'board_first_profile_id'::uuid
      and al.action_code='BOOTSTRAP_FIRST_BOARD_UAT'
  ),
  'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_AUDIT_MISSING'
);

-- Exact bootstrap retry remains idempotent despite one-time marker.
select pg_temp.assert_true(
  coalesce((public.bootstrap_first_board_uat(
    :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000003'::uuid,'CI First Board',null,
    :'cooperative_scope_id'::uuid,'CI one-time DEVELOPMENT first BOARD','ACCESS-CI-BOARD-FIRST'
  )->>'idempotent_replay')::boolean,false),
  'CI_ACCESS_ADMIN_BOARD_BOOTSTRAP_REPLAY_FAILED'
);

-- General Manager path cannot touch a BOARD profile.
select pg_temp.expect_access_error(
  :'manager_profile_id'::uuid,'UPDATE_USER',null,:'board_first_profile_id'::uuid,'Changed Board',null,null,null,
  'must reject protected board','ACCESS-CI-BOARD-UPDATE','ACCESS_ADMIN_PROTECTED_ROLE_DENIED'
);

-- A different Auth user cannot consume first-BOARD bootstrap after the marker exists.
select pg_temp.expect_board_error(
  :'manager_profile_id'::uuid,'13000000-0000-4000-8000-000000000004'::uuid,'CI Second Board',:'cooperative_scope_id'::uuid,
  'must reject second bootstrap','ACCESS-CI-BOARD-SECOND','ACCESS_ADMIN_FIRST_BOARD_BOOTSTRAP_ALREADY_USED'
);

-- Successful command families append audit evidence.
select pg_temp.assert_true(
  exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_PROVISION_USER'),
  'CI_ACCESS_ADMIN_PROVISION_AUDIT_MISSING'
);
select pg_temp.assert_true(
  exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_ASSIGN_ROLE'),
  'CI_ACCESS_ADMIN_ROLE_AUDIT_MISSING'
);
select pg_temp.assert_true(
  exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_SUSPEND_USER'),
  'CI_ACCESS_ADMIN_SUSPEND_AUDIT_MISSING'
);
select pg_temp.assert_true(
  exists(select 1 from public.audit_logs where actor_profile_id=:'manager_profile_id'::uuid and action_code='ACCESS_ADMIN_ARCHIVE_USER'),
  'CI_ACCESS_ADMIN_ARCHIVE_AUDIT_MISSING'
);

rollback;
