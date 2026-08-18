\set ON_ERROR_STOP on

-- Disposable/local-CI-only fixture. The focused rollback test needs two posting
-- accounts but must not depend on the DEVELOPMENT-only POS accounting seed,
-- which requires an operational manager profile. These rows live only in the
-- local Supabase container used by POS Cash Reversal CI.

insert into public.accounting_accounts(
  organization_id,organization_node_id,code,name,account_class,normal_balance,
  is_posting,is_control_account,status,effective_from,notes
)
select
  o.id,n.id,'110100','CI — Kas POS','ASSET','DEBIT',true,false,'ACTIVE',current_date,
  'Disposable POS cash reversal CI fixture'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code='DEMO-KDKMP'
where o.code='DEMO-KDKMP-DEV'
on conflict (organization_node_id,code) do nothing;

insert into public.accounting_accounts(
  organization_id,organization_node_id,code,name,account_class,normal_balance,
  is_posting,is_control_account,status,effective_from,notes
)
select
  o.id,n.id,'410100','CI — Pendapatan POS','REVENUE','CREDIT',true,false,'ACTIVE',current_date,
  'Disposable POS cash reversal CI fixture'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code='DEMO-KDKMP'
where o.code='DEMO-KDKMP-DEV'
on conflict (organization_node_id,code) do nothing;

-- Fail loudly if the baseline DEMO scope was not reconstructed by migrations.
do $$
begin
  if not exists(
    select 1 from public.accounting_accounts a
    join public.organization_nodes n on n.id=a.organization_node_id and n.code='DEMO-KDKMP'
    where a.code='110100' and a.status='ACTIVE' and a.is_posting
  ) then raise exception 'POS_REVERSAL_CI_CASH_ACCOUNT_MISSING'; end if;
  if not exists(
    select 1 from public.accounting_accounts a
    join public.organization_nodes n on n.id=a.organization_node_id and n.code='DEMO-KDKMP'
    where a.code='410100' and a.status='ACTIVE' and a.is_posting
  ) then raise exception 'POS_REVERSAL_CI_REVENUE_ACCOUNT_MISSING'; end if;
end $$;
