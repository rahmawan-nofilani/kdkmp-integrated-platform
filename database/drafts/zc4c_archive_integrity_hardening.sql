-- ZC-4C REVIEW DRAFT ONLY
--
-- THIS FILE IS NOT A SUPABASE MIGRATION AND MUST NOT BE APPLIED DIRECTLY.
-- It is the reviewed SQL contract used by the pinned Supabase CLI generator proof.
--
-- Safety invariants:
--   * hardens archive metadata validation only;
--   * no business-row archive execution or data movement;
--   * no DELETE, prune, purge, partition detach/drop, or vacuum-reclaim path;
--   * no archive destination, R2, paid storage, or billing activation;
--   * ELIGIBLE_FOR_PRUNE remains unreachable;
--   * ordinary authenticated users remain read-only through the existing RLS contract.

-- A packaged archive cannot claim a zero-byte payload. The original >= 0
-- constraint remains compatible; this stricter defense-in-depth constraint
-- makes a non-null package size positive.
alter table public.system_archive_runs
  add constraint system_archive_runs_size_bytes_positive
  check (size_bytes is null or size_bytes > 0);

-- A destination identity cannot be represented by an empty/whitespace key.
alter table public.system_archive_runs
  add constraint system_archive_runs_object_key_nonblank
  check (object_key is null or btrim(object_key) <> '');

-- PASSED recovery evidence has a version-1 minimum portable contract:
-- row counts must match, encrypted-package SHA must match, and the payload must
-- have been decryptable. Archive-class-specific checks may add more evidence.
alter table public.system_archive_recovery_tests
  add constraint system_archive_recovery_tests_passed_evidence
  check (
    status <> 'PASSED'
    or (
      jsonb_typeof(row_count_checks) = 'object'
      and row_count_checks @> '{"row_counts_match": true}'::jsonb
      and jsonb_typeof(integrity_checks) = 'object'
      and integrity_checks @> '{"sha256_match": true, "decryptable": true}'::jsonb
    )
  );

-- Harden the archive run state machine with explicit positive-size and
-- non-blank destination checks while preserving all ZC-4B transition rules.
create or replace function app_private.guard_system_archive_run_transition()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op='INSERT' then
    if new.status<>'REQUESTED' then
      raise exception 'archive_run_must_start_requested';
    end if;
    return new;
  end if;

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
       or new.sha256 is null
       or new.manifest='{}'::jsonb
       or new.source_row_counts='{}'::jsonb
       or new.reconciliation_checks='{}'::jsonb then
      raise exception 'archive_package_requires_integrity_metadata';
    end if;

    if new.size_bytes is null or new.size_bytes <= 0 then
      raise exception 'archive_package_requires_positive_size';
    end if;

    new.packaged_at:=coalesce(new.packaged_at,now());
  end if;

  if new.status in ('WRITTEN','READBACK_VERIFIED','RECOVERY_VERIFIED') then
    if new.storage_provider='UNASSIGNED'
       or new.object_key is null
       or btrim(new.object_key)='' then
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

-- Harden PASSED recovery transitions so empty or failed evidence cannot be
-- promoted into archive RECOVERY_VERIFIED eligibility.
create or replace function app_private.guard_system_archive_recovery_test_transition()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if tg_op='INSERT' then
    if new.status<>'REQUESTED' then
      raise exception 'archive_recovery_test_must_start_requested';
    end if;
    return new;
  end if;

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

  if new.status='PASSED' then
    if jsonb_typeof(new.row_count_checks)<>'object'
       or not (new.row_count_checks @> '{"row_counts_match": true}'::jsonb)
       or jsonb_typeof(new.integrity_checks)<>'object'
       or not (
         new.integrity_checks @> '{"sha256_match": true, "decryptable": true}'::jsonb
       ) then
      raise exception 'archive_recovery_passed_requires_evidence';
    end if;
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

comment on constraint system_archive_runs_size_bytes_positive
  on public.system_archive_runs is
  'ZC-4C: non-null archive package sizes must be strictly positive.';
comment on constraint system_archive_runs_object_key_nonblank
  on public.system_archive_runs is
  'ZC-4C: destination object identity cannot be empty or whitespace.';
comment on constraint system_archive_recovery_tests_passed_evidence
  on public.system_archive_recovery_tests is
  'ZC-4C: PASSED requires row-count match, package SHA match, and decryptability evidence.';
