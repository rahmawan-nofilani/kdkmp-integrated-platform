insert into public.permissions(code, domain, description, is_privileged)
values
('MEMBERSHIP_FINANCE_VIEW','COOPERATIVE_CORE','View membership capital/contribution configuration, accounts, and ledger summaries',false),
('MEMBERSHIP_FINANCE_POLICY_DRAFT','COOPERATIVE_CORE','Draft membership contribution/capital policy versions',true),
('MEMBERSHIP_FINANCE_POLICY_APPROVE','COOPERATIVE_CORE','Approve membership contribution/capital policy versions according to governance workflow',true),
('MEMBERSHIP_FINANCE_POST','COOPERATIVE_CORE','Post controlled membership financial entries after accounting integration is enabled',true)
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('MEMBERSHIP_FINANCE_VIEW','MEMBERSHIP_FINANCE_POLICY_DRAFT') where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('MEMBERSHIP_FINANCE_VIEW','MEMBERSHIP_FINANCE_POLICY_APPROVE') where r.code='BOARD' on conflict do nothing;
insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='MEMBERSHIP_FINANCE_VIEW' where r.code in ('SUPERVISOR','FINANCE_OFFICER','COMPLIANCE_OFFICER') on conflict do nothing;

create table public.membership_contribution_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  code text not null,
  name text not null,
  category text not null check (category in ('CAPITAL_RELATED','MEMBERSHIP_SAVINGS_RELATED','OTHER_MEMBERSHIP')),
  legal_classification text,
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','SUSPENDED','RETIRED','ARCHIVED')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,organization_node_id,code)
);

create table public.membership_contribution_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  contribution_type_id uuid not null references public.membership_contribution_types(id) on delete restrict,
  version_no integer not null check(version_no>0),
  effective_from date,
  effective_until date,
  configuration jsonb not null default '{}'::jsonb,
  legal_basis text,
  status text not null default 'DRAFT' check(status in ('DRAFT','APPROVED','ACTIVE','SUPERSEDED','ARCHIVED')),
  created_by uuid references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  unique(contribution_type_id,version_no)
);

create table public.member_membership_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  contribution_type_id uuid not null references public.membership_contribution_types(id) on delete restrict,
  policy_version_id uuid references public.membership_contribution_versions(id) on delete restrict,
  status text not null default 'OPEN' check(status in ('OPEN','FROZEN','CLOSED','ARCHIVED')),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(member_id,contribution_type_id)
);

create table public.member_membership_ledger (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  account_id uuid not null references public.member_membership_accounts(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  entry_type text not null check(entry_type in ('CONTRIBUTION','WITHDRAWAL','ADJUSTMENT','REVERSAL')),
  direction text not null check(direction in ('INCREASE','DECREASE')),
  amount numeric(20,2) not null check(amount>0),
  currency text not null default 'IDR',
  transaction_date date not null default current_date,
  reference_number text,
  source_channel text,
  reversal_of uuid references public.member_membership_ledger(id) on delete restrict,
  status text not null default 'POSTED' check(status in ('POSTED','REVERSED')),
  reason text,
  accounting_status text not null default 'NOT_INTEGRATED' check(accounting_status in ('NOT_INTEGRATED','PENDING','POSTED','FAILED')),
  accounting_reference text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index idx_membership_contribution_types_node on public.membership_contribution_types(organization_node_id,status);
create index idx_membership_contribution_versions_type on public.membership_contribution_versions(contribution_type_id,version_no desc);
create index idx_member_membership_accounts_member on public.member_membership_accounts(member_id,status);
create index idx_member_membership_accounts_node on public.member_membership_accounts(organization_node_id,status);
create index idx_member_membership_ledger_account on public.member_membership_ledger(account_id,transaction_date desc,created_at desc);
create index idx_member_membership_ledger_member on public.member_membership_ledger(member_id,transaction_date desc);

alter table public.membership_contribution_types enable row level security;
alter table public.membership_contribution_versions enable row level security;
alter table public.member_membership_accounts enable row level security;
alter table public.member_membership_ledger enable row level security;

revoke all on public.membership_contribution_types,public.membership_contribution_versions,public.member_membership_accounts,public.member_membership_ledger from anon,authenticated;
grant select on public.membership_contribution_types,public.membership_contribution_versions,public.member_membership_accounts,public.member_membership_ledger to authenticated;

create policy membership_contribution_types_select_scoped on public.membership_contribution_types for select to authenticated using(public.has_permission('MEMBERSHIP_FINANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
create policy membership_contribution_versions_select_scoped on public.membership_contribution_versions for select to authenticated using(public.has_permission('MEMBERSHIP_FINANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
create policy member_membership_accounts_select_scoped on public.member_membership_accounts for select to authenticated using(public.has_permission('MEMBERSHIP_FINANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
create policy member_membership_ledger_select_scoped on public.member_membership_ledger for select to authenticated using(public.has_permission('MEMBERSHIP_FINANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));

create or replace view public.member_membership_balances with (security_invoker=true) as
select a.id as account_id,a.organization_id,a.organization_node_id,a.member_id,a.contribution_type_id,a.status as account_status,
  coalesce(sum(case when l.status='POSTED' and l.direction='INCREASE' then l.amount when l.status='POSTED' and l.direction='DECREASE' then -l.amount else 0 end),0::numeric) as balance,
  coalesce(max(l.currency),'IDR') as currency,
  max(l.transaction_date) as last_transaction_date
from public.member_membership_accounts a
left join public.member_membership_ledger l on l.account_id=a.id
group by a.id,a.organization_id,a.organization_node_id,a.member_id,a.contribution_type_id,a.status;
grant select on public.member_membership_balances to authenticated;

comment on table public.membership_contribution_types is 'Cooperative Core financial membership classification. It is explicitly separate from Financial Services/Simpan Pinjam products.';
comment on table public.membership_contribution_versions is 'Versioned membership contribution/capital policy. Nominal, frequency, withdrawal, formula, and legal basis belong in configuration only after AD/ART/policy validation.';
comment on table public.member_membership_ledger is 'Immutable ledger foundation. Balance must be derived from entries, never overwritten. Operational posting is intentionally disabled in Phase 2B until Accounting/Approval integration is ready.';
comment on view public.member_membership_balances is 'Derived balance read model; not a transaction source.';