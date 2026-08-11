create table public.zero_cost_capacity_policies (
  id uuid primary key default gen_random_uuid(),
  policy_code text not null unique,
  database_normal_mb integer not null check (database_normal_mb > 0),
  database_warning_mb integer not null,
  database_archive_required_mb integer not null,
  database_critical_mb integer not null,
  database_emergency_mb integer not null,
  supabase_egress_target_mb integer not null,
  cloudflare_dynamic_target_per_day integer not null,
  r2_storage_target_mb integer not null,
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')),
  effective_from timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now(),
  check (database_warning_mb > database_normal_mb),
  check (database_archive_required_mb > database_warning_mb),
  check (database_critical_mb > database_archive_required_mb),
  check (database_emergency_mb > database_critical_mb)
);

create table public.system_capacity_snapshots (
  id uuid primary key default gen_random_uuid(),
  capacity_policy_id uuid not null references public.zero_cost_capacity_policies(id) on delete restrict,
  captured_at timestamptz not null default now(),
  database_bytes bigint not null check (database_bytes >= 0),
  database_mb numeric(14,2) not null check (database_mb >= 0),
  capacity_state text not null check (capacity_state in ('NORMAL','WARNING','ARCHIVE_REQUIRED','CRITICAL','EMERGENCY')),
  archive_bytes bigint not null default 0 check (archive_bytes >= 0),
  backup_status text not null default 'NOT_CONFIGURED' check (backup_status in ('NOT_CONFIGURED','PENDING','VERIFIED','FAILED','STALE')),
  archive_status text not null default 'NOT_CONFIGURED' check (archive_status in ('NOT_CONFIGURED','PENDING','VERIFIED','FAILED','STALE')),
  restore_test_status text not null default 'NOT_TESTED' check (restore_test_status in ('NOT_TESTED','PENDING','PASSED','FAILED','STALE')),
  source text not null default 'SYSTEM' check (source in ('MIGRATION','SYSTEM','SCHEDULED_JOB','MANUAL_INTERNAL')),
  notes text,
  created_at timestamptz not null default now()
);

create index idx_system_capacity_snapshots_captured on public.system_capacity_snapshots(captured_at desc);
create index idx_system_capacity_snapshots_policy on public.system_capacity_snapshots(capacity_policy_id,captured_at desc);

alter table public.zero_cost_capacity_policies enable row level security;
alter table public.system_capacity_snapshots enable row level security;

insert into public.permissions(code,domain,description,is_privileged)
values ('SYSTEM_CAPACITY_VIEW','SYSTEM','View Zero-Cost Mode capacity, backup and archive readiness metrics',false)
on conflict (code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.code='SYSTEM_CAPACITY_VIEW'
where r.code in ('MANAGER','SUPERVISOR')
on conflict do nothing;

create policy zero_cost_capacity_policy_read
on public.zero_cost_capacity_policies
for select to authenticated
using (public.has_permission('SYSTEM_CAPACITY_VIEW'));

create policy system_capacity_snapshots_read
on public.system_capacity_snapshots
for select to authenticated
using (public.has_permission('SYSTEM_CAPACITY_VIEW'));

grant select on public.zero_cost_capacity_policies,public.system_capacity_snapshots to authenticated;
revoke insert,update,delete on public.zero_cost_capacity_policies,public.system_capacity_snapshots from anon,authenticated;

create or replace function app_private.prevent_capacity_snapshot_mutation()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'system_capacity_snapshot_is_append_only';
end;
$$;
revoke all on function app_private.prevent_capacity_snapshot_mutation() from public,anon,authenticated;

create trigger trg_system_capacity_snapshot_immutable
before update or delete on public.system_capacity_snapshots
for each row execute function app_private.prevent_capacity_snapshot_mutation();

insert into public.zero_cost_capacity_policies(
  policy_code,database_normal_mb,database_warning_mb,database_archive_required_mb,database_critical_mb,database_emergency_mb,
  supabase_egress_target_mb,cloudflare_dynamic_target_per_day,r2_storage_target_mb,status,effective_from,notes
) values (
  'ZERO_COST_V1',300,350,400,450,475,3500,50000,8192,'ACTIVE',now(),
  'Engineering guardrails for initial Zero-Cost Mode. Provider limits must be re-verified before production cutover.'
)
on conflict (policy_code) do nothing;

do $$
declare
  v_policy public.zero_cost_capacity_policies%rowtype;
  v_bytes bigint;
  v_mb numeric(14,2);
  v_state text;
begin
  select * into v_policy from public.zero_cost_capacity_policies where policy_code='ZERO_COST_V1' limit 1;
  v_bytes := pg_database_size(current_database());
  v_mb := round((v_bytes::numeric/1024/1024),2);
  v_state := case
    when v_mb < v_policy.database_normal_mb then 'NORMAL'
    when v_mb < v_policy.database_warning_mb then 'WARNING'
    when v_mb < v_policy.database_archive_required_mb then 'ARCHIVE_REQUIRED'
    when v_mb < v_policy.database_critical_mb then 'CRITICAL'
    else 'EMERGENCY'
  end;

  insert into public.system_capacity_snapshots(
    capacity_policy_id,database_bytes,database_mb,capacity_state,archive_bytes,backup_status,archive_status,restore_test_status,source,notes
  ) values (
    v_policy.id,v_bytes,v_mb,v_state,0,'NOT_CONFIGURED','NOT_CONFIGURED','NOT_TESTED','MIGRATION',
    'Initial Zero-Cost Mode baseline snapshot. Archive/backup providers not configured yet.'
  );
end $$;