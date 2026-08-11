revoke all on table public.organizations from anon, authenticated;
revoke all on table public.organization_nodes from anon, authenticated;
revoke all on table public.organization_units from anon, authenticated;
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.roles from anon, authenticated;
revoke all on table public.permissions from anon, authenticated;
revoke all on table public.role_permissions from anon, authenticated;
revoke all on table public.user_roles from anon, authenticated;
revoke all on table public.user_permissions from anon, authenticated;
revoke all on table public.data_scopes from anon, authenticated;
revoke all on table public.user_scope_assignments from anon, authenticated;
revoke all on table public.feature_modules from anon, authenticated;
revoke all on table public.regulatory_authorizations from anon, authenticated;
revoke all on table public.audit_logs from anon, authenticated;

grant select on table public.profiles to authenticated;
grant select on table public.roles to authenticated;
grant select on table public.permissions to authenticated;

comment on table public.roles is 'Role catalog is readable by authenticated users; mutations require trusted server workflows.';
comment on table public.permissions is 'Permission catalog is readable by authenticated users; mutations require trusted server workflows.';
