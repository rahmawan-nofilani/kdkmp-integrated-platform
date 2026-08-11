grant select on table public.user_roles to authenticated;

create policy "user_roles_select_own" on public.user_roles
for select to authenticated
using (
  profile_id in (
    select p.id
    from public.profiles p
    where p.auth_user_id = (select auth.uid())
  )
);

comment on table public.user_roles is 'Authenticated users may read only their own role assignments; role mutations require trusted server workflows.';
