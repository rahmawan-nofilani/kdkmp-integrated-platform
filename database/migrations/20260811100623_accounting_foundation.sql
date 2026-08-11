create table public.accounting_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  parent_account_id uuid references public.accounting_accounts(id) on delete restrict,
  code text not null,
  name text not null,
  account_class text not null check (account_class in ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE')),
  normal_balance text not null check (normal_balance in ('DEBIT','CREDIT')),
  is_posting boolean not null default true,
  is_control_account boolean not null default false,
  control_purpose text,
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')),
  effective_from date,
  effective_until date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, code),
  check (effective_until is null or effective_from is null or effective_until >= effective_from)
);

create table public.fiscal_years (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  fiscal_year integer not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'OPEN' check (status in ('DRAFT','OPEN','SOFT_CLOSED','HARD_CLOSED','ARCHIVED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, fiscal_year),
  check (end_date >= start_date)
);

create table public.accounting_periods (
  id uuid primary key default gen_random_uuid(),
  fiscal_year_id uuid not null references public.fiscal_years(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  period_code text not null,
  period_name text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'OPEN' check (status in ('OPEN','SOFT_CLOSED','HARD_CLOSED')),
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, period_code),
  check (end_date >= start_date)
);

create table public.journal_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  batch_number text not null,
  description text,
  source_domain text not null default 'MANUAL',
  source_batch_ref text,
  status text not null default 'DRAFT' check (status in ('DRAFT','CLOSED','CANCELLED')),
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, batch_number)
);

create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  batch_id uuid references public.journal_batches(id) on delete restrict,
  accounting_period_id uuid not null references public.accounting_periods(id) on delete restrict,
  journal_number text not null,
  entry_date date not null,
  description text not null,
  source_domain text not null,
  source_entity_type text,
  source_entity_id uuid,
  source_reference text,
  correlation_id text,
  idempotency_key text,
  reversal_of_entry_id uuid references public.journal_entries(id) on delete restrict,
  status text not null default 'DRAFT' check (status in ('DRAFT','VALIDATED','POSTED','CANCELLED')),
  created_by uuid references public.profiles(id) on delete restrict,
  validated_by uuid references public.profiles(id) on delete restrict,
  validated_at timestamptz,
  posted_by uuid references public.profiles(id) on delete restrict,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, journal_number),
  unique (organization_node_id, idempotency_key)
);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  account_id uuid not null references public.accounting_accounts(id) on delete restrict,
  debit numeric(20,2) not null default 0 check (debit >= 0),
  credit numeric(20,2) not null default 0 check (credit >= 0),
  memo text,
  subledger_type text,
  subledger_id uuid,
  dimensions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (journal_entry_id, line_no),
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create table public.accounting_event_definitions (
  id uuid primary key default gen_random_uuid(),
  event_code text not null unique,
  domain text not null,
  name text not null,
  description text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','ARCHIVED')),
  created_at timestamptz not null default now()
);

create table public.accounting_event_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  event_definition_id uuid not null references public.accounting_event_definitions(id) on delete restrict,
  version_no integer not null,
  configuration jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT' check (status in ('DRAFT','REVIEW','ACTIVE','SUPERSEDED','ARCHIVED')),
  effective_from date,
  effective_until date,
  created_by uuid references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_node_id, event_definition_id, version_no)
);

create table public.subledger_control_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  subledger_code text not null,
  control_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')),
  effective_from date,
  effective_until date,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_node_id, subledger_code, effective_from)
);

create table public.reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  reconciliation_type text not null,
  period_id uuid references public.accounting_periods(id) on delete restrict,
  as_of_date date not null,
  subledger_amount numeric(20,2),
  gl_amount numeric(20,2),
  difference_amount numeric(20,2),
  status text not null default 'PENDING' check (status in ('PENDING','MATCHED','EXCEPTION','REVIEWED','CLOSED')),
  generated_by uuid references public.profiles(id) on delete restrict,
  generated_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  notes text
);

create table public.reconciliation_exceptions (
  id uuid primary key default gen_random_uuid(),
  reconciliation_run_id uuid not null references public.reconciliation_runs(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  exception_code text not null,
  description text not null,
  amount numeric(20,2),
  status text not null default 'OPEN' check (status in ('OPEN','UNDER_REVIEW','RESOLVED','ACCEPTED')),
  resolution_notes text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete restrict
);

create index idx_accounting_accounts_scope on public.accounting_accounts(organization_id, organization_node_id, status);
create index idx_periods_scope_dates on public.accounting_periods(organization_node_id, start_date, end_date, status);
create index idx_journal_entries_scope_date on public.journal_entries(organization_id, organization_node_id, entry_date desc, status);
create index idx_journal_entries_source on public.journal_entries(source_domain, source_entity_type, source_entity_id);
create index idx_journal_lines_entry on public.journal_lines(journal_entry_id, line_no);
create index idx_journal_lines_account on public.journal_lines(account_id);
create index idx_event_mappings_scope on public.accounting_event_mappings(organization_node_id, status, effective_from);
create index idx_reconciliation_runs_scope on public.reconciliation_runs(organization_node_id, as_of_date desc, status);

alter table public.accounting_accounts enable row level security;
alter table public.fiscal_years enable row level security;
alter table public.accounting_periods enable row level security;
alter table public.journal_batches enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.accounting_event_definitions enable row level security;
alter table public.accounting_event_mappings enable row level security;
alter table public.subledger_control_accounts enable row level security;
alter table public.reconciliation_runs enable row level security;
alter table public.reconciliation_exceptions enable row level security;

create policy accounting_accounts_scope_read on public.accounting_accounts for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy fiscal_years_scope_read on public.fiscal_years for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy accounting_periods_scope_read on public.accounting_periods for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy journal_batches_scope_read on public.journal_batches for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy journal_entries_scope_read on public.journal_entries for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy journal_lines_scope_read on public.journal_lines for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy accounting_event_definitions_read on public.accounting_event_definitions for select to authenticated using (public.has_permission('ACCOUNTING_VIEW'));
create policy accounting_event_mappings_scope_read on public.accounting_event_mappings for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy subledger_control_accounts_scope_read on public.subledger_control_accounts for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy reconciliation_runs_scope_read on public.reconciliation_runs for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));
create policy reconciliation_exceptions_scope_read on public.reconciliation_exceptions for select to authenticated
using (public.has_permission('ACCOUNTING_VIEW') and public.has_data_scope(organization_id, organization_node_id, null, null, null));

grant select on public.accounting_accounts, public.fiscal_years, public.accounting_periods, public.journal_batches,
  public.journal_entries, public.journal_lines, public.accounting_event_definitions, public.accounting_event_mappings,
  public.subledger_control_accounts, public.reconciliation_runs, public.reconciliation_exceptions to authenticated;
revoke insert, update, delete on public.accounting_accounts, public.fiscal_years, public.accounting_periods, public.journal_batches,
  public.journal_entries, public.journal_lines, public.accounting_event_definitions, public.accounting_event_mappings,
  public.subledger_control_accounts, public.reconciliation_runs, public.reconciliation_exceptions from anon, authenticated;

insert into public.permissions(code, domain, description, is_privileged)
values
 ('ACCOUNTING_VIEW','ACCOUNTING','View accounting configuration, periods, journals and reconciliation within scope',false),
 ('ACCOUNTING_DRAFT_CREATE','ACCOUNTING','Create draft journal entries within scope',true),
 ('ACCOUNTING_VALIDATE','ACCOUNTING','Validate balanced journal entries before posting',true),
 ('ACCOUNTING_POST','ACCOUNTING','Post validated journals to the General Ledger',true),
 ('ACCOUNTING_PERIOD_MANAGE','ACCOUNTING','Manage accounting period lifecycle',true),
 ('ACCOUNTING_RECONCILE','ACCOUNTING','Run and review subledger-to-GL reconciliation',true)
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code='ACCOUNTING_VIEW'
where r.code in ('MANAGER','FINANCE_OFFICER','BOARD','SUPERVISOR','COMPLIANCE_OFFICER') on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code='ACCOUNTING_DRAFT_CREATE'
where r.code='FINANCE_OFFICER' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code='ACCOUNTING_VALIDATE'
where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code='ACCOUNTING_PERIOD_MANAGE'
where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id, p.id from public.roles r join public.permissions p on p.code='ACCOUNTING_RECONCILE'
where r.code in ('FINANCE_OFFICER','MANAGER') on conflict do nothing;

create or replace function app_private.guard_journal_line_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_status text;
begin
  select je.status into v_status from public.journal_entries je where je.id=coalesce(new.journal_entry_id,old.journal_entry_id);
  if v_status='POSTED' then raise exception 'posted_journal_lines_are_immutable'; end if;
  return coalesce(new,old);
end; $$;
revoke all on function app_private.guard_journal_line_mutation() from public,anon,authenticated;
create trigger trg_guard_journal_line_mutation before update or delete on public.journal_lines
for each row execute function app_private.guard_journal_line_mutation();

create or replace function app_private.guard_journal_entry_transition()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_period public.accounting_periods%rowtype;
  v_debit numeric(20,2); v_credit numeric(20,2); v_line_count integer; v_invalid_accounts integer;
begin
  if old.status='POSTED' then
    if new is distinct from old then raise exception 'posted_journal_is_immutable_use_reversal_entry'; end if;
    return new;
  end if;
  if old.status='DRAFT' and new.status not in ('DRAFT','VALIDATED','CANCELLED') then raise exception 'invalid_journal_status_transition'; end if;
  if old.status='VALIDATED' and new.status not in ('VALIDATED','POSTED','DRAFT','CANCELLED') then raise exception 'invalid_journal_status_transition'; end if;
  if old.status='CANCELLED' and new.status<>'CANCELLED' then raise exception 'cancelled_journal_is_immutable'; end if;

  if new.status in ('VALIDATED','POSTED') and old.status is distinct from new.status then
    select * into v_period from public.accounting_periods ap where ap.id=new.accounting_period_id;
    if not found then raise exception 'accounting_period_not_found'; end if;
    if new.entry_date<v_period.start_date or new.entry_date>v_period.end_date then raise exception 'entry_date_outside_accounting_period'; end if;
    if new.status='POSTED' and v_period.status<>'OPEN' then raise exception 'accounting_period_not_open'; end if;
    select count(*),coalesce(sum(jl.debit),0),coalesce(sum(jl.credit),0) into v_line_count,v_debit,v_credit
      from public.journal_lines jl where jl.journal_entry_id=new.id;
    if v_line_count<2 then raise exception 'journal_requires_at_least_two_lines'; end if;
    if v_debit<=0 or v_debit<>v_credit then raise exception 'journal_not_balanced'; end if;
    select count(*) into v_invalid_accounts from public.journal_lines jl join public.accounting_accounts aa on aa.id=jl.account_id
      where jl.journal_entry_id=new.id and (aa.organization_id<>new.organization_id or aa.organization_node_id<>new.organization_node_id or aa.status<>'ACTIVE' or aa.is_posting=false);
    if v_invalid_accounts>0 then raise exception 'journal_contains_invalid_account'; end if;
  end if;
  if new.status='VALIDATED' and old.status<>'VALIDATED' then new.validated_at:=coalesce(new.validated_at,now()); end if;
  if new.status='POSTED' and old.status<>'POSTED' then new.posted_at:=coalesce(new.posted_at,now()); end if;
  new.updated_at:=now();
  return new;
end; $$;
revoke all on function app_private.guard_journal_entry_transition() from public,anon,authenticated;
create trigger trg_guard_journal_entry_transition before update on public.journal_entries
for each row execute function app_private.guard_journal_entry_transition();

insert into public.accounting_event_definitions(event_code,domain,name,description)
values
 ('MEMBERSHIP_CONTRIBUTION_POST','COOPERATIVE_CORE','Membership contribution posting','Future mapping from membership contribution ledger to GL.'),
 ('SAVINGS_DEPOSIT_POST','FINANCIAL_SERVICES','Savings deposit posting','Future mapping from savings subledger to GL.'),
 ('SAVINGS_WITHDRAWAL_POST','FINANCIAL_SERVICES','Savings withdrawal posting','Future mapping from savings subledger to GL.'),
 ('LOAN_DISBURSEMENT_POST','FINANCIAL_SERVICES','Loan disbursement posting','Future mapping from loan subledger to GL.'),
 ('LOAN_REPAYMENT_POST','FINANCIAL_SERVICES','Loan repayment posting','Future mapping from loan subledger to GL.'),
 ('SALE_POST','COMMERCIAL','Sales posting','Future mapping from sales/POS to GL.'),
 ('PURCHASE_RECEIPT_POST','PROCUREMENT','Purchase/receipt posting','Future mapping from procurement/inventory to GL.')
on conflict (event_code) do nothing;

do $$
declare v_org uuid; v_node uuid; v_fy uuid;
begin
  select o.id,n.id into v_org,v_node from public.organizations o join public.organization_nodes n on n.organization_id=o.id
  where o.code='DEMO-KDKMP-DEV' and n.code='DEMO-KDKMP' and n.node_type='KDKMP' limit 1;
  if v_org is null or v_node is null then raise exception 'demo_kdkmp_scope_not_found'; end if;

  insert into public.accounting_accounts(organization_id,organization_node_id,code,name,account_class,normal_balance,is_posting,is_control_account,control_purpose,status,notes)
  values
   (v_org,v_node,'1000','DEMO — Aset','ASSET','DEBIT',false,false,null,'ACTIVE','Header account DEVELOPMENT.'),
   (v_org,v_node,'1110','DEMO — Kas KDKMP','ASSET','DEBIT',true,false,null,'ACTIVE','Posting account DEVELOPMENT.'),
   (v_org,v_node,'1120','DEMO — Bank KDKMP','ASSET','DEBIT',true,false,null,'ACTIVE','Posting account DEVELOPMENT.'),
   (v_org,v_node,'1210','DEMO — Piutang Usaha','ASSET','DEBIT',true,true,'AR','ACTIVE','Control candidate; mapping not active.'),
   (v_org,v_node,'1220','DEMO — Piutang Pinjaman Anggota','ASSET','DEBIT',true,true,'LOANS','ACTIVE','Control candidate; mapping not active.'),
   (v_org,v_node,'1300','DEMO — Persediaan','ASSET','DEBIT',true,true,'INVENTORY','ACTIVE','Control candidate; mapping not active.'),
   (v_org,v_node,'2000','DEMO — Liabilitas','LIABILITY','CREDIT',false,false,null,'ACTIVE','Header account DEVELOPMENT.'),
   (v_org,v_node,'2100','DEMO — Simpanan Unit Simpan Pinjam','LIABILITY','CREDIT',true,true,'SAVINGS','ACTIVE','Control candidate; legal/accounting validation pending.'),
   (v_org,v_node,'2200','DEMO — Utang Usaha','LIABILITY','CREDIT',true,true,'AP','ACTIVE','Control candidate; mapping not active.'),
   (v_org,v_node,'3000','DEMO — Ekuitas','EQUITY','CREDIT',false,false,null,'ACTIVE','Header account DEVELOPMENT.'),
   (v_org,v_node,'3100','DEMO — Modal/Saldo Keanggotaan','EQUITY','CREDIT',true,true,'MEMBERSHIP_FINANCE','ACTIVE','Placeholder classification pending AD/ART/accounting validation.'),
   (v_org,v_node,'4000','DEMO — Pendapatan Usaha','REVENUE','CREDIT',true,false,null,'ACTIVE','Posting account DEVELOPMENT.'),
   (v_org,v_node,'5000','DEMO — Beban Operasional','EXPENSE','DEBIT',true,false,null,'ACTIVE','Posting account DEVELOPMENT.'),
   (v_org,v_node,'5100','DEMO — Harga Pokok/Pengeluaran Terkait Penjualan','EXPENSE','DEBIT',true,false,null,'ACTIVE','Posting account DEVELOPMENT; final COA policy pending.')
  on conflict (organization_node_id,code) do nothing;

  insert into public.fiscal_years(organization_id,organization_node_id,fiscal_year,start_date,end_date,status)
  values(v_org,v_node,2026,date '2026-01-01',date '2026-12-31','OPEN')
  on conflict (organization_node_id,fiscal_year) do update set status=excluded.status returning id into v_fy;
  if v_fy is null then select id into v_fy from public.fiscal_years where organization_node_id=v_node and fiscal_year=2026; end if;
  insert into public.accounting_periods(fiscal_year_id,organization_id,organization_node_id,period_code,period_name,start_date,end_date,status)
  values(v_fy,v_org,v_node,'2026-08','DEMO — Agustus 2026',date '2026-08-01',date '2026-08-31','OPEN')
  on conflict (organization_node_id,period_code) do nothing;
end $$;

comment on table public.accounting_accounts is 'Accounting foundation. DEMO COA is provisional and must be replaced/validated before production.';
comment on table public.journal_entries is 'Posted journals are immutable; corrections use separate reversal/correcting entries.';
comment on table public.subledger_control_accounts is 'Maps subledgers to GL control accounts. Keep DRAFT until reconciliation design is validated.';
