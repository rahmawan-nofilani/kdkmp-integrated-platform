-- DEVELOPMENT ONLY.
-- Synthetic accounting configuration for POS end-to-end testing.
-- Replace with the cooperative's approved COA and accounting policies before production.

do $$
declare
  v_terminal public.pos_terminals%rowtype;
  v_manager uuid;
  v_fy_id uuid;
  v_event_id uuid;
begin
  select * into v_terminal from public.pos_terminals where code='DEMO-POS-01' and status='ACTIVE' limit 1;
  if v_terminal.id is null then raise exception 'DEMO_POS_TERMINAL_NOT_FOUND'; end if;

  select p.id into v_manager
  from public.profiles p
  join public.user_roles ur on ur.profile_id=p.id and ur.valid_from<=now() and (ur.valid_until is null or ur.valid_until>now())
  join public.roles r on r.id=ur.role_id and r.code='MANAGER'
  where p.organization_id=v_terminal.organization_id and p.status='ACTIVE'
  order by p.created_at limit 1;
  if v_manager is null then raise exception 'DEMO_MANAGER_NOT_FOUND'; end if;

  insert into public.accounting_accounts(
    organization_id,organization_node_id,code,name,account_class,normal_balance,is_posting,is_control_account,status,effective_from,notes
  ) values
    (v_terminal.organization_id,v_terminal.organization_node_id,'110100','DEMO — Kas POS Gerai','ASSET','DEBIT',true,false,'ACTIVE','2026-08-01','DEVELOPMENT synthetic account; replace with approved cooperative COA before production'),
    (v_terminal.organization_id,v_terminal.organization_node_id,'130100','DEMO — Persediaan Barang Dagang','ASSET','DEBIT',true,false,'ACTIVE','2026-08-01','DEVELOPMENT synthetic account; replace with approved cooperative COA before production'),
    (v_terminal.organization_id,v_terminal.organization_node_id,'210100','DEMO — Pajak Penjualan Terutang','LIABILITY','CREDIT',true,false,'ACTIVE','2026-08-01','DEVELOPMENT synthetic account; replace with approved cooperative COA before production'),
    (v_terminal.organization_id,v_terminal.organization_node_id,'410100','DEMO — Pendapatan Penjualan Gerai','REVENUE','CREDIT',true,false,'ACTIVE','2026-08-01','DEVELOPMENT synthetic account; replace with approved cooperative COA before production'),
    (v_terminal.organization_id,v_terminal.organization_node_id,'510100','DEMO — Harga Pokok Penjualan','EXPENSE','DEBIT',true,false,'ACTIVE','2026-08-01','DEVELOPMENT synthetic account; replace with approved cooperative COA before production')
  on conflict (organization_node_id,code) do update
  set name=excluded.name,account_class=excluded.account_class,normal_balance=excluded.normal_balance,is_posting=true,status='ACTIVE',effective_from=excluded.effective_from,notes=excluded.notes,updated_at=now();

  insert into public.fiscal_years(organization_id,organization_node_id,fiscal_year,start_date,end_date,status)
  values(v_terminal.organization_id,v_terminal.organization_node_id,2026,'2026-01-01','2026-12-31','OPEN')
  on conflict (organization_node_id,fiscal_year) do update
  set start_date=excluded.start_date,end_date=excluded.end_date,status='OPEN',updated_at=now()
  returning id into v_fy_id;

  insert into public.accounting_periods(fiscal_year_id,organization_id,organization_node_id,period_code,period_name,start_date,end_date,status)
  values(v_fy_id,v_terminal.organization_id,v_terminal.organization_node_id,'2026-08','DEMO — Agustus 2026','2026-08-01','2026-08-31','OPEN')
  on conflict (organization_node_id,period_code) do update
  set fiscal_year_id=excluded.fiscal_year_id,period_name=excluded.period_name,start_date=excluded.start_date,end_date=excluded.end_date,status='OPEN',closed_at=null,closed_by=null,updated_at=now();

  select id into v_event_id from public.accounting_event_definitions where event_code='SALE_POST' and status='ACTIVE' limit 1;
  if v_event_id is null then raise exception 'SALE_POST_EVENT_NOT_FOUND'; end if;

  insert into public.accounting_event_mappings(
    organization_id,organization_node_id,event_definition_id,version_no,configuration,status,effective_from,created_by,approved_by,approved_at
  ) values(
    v_terminal.organization_id,v_terminal.organization_node_id,v_event_id,1,
    jsonb_build_object(
      'cash_account_code','110100',
      'sales_revenue_account_code','410100',
      'inventory_account_code','130100',
      'cogs_account_code','510100',
      'tax_payable_account_code','210100',
      'environment','DEVELOPMENT',
      'note','Synthetic DEMO accounting mapping; replace with approved cooperative COA and accounting policy before production'
    ),
    'ACTIVE','2026-08-01',v_manager,v_manager,now()
  )
  on conflict (organization_node_id,event_definition_id,version_no) do update
  set configuration=excluded.configuration,status='ACTIVE',effective_from=excluded.effective_from,effective_until=null,approved_by=excluded.approved_by,approved_at=excluded.approved_at;
end $$;
