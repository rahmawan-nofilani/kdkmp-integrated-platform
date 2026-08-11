insert into public.permissions(code,domain,description,is_privileged) values
('FINANCIAL_PRODUCT_VIEW','FINANCIAL_SERVICES','View savings/loan product catalog, versions, and activation readiness',false),
('FINANCIAL_PRODUCT_EDIT_DRAFT','FINANCIAL_SERVICES','Edit DRAFT financial product configuration before review',true)
on conflict(code) do nothing;
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from public.roles r join public.permissions p on p.code in ('FINANCIAL_PRODUCT_VIEW','FINANCIAL_PRODUCT_EDIT_DRAFT') where r.code='MANAGER' on conflict do nothing;
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from public.roles r join public.permissions p on p.code='FINANCIAL_PRODUCT_VIEW' where r.code in ('COMPLIANCE_OFFICER','LOAN_OFFICER','TELLER','SUPERVISOR','BOARD') on conflict do nothing;

create table public.financial_product_templates(
 id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
 product_category text not null check(product_category in('SAVINGS','LOAN')), description text not null,
 default_configuration jsonb not null default '{}'::jsonb,
 template_status text not null default 'ACTIVE' check(template_status in('ACTIVE','INACTIVE','ARCHIVED')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now());

insert into public.financial_product_templates(code,name,product_category,description,default_configuration) values
('SAVINGS_FLEXIBLE','Simpanan Fleksibel','SAVINGS','Template teknis untuk simpanan fleksibel/on-demand. Bukan klasifikasi hukum.',jsonb_build_object('savings_pattern','FLEXIBLE','maturity_required',false,'target_based',false,'withdrawal_rule','CONFIGURABLE','channel_options',jsonb_build_array('CASH_TELLER','BANK_TRANSFER','QRIS','VIRTUAL_ACCOUNT','AUTODEBIT'))),
('SAVINGS_TERM','Simpanan Berjangka','SAVINGS','Template teknis dengan tenor/jatuh tempo. Legal product type tetap harus divalidasi.',jsonb_build_object('savings_pattern','TERM','maturity_required',true,'tenor_unit_options',jsonb_build_array('DAYS','MONTHS','YEARS'),'early_withdrawal','CONFIGURABLE','channel_options',jsonb_build_array('CASH_TELLER','BANK_TRANSFER','QRIS'))),
('SAVINGS_GOAL_EVENT','Simpanan Target / Event','SAVINGS','Template tujuan/event; marketing purpose bukan klasifikasi hukum.',jsonb_build_object('savings_pattern','GOAL_EVENT','target_amount','CONFIGURABLE','target_date','CONFIGURABLE','deposit_frequency','CONFIGURABLE','withdrawal_rule','CONFIGURABLE','channel_options',jsonb_build_array('CASH_TELLER','BANK_TRANSFER','QRIS'))),
('SAVINGS_PERIODIC','Simpanan Berkala','SAVINGS','Template setoran berkala dengan frekuensi configurable.',jsonb_build_object('savings_pattern','PERIODIC','deposit_frequency_options',jsonb_build_array('DAILY','WEEKLY','BIWEEKLY','MONTHLY','CUSTOM'),'maturity_required','CONFIGURABLE','channel_options',jsonb_build_array('CASH_TELLER','BANK_TRANSFER','QRIS','AUTODEBIT'))),
('LOAN_MONTHLY_INSTALLMENT','Pinjaman Angsuran Bulanan','LOAN','Template pinjaman dengan repayment bulanan.',jsonb_build_object('repayment_pattern','INSTALLMENT','frequency','MONTHLY','tenor','CONFIGURABLE','grace_period','CONFIGURABLE','rate_method_options',jsonb_build_array('FLAT','EFFECTIVE','ANNUITY','CUSTOM_APPROVED'))),
('LOAN_WEEKLY_INSTALLMENT','Pinjaman Angsuran Mingguan / Dua Mingguan','LOAN','Template installment mingguan/dua mingguan.',jsonb_build_object('repayment_pattern','INSTALLMENT','frequency_options',jsonb_build_array('WEEKLY','BIWEEKLY'),'tenor','CONFIGURABLE','grace_period','CONFIGURABLE','rate_method_options',jsonb_build_array('FLAT','EFFECTIVE','CUSTOM_APPROVED'))),
('LOAN_SEASONAL','Pinjaman Musiman','LOAN','Template repayment menyesuaikan siklus musiman/panen.',jsonb_build_object('repayment_pattern','SEASONAL','frequency','SEASONAL','grace_period','CONFIGURABLE','schedule','CONFIGURABLE_APPROVED')),
('LOAN_AT_MATURITY','Pinjaman Jatuh Tempo','LOAN','Template bullet/single maturity.',jsonb_build_object('repayment_pattern','BULLET','frequency','AT_MATURITY','principal_payment','AT_MATURITY','tenor','CONFIGURABLE')),
('LOAN_BALLOON','Pinjaman Balloon','LOAN','Template residual/balloon payment.',jsonb_build_object('repayment_pattern','BALLOON','frequency','CONFIGURABLE','balloon_rule','CONFIGURABLE_APPROVED','tenor','CONFIGURABLE')),
('LOAN_CUSTOM_SCHEDULE','Pinjaman Jadwal Khusus','LOAN','Template custom schedule melalui approved schedule policy.',jsonb_build_object('repayment_pattern','CUSTOM_SCHEDULE','schedule','REQUIRES_APPROVAL','tenor','CONFIGURABLE'));

create table public.financial_products(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 code text not null,name text not null,product_category text not null check(product_category in('SAVINGS','LOAN')),
 template_code text references public.financial_product_templates(code) on delete restrict,legal_product_type text,purpose_code text,description text,
 status text not null default 'DRAFT' check(status in('DRAFT','UNDER_REVIEW','APPROVED','ACTIVE','SUSPENDED','RETIRED','ARCHIVED')),
 created_by uuid references public.profiles(id) on delete restrict,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(organization_id,organization_node_id,organization_unit_id,code));

create table public.financial_product_versions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,
 organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,organization_unit_id uuid not null references public.organization_units(id) on delete restrict,
 financial_product_id uuid not null references public.financial_products(id) on delete restrict,version_no integer not null check(version_no>0),
 status text not null default 'DRAFT' check(status in('DRAFT','UNDER_REVIEW','APPROVED','ACTIVE','SUPERSEDED','ARCHIVED')),
 effective_from date,effective_until date,currency text not null default 'IDR',core_configuration jsonb not null default '{}'::jsonb,
 eligibility_configuration jsonb not null default '{}'::jsonb,pricing_configuration jsonb not null default '{}'::jsonb,
 repayment_configuration jsonb not null default '{}'::jsonb,channel_configuration jsonb not null default '{}'::jsonb,
 collateral_configuration jsonb not null default '{}'::jsonb,withdrawal_configuration jsonb not null default '{}'::jsonb,
 accounting_mapping_status text not null default 'NOT_CONFIGURED' check(accounting_mapping_status in('NOT_CONFIGURED','DRAFT','COMPLETE')),
 regulatory_validation_status text not null default 'PENDING' check(regulatory_validation_status in('PENDING','PASSED','FAILED')),
 legal_basis text,created_by uuid references public.profiles(id) on delete restrict,approved_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),approved_at timestamptz,unique(financial_product_id,version_no));

create table public.financial_product_draft_commands(
 id uuid primary key default gen_random_uuid(),organization_unit_id uuid,template_code text not null references public.financial_product_templates(code) on delete restrict,
 product_code text not null,product_name text not null,legal_product_type text,purpose_code text,description text,
 result_product_id uuid references public.financial_products(id) on delete restrict,requested_by uuid references public.profiles(id) on delete restrict,created_at timestamptz not null default now());
create index idx_financial_products_unit_status on public.financial_products(organization_unit_id,status,product_category);
create index idx_financial_product_versions_product on public.financial_product_versions(financial_product_id,version_no desc);

alter table public.financial_product_templates enable row level security;alter table public.financial_products enable row level security;alter table public.financial_product_versions enable row level security;alter table public.financial_product_draft_commands enable row level security;
revoke all on public.financial_product_templates,public.financial_products,public.financial_product_versions,public.financial_product_draft_commands from anon,authenticated;
grant select on public.financial_product_templates,public.financial_products,public.financial_product_versions to authenticated;
grant insert(template_code,organization_unit_id,product_code,product_name,legal_product_type,purpose_code,description) on public.financial_product_draft_commands to authenticated;
create policy financial_product_templates_read on public.financial_product_templates for select to authenticated using(template_status='ACTIVE');
create policy financial_products_select_scoped on public.financial_products for select to authenticated using(public.has_permission('FINANCIAL_PRODUCT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id));
create policy financial_product_versions_select_scoped on public.financial_product_versions for select to authenticated using(public.has_permission('FINANCIAL_PRODUCT_VIEW') and public.has_data_scope(organization_id,organization_node_id,organization_unit_id));
create policy financial_product_draft_commands_insert on public.financial_product_draft_commands for insert to authenticated with check(public.has_permission('FINANCIAL_PRODUCT_CREATE'));

create or replace function app_private.financial_product_draft_command_before_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype;v_unit public.organization_units%rowtype;v_template public.financial_product_templates%rowtype;v_product_id uuid;v_scope_count integer;
begin
 select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
 if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';end if;
 if not public.has_permission('FINANCIAL_PRODUCT_CREATE') then raise exception 'FINANCIAL_PRODUCT_CREATE_DENIED' using errcode='42501';end if;
 select * into v_template from public.financial_product_templates where code=new.template_code and template_status='ACTIVE';if v_template.id is null then raise exception 'FINANCIAL_PRODUCT_TEMPLATE_INVALID' using errcode='22023';end if;
 if new.organization_unit_id is null then
  select count(*),(array_agg(u.id order by u.id))[1] into v_scope_count,new.organization_unit_id from public.organization_units u join public.organization_nodes n on n.id=u.organization_node_id where u.organization_id=v_profile.organization_id and u.unit_type='SAVINGS_LOANS' and u.status='ACTIVE' and n.node_type='KDKMP' and public.has_data_scope(u.organization_id,u.organization_node_id,u.id);
  if v_scope_count<>1 then raise exception 'SAVINGS_LOANS_UNIT_REQUIRED' using errcode='22023';end if;
 end if;
 select * into v_unit from public.organization_units where id=new.organization_unit_id and organization_id=v_profile.organization_id and unit_type='SAVINGS_LOANS' and status='ACTIVE';if v_unit.id is null then raise exception 'INVALID_SAVINGS_LOANS_UNIT' using errcode='22023';end if;
 if not public.has_data_scope(v_profile.organization_id,v_unit.organization_node_id,v_unit.id) then raise exception 'FINANCIAL_PRODUCT_SCOPE_DENIED' using errcode='42501';end if;
 if nullif(trim(new.product_code),'') is null or nullif(trim(new.product_name),'') is null then raise exception 'FINANCIAL_PRODUCT_IDENTITY_REQUIRED' using errcode='22023';end if;
 insert into public.financial_products(organization_id,organization_node_id,organization_unit_id,code,name,product_category,template_code,legal_product_type,purpose_code,description,status,created_by)
 values(v_profile.organization_id,v_unit.organization_node_id,v_unit.id,upper(trim(new.product_code)),trim(new.product_name),v_template.product_category,v_template.code,nullif(trim(new.legal_product_type),''),nullif(trim(new.purpose_code),''),nullif(trim(new.description),''),'DRAFT',v_profile.id) returning id into v_product_id;
 insert into public.financial_product_versions(organization_id,organization_node_id,organization_unit_id,financial_product_id,version_no,status,core_configuration,regulatory_validation_status,accounting_mapping_status,created_by)
 values(v_profile.organization_id,v_unit.organization_node_id,v_unit.id,v_product_id,1,'DRAFT',v_template.default_configuration,'PENDING','NOT_CONFIGURED',v_profile.id);
 insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason) values(v_profile.organization_id,v_profile.id,'FINANCIAL_PRODUCT_DRAFT_CREATED','FINANCIAL_PRODUCT',v_product_id,jsonb_build_object('unit_id',v_unit.id,'code',upper(trim(new.product_code)),'name',trim(new.product_name),'category',v_template.product_category,'template',v_template.code,'status','DRAFT'),'Financial product draft created from configurable template');
 new.product_code:=upper(trim(new.product_code));new.product_name:=trim(new.product_name);new.legal_product_type:=nullif(trim(new.legal_product_type),'');new.purpose_code:=nullif(trim(new.purpose_code),'');new.description:=nullif(trim(new.description),'');new.result_product_id:=v_product_id;new.requested_by:=v_profile.id;new.created_at:=now();return new;
exception when unique_violation then raise exception 'FINANCIAL_PRODUCT_CODE_ALREADY_EXISTS' using errcode='23505';end;$$;
revoke all on function app_private.financial_product_draft_command_before_insert() from public,anon,authenticated;
create trigger trg_financial_product_draft_command before insert on public.financial_product_draft_commands for each row execute function app_private.financial_product_draft_command_before_insert();

create or replace function public.create_financial_product_draft(p_template_code text,p_product_code text,p_product_name text,p_legal_product_type text default null,p_purpose_code text default null,p_description text default null,p_organization_unit_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$declare v_product_id uuid;begin insert into public.financial_product_draft_commands(template_code,organization_unit_id,product_code,product_name,legal_product_type,purpose_code,description) values(p_template_code,p_organization_unit_id,p_product_code,p_product_name,p_legal_product_type,p_purpose_code,p_description) returning result_product_id into v_product_id;return v_product_id;end;$$;
revoke all on function public.create_financial_product_draft(text,text,text,text,text,text,uuid) from public,anon;grant execute on function public.create_financial_product_draft(text,text,text,text,text,text,uuid) to authenticated;

create or replace view public.financial_product_readiness with(security_invoker=true) as
select p.id financial_product_id,p.organization_id,p.organization_node_id,p.organization_unit_id,p.code,p.name,p.product_category,p.status product_status,v.id version_id,v.version_no,v.status version_status,v.accounting_mapping_status,v.regulatory_validation_status,
exists(select 1 from public.regulatory_authorizations ra where ra.organization_id=p.organization_id and (ra.organization_unit_id=p.organization_unit_id or ra.organization_unit_id is null) and ra.module_code in('SAVINGS_LOANS','FINANCIAL_SERVICES') and ra.status='ACTIVE' and (ra.effective_date is null or ra.effective_date<=current_date) and (ra.expiry_date is null or ra.expiry_date>=current_date)) authorization_active,
(p.legal_product_type is not null and v.status='APPROVED' and v.accounting_mapping_status='COMPLETE' and v.regulatory_validation_status='PASSED' and exists(select 1 from public.regulatory_authorizations ra where ra.organization_id=p.organization_id and (ra.organization_unit_id=p.organization_unit_id or ra.organization_unit_id is null) and ra.module_code in('SAVINGS_LOANS','FINANCIAL_SERVICES') and ra.status='ACTIVE' and (ra.effective_date is null or ra.effective_date<=current_date) and (ra.expiry_date is null or ra.expiry_date>=current_date))) activation_ready
from public.financial_products p join public.financial_product_versions v on v.financial_product_id=p.id where v.version_no=(select max(v2.version_no) from public.financial_product_versions v2 where v2.financial_product_id=p.id);
grant select on public.financial_product_readiness to authenticated;
comment on table public.financial_product_templates is 'Technical Product Builder templates. Template names are not legal classifications and contain no hardcoded rates/nominals.';
comment on table public.financial_product_versions is 'Version snapshot for savings/loan product configuration. Existing accounts must retain their contracted version when transaction engines are implemented.';
comment on view public.financial_product_readiness is 'Activation gate read model. ACTIVE product transactions must remain blocked unless authorization, accounting, regulatory validation, and approved version requirements pass.';