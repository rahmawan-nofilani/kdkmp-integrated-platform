-- ZC-4B REVIEW DRAFT ONLY
--
-- THIS FILE IS NOT A SUPABASE MIGRATION AND MUST NOT BE APPLIED DIRECTLY.
-- It intentionally lives under database/drafts/ because the approved Supabase
-- migration generator is not available in the current execution environment.
--
-- Activation procedure:
--   1. use pinned/approved Supabase CLI and run:
--        supabase migration new zc4b_archive_registry_foundation
--   2. copy the reviewed SQL contract into the generated migration file;
--   3. run the migration against an isolated/local database first;
--   4. run security + performance advisors and verify RLS/grants;
--   5. commit the generated migration through a separate branch/PR/CI flow;
--   6. only after merge, apply the migration to DEVELOPMENT in a controlled step.
--
-- Safety invariants:
--   * metadata registry only; this draft does not archive/move/delete business data;
--   * no DELETE/prune/purge path is granted or implemented;
--   * ELIGIBLE_FOR_PRUNE is deliberately blocked until a later owner-authorized phase;
--   * Cloudflare R2 and paid storage remain NOT AUTHORIZED / NOT ACTIVATED;
--   * ordinary authenticated users receive SELECT only when permission + node scope pass.

create table public.system_archive_runs (
  id uuid primary key default gen_random_uuid(),
  archive_run_number text not null unique,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  archive_class text not null check (
    archive_class in (
      'POS_TRANSACTION',
      'ACCOUNTING_DETAIL',
      'INVENTORY_MOVEMENT',
      'PROCUREMENT_DETAIL',
      'LOGISTICS_DETAIL',
      'OTHER_CONTROLLED'
    )
  ),
  source_period_start timestamptz not null,
  source_period_end timestamptz not null,
  source_timezone text not null default 'Asia/Jakarta',
  source_schema_version text not null,
  application_commit_sha text not null,
  status text not null default 'REQUESTED' check (
    status in (
      'REQUESTED',
      'SNAPSHOTTED',
      'PACKAGED',
      'WRITTEN',
      'READBACK_VERIFIED',
      'RECOVERY_VERIFIED',
      'ELIGIBLE_FOR_PRUNE',
      'FAILED',
      'CANCELLED'
    )
  ),
  storage_provider text not null default 'UNASSIGNED' check (
    storage_provider in ('UNASSIGNED','MANUAL_OFFSITE','OTHER_APPROVED')
  ),
  object_key text,
  encrypted boolean not null default true,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  manifest jsonb not null default '{}'::jsonb,
  source_row_counts jsonb not null default '{}'::jsonb,
  reconciliation_checks jsonb not null default '{}'::jsonb,
  snapshotted_at timestamptz,
  packaged_at timestamptz,
  written_at timestamptz,
  readback_verified_at timestamptz,
  recovery_verified_at timestamptz,
  completed_at timestamptz,
  error_summary text,
  created_at timestamptz not null default now(),
  check (source_period_start < source_period_end)
);

create table public.system_archive_recovery_tests (
  id uuid primary key default gen_random_uuid(),
  archive_run_id uuid not null references public.system_archive_runs(id) on delete restrict,
  recovery_test_number text not null unique,
  status text not null default 'REQUESTED' check (
    status in ('REQUESTED','RUNNING','PASSED','FAILED','CANCELLED')
  ),
  target_type text not null check (
    target_type in ('TEMPORARY_LOCAL','TEMPORARY_READ_MODEL','OTHER')
  ),
  row_count_checks jsonb not null default '{}'::jsonb,
  integrity_checks jsonb not null default '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  notes text,
  error_summary text,
  created_at timestamptz not null default now()
);

-- Cover every new FK used by the registry so this foundation does not add to
-- the existing unindexed-FK advisor backlog.
create index idx_system_archive_runs_organization_created
  on public.system_archive_runs(organization_id, created_at desc);
create index idx_system_archive_runs_node_created
  on public.system_archive_runs(organization_node_id, created_at desc);
create index idx_system_archive_runs_status_class_period
  on public.system_archive_runs(status, archive_class, source_period_start desc);
create index idx_system_archive_recovery_tests_archive_created
  on public.system_archive_recovery_tests(archive_run_id, created_at desc);

alter table public.system_archive_runs enable row level security;
alter table public.system_archive_recovery_tests enable row level security;

-- Node-aware scope guard for archive metadata. REGION_SCOPE may see descendant
-- nodes of its assigned node; COOPERATIVE_SCOPE may see its assigned KDKMP node.
-- UNIT_SCOPE is intentionally not sufficient for cooperative-level archive metadata.
create or replace function app_private.can_access_archive_node(
  p_organization_id uuid,
  p_organization_node_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  with recursive target_lineage as (
    select n.id,n.parent_id,n.organization_id
    from public.organization_nodes n
    where n.id=p_organization_node_id
      and n.organization_id=p_organization_id

    union all

    select parent.id,parent.parent_id,parent.organization_id
    from public.organization_nodes parent
    join target_lineage child on child.parent_id=parent.id
    where parent.organization_id=p_organization_id
  ), active_scopes as (
    select ds.scope_type,ds.organization_node_id
    from public.user_scope_assignments usa
    join public.data_scopes ds on ds.id=usa.data_scope_id
    where usa.profile_id=app_private.current_profile_id()
      and usa.valid_from<=now()
      and (usa.valid_until is null or usa.valid_until>now())
      and ds.organization_id=p_organization_id
  )
  select (select auth.uid()) is not null
    and p_organization_id=app_private.current_organization_id()
    and exists (select 1 from target_lineage)
    and exists (
      select 1
      from active_scopes s
      where s.scope_type='PLATFORM_SCOPE'
         or (
           s.scope_type in ('REGION_SCOPE','COOPERATIVE_SCOPE')
           and s.organization_node_id in (select id from target_lineage)
         )
    )
$$;

revoke all on function app_private.can_access_archive_node(uuid,uuid)
  from public,anon;
grant execute on function app_private.can_access_archive_node(uuid,uuid)
  to authenticated;

-- Archive metadata requires both explicit permission and hierarchical node scope.
create policy system_archive_runs_read
on public.system_archive_runs
for select to authenticated
using (
  (select app_private.has_permission('SYSTEM_CAPACITY_VIEW'))
  and (select app_private.can_access_archive_node(organization_id,organization_node_id))
);

create policy system_archive_recovery_tests_read
on public.system_archive_recovery_tests
for select to authenticated
using (
  (select app_private.has_permission('SYSTEM_CAPACITY_VIEW'))
  and exists (
    select 1
    from public.system_archive_runs ar
    where ar.id=public.system_archive_recovery_tests.archive_run_id
  )
);

-- Fail closed for application users. Future trusted archive automation must use
-- the approved server/database execution path; it must not rely on client grants.
revoke all on public.system_archive_runs,public.system_archive_recovery_tests
  from anon,authenticated;
grant select on public.system_archive_runs,public.system_archive_recovery_tests
  to authenticated;

comment on table public.system_archive_runs is
  'ZC-4 archive metadata registry. Metadata only; does not authorize or perform hot-data pruning.';
comment on table public.system_archive_recovery_tests is
  'Controlled recovery/read-back evidence for ZC-4 archive packages.';

-- Enforce that the KDKMP/organization node belongs to the same organization.
create or replace function app_private.guard_system_archive_run_scope()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  v_node_organization_id uuid;
begin
  select n.organization_id
    into v_node_organization_id
  from public.organization_nodes n
  where n.id=new.organization_node_id;

  if v_node_organization_id is null
     or v_node_organization_id<>new.organization_id then
    raise exception 'archive_node_organization_mismatch';
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_system_archive_run_scope()
  from public,anon,authenticated;

create trigger trg_guard_system_archive_run_scope
before insert or update of organization_id,organization_node_id
on public.system_archive_runs
for each row execute function app_private.guard_system_archive_run_scope();

-- Archive state machine. RECOVERY_VERIFIED is terminal in this phase.
-- ELIGIBLE_FOR_PRUNE exists in the model but is deliberately unreachable until
-- a future owner-authorized migration adds legal/audit hold controls and unlocks it.
create or replace function app_private.guard_system_archive_run_transition()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if old.status in ('RECOVERY_VERIFIED','ELIGIBLE_FOR_PRUNE','FAILED','CANCELLED')
     and new is distinct from old then
    if old.status='RECOVERY_VERIFIED' and new.status='ELIGIBLE_FOR_PRUNE' then
      raise exception 'archive_prune_eligibility_not_activated';
    end if;
    raise exception 'terminal_archive_run_is_immutable';
  end if;

  if old.status<>new.status then
    if old.status='REQUESTED'
       and new.status not in ('SNAPSHOTTED','FAILED','CANCELLED') then
      raise exception 'invalid_archive_status_transition';
    elsif old.status='SNAPSHOTTED'
       and new.status not in ('PACKAGED','FAILED','CANCELLED') then
      raise exception 'invalid_archive_status_transition';
    elsif old.status='PACKAGED'
       and new.status not in ('WRITTEN','FAILED','CANCELLED') then
      raise exception 'invalid_archive_status_transition';
    elsif old.status='WRITTEN'
       and new.status not in ('READBACK_VERIFIED','FAILED') then
      raise exception 'invalid_archive_status_transition';
    elsif old.status='READBACK_VERIFIED'
       and new.status not in ('RECOVERY_VERIFIED','FAILED') then
      raise exception 'invalid_archive_status_transition';
    end if;
  end if;

  if new.status='SNAPSHOTTED' then
    new.snapshotted_at:=coalesce(new.snapshotted_at,now());
  end if;

  if new.status in ('PACKAGED','WRITTEN','READBACK_VERIFIED','RECOVERY_VERIFIED') then
    if new.encrypted is not true
       or new.size_bytes is null
       or new.sha256 is null
       or new.manifest='{}'::jsonb
       or new.source_row_counts='{}'::jsonb
       or new.reconciliation_checks='{}'::jsonb then
      raise exception 'archive_package_requires_integrity_metadata';
    end if;
    new.packaged_at:=coalesce(new.packaged_at,now());
  end if;

  if new.status in ('WRITTEN','READBACK_VERIFIED','RECOVERY_VERIFIED') then
    if new.storage_provider='UNASSIGNED' or new.object_key is null then
      raise exception 'written_archive_requires_destination_identity';
    end if;
    new.written_at:=coalesce(new.written_at,now());
  end if;

  if new.status in ('READBACK_VERIFIED','RECOVERY_VERIFIED') then
    new.readback_verified_at:=coalesce(new.readback_verified_at,now());
  end if;

  if new.status='RECOVERY_VERIFIED' then
    if not exists (
      select 1
      from public.system_archive_recovery_tests rt
      where rt.archive_run_id=new.id
        and rt.status='PASSED'
    ) then
      raise exception 'archive_recovery_verified_requires_passed_test';
    end if;
    new.recovery_verified_at:=coalesce(new.recovery_verified_at,now());
    new.completed_at:=coalesce(new.completed_at,now());
  elsif new.status in ('FAILED','CANCELLED') then
    new.completed_at:=coalesce(new.completed_at,now());
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_system_archive_run_transition()
  from public,anon,authenticated;

create trigger trg_guard_system_archive_run_transition
before update on public.system_archive_runs
for each row execute function app_private.guard_system_archive_run_transition();

create or replace function app_private.guard_system_archive_recovery_test_transition()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if old.status in ('PASSED','FAILED','CANCELLED')
     and new is distinct from old then
    raise exception 'terminal_archive_recovery_test_is_immutable';
  end if;

  if old.status<>new.status then
    if old.status='REQUESTED'
       and new.status not in ('RUNNING','FAILED','CANCELLED') then
      raise exception 'invalid_archive_recovery_status_transition';
    elsif old.status='RUNNING'
       and new.status not in ('PASSED','FAILED','CANCELLED') then
      raise exception 'invalid_archive_recovery_status_transition';
    end if;
  end if;

  if new.status='RUNNING' then
    new.started_at:=coalesce(new.started_at,now());
  end if;

  if new.status in ('PASSED','FAILED','CANCELLED') then
    new.completed_at:=coalesce(new.completed_at,now());
    if new.started_at is not null and new.duration_seconds is null then
      new.duration_seconds:=greatest(
        0,
        extract(epoch from (new.completed_at-new.started_at))::integer
      );
    end if;
  end if;

  return new;
end;
$$;

revoke all on function app_private.guard_system_archive_recovery_test_transition()
  from public,anon,authenticated;

create trigger trg_guard_system_archive_recovery_test_transition
before update on public.system_archive_recovery_tests
for each row execute function app_private.guard_system_archive_recovery_test_transition();
