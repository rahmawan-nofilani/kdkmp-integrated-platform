create table public.payment_provider_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict,
  code text not null,
  provider_type text not null check (provider_type in ('PJP','BANK','INTERNAL_CASH','OTHER')),
  provider_name text not null,
  supported_channels text[] not null default '{}',
  config_status text not null default 'NOT_CONFIGURED' check (config_status in ('NOT_CONFIGURED','CONFIGURED','VALIDATED','ERROR')),
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','SUSPENDED','INACTIVE','ARCHIVED')),
  secret_storage_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, code)
);

create table public.teller_sessions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  teller_profile_id uuid not null references public.profiles(id) on delete restrict, session_number text not null,
  business_date date not null default current_date, opening_cash numeric(20,2) not null default 0 check (opening_cash >= 0),
  expected_closing_cash numeric(20,2), actual_closing_cash numeric(20,2), variance_amount numeric(20,2),
  status text not null default 'DRAFT' check (status in ('DRAFT','OPEN','CLOSING','RECONCILIATION_REQUIRED','RECONCILED','CLOSED','CANCELLED')),
  opened_at timestamptz, closed_at timestamptz, opened_by uuid references public.profiles(id) on delete restrict,
  closed_by uuid references public.profiles(id) on delete restrict, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_unit_id, session_number)
);

create table public.payment_intents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict, intent_number text not null,
  business_purpose text not null check (business_purpose in ('MEMBERSHIP_CONTRIBUTION','SAVINGS_DEPOSIT','SAVINGS_WITHDRAWAL','LOAN_REPAYMENT','LOAN_DISBURSEMENT','SALE','PURCHASE_PAYMENT','EXPENSE','REFUND','OTHER')),
  source_domain text not null, source_entity_type text, source_entity_id uuid, source_reference text,
  payer_member_id uuid references public.members(id) on delete restrict, payee_member_id uuid references public.members(id) on delete restrict,
  amount numeric(20,2) not null check (amount > 0), currency text not null default 'IDR',
  status text not null default 'CREATED' check (status in ('CREATED','PENDING','CONFIRMED','SETTLEMENT_PENDING','SETTLED','FAILED','EXPIRED','CANCELLED','REFUND_PENDING','REFUNDED')),
  idempotency_key text, approval_request_id uuid references public.approval_requests(id) on delete restrict,
  expires_at timestamptz, confirmed_at timestamptz, settled_at timestamptz, created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_node_id, intent_number), unique (organization_node_id, idempotency_key)
);

create table public.payment_attempts (
  id uuid primary key default gen_random_uuid(), payment_intent_id uuid not null references public.payment_intents(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict, provider_config_id uuid references public.payment_provider_configs(id) on delete restrict,
  teller_session_id uuid references public.teller_sessions(id) on delete restrict, attempt_no integer not null check (attempt_no > 0),
  channel text not null check (channel in ('CASH_TELLER','BANK_TRANSFER','QRIS','VIRTUAL_ACCOUNT','AUTODEBIT','INTERNAL','OTHER')),
  amount numeric(20,2) not null check (amount > 0), currency text not null default 'IDR',
  status text not null default 'CREATED' check (status in ('CREATED','PENDING','CONFIRMED','SETTLEMENT_PENDING','SETTLED','FAILED','EXPIRED','CANCELLED','REFUNDED')),
  provider_reference text, merchant_reference text, failure_code text, failure_message text,
  created_at timestamptz not null default now(), confirmed_at timestamptz, settled_at timestamptz, unique (payment_intent_id, attempt_no)
);

create table public.payment_external_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, provider_config_id uuid references public.payment_provider_configs(id) on delete restrict,
  payment_attempt_id uuid references public.payment_attempts(id) on delete restrict, external_event_id text not null, event_type text not null,
  received_at timestamptz not null default now(), payload_hash text not null, sanitized_metadata jsonb not null default '{}'::jsonb,
  signature_validation_status text not null default 'NOT_VALIDATED' check (signature_validation_status in ('NOT_VALIDATED','VALID','INVALID','NOT_APPLICABLE')),
  processing_status text not null default 'RECEIVED' check (processing_status in ('RECEIVED','VALIDATED','PROCESSED','IGNORED','FAILED')),
  processed_at timestamptz, error_message text, unique (organization_node_id, external_event_id)
);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(), payment_intent_id uuid not null references public.payment_intents(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  organization_unit_id uuid references public.organization_units(id) on delete restrict, allocation_no integer not null check (allocation_no > 0),
  target_type text not null check (target_type in ('MEMBERSHIP_LEDGER','SAVINGS_ACCOUNT','LOAN_ACCOUNT','SALE','PURCHASE','EXPENSE','OTHER')),
  target_id uuid, target_reference text, amount numeric(20,2) not null check (amount > 0),
  status text not null default 'PLANNED' check (status in ('PLANNED','ALLOCATED','REVERSED','FAILED')), allocated_at timestamptz,
  unique (payment_intent_id, allocation_no)
);

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
  teller_session_id uuid not null references public.teller_sessions(id) on delete restrict, payment_intent_id uuid references public.payment_intents(id) on delete restrict,
  payment_attempt_id uuid references public.payment_attempts(id) on delete restrict,
  movement_type text not null check (movement_type in ('OPENING_FLOAT','CASH_IN','CASH_OUT','CASH_TRANSFER_IN','CASH_TRANSFER_OUT','CASH_ADJUSTMENT','REVERSAL')),
  direction text not null check (direction in ('IN','OUT')), amount numeric(20,2) not null check (amount > 0), currency text not null default 'IDR',
  receipt_number text, reason text, approval_request_id uuid references public.approval_requests(id) on delete restrict,
  accounting_status text not null default 'NOT_POSTED' check (accounting_status in ('NOT_POSTED','POSTED','RECONCILED','EXCEPTION')),
  journal_entry_id uuid references public.journal_entries(id) on delete restrict, reversal_of_movement_id uuid references public.cash_movements(id) on delete restrict,
  occurred_at timestamptz not null default now(), created_by uuid references public.profiles(id) on delete restrict, created_at timestamptz not null default now()
);

create table public.payment_settlement_batches (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict, provider_config_id uuid not null references public.payment_provider_configs(id) on delete restrict,
  settlement_reference text not null, settlement_date date not null, currency text not null default 'IDR', gross_amount numeric(20,2) not null default 0,
  fee_amount numeric(20,2) not null default 0, net_amount numeric(20,2) not null default 0,
  status text not null default 'RECEIVED' check (status in ('RECEIVED','MATCHING','MATCHED','EXCEPTION','RECONCILED','CLOSED')),
  received_at timestamptz not null default now(), reconciled_at timestamptz, notes text, unique (organization_node_id, provider_config_id, settlement_reference)
);

create table public.payment_settlement_items (
  id uuid primary key default gen_random_uuid(), settlement_batch_id uuid not null references public.payment_settlement_batches(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict, organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  payment_attempt_id uuid references public.payment_attempts(id) on delete restrict, provider_reference text,
  gross_amount numeric(20,2) not null default 0, fee_amount numeric(20,2) not null default 0, net_amount numeric(20,2) not null default 0,
  match_status text not null default 'UNMATCHED' check (match_status in ('UNMATCHED','MATCHED','AMOUNT_MISMATCH','REFERENCE_MISMATCH','DUPLICATE','MISSING_INTERNAL','MISSING_PROVIDER')),
  notes text, created_at timestamptz not null default now()
);

create index idx_teller_sessions_unit_date on public.teller_sessions(organization_unit_id,business_date desc,status);
create index idx_payment_intents_scope_status on public.payment_intents(organization_node_id,status,created_at desc);
create index idx_payment_attempts_intent on public.payment_attempts(payment_intent_id,attempt_no);
create index idx_payment_events_attempt on public.payment_external_events(payment_attempt_id,received_at desc);
create index idx_payment_allocations_intent on public.payment_allocations(payment_intent_id,allocation_no);
create index idx_cash_movements_session on public.cash_movements(teller_session_id,occurred_at);
create index idx_settlement_batches_provider on public.payment_settlement_batches(provider_config_id,settlement_date desc,status);

alter table public.payment_provider_configs enable row level security;
alter table public.teller_sessions enable row level security;
alter table public.payment_intents enable row level security;
alter table public.payment_attempts enable row level security;
alter table public.payment_external_events enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.cash_movements enable row level security;
alter table public.payment_settlement_batches enable row level security;
alter table public.payment_settlement_items enable row level security;

create policy payment_provider_configs_read on public.payment_provider_configs for select to authenticated using (public.has_permission('PAYMENT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy teller_sessions_read on public.teller_sessions for select to authenticated using (public.has_permission('TELLER_SESSION_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy payment_intents_read on public.payment_intents for select to authenticated using (public.has_permission('PAYMENT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy payment_attempts_read on public.payment_attempts for select to authenticated using (public.has_permission('PAYMENT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy payment_external_events_read on public.payment_external_events for select to authenticated using (public.has_permission('PAYMENT_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy payment_allocations_read on public.payment_allocations for select to authenticated using (public.has_permission('PAYMENT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy cash_movements_read on public.cash_movements for select to authenticated using (public.has_permission('TELLER_SESSION_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null));
create policy settlement_batches_read on public.payment_settlement_batches for select to authenticated using (public.has_permission('PAYMENT_RECONCILE') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy settlement_items_read on public.payment_settlement_items for select to authenticated using (public.has_permission('PAYMENT_RECONCILE') and public.has_data_scope(organization_id,organization_node_id,null,null,null));

grant select on public.payment_provider_configs,public.teller_sessions,public.payment_intents,public.payment_attempts,public.payment_external_events,public.payment_allocations,public.cash_movements,public.payment_settlement_batches,public.payment_settlement_items to authenticated;
revoke insert,update,delete on public.payment_provider_configs,public.teller_sessions,public.payment_intents,public.payment_attempts,public.payment_external_events,public.payment_allocations,public.cash_movements,public.payment_settlement_batches,public.payment_settlement_items from anon,authenticated;

insert into public.permissions(code,domain,description,is_privileged)
values
 ('PAYMENT_VIEW','PAYMENT','View payment intent, attempt, provider and settlement status within scope',false),
 ('TELLER_SESSION_VIEW','PAYMENT','View teller session and cash movements within scope',false),
 ('TELLER_SESSION_MANAGE','PAYMENT','Open/close controlled teller sessions',true),
 ('PAYMENT_RECONCILE','PAYMENT','Review provider settlement and payment reconciliation',true)
on conflict(code) do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='PAYMENT_VIEW' where r.code in ('MANAGER','FINANCE_OFFICER','TELLER','COMPLIANCE_OFFICER','SUPERVISOR') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='TELLER_SESSION_VIEW' where r.code in ('MANAGER','FINANCE_OFFICER','TELLER','SUPERVISOR') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='TELLER_SESSION_MANAGE' where r.code='TELLER' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='PAYMENT_RECONCILE' where r.code in ('MANAGER','FINANCE_OFFICER') on conflict do nothing;

do $$
declare v_org uuid; v_node uuid; v_unit uuid;
begin
  select o.id,n.id,u.id into v_org,v_node,v_unit
  from public.organizations o
  join public.organization_nodes n on n.organization_id=o.id and n.code='DEMO-KDKMP'
  join public.organization_units u on u.organization_node_id=n.id and u.unit_type='SAVINGS_LOANS'
  where o.code='DEMO-KDKMP-DEV' limit 1;
  if v_org is null then raise exception 'demo_scope_not_found'; end if;
  insert into public.payment_provider_configs(organization_id,organization_node_id,organization_unit_id,code,provider_type,provider_name,supported_channels,config_status,status,notes)
  values
    (v_org,v_node,v_unit,'DEMO-CASH-TELLER','INTERNAL_CASH','DEMO — Cash/Teller',ARRAY['CASH_TELLER'],'NOT_CONFIGURED','DRAFT','Cash transaction flow exists as architecture only; execution gate remains blocked.'),
    (v_org,v_node,v_unit,'DEMO-QRIS-ADAPTER','PJP','DEMO — QRIS Adapter Placeholder',ARRAY['QRIS'],'NOT_CONFIGURED','DRAFT','REPLACE WITH AUTHORIZED PJP INTEGRATION. No credentials or fake confirmation.'),
    (v_org,v_node,v_unit,'DEMO-BANK-TRANSFER','BANK','DEMO — Bank Transfer Adapter Placeholder',ARRAY['BANK_TRANSFER'],'NOT_CONFIGURED','DRAFT','Bank integration not configured.')
  on conflict(organization_node_id,code) do nothing;
end $$;

comment on table public.payment_external_events is 'Stores event identity/hash and sanitized metadata. Never treat user screenshots as authoritative provider events.';
comment on table public.payment_provider_configs is 'Provider metadata only. Secrets must be held outside public database/application source.';
comment on table public.payment_intents is 'Business payment intent. Ledger allocation occurs only after controlled confirmation/settlement rules.';
comment on table public.cash_movements is 'Cash movements must belong to a teller session and be reconciled; never overwrite cash balance directly.';
