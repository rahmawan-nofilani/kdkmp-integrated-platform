\set ON_ERROR_STOP on

-- Private helpers must not inherit PUBLIC/anon execute. Authenticated execution is
-- intentionally retained because public SECURITY INVOKER wrappers delegate to them.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='app_private'
      and p.proname in (
        'create_manual_journal_reversal_draft','validate_manual_journal_reversal',
        'authorize_manual_journal_reversal','post_manual_journal_reversal',
        'soft_close_accounting_period','hard_close_accounting_period'
      )
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then raise exception 'ACCOUNTING_PRIVATE_HELPER_ANON_EXECUTE_PRESENT'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='app_private'
      and p.proname in (
        'create_manual_journal_reversal_draft','validate_manual_journal_reversal',
        'authorize_manual_journal_reversal','post_manual_journal_reversal',
        'soft_close_accounting_period','hard_close_accounting_period'
      )
      and not has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) then raise exception 'ACCOUNTING_PRIVATE_HELPER_AUTHENTICATED_EXECUTE_MISSING'; end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'create_manual_journal_reversal_draft','validate_manual_journal_reversal',
        'authorize_manual_journal_reversal','post_manual_journal_reversal',
        'soft_close_accounting_period','hard_close_accounting_period'
      )
      and (p.prosecdef or has_function_privilege('anon',p.oid,'EXECUTE'))
  ) then raise exception 'ACCOUNTING_PUBLIC_RPC_ACL_INVALID'; end if;

  if has_schema_privilege('anon','app_private','USAGE') then
    raise exception 'ACCOUNTING_PRIVATE_SCHEMA_ANON_USAGE_PRESENT';
  end if;
end $$;
