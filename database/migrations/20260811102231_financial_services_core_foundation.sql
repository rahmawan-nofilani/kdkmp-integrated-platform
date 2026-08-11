create table public.financial_service_member_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  status text not null default 'PENDING' check (status in ('PENDING','ACTIVE','RESTRICTED','SUSPENDED','CLOSED')),
  identity_verification_status text not null default 'NOT_STARTED' check (identity_verification_status in ('NOT_STARTED','PENDING','VERIFIED','FAILED','REVIEW_REQUIRED')),
  kyc_status text not null default 'NOT_STARTED' check (kyc_status in ('NOT_STARTED','IN_PROGRESS','COMPLETE','REVIEW_REQUIRED','EXPIRED')),
  pmpj_status text not null default 'NOT_ASSESSED' check (pmpj_status in ('NOT_ASSESSED','IN_PROGRESS','COMPLETE','REVIEW_REQUIRED')),
  risk_level text not null default 'UNASSESSED' check (risk_level in ('UNASSESSED','LOW','MEDIUM','HIGH','RESTRICTED')),
  source_of_funds_status text not null default 'NOT_REVIEWED' check (source_of_funds_status in ('NOT_REVIEWED','DECLARED','VERIFIED','REVIEW_REQUIRED')),
  last_review_at timestamptz,
  next_review_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_unit_id, member_id)
);

create table public.savings_accounts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  financial_service_profile_id uuid not null references public.financial_service_member_profiles(id) on delete restrict,
  financial_product_id uuid not null references public.financial_products(id) on delete restrict,
  financial_product_version_id uuid not null references public.financial_product_versions(id) on delete restrict,
  account_number text, currency text not null default 'IDR', product_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING_ACTIVATION' check (status in ('PENDING_ACTIVATION','ACTIVE','FROZEN','BLOCKED','CLOSED')),
  opened_at timestamptz, closed_at timestamptz, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), unique (organization_unit_id, account_number)
);

create table public.savings_ledger_entries (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  savings_account_id uuid not null references public.savings_accounts(id) on delete restrict,
  entry_type text not null check (entry_type in ('DEPOSIT','WITHDRAWAL','RETURN','FEE','ADJUSTMENT','REVERSAL')),
  direction text not null check (direction in ('CREDIT','DEBIT')), amount numeric(20,2) not null check (amount > 0),
  currency text not null default 'IDR', channel text not null check (channel in ('CASH_TELLER','BANK_TRANSFER','QRIS','VIRTUAL_ACCOUNT','AUTODEBIT','INTERNAL','OTHER')),
  payment_reference text, source_transaction_id uuid, idempotency_key text,
  reversal_of_entry_id uuid references public.savings_ledger_entries(id) on delete restrict,
  accounting_status text not null default 'NOT_POSTED' check (accounting_status in ('NOT_POSTED','POSTED','RECONCILED','EXCEPTION')),
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  approval_request_id uuid references public.approval_requests(id) on delete restrict,
  occurred_at timestamptz not null default now(), value_date date not null default current_date,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
  unique (organization_node_id, idempotency_key)
);

create table public.loan_applications (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  financial_service_profile_id uuid not null references public.financial_service_member_profiles(id) on delete restrict,
  financial_product_id uuid not null references public.financial_products(id) on delete restrict,
  financial_product_version_id uuid not null references public.financial_product_versions(id) on delete restrict,
  application_number text, requested_amount numeric(20,2) not null check (requested_amount > 0), currency text not null default 'IDR',
  requested_term integer, requested_term_unit text check (requested_term_unit is null or requested_term_unit in ('DAY','WEEK','MONTH','YEAR','AT_MATURITY','CUSTOM')),
  purpose_text text, product_snapshot jsonb not null default '{}'::jsonb, analysis_snapshot jsonb not null default '{}'::jsonb,
  risk_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT' check (status in ('DRAFT','SUBMITTED','ELIGIBILITY_REVIEW','KYC_REVIEW','CREDIT_ANALYSIS','RISK_REVIEW','APPROVAL_PENDING','APPROVED','REJECTED','CANCELLED','EXPIRED')),
  approval_request_id uuid references public.approval_requests(id) on delete restrict, submitted_at timestamptz, decided_at timestamptz,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_unit_id, application_number)
);

create table public.loan_accounts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  member_id uuid not null references public.members(id) on delete restrict,
  financial_service_profile_id uuid not null references public.financial_service_member_profiles(id) on delete restrict,
  loan_application_id uuid not null unique references public.loan_applications(id) on delete restrict,
  financial_product_id uuid not null references public.financial_products(id) on delete restrict,
  financial_product_version_id uuid not null references public.financial_product_versions(id) on delete restrict,
  account_number text, approved_amount numeric(20,2) not null check (approved_amount > 0), currency text not null default 'IDR',
  contract_snapshot jsonb not null default '{}'::jsonb, repayment_configuration_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING_DISBURSEMENT' check (status in ('PENDING_DISBURSEMENT','ACTIVE','OVERDUE','COLLECTION','RESTRUCTURING','SETTLED','WRITTEN_OFF','CLOSED','CANCELLED')),
  disbursed_at timestamptz, maturity_date date, settled_at timestamptz, created_at timestamptz not null default now(),
  unique (organization_unit_id, account_number)
);

create table public.loan_repayment_schedule (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  loan_account_id uuid not null references public.loan_accounts(id) on delete restrict,
  installment_no integer not null check (installment_no > 0), due_date date not null,
  principal_due numeric(20,2) not null default 0 check (principal_due >= 0),
  return_or_margin_due numeric(20,2) not null default 0 check (return_or_margin_due >= 0),
  fee_due numeric(20,2) not null default 0 check (fee_due >= 0), total_due numeric(20,2) not null check (total_due >= 0),
  status text not null default 'SCHEDULED' check (status in ('SCHEDULED','DUE','PARTIALLY_PAID','PAID','OVERDUE','RESTRUCTURED','WAIVED')),
  paid_at timestamptz, created_at timestamptz not null default now(), unique (loan_account_id, installment_no)
);

create table public.loan_ledger_entries (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  loan_account_id uuid not null references public.loan_accounts(id) on delete restrict,
  entry_type text not null check (entry_type in ('DISBURSEMENT','PRINCIPAL_PAYMENT','RETURN_OR_MARGIN_PAYMENT','FEE','PENALTY','WAIVER','ADJUSTMENT','REVERSAL')),
  principal_amount numeric(20,2) not null default 0, return_or_margin_amount numeric(20,2) not null default 0,
  fee_amount numeric(20,2) not null default 0, penalty_amount numeric(20,2) not null default 0, currency text not null default 'IDR',
  channel text not null check (channel in ('CASH_TELLER','BANK_TRANSFER','QRIS','VIRTUAL_ACCOUNT','AUTODEBIT','INTERNAL','OTHER')),
  payment_reference text, source_transaction_id uuid, idempotency_key text,
  reversal_of_entry_id uuid references public.loan_ledger_entries(id) on delete restrict,
  accounting_status text not null default 'NOT_POSTED' check (accounting_status in ('NOT_POSTED','POSTED','RECONCILED','EXCEPTION')),
  journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  approval_request_id uuid references public.approval_requests(id) on delete restrict,
  occurred_at timestamptz not null default now(), value_date date not null default current_date,
  created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now(),
  unique (organization_node_id, idempotency_key),
  check (principal_amount <> 0 or return_or_margin_amount <> 0 or fee_amount <> 0 or penalty_amount <> 0)
);

create table public.collection_cases (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  loan_account_id uuid not null references public.loan_accounts(id) on delete restrict,
  case_number text, status text not null default 'OPEN' check (status in ('OPEN','CONTACTING','PROMISE_TO_PAY','RESTRUCTURING_REVIEW','ESCALATED','RESOLVED','CLOSED')),
  assigned_profile_id uuid references public.profiles(id) on delete restrict, opened_at timestamptz not null default now(), resolved_at timestamptz,
  notes text, unique (organization_unit_id, case_number)
);

create index idx_fs_profile_member on public.financial_service_member_profiles(organization_unit_id,member_id,status);
create index idx_savings_accounts_member on public.savings_accounts(organization_unit_id,member_id,status);
create index idx_savings_ledger_account_date on public.savings_ledger_entries(savings_account_id,occurred_at desc);
create index idx_loan_applications_member on public.loan_applications(organization_unit_id,member_id,status);
create index idx_loan_accounts_member on public.loan_accounts(organization_unit_id,member_id,status);
create index idx_loan_schedule_due on public.loan_repayment_schedule(loan_account_id,due_date,status);
create index idx_loan_ledger_account_date on public.loan_ledger_entries(loan_account_id,occurred_at desc);
create index idx_collection_cases_status on public.collection_cases(organization_unit_id,status,opened_at desc);

alter table public.financial_service_member_profiles enable row level security;
alter table public.savings_accounts enable row level security;
alter table public.savings_ledger_entries enable row level security;
alter table public.loan_applications enable row level security;
alter table public.loan_accounts enable row level security;
alter table public.loan_repayment_schedule enable row level security;
alter table public.loan_ledger_entries enable row level security;
alter table public.collection_cases enable row level security;

create policy fs_member_profile_read on public.financial_service_member_profiles for select to authenticated using ((public.has_permission('SAVINGS_VIEW') or public.has_permission('LOAN_VIEW')) and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy savings_accounts_read on public.savings_accounts for select to authenticated using (public.has_permission('SAVINGS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy savings_ledger_read on public.savings_ledger_entries for select to authenticated using (public.has_permission('SAVINGS_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy loan_applications_read on public.loan_applications for select to authenticated using (public.has_permission('LOAN_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy loan_accounts_read on public.loan_accounts for select to authenticated using (public.has_permission('LOAN_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy loan_schedule_read on public.loan_repayment_schedule for select to authenticated using (public.has_permission('LOAN_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy loan_ledger_read on public.loan_ledger_entries for select to authenticated using (public.has_permission('LOAN_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy collection_cases_read on public.collection_cases for select to authenticated using (public.has_permission('LOAN_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));

grant select on public.financial_service_member_profiles,public.savings_accounts,public.savings_ledger_entries,public.loan_applications,public.loan_accounts,public.loan_repayment_schedule,public.loan_ledger_entries,public.collection_cases to authenticated;
revoke insert,update,delete on public.financial_service_member_profiles,public.savings_accounts,public.savings_ledger_entries,public.loan_applications,public.loan_accounts,public.loan_repayment_schedule,public.loan_ledger_entries,public.collection_cases from anon,authenticated;

create or replace function app_private.prevent_financial_ledger_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ begin raise exception 'financial_ledger_is_immutable_use_reversal_entry'; end; $$;
revoke all on function app_private.prevent_financial_ledger_mutation() from public,anon,authenticated;
create trigger trg_savings_ledger_immutable before update or delete on public.savings_ledger_entries for each row execute function app_private.prevent_financial_ledger_mutation();
create trigger trg_loan_ledger_immutable before update or delete on public.loan_ledger_entries for each row execute function app_private.prevent_financial_ledger_mutation();

create view public.savings_account_balances with (security_invoker=true) as
select sa.id savings_account_id,sa.organization_id,sa.organization_node_id,sa.organization_unit_id,sa.member_id,sa.currency,
 coalesce(sum(case when le.direction='CREDIT' then le.amount else -le.amount end),0)::numeric(20,2) ledger_balance
from public.savings_accounts sa left join public.savings_ledger_entries le on le.savings_account_id=sa.id
group by sa.id,sa.organization_id,sa.organization_node_id,sa.organization_unit_id,sa.member_id,sa.currency;
grant select on public.savings_account_balances to authenticated;

create view public.loan_account_balances with (security_invoker=true) as
select la.id loan_account_id,la.organization_id,la.organization_node_id,la.organization_unit_id,la.member_id,la.currency,la.approved_amount,
 coalesce(sum(case when le.entry_type='DISBURSEMENT' then le.principal_amount when le.entry_type in ('PRINCIPAL_PAYMENT','WAIVER','REVERSAL') then -le.principal_amount else 0 end),0)::numeric(20,2) principal_ledger_balance
from public.loan_accounts la left join public.loan_ledger_entries le on le.loan_account_id=la.id
group by la.id,la.organization_id,la.organization_node_id,la.organization_unit_id,la.member_id,la.currency,la.approved_amount;
grant select on public.loan_account_balances to authenticated;

comment on table public.financial_service_member_profiles is 'KYC/PMPJ status metadata only. Real identity numbers/documents remain restricted and are not seeded in DEVELOPMENT.';
comment on table public.savings_ledger_entries is 'Immutable financial subledger. Balance is derived from entries; never overwrite a stored balance.';
comment on table public.loan_ledger_entries is 'Immutable loan subledger. Corrections use reversal entries.';
comment on table public.loan_applications is 'Product and analysis snapshots preserve the terms reviewed at application time.';
