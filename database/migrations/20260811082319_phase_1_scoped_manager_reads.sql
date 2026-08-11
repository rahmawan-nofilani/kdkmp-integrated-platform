create schema if not exists app_private;

create or replace function app_private.current_profile_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p
  where p.auth_user_id = (select auth.uid()) and p.status = 'ACTIVE'
  limit 1
$$;

create or replace function app_private.current_organization_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.organization_id from public.profiles p
  where p.auth_user_id = (select auth.uid()) and p.status = 'ACTIVE'
  limit 1
$$;

create or replace function app_private.has_permission(p_permission_code text)
returns boolean language sql stable security definer set search_path = '' as $$
  with current_profile as (
    select p.id from public.profiles p
    where p.auth_user_id = (select auth.uid()) and p.status = 'ACTIVE' limit 1
  ), target_permission as (
    select p.id from public.permissions p where p.code = p_permission_code limit 1
  ), explicit_deny as (
    select 1 from public.user_permissions up
    join current_profile cp on cp.id = up.profile_id
    join target_permission tp on tp.id = up.permission_id
    where up.effect = 'DENY' and up.valid_from <= now()
      and (up.valid_until is null or up.valid_until > now()) limit 1
  ), explicit_allow as (
    select 1 from public.user_permissions up
    join current_profile cp on cp.id = up.profile_id
    join target_permission tp on tp.id = up.permission_id
    where up.effect = 'ALLOW' and up.valid_from <= now()
      and (up.valid_until is null or up.valid_until > now()) limit 1
  ), role_allow as (
    select 1 from public.user_roles ur
    join current_profile cp on cp.id = ur.profile_id
    join public.roles r on r.id = ur.role_id and r.status = 'ACTIVE'
    join public.role_permissions rp on rp.role_id = ur.role_id
    join target_permission tp on tp.id = rp.permission_id
    where ur.valid_from <= now() and (ur.valid_until is null or ur.valid_until > now()) limit 1
  )
  select case
    when (select auth.uid()) is null then false
    when not exists (select 1 from current_profile) then false
    when not exists (select 1 from target_permission) then false
    when exists (select 1 from explicit_deny) then false
    when exists (select 1 from explicit_allow) then true
    when exists (select 1 from role_allow) then true
    else false end
$$;

create or replace function app_private.can_access_organization(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
    and p_organization_id = app_private.current_organization_id()
    and exists (
      select 1 from public.user_scope_assignments usa
      join public.data_scopes ds on ds.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and usa.valid_from <= now() and (usa.valid_until is null or usa.valid_until > now())
        and ds.organization_id = p_organization_id
        and ds.scope_type in ('PLATFORM_SCOPE','REGION_SCOPE','COOPERATIVE_SCOPE','UNIT_SCOPE')
    )
$$;

create or replace function app_private.can_access_unit(p_organization_id uuid, p_unit_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select app_private.can_access_organization(p_organization_id)
    and exists (
      select 1 from public.user_scope_assignments usa
      join public.data_scopes ds on ds.id = usa.data_scope_id
      where usa.profile_id = app_private.current_profile_id()
        and usa.valid_from <= now() and (usa.valid_until is null or usa.valid_until > now())
        and ds.organization_id = p_organization_id
        and (ds.scope_type in ('PLATFORM_SCOPE','REGION_SCOPE','COOPERATIVE_SCOPE')
          or (ds.scope_type = 'UNIT_SCOPE' and ds.organization_unit_id = p_unit_id))
    )
$$;

revoke all on function app_private.current_profile_id() from public, anon;
revoke all on function app_private.current_organization_id() from public, anon;
revoke all on function app_private.has_permission(text) from public, anon;
revoke all on function app_private.can_access_organization(uuid) from public, anon;
revoke all on function app_private.can_access_unit(uuid,uuid) from public, anon;
grant usage on schema app_private to authenticated;
grant execute on function app_private.current_profile_id() to authenticated;
grant execute on function app_private.current_organization_id() to authenticated;
grant execute on function app_private.has_permission(text) to authenticated;
grant execute on function app_private.can_access_organization(uuid) to authenticated;
grant execute on function app_private.can_access_unit(uuid,uuid) to authenticated;

grant select on public.organizations, public.organization_nodes, public.organization_units,
  public.feature_modules, public.regulatory_authorizations, public.profiles,
  public.user_roles, public.data_scopes, public.user_scope_assignments, public.audit_logs to authenticated;

drop policy if exists organizations_select_current_scope on public.organizations;
create policy organizations_select_current_scope on public.organizations for select to authenticated
using ((select app_private.can_access_organization(id)));

drop policy if exists organization_nodes_select_current_scope on public.organization_nodes;
create policy organization_nodes_select_current_scope on public.organization_nodes for select to authenticated
using ((select app_private.can_access_organization(organization_id)));

drop policy if exists organization_units_select_current_scope on public.organization_units;
create policy organization_units_select_current_scope on public.organization_units for select to authenticated
using ((select app_private.can_access_unit(organization_id, id)));

drop policy if exists feature_modules_select_current_scope on public.feature_modules;
create policy feature_modules_select_current_scope on public.feature_modules for select to authenticated
using ((select app_private.can_access_organization(organization_id))
  and (organization_unit_id is null or (select app_private.can_access_unit(organization_id, organization_unit_id))));

drop policy if exists regulatory_authorizations_select_current_scope on public.regulatory_authorizations;
create policy regulatory_authorizations_select_current_scope on public.regulatory_authorizations for select to authenticated
using ((select app_private.can_access_organization(organization_id))
  and (select app_private.has_permission('CONTROL_REVIEW'))
  and (organization_unit_id is null or (select app_private.can_access_unit(organization_id, organization_unit_id))));

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_org_with_user_view on public.profiles;
drop policy if exists profiles_select_scoped on public.profiles;
create policy profiles_select_scoped on public.profiles for select to authenticated
using (auth_user_id = (select auth.uid()) or
  (organization_id = (select app_private.current_organization_id()) and (select app_private.has_permission('USER_VIEW'))));

drop policy if exists user_roles_select_own on public.user_roles;
drop policy if exists user_roles_select_org_with_user_view on public.user_roles;
drop policy if exists user_roles_select_scoped on public.user_roles;
create policy user_roles_select_scoped on public.user_roles for select to authenticated
using (profile_id = (select app_private.current_profile_id()) or
  ((select app_private.has_permission('USER_VIEW')) and profile_id in (
    select p.id from public.profiles p where p.organization_id = (select app_private.current_organization_id())
  )));

drop policy if exists data_scopes_select_assigned on public.data_scopes;
drop policy if exists data_scopes_select_org_with_user_view on public.data_scopes;
drop policy if exists data_scopes_select_scoped on public.data_scopes;
create policy data_scopes_select_scoped on public.data_scopes for select to authenticated
using (id in (
    select usa.data_scope_id from public.user_scope_assignments usa
    where usa.profile_id = (select app_private.current_profile_id())
      and usa.valid_from <= now() and (usa.valid_until is null or usa.valid_until > now())
  ) or (organization_id = (select app_private.current_organization_id())
    and ((select app_private.has_permission('USER_VIEW')) or (select app_private.has_permission('SCOPE_ASSIGN')))));

drop policy if exists user_scope_assignments_select_own on public.user_scope_assignments;
drop policy if exists user_scope_assignments_select_org_with_user_view on public.user_scope_assignments;
drop policy if exists user_scope_assignments_select_scoped on public.user_scope_assignments;
create policy user_scope_assignments_select_scoped on public.user_scope_assignments for select to authenticated
using (profile_id = (select app_private.current_profile_id()) or
  (((select app_private.has_permission('USER_VIEW')) or (select app_private.has_permission('SCOPE_ASSIGN')))
   and profile_id in (
     select p.id from public.profiles p where p.organization_id = (select app_private.current_organization_id())
   )));

drop policy if exists audit_logs_select_current_org on public.audit_logs;
create policy audit_logs_select_current_org on public.audit_logs for select to authenticated
using (organization_id = (select app_private.current_organization_id()) and (select app_private.has_permission('AUDIT_VIEW')));

create index if not exists idx_feature_modules_org_enabled on public.feature_modules(organization_id, enabled);
create index if not exists idx_regulatory_authorizations_org_status on public.regulatory_authorizations(organization_id, status);
create index if not exists idx_profiles_org_status on public.profiles(organization_id, status);
