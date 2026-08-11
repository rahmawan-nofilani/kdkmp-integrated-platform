insert into public.permissions(code, domain, description, is_privileged)
values
('GOVERNANCE_VIEW','COOPERATIVE_CORE','View governance bodies, positions, and assignments',false),
('GOVERNANCE_RECORD_MAINTAIN','COOPERATIVE_CORE','Maintain governance master records without changing application roles',true),
('RAT_VIEW','COOPERATIVE_CORE','View RAT/general meeting records',false),
('RAT_RECORD_MAINTAIN','COOPERATIVE_CORE','Maintain RAT/general meeting records and evidence',true),
('RAT_DECIDE','COOPERATIVE_CORE','Record/finalize governance decisions according to approved workflow',true),
('SHU_VIEW','COOPERATIVE_CORE','View SHU policy and period records',false),
('SHU_POLICY_DRAFT','COOPERATIVE_CORE','Draft versioned SHU policy configuration',true),
('SHU_APPROVE','COOPERATIVE_CORE','Approve SHU policy/period according to governance workflow',true)
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code in ('GOVERNANCE_VIEW','GOVERNANCE_RECORD_MAINTAIN','RAT_VIEW','RAT_RECORD_MAINTAIN','SHU_VIEW','SHU_POLICY_DRAFT') where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code in ('GOVERNANCE_VIEW','GOVERNANCE_RECORD_MAINTAIN','RAT_VIEW','RAT_RECORD_MAINTAIN','RAT_DECIDE','SHU_VIEW','SHU_POLICY_DRAFT','SHU_APPROVE') where r.code='BOARD' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code in ('GOVERNANCE_VIEW','RAT_VIEW','SHU_VIEW') where r.code in ('SUPERVISOR','COMPLIANCE_OFFICER') on conflict do nothing;

create table public.governance_bodies (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null, name text not null, body_type text not null check (body_type in ('BOARD','SUPERVISORY_BOARD','COMMITTEE','OTHER')),
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')), effective_from date, effective_until date, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id, code)
);
create table public.governance_positions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  governance_body_id uuid not null references public.governance_bodies(id) on delete restrict, code text not null, name text not null,
  position_type text not null default 'OTHER' check (position_type in ('CHAIR','VICE_CHAIR','SECRETARY','TREASURER','MEMBER','OTHER')),
  sort_order integer not null default 100, status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (governance_body_id, code)
);
create table public.governance_assignments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  governance_body_id uuid not null references public.governance_bodies(id) on delete restrict,
  governance_position_id uuid not null references public.governance_positions(id) on delete restrict,
  member_id uuid references public.members(id) on delete restrict, profile_id uuid references public.profiles(id) on delete restrict,
  person_name_snapshot text not null, term_start date, term_end date,
  status text not null default 'PLANNED' check (status in ('PLANNED','ACTIVE','SUSPENDED','ENDED','ARCHIVED')),
  appointment_reference text, notes text, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index idx_governance_bodies_org on public.governance_bodies(organization_id,status);
create index idx_governance_positions_body on public.governance_positions(governance_body_id,sort_order);
create index idx_governance_assignments_org_status on public.governance_assignments(organization_id,status);
create index idx_governance_assignments_member on public.governance_assignments(member_id);

create table public.general_meetings (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null, title text not null, meeting_type text not null default 'RAT' check (meeting_type in ('RAT','SPECIAL','OTHER')),
  period_year integer check (period_year between 1900 and 2200), status text not null default 'DRAFT' check (status in ('DRAFT','SCHEDULED','OPEN','CLOSED','ARCHIVED')),
  scheduled_at timestamptz, held_at timestamptz, venue text, notes text, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,code)
);
create table public.meeting_agendas (
  id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.general_meetings(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, sequence_no integer not null, title text not null, description text,
  status text not null default 'DRAFT' check (status in ('DRAFT','READY','DISCUSSED','CLOSED','ARCHIVED')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (meeting_id,sequence_no)
);
create table public.meeting_attendance (
  id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.general_meetings(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, member_id uuid not null references public.members(id) on delete restrict,
  attendance_status text not null default 'INVITED' check (attendance_status in ('INVITED','PRESENT','ABSENT','REPRESENTED')),
  check_in_at timestamptz, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(meeting_id,member_id)
);
create table public.meeting_resolutions (
  id uuid primary key default gen_random_uuid(), meeting_id uuid not null references public.general_meetings(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, resolution_number text, title text not null, decision_text text,
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','SUPERSEDED','ARCHIVED')), decided_at timestamptz,
  created_by uuid references public.profiles(id) on delete restrict, approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index idx_general_meetings_org_status on public.general_meetings(organization_id,status,period_year desc);
create index idx_meeting_agendas_meeting on public.meeting_agendas(meeting_id,sequence_no);
create index idx_meeting_attendance_meeting on public.meeting_attendance(meeting_id,attendance_status);
create index idx_meeting_resolutions_meeting on public.meeting_resolutions(meeting_id,status);

create table public.shu_policies (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null, name text not null, status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','SUPERSEDED','ARCHIVED')),
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(organization_id,code)
);
create table public.shu_policy_versions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  shu_policy_id uuid not null references public.shu_policies(id) on delete restrict, version_no integer not null check (version_no>0),
  effective_from date, effective_until date, configuration jsonb not null default '{}'::jsonb, legal_basis text,
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVED','ACTIVE','SUPERSEDED','ARCHIVED')),
  created_by uuid references public.profiles(id) on delete restrict, approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), approved_at timestamptz, unique(shu_policy_id,version_no)
);
create table public.shu_periods (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  fiscal_year integer not null check (fiscal_year between 1900 and 2200), shu_policy_version_id uuid references public.shu_policy_versions(id) on delete restrict,
  status text not null default 'DRAFT' check (status in ('DRAFT','OPEN','CALCULATED','APPROVED','DISTRIBUTED','CLOSED')),
  calculation_snapshot jsonb, notes text, created_by uuid references public.profiles(id) on delete restrict, approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), approved_at timestamptz, unique(organization_id,fiscal_year)
);
create index idx_shu_policies_org on public.shu_policies(organization_id,status);
create index idx_shu_policy_versions_policy on public.shu_policy_versions(shu_policy_id,version_no desc);
create index idx_shu_periods_org_year on public.shu_periods(organization_id,fiscal_year desc);

alter table public.governance_bodies enable row level security; alter table public.governance_positions enable row level security; alter table public.governance_assignments enable row level security;
alter table public.general_meetings enable row level security; alter table public.meeting_agendas enable row level security; alter table public.meeting_attendance enable row level security; alter table public.meeting_resolutions enable row level security;
alter table public.shu_policies enable row level security; alter table public.shu_policy_versions enable row level security; alter table public.shu_periods enable row level security;

revoke all on public.governance_bodies,public.governance_positions,public.governance_assignments,public.general_meetings,public.meeting_agendas,public.meeting_attendance,public.meeting_resolutions,public.shu_policies,public.shu_policy_versions,public.shu_periods from anon,authenticated;
grant select on public.governance_bodies,public.governance_positions,public.governance_assignments,public.general_meetings,public.meeting_agendas,public.meeting_attendance,public.meeting_resolutions,public.shu_policies,public.shu_policy_versions,public.shu_periods to authenticated;

create policy governance_bodies_select_scoped on public.governance_bodies for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id));
create policy governance_positions_select_scoped on public.governance_positions for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id));
create policy governance_assignments_select_scoped on public.governance_assignments for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id));
create policy general_meetings_select_scoped on public.general_meetings for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id));
create policy meeting_agendas_select_scoped on public.meeting_agendas for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id));
create policy meeting_attendance_select_scoped on public.meeting_attendance for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id));
create policy meeting_resolutions_select_scoped on public.meeting_resolutions for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id));
create policy shu_policies_select_scoped on public.shu_policies for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id));
create policy shu_policy_versions_select_scoped on public.shu_policy_versions for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id));
create policy shu_periods_select_scoped on public.shu_periods for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id));

comment on table public.governance_assignments is 'Historical governance assignment. Organizational position is separate from application role/permission.';
comment on table public.shu_policy_versions is 'Versioned SHU configuration foundation. Formula/legal basis remain pending final organizational and regulatory validation.';
comment on table public.shu_periods is 'SHU period lifecycle foundation; calculation/distribution engine is not implemented in this migration.';