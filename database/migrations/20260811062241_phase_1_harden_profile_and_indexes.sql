drop policy if exists "profiles_update_own_basic" on public.profiles;

create index if not exists idx_data_scopes_organization_id on public.data_scopes(organization_id);
create index if not exists idx_data_scopes_organization_node_id on public.data_scopes(organization_node_id);
create index if not exists idx_data_scopes_organization_unit_id on public.data_scopes(organization_unit_id);
create index if not exists idx_feature_modules_organization_unit_id on public.feature_modules(organization_unit_id);
create index if not exists idx_regulatory_authorizations_organization_id on public.regulatory_authorizations(organization_id);
create index if not exists idx_regulatory_authorizations_organization_unit_id on public.regulatory_authorizations(organization_unit_id);
create index if not exists idx_role_permissions_permission_id on public.role_permissions(permission_id);
create index if not exists idx_user_permissions_assigned_by on public.user_permissions(assigned_by);
create index if not exists idx_user_permissions_permission_id on public.user_permissions(permission_id);
create index if not exists idx_user_roles_assigned_by on public.user_roles(assigned_by);
create index if not exists idx_user_roles_role_id on public.user_roles(role_id);
create index if not exists idx_user_scope_assignments_assigned_by on public.user_scope_assignments(assigned_by);
create index if not exists idx_user_scope_assignments_data_scope_id on public.user_scope_assignments(data_scope_id);

comment on table public.profiles is 'Direct browser updates are denied in Phase 1. Profile mutations must use validated server-side workflows.';
