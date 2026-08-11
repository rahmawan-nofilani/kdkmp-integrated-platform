revoke all on public.system_backup_runs,public.system_restore_tests from anon,authenticated;
grant select on public.system_backup_runs,public.system_restore_tests to authenticated;
