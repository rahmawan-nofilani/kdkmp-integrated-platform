-- Explicit ACL hardening for private reversal/period-close helpers.
-- Public RPC wrappers remain the only exposed API surface. Authenticated callers
-- retain helper EXECUTE only because SECURITY INVOKER wrappers delegate to these
-- bounded SECURITY DEFINER helpers through the private schema.

revoke all on function app_private.create_manual_journal_reversal_draft(uuid,uuid,date,text,text) from public,anon;
revoke all on function app_private.validate_manual_journal_reversal(uuid,text,text) from public,anon;
revoke all on function app_private.authorize_manual_journal_reversal(uuid,text,text,boolean) from public,anon;
revoke all on function app_private.post_manual_journal_reversal(uuid,text,text) from public,anon;
revoke all on function app_private.soft_close_accounting_period(uuid,text,text) from public,anon;
revoke all on function app_private.hard_close_accounting_period(uuid,text,text,boolean) from public,anon;

grant execute on function app_private.create_manual_journal_reversal_draft(uuid,uuid,date,text,text) to authenticated,service_role;
grant execute on function app_private.validate_manual_journal_reversal(uuid,text,text) to authenticated,service_role;
grant execute on function app_private.authorize_manual_journal_reversal(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function app_private.post_manual_journal_reversal(uuid,text,text) to authenticated,service_role;
grant execute on function app_private.soft_close_accounting_period(uuid,text,text) to authenticated,service_role;
grant execute on function app_private.hard_close_accounting_period(uuid,text,text,boolean) to authenticated,service_role;

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='app_private'
      and p.proname in (
        'create_manual_journal_reversal_draft','validate_manual_journal_reversal',
        'authorize_manual_journal_reversal','post_manual_journal_reversal',
        'soft_close_accounting_period','hard_close_accounting_period'
      )
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then raise exception 'ACCOUNTING_PRIVATE_HELPER_ANON_EXECUTE_PRESENT'; end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'create_manual_journal_reversal_draft','validate_manual_journal_reversal',
        'authorize_manual_journal_reversal','post_manual_journal_reversal',
        'soft_close_accounting_period','hard_close_accounting_period'
      )
      and p.prosecdef
  ) then raise exception 'ACCOUNTING_PUBLIC_RPC_MUST_REMAIN_INVOKER'; end if;
end $$;
