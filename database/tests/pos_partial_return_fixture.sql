\set ON_ERROR_STOP on

-- Disposable local-CI posting accounts used by the controlled partial-return suite.
insert into public.accounting_accounts(
  organization_id,organization_node_id,code,name,account_class,normal_balance,
  is_posting,is_control_account,status,effective_from,notes
)
select o.id,n.id,v.code,v.name,v.account_class,v.normal_balance,true,false,'ACTIVE',current_date,
       'Disposable POS partial return CI fixture'
from public.organizations o
join public.organization_nodes n on n.organization_id=o.id and n.code='DEMO-KDKMP'
cross join (values
  ('110100','CI — Kas POS','ASSET','DEBIT'),
  ('410100','CI — Pendapatan POS','REVENUE','CREDIT'),
  ('130100','CI — Persediaan POS','ASSET','DEBIT'),
  ('510100','CI — HPP POS','EXPENSE','DEBIT')
) as v(code,name,account_class,normal_balance)
where o.code='DEMO-KDKMP-DEV'
on conflict (organization_node_id,code) do nothing;

do $$
begin
  if (select count(*) from public.accounting_accounts a
      join public.organization_nodes n on n.id=a.organization_node_id and n.code='DEMO-KDKMP'
      where a.code in ('110100','410100','130100','510100') and a.status='ACTIVE' and a.is_posting) < 4 then
    raise exception 'POS_PARTIAL_RETURN_CI_ACCOUNTS_MISSING';
  end if;
end $$;
