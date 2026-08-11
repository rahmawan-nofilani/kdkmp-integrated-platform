create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  status text not null default 'ACTIVE' check (status in ('PENDING','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_nodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  parent_id uuid references public.organization_nodes(id) on delete restrict,
  node_type text not null check (node_type in ('PLATFORM','PROVINCE','REGENCY_CITY','DISTRICT','VILLAGE','KDKMP')),
  code text not null,
  name text not null,
  status text not null default 'ACTIVE' check (status in ('PENDING','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.organization_units (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  code text not null,
  name text not null,
  unit_type text not null,
  status text not null default 'ACTIVE' check (status in ('PENDING','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete restrict,
  organization_id uuid references public.organizations(id) on delete restrict,
  full_name text,
  phone text,
  status text not null default 'PENDING' check (status in ('PENDING','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  is_privileged boolean not null default false,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  domain text not null,
  description text,
  is_privileged boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete restrict,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  role_id uuid not null references public.roles(id) on delete restrict,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  assigned_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (profile_id, role_id, valid_from)
);

create table public.user_permissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  permission_id uuid not null references public.permissions(id) on delete restrict,
  effect text not null check (effect in ('ALLOW','DENY')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  assigned_by uuid references public.profiles(id) on delete restrict,
  reason text,
  created_at timestamptz not null default now()
);

create table public.data_scopes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  organization_node_id uuid references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  scope_type text not null check (scope_type in ('PLATFORM_SCOPE','REGION_SCOPE','COOPERATIVE_SCOPE','UNIT_SCOPE','OWN_DATA_ONLY','ASSIGNED_RECORDS_ONLY')),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.user_scope_assignments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  data_scope_id uuid not null references public.data_scopes(id) on delete restrict,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  assigned_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (profile_id, data_scope_id, valid_from)
);

create table public.feature_modules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  module_code text not null,
  enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, organization_unit_id, module_code)
);

create table public.regulatory_authorizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  module_code text not null,
  authorization_type text not null,
  authorization_number text,
  issuing_authority text,
  effective_date date,
  expiry_date date,
  status text not null default 'PENDING_VALIDATION' check (status in ('DRAFT','PENDING_VALIDATION','ACTIVE','SUSPENDED','EXPIRED','SUPERSEDED')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  actor_profile_id uuid references public.profiles(id) on delete restrict,
  action_code text not null,
  entity_type text,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  reason text,
  request_id text,
  session_id text,
  source_ip inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index idx_org_nodes_parent on public.organization_nodes(parent_id);
create index idx_org_units_node on public.organization_units(organization_node_id);
create index idx_profiles_org on public.profiles(organization_id);
create index idx_user_roles_profile on public.user_roles(profile_id);
create index idx_user_permissions_profile on public.user_permissions(profile_id);
create index idx_scope_assignments_profile on public.user_scope_assignments(profile_id);
create index idx_audit_logs_org_created on public.audit_logs(organization_id, created_at desc);
create index idx_audit_logs_actor_created on public.audit_logs(actor_profile_id, created_at desc);

alter table public.organizations enable row level security;
alter table public.organization_nodes enable row level security;
alter table public.organization_units enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.user_permissions enable row level security;
alter table public.data_scopes enable row level security;
alter table public.user_scope_assignments enable row level security;
alter table public.feature_modules enable row level security;
alter table public.regulatory_authorizations enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles_select_own" on public.profiles
for select to authenticated
using ((select auth.uid()) = auth_user_id);

create policy "profiles_update_own_basic" on public.profiles
for update to authenticated
using ((select auth.uid()) = auth_user_id)
with check ((select auth.uid()) = auth_user_id);

create policy "roles_read_authenticated" on public.roles
for select to authenticated
using (true);

create policy "permissions_read_authenticated" on public.permissions
for select to authenticated
using (true);

comment on table public.regulatory_authorizations is 'Regulatory details are placeholders until validated against official KDKMP and applicable sector regulations.';
comment on table public.audit_logs is 'Append-only from normal application flows; no authenticated UPDATE/DELETE policies should be created.';
