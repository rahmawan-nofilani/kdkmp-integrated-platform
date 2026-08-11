create table public.system_backup_runs (
  id uuid primary key default gen_random_uuid(),
  backup_run_number text not null unique,
  backup_type text not null default 'FULL_LOGICAL' check (backup_type in ('FULL_LOGICAL','MANUAL_LOGICAL')),
  retention_class text not null check (retention_class in ('DAILY','WEEKLY','MONTHLY','MANUAL')),
  status text not null default 'REQUESTED' check (status in ('REQUESTED','RUNNING','UPLOADED','VERIFIED','FAILED','CANCELLED')),
  storage_provider text not null default 'UNASSIGNED' check (storage_provider in ('UNASSIGNED','CLOUDFLARE_R2','GITHUB_ARTIFACT','MANUAL_OFFSITE')),
  object_key text,
  encrypted boolean not null default true,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  manifest jsonb not null default '{}'::jsonb,
  source text not null default 'GITHUB_ACTIONS' check (source in ('GITHUB_ACTIONS','MANUAL','OTHER')),
  started_at timestamptz,
  uploaded_at timestamptz,
  verified_at timestamptz,
  completed_at timestamptz,
  error_summary text,
  created_at timestamptz not null default now()
);

create table public.system_restore_tests (
  id uuid primary key default gen_random_uuid(),
  backup_run_id uuid not null references public.system_backup_runs(id) on delete restrict,
  restore_test_number text not null unique,
  status text not null default 'REQUESTED' check (status in ('REQUESTED','RUNNING','PASSED','FAILED','CANCELLED')),
  target_type text not null check (target_type in ('TEMPORARY_LOCAL','TEMPORARY_PROJECT','OTHER')),
  row_count_checks jsonb not null default '{}'::jsonb,
  integrity_checks jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  notes text,
  error_summary text,
  created_at timestamptz not null default now()
);

create index idx_system_backup_runs_created on public.system_backup_runs(created_at desc);
create index idx_system_backup_runs_status_retention on public.system_backup_runs(status,retention_class,created_at desc);
create index idx_system_restore_tests_backup on public.system_restore_tests(backup_run_id,created_at desc);

alter table public.system_backup_runs enable row level security;
alter table public.system_restore_tests enable row level security;

create policy system_backup_runs_read
on public.system_backup_runs
for select to authenticated
using (public.has_permission('SYSTEM_CAPACITY_VIEW'));

create policy system_restore_tests_read
on public.system_restore_tests
for select to authenticated
using (public.has_permission('SYSTEM_CAPACITY_VIEW'));

grant select on public.system_backup_runs,public.system_restore_tests to authenticated;
revoke insert,update,delete on public.system_backup_runs,public.system_restore_tests from anon,authenticated;

create or replace function app_private.guard_system_backup_run_transition()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.status in ('VERIFIED','FAILED','CANCELLED') and new is distinct from old then
    raise exception 'terminal_backup_run_is_immutable';
  end if;

  if old.status <> new.status then
    if old.status='REQUESTED' and new.status not in ('RUNNING','FAILED','CANCELLED') then
      raise exception 'invalid_backup_status_transition';
    elsif old.status='RUNNING' and new.status not in ('UPLOADED','FAILED','CANCELLED') then
      raise exception 'invalid_backup_status_transition';
    elsif old.status='UPLOADED' and new.status not in ('VERIFIED','FAILED') then
      raise exception 'invalid_backup_status_transition';
    end if;
  end if;

  if new.status='RUNNING' then
    new.started_at := coalesce(new.started_at,now());
  end if;

  if new.status in ('UPLOADED','VERIFIED') then
    if new.object_key is null or new.size_bytes is null or new.sha256 is null then
      raise exception 'uploaded_backup_requires_object_size_and_sha256';
    end if;
    new.uploaded_at := coalesce(new.uploaded_at,now());
  end if;

  if new.status='VERIFIED' then
    new.verified_at := coalesce(new.verified_at,now());
    new.completed_at := coalesce(new.completed_at,now());
  elsif new.status in ('FAILED','CANCELLED') then
    new.completed_at := coalesce(new.completed_at,now());
  end if;

  return new;
end;
$$;
revoke all on function app_private.guard_system_backup_run_transition() from public,anon,authenticated;
create trigger trg_guard_system_backup_run_transition
before update on public.system_backup_runs
for each row execute function app_private.guard_system_backup_run_transition();

create or replace function app_private.guard_system_restore_test_transition()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.status in ('PASSED','FAILED','CANCELLED') and new is distinct from old then
    raise exception 'terminal_restore_test_is_immutable';
  end if;

  if old.status <> new.status then
    if old.status='REQUESTED' and new.status not in ('RUNNING','FAILED','CANCELLED') then
      raise exception 'invalid_restore_test_status_transition';
    elsif old.status='RUNNING' and new.status not in ('PASSED','FAILED','CANCELLED') then
      raise exception 'invalid_restore_test_status_transition';
    end if;
  end if;

  if new.status='RUNNING' then
    new.started_at := coalesce(new.started_at,now());
  end if;

  if new.status in ('PASSED','FAILED','CANCELLED') then
    new.completed_at := coalesce(new.completed_at,now());
    if new.started_at is not null and new.duration_seconds is null then
      new.duration_seconds := greatest(0,extract(epoch from (new.completed_at-new.started_at))::integer);
    end if;
  end if;

  return new;
end;
$$;
revoke all on function app_private.guard_system_restore_test_transition() from public,anon,authenticated;
create trigger trg_guard_system_restore_test_transition
before update on public.system_restore_tests
for each row execute function app_private.guard_system_restore_test_transition();