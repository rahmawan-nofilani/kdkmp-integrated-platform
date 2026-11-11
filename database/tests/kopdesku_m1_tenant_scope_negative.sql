\set ON_ERROR_STOP on
-- STAGING / CI only. Uses synthetic identities, leaves no records (ROLLBACK).
-- Requires the full repo migration replay + the new KopdesKu M1 migration.
begin;

create or replace function pg_temp.assert_true(p_value boolean, p_code text)
returns void language plpgsql as $$
begin
  if p_value is distinct from true then raise exception 'KOPDESKU_M1_ASSERT:%',p_code; end if;
end;
$$;

insert into public.organizations(code,name,status) values
('CI-KOPDESKU-A','CI KopdesKu Tenant A','ACTIVE'),
('CI-KOPDESKU-B','CI KopdesKu Tenant B','ACTIVE');

insert into public.organization_nodes(organization_id,node_type,code,name,status)
select o.id,'KDKMP',o.code||'-NODE',o.name,'ACTIVE'
from public.organizations o where o.code in ('CI-KOPDESKU-A','CI-KOPDESKU-B');

insert into public.organization_units(organization_id,organization_node_id,code,name,unit_type,status)
select o.id,n.id,o.code||'-STORE','CI Retail','RETAIL','ACTIVE'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code=o.code||'-NODE'
where o.code in ('CI-KOPDESKU-A','CI-KOPDESKU-B');

insert into public.data_scopes(organization_id,organization_node_id,scope_type,name)
select o.id,n.id,'COOPERATIVE_SCOPE',o.code||' Cooperative'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code=o.code||'-NODE'
where o.code in ('CI-KOPDESKU-A','CI-KOPDESKU-B');

insert into public.data_scopes(organization_id,scope_type,name)
select o.id,'PLATFORM_SCOPE','CI Bad Platform Role on Tenant A'
from public.organizations o where o.code='CI-KOPDESKU-A';

insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
  created_at,updated_at,is_sso_user,is_anonymous
) values
('36000000-0000-4000-8000-000000000001','authenticated','authenticated','ci-kopdesku-a@example.invalid',now(),'{}','{}',now(),now(),false,false),
('36000000-0000-4000-8000-000000000002','authenticated','authenticated','ci-kopdesku-b@example.invalid',now(),'{}','{}',now(),now(),false,false),
('36000000-0000-4000-8000-000000000003','authenticated','authenticated','ci-kopdesku-platform@example.invalid',now(),'{}','{}',now(),now(),false,false);

update public.profiles p
set organization_id = (select o.id from public.organizations o where o.code =
    case when p.auth_user_id='36000000-0000-4000-8000-000000000002' then 'CI-KOPDESKU-B' else 'CI-KOPDESKU-A' end),
    status='ACTIVE', updated_at=now()
where p.auth_user_id in (
 '36000000-0000-4000-8000-000000000001',
 '36000000-0000-4000-8000-000000000002',
 '36000000-0000-4000-8000-000000000003');

-- A and B have their own cooperation scope; platform user deliberately has
-- BOTH platform and cooperative scope to test fail-closed behavior.
insert into public.user_scope_assignments(profile_id,data_scope_id)
select p.id,s.id
from public.profiles p
join public.data_scopes s on s.organization_id=p.organization_id
where p.auth_user_id in (
 '36000000-0000-4000-8000-000000000001',
 '36000000-0000-4000-8000-000000000002',
 '36000000-0000-4000-8000-000000000003')
  and s.scope_type='COOPERATIVE_SCOPE'
  and s.name like 'CI-KOPDESKU-% Cooperative';

insert into public.user_scope_assignments(profile_id,data_scope_id)
select p.id,s.id
from public.profiles p cross join public.data_scopes s
where p.auth_user_id='36000000-0000-4000-8000-000000000003'
  and s.scope_type='PLATFORM_SCOPE'
  and s.name='CI Bad Platform Role on Tenant A';

select id as org_a from public.organizations where code='CI-KOPDESKU-A' \gset
select id as org_b from public.organizations where code='CI-KOPDESKU-B' \gset
select id as node_a from public.organization_nodes where code='CI-KOPDESKU-A-NODE' \gset
select id as node_b from public.organization_nodes where code='CI-KOPDESKU-B-NODE' \gset
select id as unit_a from public.organization_units where code='CI-KOPDESKU-A-STORE' \gset
select id as unit_b from public.organization_units where code='CI-KOPDESKU-B-STORE' \gset
select p.id as manager_a from public.profiles p where p.auth_user_id='36000000-0000-4000-8000-000000000001' \gset
select p.id as platform_id from public.profiles p where p.auth_user_id='36000000-0000-4000-8000-000000000003' \gset
select id as scope_a from public.data_scopes where name='CI-KOPDESKU-A Cooperative' \gset

-- Actual business-table RLS read fixture: role permission is present,
-- but RLS must still prevent cross-tenant/platform access.
insert into public.user_roles(profile_id,role_id)
select p.id,r.id from public.profiles p cross join public.roles r
where r.code='MANAGER'
  and p.auth_user_id in (
    '36000000-0000-4000-8000-000000000001',
    '36000000-0000-4000-8000-000000000002',
    '36000000-0000-4000-8000-000000000003');

-- Create fixtures through the real authenticated member-write path.
-- Do not bypass member triggers or disable RLS for this test.
set local role authenticated;
select set_config('request.jwt.claim.sub','36000000-0000-4000-8000-000000000001',true);
select public.create_member('CI Synthetic Member A',null,null,:'node_a'::uuid);
select set_config('request.jwt.claim.sub','36000000-0000-4000-8000-000000000002',true);
select public.create_member('CI Synthetic Member B',null,null,:'node_b'::uuid);
reset role;

-- Check delegated scope from trusted context only.
select pg_temp.assert_true(
 app_private.profile_scope_covers(:'manager_a'::uuid,:'scope_a'::uuid),
 'trusted_scope_covers_own_tenant'
);
select pg_temp.assert_true(
 not app_private.profile_scope_covers(:'platform_id'::uuid,:'scope_a'::uuid),
 'platform_cannot_delegate_cooperative_scope'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','36000000-0000-4000-8000-000000000001',true);
select pg_temp.assert_true(public.has_data_scope(:'org_a'::uuid,:'node_a'::uuid,:'unit_a'::uuid), 'tenant_a_allowed');
select pg_temp.assert_true(public.has_data_scope(:'org_a'::uuid), 'cooperative_scope_org_only_for_members');
select pg_temp.assert_true((select count(*) from public.members where full_name like 'CI Synthetic Member %')=1, 'rls_a_sees_only_own_member');
select pg_temp.assert_true(not public.has_data_scope(:'org_b'::uuid,:'node_b'::uuid,:'unit_b'::uuid), 'tenant_a_cannot_read_b');
select pg_temp.assert_true(not public.has_data_scope(:'org_a'::uuid,:'node_b'::uuid), 'forged_node_denied');
select pg_temp.assert_true(not public.has_data_scope(:'org_a'::uuid,:'node_a'::uuid,:'unit_b'::uuid), 'forged_unit_denied');
select pg_temp.assert_true(not public.has_data_scope(null,null,null), 'unbound_business_denied');
select pg_temp.assert_true(app_private.can_access_organization(:'org_a'::uuid), 'tenant_a_organization_allowed');
select pg_temp.assert_true(not app_private.can_access_organization(:'org_b'::uuid), 'tenant_a_other_organization_denied');
select pg_temp.assert_true(app_private.can_access_unit(:'org_a'::uuid,:'unit_a'::uuid), 'tenant_a_unit_allowed');
select pg_temp.assert_true(not app_private.can_access_unit(:'org_b'::uuid,:'unit_b'::uuid), 'tenant_a_other_unit_denied');
select pg_temp.assert_true(app_private.can_access_archive_node(:'org_a'::uuid,:'node_a'::uuid), 'tenant_a_archive_node_allowed');

select set_config('request.jwt.claim.sub','36000000-0000-4000-8000-000000000002',true);
select pg_temp.assert_true(public.has_data_scope(:'org_b'::uuid,:'node_b'::uuid), 'tenant_b_allowed');
select pg_temp.assert_true((select count(*) from public.members where full_name like 'CI Synthetic Member %')=1, 'rls_b_sees_only_own_member');
select pg_temp.assert_true(not public.has_data_scope(:'org_a'::uuid,:'node_a'::uuid), 'tenant_b_cannot_read_a');

select set_config('request.jwt.claim.sub','36000000-0000-4000-8000-000000000003',true);
select pg_temp.assert_true(not public.has_data_scope(:'org_a'::uuid,:'node_a'::uuid), 'platform_with_coop_scope_denied');
select pg_temp.assert_true((select count(*) from public.members where full_name like 'CI Synthetic Member %')=0, 'rls_platform_sees_no_members');
select pg_temp.assert_true(not app_private.can_access_organization(:'org_a'::uuid), 'platform_organization_denied');
select pg_temp.assert_true(not app_private.can_access_unit(:'org_a'::uuid,:'unit_a'::uuid), 'platform_unit_denied');
select pg_temp.assert_true(not app_private.can_access_archive_node(:'org_a'::uuid,:'node_a'::uuid), 'platform_archive_denied');

-- Nothing is committed to the database.
rollback;
