grant select on table public.user_permissions to authenticated;
grant select on table public.role_permissions to authenticated;

create policy "user_permissions_select_own"
on public.user_permissions
for select
to authenticated
using (
  profile_id in (
    select p.id
    from public.profiles p
    where p.auth_user_id = (select auth.uid())
  )
);

create policy "role_permissions_select_own_roles"
on public.role_permissions
for select
to authenticated
using (
  role_id in (
    select ur.role_id
    from public.user_roles ur
    join public.profiles p on p.id = ur.profile_id
    where p.auth_user_id = (select auth.uid())
  )
);

create index if not exists idx_user_permissions_resolution
  on public.user_permissions(profile_id, permission_id, effect, valid_from, valid_until);

create index if not exists idx_user_roles_resolution
  on public.user_roles(profile_id, role_id, valid_from, valid_until);

create or replace function public.has_permission(p_permission_code text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  with current_profile as (
    select p.id
    from public.profiles p
    where p.auth_user_id = (select auth.uid())
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

revoke all on function public.has_permission(text) from public;
revoke all on function public.has_permission(text) from anon;
grant execute on function public.has_permission(text) to authenticated;

comment on function public.has_permission(text) is
'Permission resolution for current authenticated user. Precedence: active explicit DENY, active explicit ALLOW, then active role permission. Requires ACTIVE profile.';
