create table public.approval_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  code text not null,
  name text not null,
  domain text not null,
  transaction_type text not null,
  status text not null default 'DRAFT' check (status in ('DRAFT','REVIEW','ACTIVE','INACTIVE','ARCHIVED')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_node_id, code)
);

create table public.approval_policy_versions (
  id uuid primary key default gen_random_uuid(),
  approval_policy_id uuid not null references public.approval_policies(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  version_no integer not null check (version_no > 0),
  condition_config jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT' check (status in ('DRAFT','REVIEW','APPROVED','ACTIVE','SUPERSEDED','ARCHIVED')),
  effective_from timestamptz,
  effective_until timestamptz,
  created_by uuid references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  unique (approval_policy_id, version_no),
  check (effective_until is null or effective_from is null or effective_until >= effective_from)
);

create table public.approval_policy_steps (
  id uuid primary key default gen_random_uuid(),
  approval_policy_version_id uuid not null references public.approval_policy_versions(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  step_no integer not null check (step_no > 0),
  step_name text not null,
  required_permission_code text not null references public.permissions(code) on delete restrict,
  min_approvers integer not null default 1 check (min_approvers > 0),
  quorum_rule text not null default 'ALL_REQUIRED' check (quorum_rule in ('ALL_REQUIRED','MINIMUM_COUNT','ANY_ONE')),
  prohibit_requester_approval boolean not null default true,
  prohibit_previous_step_actor boolean not null default false,
  require_conflict_declaration boolean not null default true,
  allow_delegation boolean not null default false,
  sla_minutes integer,
  escalation_config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (approval_policy_version_id, step_no)
);

create table public.approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  approval_policy_version_id uuid not null references public.approval_policy_versions(id) on delete restrict,
  source_domain text not null,
  source_entity_type text not null,
  source_entity_id uuid,
  source_reference text,
  correlation_id text,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  request_snapshot jsonb not null default '{}'::jsonb,
  policy_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING' check (status in ('PENDING','IN_REVIEW','APPROVED','REJECTED','RETURNED','CANCELLED','EXPIRED')),
  current_step_no integer,
  completed_at timestamptz,
  unique (organization_node_id, source_domain, source_entity_type, source_entity_id, correlation_id)
);

create table public.approval_request_steps (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null references public.approval_requests(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  step_no integer not null,
  step_name text not null,
  required_permission_code text not null,
  min_approvers integer not null,
  quorum_rule text not null,
  prohibit_requester_approval boolean not null,
  prohibit_previous_step_actor boolean not null,
  require_conflict_declaration boolean not null,
  allow_delegation boolean not null,
  status text not null default 'PENDING' check (status in ('PENDING','ACTIVE','APPROVED','REJECTED','RETURNED','SKIPPED','EXPIRED')),
  activated_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (approval_request_id, step_no)
);

create table public.approval_decisions (
  id uuid primary key default gen_random_uuid(),
  approval_request_id uuid not null references public.approval_requests(id) on delete restrict,
  approval_request_step_id uuid not null references public.approval_request_steps(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  acting_for_profile_id uuid references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('APPROVE','REJECT','RETURN')),
  conflict_declared boolean not null default false,
  conflict_note text,
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  decided_at timestamptz not null default now(),
  unique (approval_request_step_id, actor_profile_id)
);

create table public.approval_delegations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  delegator_profile_id uuid not null references public.profiles(id) on delete restrict,
  delegate_profile_id uuid not null references public.profiles(id) on delete restrict,
  permission_code text not null references public.permissions(code) on delete restrict,
  valid_from timestamptz not null,
  valid_until timestamptz not null,
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','SUSPENDED','EXPIRED','REVOKED')),
  reason text,
  created_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (valid_until > valid_from),
  check (delegator_profile_id <> delegate_profile_id)
);

create table public.sod_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  code text not null,
  name text not null,
  domain text not null,
  transaction_type text,
  rule_type text not null check (rule_type in ('REQUESTER_CANNOT_APPROVE','CREATOR_CANNOT_REVIEW','REVIEWER_CANNOT_APPROVE','APPROVER_CANNOT_EXECUTE','SAME_ACTOR_FORBIDDEN','CONFLICT_DECLARATION_REQUIRED')),
  subject_permission_code text references public.permissions(code) on delete restrict,
  conflicting_permission_code text references public.permissions(code) on delete restrict,
  condition_config jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT' check (status in ('DRAFT','ACTIVE','INACTIVE','ARCHIVED')),
  effective_from timestamptz,
  effective_until timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  unique (organization_node_id, code)
);

create index idx_approval_policies_scope on public.approval_policies(organization_node_id,domain,transaction_type,status);
create index idx_approval_requests_scope_status on public.approval_requests(organization_node_id,status,requested_at desc);
create index idx_approval_requests_source on public.approval_requests(source_domain,source_entity_type,source_entity_id);
create index idx_approval_decisions_request on public.approval_decisions(approval_request_id,decided_at);
create index idx_delegations_delegate on public.approval_delegations(delegate_profile_id,permission_code,status,valid_from,valid_until);
create index idx_sod_rules_scope on public.sod_rules(organization_node_id,domain,transaction_type,status);

alter table public.approval_policies enable row level security;
alter table public.approval_policy_versions enable row level security;
alter table public.approval_policy_steps enable row level security;
alter table public.approval_requests enable row level security;
alter table public.approval_request_steps enable row level security;
alter table public.approval_decisions enable row level security;
alter table public.approval_delegations enable row level security;
alter table public.sod_rules enable row level security;

create policy approval_policies_scope_read on public.approval_policies for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_policy_versions_scope_read on public.approval_policy_versions for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_policy_steps_scope_read on public.approval_policy_steps for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_requests_scope_read on public.approval_requests for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_request_steps_scope_read on public.approval_request_steps for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_decisions_scope_read on public.approval_decisions for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy approval_delegations_scope_read on public.approval_delegations for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));
create policy sod_rules_scope_read on public.sod_rules for select to authenticated using (public.has_permission('APPROVAL_VIEW') and public.has_data_scope(organization_id,organization_node_id,null,null,null));

grant select on public.approval_policies,public.approval_policy_versions,public.approval_policy_steps,public.approval_requests,public.approval_request_steps,public.approval_decisions,public.approval_delegations,public.sod_rules to authenticated;
revoke insert,update,delete on public.approval_policies,public.approval_policy_versions,public.approval_policy_steps,public.approval_requests,public.approval_request_steps,public.approval_decisions,public.approval_delegations,public.sod_rules from anon,authenticated;

insert into public.permissions(code,domain,description,is_privileged)
values
 ('APPROVAL_POLICY_VIEW','APPROVAL','View approval policy configuration',false),
 ('APPROVAL_POLICY_DRAFT','APPROVAL','Draft approval policy versions',true),
 ('APPROVAL_POLICY_ACTIVATE','APPROVAL','Activate approved approval-policy versions',true),
 ('APPROVAL_DELEGATION_MANAGE','APPROVAL','Manage controlled approval delegation',true),
 ('SOD_POLICY_VIEW','APPROVAL','View segregation-of-duties rules',false),
 ('SOD_POLICY_MANAGE','APPROVAL','Manage segregation-of-duties rules',true)
on conflict(code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('APPROVAL_POLICY_VIEW','SOD_POLICY_VIEW') where r.code in ('MANAGER','BOARD','SUPERVISOR','COMPLIANCE_OFFICER') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='APPROVAL_POLICY_DRAFT' where r.code in ('MANAGER','COMPLIANCE_OFFICER') on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='APPROVAL_DELEGATION_MANAGE' where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code='SOD_POLICY_MANAGE' where r.code='COMPLIANCE_OFFICER' on conflict do nothing;

-- APPROVAL_POLICY_ACTIVATE intentionally has no baseline role mapping.

do $$
declare v_org uuid; v_node uuid; v_policy uuid; v_version uuid;
begin
  select o.id,n.id into v_org,v_node from public.organizations o join public.organization_nodes n on n.organization_id=o.id where o.code='DEMO-KDKMP-DEV' and n.code='DEMO-KDKMP' and n.node_type='KDKMP' limit 1;
  if v_org is null or v_node is null then raise exception 'demo_kdkmp_scope_not_found'; end if;

  insert into public.approval_policies(organization_id,organization_node_id,code,name,domain,transaction_type,status,notes) values
   (v_org,v_node,'DEMO-FIN-PRODUCT','DEMO — Persetujuan Produk Simpan Pinjam','FINANCIAL_SERVICES','FINANCIAL_PRODUCT','DRAFT','Template workflow; nominal/rule conditions pending validation.'),
   (v_org,v_node,'DEMO-LOAN','DEMO — Persetujuan Pinjaman','FINANCIAL_SERVICES','LOAN','DRAFT','Template workflow; amount/risk bands not hardcoded.'),
   (v_org,v_node,'DEMO-PAYMENT','DEMO — Persetujuan Pembayaran','FINANCE','PAYMENT','DRAFT','Template workflow; amount bands pending organizational policy.'),
   (v_org,v_node,'DEMO-ACCOUNTING-POST','DEMO — Persetujuan Posting Jurnal','ACCOUNTING','JOURNAL_POST','DRAFT','Template workflow; posting role remains unmapped.')
  on conflict(organization_node_id,code) do nothing;

  select id into v_policy from public.approval_policies where organization_node_id=v_node and code='DEMO-FIN-PRODUCT';
  insert into public.approval_policy_versions(approval_policy_id,organization_id,organization_node_id,version_no,condition_config,status) values(v_policy,v_org,v_node,1,'{}'::jsonb,'DRAFT') on conflict(approval_policy_id,version_no) do nothing;
  select id into v_version from public.approval_policy_versions where approval_policy_id=v_policy and version_no=1;
  insert into public.approval_policy_steps(approval_policy_version_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,require_conflict_declaration,allow_delegation)
  values(v_version,v_org,v_node,1,'Compliance Review','FINANCIAL_PRODUCT_APPROVE',1,'ALL_REQUIRED',true,true,false) on conflict(approval_policy_version_id,step_no) do nothing;

  select id into v_policy from public.approval_policies where organization_node_id=v_node and code='DEMO-LOAN';
  insert into public.approval_policy_versions(approval_policy_id,organization_id,organization_node_id,version_no,condition_config,status) values(v_policy,v_org,v_node,1,'{}'::jsonb,'DRAFT') on conflict(approval_policy_id,version_no) do nothing;
  select id into v_version from public.approval_policy_versions where approval_policy_id=v_policy and version_no=1;
  insert into public.approval_policy_steps(approval_policy_version_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,prohibit_previous_step_actor,require_conflict_declaration,allow_delegation) values
   (v_version,v_org,v_node,1,'Loan Review','LOAN_REVIEW',1,'ALL_REQUIRED',true,false,true,false),
   (v_version,v_org,v_node,2,'Loan Approval','LOAN_APPROVE',1,'ALL_REQUIRED',true,true,true,false)
  on conflict(approval_policy_version_id,step_no) do nothing;

  select id into v_policy from public.approval_policies where organization_node_id=v_node and code='DEMO-PAYMENT';
  insert into public.approval_policy_versions(approval_policy_id,organization_id,organization_node_id,version_no,condition_config,status) values(v_policy,v_org,v_node,1,'{}'::jsonb,'DRAFT') on conflict(approval_policy_id,version_no) do nothing;
  select id into v_version from public.approval_policy_versions where approval_policy_id=v_policy and version_no=1;
  insert into public.approval_policy_steps(approval_policy_version_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,require_conflict_declaration,allow_delegation)
  values(v_version,v_org,v_node,1,'Payment Approval','PAYMENT_APPROVE',1,'ALL_REQUIRED',true,true,false) on conflict(approval_policy_version_id,step_no) do nothing;

  select id into v_policy from public.approval_policies where organization_node_id=v_node and code='DEMO-ACCOUNTING-POST';
  insert into public.approval_policy_versions(approval_policy_id,organization_id,organization_node_id,version_no,condition_config,status) values(v_policy,v_org,v_node,1,'{}'::jsonb,'DRAFT') on conflict(approval_policy_id,version_no) do nothing;
  select id into v_version from public.approval_policy_versions where approval_policy_id=v_policy and version_no=1;
  insert into public.approval_policy_steps(approval_policy_version_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,require_conflict_declaration,allow_delegation)
  values(v_version,v_org,v_node,1,'Accounting Posting Authorization','ACCOUNTING_POST',1,'ALL_REQUIRED',true,true,false) on conflict(approval_policy_version_id,step_no) do nothing;

  insert into public.sod_rules(organization_id,organization_node_id,code,name,domain,transaction_type,rule_type,subject_permission_code,conflicting_permission_code,status,notes) values
   (v_org,v_node,'DEMO-LOAN-REVIEW-APPROVE','DEMO — Reviewer berbeda dari Approver','FINANCIAL_SERVICES','LOAN','REVIEWER_CANNOT_APPROVE','LOAN_REVIEW','LOAN_APPROVE','DRAFT','Activate only after governance review.'),
   (v_org,v_node,'DEMO-LOAN-APPROVE-DISBURSE','DEMO — Approver berbeda dari Disburser','FINANCIAL_SERVICES','LOAN','APPROVER_CANNOT_EXECUTE','LOAN_APPROVE','LOAN_DISBURSE','DRAFT','Activate only after governance review.'),
   (v_org,v_node,'DEMO-PAYMENT-CREATOR-APPROVER','DEMO — Pembuat tidak menyetujui sendiri','FINANCE','PAYMENT','REQUESTER_CANNOT_APPROVE','PAYMENT_CREATE','PAYMENT_APPROVE','DRAFT','Activate only after governance review.'),
   (v_org,v_node,'DEMO-ACCOUNTING-DRAFT-POST','DEMO — Pembuat jurnal berbeda dari poster','ACCOUNTING','JOURNAL_POST','SAME_ACTOR_FORBIDDEN','ACCOUNTING_DRAFT_CREATE','ACCOUNTING_POST','DRAFT','Posting role remains intentionally unmapped.')
  on conflict(organization_node_id,code) do nothing;
end $$;

comment on table public.approval_policy_versions is 'Approval policy versions are snapshot-oriented. Never rewrite a version already referenced by a request.';
comment on table public.approval_requests is 'Approval requests preserve request and policy snapshots for traceability.';
comment on table public.sod_rules is 'SoD rules are configuration and must be reviewed before ACTIVE status.';
