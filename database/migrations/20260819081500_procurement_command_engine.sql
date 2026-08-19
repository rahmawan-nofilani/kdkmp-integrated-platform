-- Release-1 DEVELOPMENT Procurement Command Engine.
-- Controlled UAT path: MANAGER requester/receiver -> BOARD approver -> FINANCE invoice/match.
-- No provider activation and no true-production policy is implied.

-- 1) Explicit write permissions and role boundary.
insert into public.permissions(code,domain,description,is_privileged)
values ('PURCHASE_INVOICE_CREATE','PROCUREMENT','Record supplier invoice against an approved purchase order.',true)
on conflict(code) do update
set domain=excluded.domain,description=excluded.description,is_privileged=true;

do $$
declare
  v_receive uuid;
  v_approve uuid;
  v_invoice_create uuid;
  v_manager uuid;
  v_board uuid;
  v_finance uuid;
begin
  select id into v_receive from public.permissions where code='PURCHASE_RECEIVE';
  select id into v_approve from public.permissions where code='PURCHASE_APPROVE' and is_privileged=true;
  select id into v_invoice_create from public.permissions where code='PURCHASE_INVOICE_CREATE' and is_privileged=true;
  select id into v_manager from public.roles where code='MANAGER' and status='ACTIVE';
  select id into v_board from public.roles where code='BOARD' and status='ACTIVE';
  select id into v_finance from public.roles where code='FINANCE_OFFICER' and status='ACTIVE';

  if v_receive is null or v_approve is null or v_invoice_create is null
     or v_manager is null or v_board is null or v_finance is null then
    raise exception 'PROCUREMENT_RELEASE_ROLE_OR_PERMISSION_MISSING';
  end if;

  delete from public.role_permissions where permission_id=v_approve and role_id<>v_board;
  insert into public.role_permissions(role_id,permission_id) values(v_board,v_approve) on conflict do nothing;
  insert into public.role_permissions(role_id,permission_id) values(v_manager,v_receive) on conflict do nothing;
  insert into public.role_permissions(role_id,permission_id) values(v_finance,v_invoice_create) on conflict do nothing;

  if (select count(*) from public.role_permissions where permission_id=v_approve)<>1 then
    raise exception 'PROCUREMENT_APPROVE_MAPPING_INVALID';
  end if;
  if exists(
    select 1 from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_approve and r.code<>'BOARD'
  ) then raise exception 'PROCUREMENT_APPROVE_NON_BOARD_MAPPING_PRESENT'; end if;
  if exists(
    select 1 from public.role_permissions rp
    join public.permissions p on p.id=rp.permission_id
    join public.roles r on r.id=rp.role_id
    where r.code='SUPERVISOR'
      and p.code in ('PURCHASE_CREATE','PURCHASE_SUBMIT','PURCHASE_APPROVE','PURCHASE_RECEIVE','PURCHASE_INVOICE_CREATE','PURCHASE_MATCH')
  ) then raise exception 'PROCUREMENT_SUPERVISOR_MUST_REMAIN_READ_ONLY'; end if;
end $$;

-- 2) Release-specific ACTIVE policies, scoped only to DEMO-KDKMP-DEV.
do $$
declare
  v_org uuid;
  v_node uuid;
  v_policy uuid;
  v_version uuid;
begin
  select o.id,n.id into v_org,v_node
  from public.organizations o
  join public.organization_nodes n on n.organization_id=o.id
  where o.code='DEMO-KDKMP-DEV' and n.code='DEMO-KDKMP' and n.node_type='KDKMP'
  limit 1;
  if v_org is null or v_node is null then raise exception 'PROCUREMENT_DEVELOPMENT_SCOPE_NOT_FOUND'; end if;

  insert into public.approval_policies(
    organization_id,organization_node_id,code,name,domain,transaction_type,status,notes
  ) values
    (v_org,v_node,'DEMO-PROC-REQUISITION','DEMO — Persetujuan Purchase Requisition','PROCUREMENT','PURCHASE_REQUISITION','ACTIVE',
     'Release-1 DEVELOPMENT UAT only: MANAGER requester -> BOARD approval.'),
    (v_org,v_node,'DEMO-PROC-PO','DEMO — Persetujuan Purchase Order','PROCUREMENT','PURCHASE_ORDER','ACTIVE',
     'Release-1 DEVELOPMENT UAT only: MANAGER creator -> BOARD approval.')
  on conflict(organization_node_id,code) do update
  set status='ACTIVE',updated_at=now(),notes=excluded.notes;

  for v_policy in
    select id from public.approval_policies
    where organization_id=v_org and organization_node_id=v_node
      and code in ('DEMO-PROC-REQUISITION','DEMO-PROC-PO')
  loop
    insert into public.approval_policy_versions(
      approval_policy_id,organization_id,organization_node_id,version_no,condition_config,status,effective_from,effective_until
    ) values(v_policy,v_org,v_node,1,'{}'::jsonb,'ACTIVE',timestamptz '2026-08-19 00:00:00+00',null)
    on conflict(approval_policy_id,version_no) do update
      set status='ACTIVE',effective_from=coalesce(public.approval_policy_versions.effective_from,excluded.effective_from),effective_until=null;

    select id into v_version from public.approval_policy_versions
    where approval_policy_id=v_policy and version_no=1;

    insert into public.approval_policy_steps(
      approval_policy_version_id,organization_id,organization_node_id,step_no,step_name,
      required_permission_code,min_approvers,quorum_rule,prohibit_requester_approval,
      prohibit_previous_step_actor,require_conflict_declaration,allow_delegation
    ) values(
      v_version,v_org,v_node,1,'BOARD Procurement Approval','PURCHASE_APPROVE',1,'ALL_REQUIRED',true,false,true,false
    )
    on conflict(approval_policy_version_id,step_no) do update
    set step_name=excluded.step_name,required_permission_code='PURCHASE_APPROVE',min_approvers=1,
        quorum_rule='ALL_REQUIRED',prohibit_requester_approval=true,prohibit_previous_step_actor=false,
        require_conflict_declaration=true,allow_delegation=false;
  end loop;

  insert into public.sod_rules(
    organization_id,organization_node_id,code,name,domain,transaction_type,rule_type,
    subject_permission_code,conflicting_permission_code,status,effective_from,notes
  ) values(
    v_org,v_node,'PROCUREMENT-REQUESTER-APPROVER','Procurement requester cannot approve own request',
    'PROCUREMENT',null,'REQUESTER_CANNOT_APPROVE','PURCHASE_SUBMIT','PURCHASE_APPROVE','ACTIVE',
    timestamptz '2026-08-19 00:00:00+00','Enforced by procurement approval commands; Release-1 DEVELOPMENT UAT.'
  )
  on conflict(organization_node_id,code) do update
  set status='ACTIVE',effective_until=null,notes=excluded.notes;
end $$;

-- 3) Explicit synthetic supplier fixture for controlled UAT only.
with o as (
  select id from public.organizations where code='DEMO-KDKMP-DEV' limit 1
), n as (
  select id from public.organization_nodes where code='DEMO-KDKMP' and organization_id=(select id from o) limit 1
)
insert into public.suppliers(
  organization_id,organization_node_id,code,name,legal_name,supplier_type,
  qualification_status,risk_status,tax_profile_status,regulatory_status,status,notes
)
select o.id,n.id,'UAT-SUP-PANGAN','UAT — Supplier Pangan Terkontrol','UAT — Supplier Pangan Terkontrol',
       'DISTRIBUTOR','QUALIFIED','LOW','NOT_CONFIGURED','NOT_REQUIRED','ACTIVE',
       'Synthetic DEVELOPMENT/UAT fixture only. Qualification is not evidence of a real supplier due-diligence decision.'
from o,n
on conflict(organization_node_id,code) do update
set status='ACTIVE',qualification_status='QUALIFIED',risk_status='LOW',notes=excluded.notes,updated_at=now();

-- 4) Append-only command ledger for idempotency and correlation.
create table app_private.procurement_commands(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  organization_node_id uuid not null references public.organization_nodes(id) on delete restrict,
  actor_profile_id uuid not null references public.profiles(id) on delete restrict,
  command_type text not null check(command_type in (
    'CREATE_SUBMIT_REQUISITION','APPROVE_REQUISITION','CREATE_SUBMIT_PO',
    'APPROVE_PO','RECEIVE_PO','CREATE_MATCH_INVOICE'
  )),
  idempotency_key text not null,
  request_hash text not null,
  source_entity_id uuid,
  result_entity_id uuid,
  result_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(actor_profile_id,command_type,idempotency_key)
);
revoke all on table app_private.procurement_commands from public,anon,authenticated;
grant select,insert on table app_private.procurement_commands to service_role;

create or replace function app_private.procurement_profile_for(p_permission text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_profile uuid;
begin
  if v_uid is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select p.id into v_profile from public.profiles p
  where p.auth_user_id=v_uid and p.status='ACTIVE' limit 1;
  if v_profile is null then raise exception using errcode='42501',message='PROCUREMENT_CONTEXT_UNAVAILABLE'; end if;
  if not app_private.has_permission(p_permission) then
    raise exception using errcode='42501',message='PROCUREMENT_PERMISSION_DENIED';
  end if;
  return v_profile;
end;
$$;
revoke all on function app_private.procurement_profile_for(text) from public,anon,authenticated;

create or replace function app_private.create_procurement_approval_request(
  p_entity_type text,
  p_entity_id uuid,
  p_source_reference text,
  p_requested_by uuid,
  p_organization_id uuid,
  p_organization_node_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_transaction_type text;
  v_version uuid;
  v_step public.approval_policy_steps%rowtype;
  v_request uuid;
begin
  v_transaction_type:=case p_entity_type
    when 'PURCHASE_REQUISITION' then 'PURCHASE_REQUISITION'
    when 'PURCHASE_ORDER' then 'PURCHASE_ORDER'
    else null end;
  if v_transaction_type is null then raise exception 'PROCUREMENT_APPROVAL_ENTITY_INVALID'; end if;

  select apv.id into v_version
  from public.approval_policies ap
  join public.approval_policy_versions apv on apv.approval_policy_id=ap.id
  where ap.organization_id=p_organization_id and ap.organization_node_id=p_organization_node_id
    and ap.domain='PROCUREMENT' and ap.transaction_type=v_transaction_type
    and ap.status='ACTIVE' and apv.status='ACTIVE'
    and (apv.effective_from is null or apv.effective_from<=now())
    and (apv.effective_until is null or apv.effective_until>now())
  order by apv.version_no desc limit 1;
  if v_version is null then raise exception using errcode='42501',message='PROCUREMENT_APPROVAL_POLICY_NOT_ACTIVE'; end if;

  select * into v_step from public.approval_policy_steps
  where approval_policy_version_id=v_version and step_no=1;
  if not found or v_step.required_permission_code<>'PURCHASE_APPROVE'
     or v_step.prohibit_requester_approval is not true
     or v_step.require_conflict_declaration is not true
     or v_step.allow_delegation is not false then
    raise exception using errcode='42501',message='PROCUREMENT_APPROVAL_POLICY_INVALID';
  end if;

  insert into public.approval_requests(
    organization_id,organization_node_id,approval_policy_version_id,source_domain,source_entity_type,
    source_entity_id,source_reference,correlation_id,requested_by,request_snapshot,policy_snapshot,status,current_step_no
  ) values(
    p_organization_id,p_organization_node_id,v_version,'PROCUREMENT',p_entity_type,p_entity_id,p_source_reference,
    'PROCUREMENT:'||p_entity_type||':'||p_entity_id::text,p_requested_by,
    jsonb_build_object('entity_id',p_entity_id,'source_reference',p_source_reference,'requested_by',p_requested_by),
    jsonb_build_object('required_permission_code',v_step.required_permission_code,
      'prohibit_requester_approval',v_step.prohibit_requester_approval,
      'require_conflict_declaration',v_step.require_conflict_declaration,'allow_delegation',v_step.allow_delegation),
    'IN_REVIEW',1
  ) on conflict(organization_node_id,source_domain,source_entity_type,source_entity_id,correlation_id) do nothing;

  select id into v_request from public.approval_requests
  where organization_node_id=p_organization_node_id and source_domain='PROCUREMENT'
    and source_entity_type=p_entity_type and source_entity_id=p_entity_id
    and correlation_id='PROCUREMENT:'||p_entity_type||':'||p_entity_id::text limit 1;
  if v_request is null then raise exception 'PROCUREMENT_APPROVAL_REQUEST_CREATE_FAILED'; end if;

  insert into public.approval_request_steps(
    approval_request_id,organization_id,organization_node_id,step_no,step_name,required_permission_code,
    min_approvers,quorum_rule,prohibit_requester_approval,prohibit_previous_step_actor,
    require_conflict_declaration,allow_delegation,status,activated_at
  ) values(
    v_request,p_organization_id,p_organization_node_id,v_step.step_no,v_step.step_name,v_step.required_permission_code,
    v_step.min_approvers,v_step.quorum_rule,v_step.prohibit_requester_approval,v_step.prohibit_previous_step_actor,
    v_step.require_conflict_declaration,v_step.allow_delegation,'ACTIVE',now()
  ) on conflict(approval_request_id,step_no) do nothing;
  return v_request;
end;
$$;
revoke all on function app_private.create_procurement_approval_request(text,uuid,text,uuid,uuid,uuid) from public,anon,authenticated;

-- 5) MANAGER creates and submits a requisition atomically.
create or replace function app_private.create_submit_purchase_requisition(
  p_organization_unit_id uuid,
  p_purpose text,
  p_required_date date,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile uuid; v_org uuid; v_node uuid;
  v_id uuid:=gen_random_uuid(); v_number text; v_approval uuid;
  v_hash text; v_existing app_private.procurement_commands%rowtype; v_invalid int;
  v_payload jsonb;
begin
  v_profile:=app_private.procurement_profile_for('PURCHASE_CREATE');
  if not app_private.has_permission('PURCHASE_SUBMIT') then raise exception using errcode='42501',message='PROCUREMENT_SUBMIT_DENIED'; end if;
  select organization_id into v_org from public.profiles where id=v_profile;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='PROCUREMENT_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_purpose is null or btrim(p_purpose)='' or length(p_purpose)>500 then raise exception using errcode='22023',message='PROCUREMENT_PURPOSE_INVALID'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>100 then raise exception using errcode='22023',message='PROCUREMENT_LINES_INVALID'; end if;

  select ou.organization_node_id into v_node from public.organization_units ou
  where ou.id=p_organization_unit_id and ou.organization_id=v_org and ou.status='ACTIVE';
  if v_node is null or not app_private.has_data_scope(v_org,v_node,p_organization_unit_id,null,null) then raise exception using errcode='42501',message='PROCUREMENT_SCOPE_DENIED'; end if;

  v_hash:=md5(jsonb_build_object('unit',p_organization_unit_id,'purpose',btrim(p_purpose),'required_date',p_required_date,'lines',p_lines)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile::text||':CREATE_SUBMIT_REQUISITION:'||p_idempotency_key,0));
  select * into v_existing from app_private.procurement_commands
  where actor_profile_id=v_profile and command_type='CREATE_SUBMIT_REQUISITION' and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then raise exception using errcode='23505',message='PROCUREMENT_IDEMPOTENCY_CONFLICT'; end if;
    return v_existing.result_payload||jsonb_build_object('idempotent_replay',true);
  end if;

  select count(*) into v_invalid
  from jsonb_to_recordset(p_lines) as x(inventory_item_id uuid,uom_id uuid,quantity numeric,estimated_unit_price numeric,description text,notes text)
  left join public.inventory_items i on i.id=x.inventory_item_id and i.organization_id=v_org and i.organization_node_id=v_node and i.status='ACTIVE'
  left join public.inventory_uoms u on u.id=x.uom_id and u.organization_id=v_org and u.organization_node_id=v_node and u.status='ACTIVE'
  where i.id is null or u.id is null or x.quantity is null or x.quantity<=0
     or x.estimated_unit_price is null or x.estimated_unit_price<0
     or not (x.uom_id=i.base_uom_id or exists(
       select 1 from public.inventory_item_uom_conversions c
       where c.inventory_item_id=i.id and c.uom_id=x.uom_id and c.status='ACTIVE'
     ));
  if v_invalid>0 then raise exception using errcode='23514',message='PROCUREMENT_LINE_REFERENCE_INVALID'; end if;

  v_number:='PR-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_id::text,'-',''),1,8));
  insert into public.purchase_requisitions(id,organization_id,organization_node_id,organization_unit_id,requisition_number,requested_by,purpose,required_date,status)
  values(v_id,v_org,v_node,p_organization_unit_id,v_number,v_profile,btrim(p_purpose),p_required_date,'DRAFT');

  insert into public.purchase_requisition_lines(
    organization_id,organization_node_id,organization_unit_id,purchase_requisition_id,line_no,
    inventory_item_id,description,uom_id,quantity,estimated_unit_price,notes
  )
  select v_org,v_node,p_organization_unit_id,v_id,e.ord::int,
         (e.value->>'inventory_item_id')::uuid,
         coalesce(nullif(btrim(e.value->>'description'),''),(select name from public.inventory_items where id=(e.value->>'inventory_item_id')::uuid)),
         (e.value->>'uom_id')::uuid,(e.value->>'quantity')::numeric,(e.value->>'estimated_unit_price')::numeric,
         nullif(btrim(e.value->>'notes'),'')
  from jsonb_array_elements(p_lines) with ordinality e(value,ord);

  v_approval:=app_private.create_procurement_approval_request('PURCHASE_REQUISITION',v_id,v_number,v_profile,v_org,v_node);
  update public.purchase_requisitions set status='PENDING_APPROVAL',approval_request_id=v_approval,submitted_at=now(),updated_at=now() where id=v_id;

  v_payload:=jsonb_build_object('purchase_requisition_id',v_id,'requisition_number',v_number,'status','PENDING_APPROVAL','approval_request_id',v_approval);
  insert into app_private.procurement_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,source_entity_id,result_entity_id,result_payload)
  values(v_org,v_node,v_profile,'CREATE_SUBMIT_REQUISITION',p_idempotency_key,v_hash,v_id,v_id,v_payload);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id)
  values(v_org,v_profile,'PROCUREMENT_REQUISITION_SUBMITTED','PURCHASE_REQUISITION',v_id,v_payload,btrim(p_purpose),p_idempotency_key);
  return v_payload||jsonb_build_object('idempotent_replay',false);
end;
$$;

-- 6) Generic BOARD approval for requisition or PO.
create or replace function app_private.approve_procurement_entity(
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_conflict_declared boolean
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile uuid; v_org uuid; v_node uuid; v_unit uuid; v_status text; v_reference text; v_request_id uuid; v_requester uuid;
  v_request public.approval_requests%rowtype; v_step public.approval_request_steps%rowtype;
  v_command text; v_hash text; v_existing app_private.procurement_commands%rowtype; v_payload jsonb; v_req_id uuid;
begin
  v_profile:=app_private.procurement_profile_for('PURCHASE_APPROVE');
  select organization_id into v_org from public.profiles where id=v_profile;
  if p_entity_type not in ('PURCHASE_REQUISITION','PURCHASE_ORDER') then raise exception using errcode='22023',message='PROCUREMENT_APPROVAL_ENTITY_INVALID'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='PROCUREMENT_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_reason is null or btrim(p_reason)='' or length(p_reason)>500 then raise exception using errcode='22023',message='PROCUREMENT_APPROVAL_REASON_REQUIRED'; end if;
  if p_conflict_declared is not true then raise exception using errcode='42501',message='PROCUREMENT_CONFLICT_DECLARATION_REQUIRED'; end if;
  v_command:=case when p_entity_type='PURCHASE_REQUISITION' then 'APPROVE_REQUISITION' else 'APPROVE_PO' end;
  v_hash:=md5(jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'reason',btrim(p_reason),'conflict',p_conflict_declared)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile::text||':'||v_command||':'||p_idempotency_key,0));
  select * into v_existing from app_private.procurement_commands where actor_profile_id=v_profile and command_type=v_command and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then raise exception using errcode='23505',message='PROCUREMENT_IDEMPOTENCY_CONFLICT'; end if;
    return v_existing.result_payload||jsonb_build_object('idempotent_replay',true);
  end if;

  if p_entity_type='PURCHASE_REQUISITION' then
    select organization_node_id,organization_unit_id,status,requisition_number,approval_request_id,requested_by
      into v_node,v_unit,v_status,v_reference,v_request_id,v_requester
    from public.purchase_requisitions where id=p_entity_id and organization_id=v_org for update;
  else
    select organization_node_id,organization_unit_id,status,po_number,approval_request_id,created_by,purchase_requisition_id
      into v_node,v_unit,v_status,v_reference,v_request_id,v_requester,v_req_id
    from public.purchase_orders where id=p_entity_id and organization_id=v_org for update;
  end if;
  if v_node is null then raise exception using errcode='42501',message='PROCUREMENT_ENTITY_NOT_ACCESSIBLE'; end if;
  if not app_private.has_data_scope(v_org,v_node,v_unit,null,null) then raise exception using errcode='42501',message='PROCUREMENT_SCOPE_DENIED'; end if;
  if v_status<>'PENDING_APPROVAL' or v_request_id is null then raise exception using errcode='23514',message='PROCUREMENT_ENTITY_NOT_PENDING_APPROVAL'; end if;
  if v_requester=v_profile then raise exception using errcode='42501',message='PROCUREMENT_REQUESTER_CANNOT_APPROVE'; end if;

  select * into v_request from public.approval_requests where id=v_request_id for update;
  if not found or v_request.source_domain<>'PROCUREMENT' or v_request.source_entity_type<>p_entity_type
     or v_request.source_entity_id<>p_entity_id or v_request.status not in ('PENDING','IN_REVIEW') then
    raise exception using errcode='42501',message='PROCUREMENT_APPROVAL_REQUEST_INVALID'; end if;
  if v_request.requested_by=v_profile then raise exception using errcode='42501',message='PROCUREMENT_REQUESTER_CANNOT_APPROVE'; end if;
  select * into v_step from public.approval_request_steps where approval_request_id=v_request_id and step_no=1 for update;
  if not found or v_step.status<>'ACTIVE' or v_step.required_permission_code<>'PURCHASE_APPROVE'
     or v_step.require_conflict_declaration is not true then raise exception using errcode='42501',message='PROCUREMENT_APPROVAL_STEP_INVALID'; end if;

  insert into public.approval_decisions(approval_request_id,approval_request_step_id,organization_id,organization_node_id,actor_profile_id,decision,conflict_declared,reason,evidence)
  values(v_request_id,v_step.id,v_org,v_node,v_profile,'APPROVE',true,btrim(p_reason),jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id));
  update public.approval_request_steps set status='APPROVED',completed_at=now() where id=v_step.id;
  update public.approval_requests set status='APPROVED',completed_at=now() where id=v_request_id;

  if p_entity_type='PURCHASE_REQUISITION' then
    update public.purchase_requisitions set status='APPROVED',decided_at=now(),updated_at=now() where id=p_entity_id;
  else
    update public.purchase_orders set status='APPROVED',approved_at=now(),updated_at=now() where id=p_entity_id;
    if v_req_id is not null then update public.purchase_requisitions set status='CONVERTED',updated_at=now() where id=v_req_id and status='APPROVED'; end if;
  end if;

  v_payload:=jsonb_build_object('entity_type',p_entity_type,'entity_id',p_entity_id,'status','APPROVED','approval_request_id',v_request_id);
  insert into app_private.procurement_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,source_entity_id,result_entity_id,result_payload)
  values(v_org,v_node,v_profile,v_command,p_idempotency_key,v_hash,p_entity_id,p_entity_id,v_payload);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason,request_id)
  values(v_org,v_profile,'PROCUREMENT_'||v_command,p_entity_type,p_entity_id,jsonb_build_object('status','PENDING_APPROVAL'),v_payload,btrim(p_reason),p_idempotency_key);
  return v_payload||jsonb_build_object('idempotent_replay',false);
end;
$$;

-- 7) MANAGER converts approved requisition into a PO and submits it for BOARD approval.
create or replace function app_private.create_submit_purchase_order(
  p_purchase_requisition_id uuid,
  p_supplier_id uuid,
  p_expected_delivery_date date,
  p_delivery_location_text text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile uuid; v_org uuid; v_req public.purchase_requisitions%rowtype; v_supplier public.suppliers%rowtype;
  v_id uuid:=gen_random_uuid(); v_number text; v_approval uuid; v_hash text;
  v_existing app_private.procurement_commands%rowtype; v_payload jsonb;
begin
  v_profile:=app_private.procurement_profile_for('PURCHASE_CREATE');
  if not app_private.has_permission('PURCHASE_SUBMIT') then raise exception using errcode='42501',message='PROCUREMENT_SUBMIT_DENIED'; end if;
  select organization_id into v_org from public.profiles where id=v_profile;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='PROCUREMENT_IDEMPOTENCY_KEY_INVALID'; end if;
  v_hash:=md5(jsonb_build_object('requisition',p_purchase_requisition_id,'supplier',p_supplier_id,'expected_delivery',p_expected_delivery_date,'delivery_location',p_delivery_location_text)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile::text||':CREATE_SUBMIT_PO:'||p_idempotency_key,0));
  select * into v_existing from app_private.procurement_commands where actor_profile_id=v_profile and command_type='CREATE_SUBMIT_PO' and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then raise exception using errcode='23505',message='PROCUREMENT_IDEMPOTENCY_CONFLICT'; end if;
    return v_existing.result_payload||jsonb_build_object('idempotent_replay',true);
  end if;

  select * into v_req from public.purchase_requisitions where id=p_purchase_requisition_id and organization_id=v_org for update;
  if not found then raise exception using errcode='42501',message='PROCUREMENT_REQUISITION_NOT_ACCESSIBLE'; end if;
  if v_req.status<>'APPROVED' then raise exception using errcode='23514',message='PROCUREMENT_REQUISITION_NOT_APPROVED'; end if;
  if not app_private.has_data_scope(v_req.organization_id,v_req.organization_node_id,v_req.organization_unit_id,null,null) then raise exception using errcode='42501',message='PROCUREMENT_SCOPE_DENIED'; end if;
  if exists(select 1 from public.purchase_orders po where po.purchase_requisition_id=v_req.id and po.status<>'CANCELLED') then raise exception using errcode='23505',message='PROCUREMENT_REQUISITION_ALREADY_CONVERTED'; end if;
  if exists(select 1 from public.purchase_requisition_lines l where l.purchase_requisition_id=v_req.id and l.estimated_unit_price is null) then raise exception using errcode='23514',message='PROCUREMENT_REQUISITION_PRICE_REQUIRED'; end if;

  select * into v_supplier from public.suppliers where id=p_supplier_id and organization_id=v_org and organization_node_id=v_req.organization_node_id;
  if not found or v_supplier.status<>'ACTIVE' or v_supplier.qualification_status<>'QUALIFIED' then raise exception using errcode='23514',message='PROCUREMENT_SUPPLIER_NOT_QUALIFIED'; end if;

  v_number:='PO-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_id::text,'-',''),1,8));
  insert into public.purchase_orders(id,organization_id,organization_node_id,organization_unit_id,supplier_id,purchase_requisition_id,po_number,expected_delivery_date,delivery_location_text,terms_snapshot,supplier_snapshot,status,created_by)
  values(v_id,v_req.organization_id,v_req.organization_node_id,v_req.organization_unit_id,p_supplier_id,v_req.id,v_number,p_expected_delivery_date,nullif(btrim(coalesce(p_delivery_location_text,'')),''),'{}'::jsonb,
    jsonb_build_object('supplier_id',v_supplier.id,'code',v_supplier.code,'name',v_supplier.name,'qualification_status',v_supplier.qualification_status),'DRAFT',v_profile);
  insert into public.purchase_order_lines(organization_id,organization_node_id,organization_unit_id,purchase_order_id,line_no,inventory_item_id,description,uom_id,ordered_quantity,unit_price,tax_configuration_snapshot)
  select l.organization_id,l.organization_node_id,l.organization_unit_id,v_id,l.line_no,l.inventory_item_id,l.description,l.uom_id,l.quantity,l.estimated_unit_price,'{}'::jsonb
  from public.purchase_requisition_lines l where l.purchase_requisition_id=v_req.id order by l.line_no;

  v_approval:=app_private.create_procurement_approval_request('PURCHASE_ORDER',v_id,v_number,v_profile,v_req.organization_id,v_req.organization_node_id);
  update public.purchase_orders set status='PENDING_APPROVAL',approval_request_id=v_approval,updated_at=now() where id=v_id;
  v_payload:=jsonb_build_object('purchase_order_id',v_id,'po_number',v_number,'status','PENDING_APPROVAL','approval_request_id',v_approval,'purchase_requisition_id',v_req.id);
  insert into app_private.procurement_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,source_entity_id,result_entity_id,result_payload)
  values(v_req.organization_id,v_req.organization_node_id,v_profile,'CREATE_SUBMIT_PO',p_idempotency_key,v_hash,v_req.id,v_id,v_payload);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id)
  values(v_req.organization_id,v_profile,'PROCUREMENT_PO_SUBMITTED','PURCHASE_ORDER',v_id,v_payload,'Approved requisition converted and submitted.',p_idempotency_key);
  return v_payload||jsonb_build_object('idempotent_replay',false);
end;
$$;

-- 8) Controlled goods receiving writes to the same authoritative inventory ledger used by POS.
create or replace function app_private.receive_purchase_order(
  p_purchase_order_id uuid,
  p_warehouse_id uuid,
  p_warehouse_node_id uuid,
  p_lines jsonb,
  p_supplier_delivery_reference text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile uuid; v_org uuid; v_po public.purchase_orders%rowtype; v_wh public.warehouses%rowtype;
  v_receipt uuid:=gen_random_uuid(); v_movement uuid:=gen_random_uuid(); v_receipt_no text; v_movement_no text;
  v_hash text; v_existing app_private.procurement_commands%rowtype; v_invalid int; v_accepted numeric; v_new_status text; v_payload jsonb;
begin
  v_profile:=app_private.procurement_profile_for('PURCHASE_RECEIVE');
  select organization_id into v_org from public.profiles where id=v_profile;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='PROCUREMENT_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>100 then raise exception using errcode='22023',message='PROCUREMENT_RECEIPT_LINES_INVALID'; end if;
  v_hash:=md5(jsonb_build_object('po',p_purchase_order_id,'warehouse',p_warehouse_id,'warehouse_node',p_warehouse_node_id,'lines',p_lines,'delivery_ref',p_supplier_delivery_reference)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile::text||':RECEIVE_PO:'||p_idempotency_key,0));
  select * into v_existing from app_private.procurement_commands where actor_profile_id=v_profile and command_type='RECEIVE_PO' and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then raise exception using errcode='23505',message='PROCUREMENT_IDEMPOTENCY_CONFLICT'; end if;
    return v_existing.result_payload||jsonb_build_object('idempotent_replay',true);
  end if;
  select * into v_po from public.purchase_orders where id=p_purchase_order_id and organization_id=v_org for update;
  if not found then raise exception using errcode='42501',message='PROCUREMENT_PO_NOT_ACCESSIBLE'; end if;
  if v_po.status not in ('APPROVED','SENT','PARTIALLY_RECEIVED') then raise exception using errcode='23514',message='PROCUREMENT_PO_NOT_RECEIVABLE'; end if;
  if not app_private.has_data_scope(v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,null,null) then raise exception using errcode='42501',message='PROCUREMENT_SCOPE_DENIED'; end if;
  select * into v_wh from public.warehouses where id=p_warehouse_id and organization_id=v_org and organization_node_id=v_po.organization_node_id and organization_unit_id=v_po.organization_unit_id and status='ACTIVE';
  if not found then raise exception using errcode='23514',message='PROCUREMENT_WAREHOUSE_INVALID'; end if;
  if not exists(select 1 from public.warehouse_nodes wn where wn.id=p_warehouse_node_id and wn.warehouse_id=p_warehouse_id and wn.node_type='BIN' and wn.status='ACTIVE') then raise exception using errcode='23514',message='PROCUREMENT_WAREHOUSE_BIN_INVALID'; end if;

  select count(*) into v_invalid
  from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,delivered_quantity numeric,accepted_quantity numeric,rejected_quantity numeric,quarantined_quantity numeric)
  left join public.purchase_order_lines pol on pol.id=x.purchase_order_line_id and pol.purchase_order_id=v_po.id
  where pol.id is null or x.delivered_quantity is null or x.delivered_quantity<0
    or coalesce(x.accepted_quantity,0)<0 or coalesce(x.rejected_quantity,0)<0 or coalesce(x.quarantined_quantity,0)<0
    or coalesce(x.accepted_quantity,0)+coalesce(x.rejected_quantity,0)+coalesce(x.quarantined_quantity,0)>x.delivered_quantity
    or coalesce((select sum(grl.accepted_quantity) from public.goods_receipt_lines grl join public.goods_receipts gr on gr.id=grl.goods_receipt_id where gr.purchase_order_id=v_po.id and gr.status='POSTED' and grl.purchase_order_line_id=pol.id),0)+coalesce(x.accepted_quantity,0)>pol.ordered_quantity;
  if v_invalid>0 then raise exception using errcode='23514',message='PROCUREMENT_RECEIPT_LINE_INVALID_OR_OVER_RECEIPT'; end if;
  select coalesce(sum(coalesce(x.accepted_quantity,0)),0) into v_accepted from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,delivered_quantity numeric,accepted_quantity numeric,rejected_quantity numeric,quarantined_quantity numeric);
  if v_accepted<=0 then raise exception using errcode='23514',message='PROCUREMENT_RECEIPT_ACCEPTED_QUANTITY_REQUIRED'; end if;

  v_receipt_no:='GR-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_receipt::text,'-',''),1,8));
  v_movement_no:='RCV-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(v_movement::text,'-',''),1,8));
  insert into public.goods_receipts(id,organization_id,organization_node_id,organization_unit_id,warehouse_id,supplier_id,purchase_order_id,receipt_number,supplier_delivery_reference,received_at,status,accounting_status,received_by)
  values(v_receipt,v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,p_warehouse_id,v_po.supplier_id,v_po.id,v_receipt_no,nullif(btrim(coalesce(p_supplier_delivery_reference,'')),''),now(),'POSTED','NOT_POSTED',v_profile);
  insert into public.goods_receipt_lines(organization_id,organization_node_id,organization_unit_id,goods_receipt_id,purchase_order_line_id,line_no,inventory_item_id,uom_id,delivered_quantity,accepted_quantity,rejected_quantity,quarantined_quantity,qc_status)
  select v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,v_receipt,(e.value->>'purchase_order_line_id')::uuid,e.ord::int,
         pol.inventory_item_id,pol.uom_id,(e.value->>'delivered_quantity')::numeric,coalesce((e.value->>'accepted_quantity')::numeric,0),coalesce((e.value->>'rejected_quantity')::numeric,0),coalesce((e.value->>'quarantined_quantity')::numeric,0),
         case when coalesce((e.value->>'accepted_quantity')::numeric,0)=(e.value->>'delivered_quantity')::numeric then 'ACCEPTED' when coalesce((e.value->>'accepted_quantity')::numeric,0)>0 then 'PARTIAL' else 'REJECTED' end
  from jsonb_array_elements(p_lines) with ordinality e(value,ord)
  join public.purchase_order_lines pol on pol.id=(e.value->>'purchase_order_line_id')::uuid and pol.purchase_order_id=v_po.id;

  insert into public.inventory_movements(id,organization_id,organization_node_id,organization_unit_id,warehouse_id,movement_number,movement_type,status,source_domain,source_entity_type,source_entity_id,source_reference,idempotency_key,occurred_at,posted_at,created_by)
  values(v_movement,v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,p_warehouse_id,v_movement_no,'RECEIPT','POSTED','PROCUREMENT','GOODS_RECEIPT',v_receipt,v_receipt_no,p_idempotency_key,now(),now(),v_profile);
  insert into public.inventory_movement_lines(organization_id,organization_node_id,organization_unit_id,inventory_movement_id,line_no,inventory_item_id,uom_id,to_warehouse_node_id,to_stock_status,quantity,base_quantity,unit_cost,notes)
  select v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,v_movement,row_number() over(order by grl.line_no)::int,
         grl.inventory_item_id,grl.uom_id,p_warehouse_node_id,'AVAILABLE',grl.accepted_quantity,
         grl.accepted_quantity*case when grl.uom_id=i.base_uom_id then 1 else c.factor_to_base end,
         pol.unit_price,'Procurement goods receipt '||v_receipt_no
  from public.goods_receipt_lines grl
  join public.purchase_order_lines pol on pol.id=grl.purchase_order_line_id
  join public.inventory_items i on i.id=grl.inventory_item_id
  left join public.inventory_item_uom_conversions c on c.inventory_item_id=i.id and c.uom_id=grl.uom_id and c.status='ACTIVE'
  where grl.goods_receipt_id=v_receipt and grl.accepted_quantity>0
    and (grl.uom_id=i.base_uom_id or c.factor_to_base is not null);
  if (select count(*) from public.inventory_movement_lines where inventory_movement_id=v_movement)<>(select count(*) from public.goods_receipt_lines where goods_receipt_id=v_receipt and accepted_quantity>0) then raise exception using errcode='23514',message='PROCUREMENT_RECEIPT_UOM_CONVERSION_MISSING'; end if;
  update public.goods_receipts set inventory_movement_id=v_movement where id=v_receipt;

  if exists(
    select 1 from public.purchase_order_lines pol
    where pol.purchase_order_id=v_po.id
      and coalesce((select sum(grl.accepted_quantity) from public.goods_receipt_lines grl join public.goods_receipts gr on gr.id=grl.goods_receipt_id where gr.purchase_order_id=v_po.id and gr.status='POSTED' and grl.purchase_order_line_id=pol.id),0)<pol.ordered_quantity
  ) then v_new_status:='PARTIALLY_RECEIVED'; else v_new_status:='RECEIVED'; end if;
  update public.purchase_orders set status=v_new_status,updated_at=now() where id=v_po.id;

  v_payload:=jsonb_build_object('goods_receipt_id',v_receipt,'receipt_number',v_receipt_no,'inventory_movement_id',v_movement,'movement_number',v_movement_no,'accepted_quantity',v_accepted,'purchase_order_status',v_new_status);
  insert into app_private.procurement_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,source_entity_id,result_entity_id,result_payload)
  values(v_po.organization_id,v_po.organization_node_id,v_profile,'RECEIVE_PO',p_idempotency_key,v_hash,v_po.id,v_receipt,v_payload);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id)
  values(v_po.organization_id,v_profile,'PROCUREMENT_GOODS_RECEIPT_POSTED','GOODS_RECEIPT',v_receipt,v_payload,'Controlled procurement receiving.',p_idempotency_key);
  return v_payload||jsonb_build_object('idempotent_replay',false);
end;
$$;

-- 9) FINANCE records an invoice and runs authoritative three-way matching atomically.
create or replace function app_private.create_match_supplier_invoice(
  p_purchase_order_id uuid,
  p_invoice_number text,
  p_invoice_date date,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile uuid; v_org uuid; v_po public.purchase_orders%rowtype; v_invoice uuid:=gen_random_uuid(); v_match uuid:=gen_random_uuid();
  v_hash text; v_existing app_private.procurement_commands%rowtype; v_invalid int; v_subtotal numeric(20,2);
  v_po_amount numeric(20,2); v_received_value numeric(20,2); v_invoice_amount numeric(20,2); v_qty_variance numeric(20,6); v_amount_variance numeric(20,2);
  v_qty_mismatch boolean; v_price_mismatch boolean; v_amount_mismatch boolean; v_exceptions text[]; v_match_status text; v_payload jsonb;
begin
  v_profile:=app_private.procurement_profile_for('PURCHASE_INVOICE_CREATE');
  if not app_private.has_permission('PURCHASE_MATCH') then raise exception using errcode='42501',message='PROCUREMENT_MATCH_DENIED'; end if;
  select organization_id into v_org from public.profiles where id=v_profile;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then raise exception using errcode='22023',message='PROCUREMENT_IDEMPOTENCY_KEY_INVALID'; end if;
  if p_invoice_number is null or btrim(p_invoice_number)='' or length(p_invoice_number)>120 or p_invoice_date is null then raise exception using errcode='22023',message='PROCUREMENT_INVOICE_REFERENCE_INVALID'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>100 then raise exception using errcode='22023',message='PROCUREMENT_INVOICE_LINES_INVALID'; end if;
  v_hash:=md5(jsonb_build_object('po',p_purchase_order_id,'invoice_number',btrim(p_invoice_number),'invoice_date',p_invoice_date,'lines',p_lines)::text);
  perform pg_advisory_xact_lock(hashtextextended(v_profile::text||':CREATE_MATCH_INVOICE:'||p_idempotency_key,0));
  select * into v_existing from app_private.procurement_commands where actor_profile_id=v_profile and command_type='CREATE_MATCH_INVOICE' and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>v_hash then raise exception using errcode='23505',message='PROCUREMENT_IDEMPOTENCY_CONFLICT'; end if;
    return v_existing.result_payload||jsonb_build_object('idempotent_replay',true);
  end if;
  select * into v_po from public.purchase_orders where id=p_purchase_order_id and organization_id=v_org;
  if not found then raise exception using errcode='42501',message='PROCUREMENT_PO_NOT_ACCESSIBLE'; end if;
  if v_po.status not in ('PARTIALLY_RECEIVED','RECEIVED') then raise exception using errcode='23514',message='PROCUREMENT_PO_NOT_INVOICE_MATCHABLE'; end if;
  if not app_private.has_data_scope(v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,null,null) then raise exception using errcode='42501',message='PROCUREMENT_SCOPE_DENIED'; end if;

  select count(*) into v_invalid
  from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,quantity numeric,unit_price numeric,description text)
  left join public.purchase_order_lines pol on pol.id=x.purchase_order_line_id and pol.purchase_order_id=v_po.id
  where pol.id is null or x.quantity is null or x.quantity<0 or x.unit_price is null or x.unit_price<0;
  if v_invalid>0 then raise exception using errcode='23514',message='PROCUREMENT_INVOICE_LINE_INVALID'; end if;
  select coalesce(sum(x.quantity*x.unit_price),0)::numeric(20,2) into v_subtotal from jsonb_to_recordset(p_lines) as x(purchase_order_line_id uuid,quantity numeric,unit_price numeric,description text);

  insert into public.supplier_invoices(id,organization_id,organization_node_id,organization_unit_id,supplier_id,purchase_order_id,invoice_number,invoice_date,currency,subtotal,tax_amount,other_amount,status,matching_status)
  values(v_invoice,v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,v_po.supplier_id,v_po.id,btrim(p_invoice_number),p_invoice_date,v_po.currency,v_subtotal,0,0,'MATCH_PENDING','PENDING');
  insert into public.supplier_invoice_lines(organization_id,organization_node_id,organization_unit_id,supplier_invoice_id,purchase_order_line_id,line_no,description,quantity,unit_price)
  select v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,v_invoice,(e.value->>'purchase_order_line_id')::uuid,e.ord::int,
         coalesce(nullif(btrim(e.value->>'description'),''),pol.description),(e.value->>'quantity')::numeric,(e.value->>'unit_price')::numeric
  from jsonb_array_elements(p_lines) with ordinality e(value,ord)
  join public.purchase_order_lines pol on pol.id=(e.value->>'purchase_order_line_id')::uuid and pol.purchase_order_id=v_po.id;

  select coalesce(sum(ordered_quantity*unit_price),0)::numeric(20,2) into v_po_amount from public.purchase_order_lines where purchase_order_id=v_po.id;
  select coalesce(sum(grl.accepted_quantity*pol.unit_price),0)::numeric(20,2) into v_received_value
  from public.goods_receipt_lines grl join public.goods_receipts gr on gr.id=grl.goods_receipt_id
  join public.purchase_order_lines pol on pol.id=grl.purchase_order_line_id
  where gr.purchase_order_id=v_po.id and gr.status='POSTED';
  v_invoice_amount:=v_subtotal;
  select (coalesce(sum(sil.quantity),0)-coalesce(sum(r.accepted_quantity),0))::numeric(20,6) into v_qty_variance
  from public.purchase_order_lines pol
  left join public.supplier_invoice_lines sil on sil.purchase_order_line_id=pol.id and sil.supplier_invoice_id=v_invoice
  left join lateral (
    select sum(grl.accepted_quantity) accepted_quantity from public.goods_receipt_lines grl
    join public.goods_receipts gr on gr.id=grl.goods_receipt_id
    where gr.purchase_order_id=v_po.id and gr.status='POSTED' and grl.purchase_order_line_id=pol.id
  ) r on true
  where pol.purchase_order_id=v_po.id;
  v_amount_variance:=(v_invoice_amount-v_received_value)::numeric(20,2);

  select exists(
    select 1 from public.purchase_order_lines pol
    left join public.supplier_invoice_lines sil on sil.purchase_order_line_id=pol.id and sil.supplier_invoice_id=v_invoice
    left join lateral (
      select sum(grl.accepted_quantity) accepted_quantity from public.goods_receipt_lines grl
      join public.goods_receipts gr on gr.id=grl.goods_receipt_id
      where gr.purchase_order_id=v_po.id and gr.status='POSTED' and grl.purchase_order_line_id=pol.id
    ) r on true
    where pol.purchase_order_id=v_po.id and coalesce(sil.quantity,0)<>coalesce(r.accepted_quantity,0)
  ) into v_qty_mismatch;
  select exists(
    select 1 from public.supplier_invoice_lines sil join public.purchase_order_lines pol on pol.id=sil.purchase_order_line_id
    where sil.supplier_invoice_id=v_invoice and sil.unit_price<>pol.unit_price
  ) into v_price_mismatch;
  v_amount_mismatch:=v_invoice_amount<>v_received_value;
  v_exceptions:=array_remove(array[
    case when v_qty_mismatch then 'QUANTITY_MISMATCH' end,
    case when v_price_mismatch then 'PRICE_MISMATCH' end,
    case when v_amount_mismatch then 'AMOUNT_MISMATCH' end
  ],null);
  v_match_status:=case when coalesce(array_length(v_exceptions,1),0)=0 then 'MATCHED' else 'EXCEPTION' end;

  insert into public.purchase_match_results(id,organization_id,organization_node_id,organization_unit_id,supplier_invoice_id,purchase_order_id,match_type,status,po_amount,received_value,invoice_amount,quantity_variance,amount_variance,exception_codes,reviewed_by,reviewed_at)
  values(v_match,v_po.organization_id,v_po.organization_node_id,v_po.organization_unit_id,v_invoice,v_po.id,'THREE_WAY',v_match_status,v_po_amount,v_received_value,v_invoice_amount,v_qty_variance,v_amount_variance,v_exceptions,v_profile,now());
  update public.supplier_invoices set matching_status=v_match_status,status=case when v_match_status='MATCHED' then 'MATCHED' else 'EXCEPTION' end where id=v_invoice;

  v_payload:=jsonb_build_object('supplier_invoice_id',v_invoice,'invoice_number',btrim(p_invoice_number),'match_result_id',v_match,'match_status',v_match_status,'po_amount',v_po_amount,'received_value',v_received_value,'invoice_amount',v_invoice_amount,'quantity_variance',v_qty_variance,'amount_variance',v_amount_variance,'exception_codes',to_jsonb(v_exceptions));
  insert into app_private.procurement_commands(organization_id,organization_node_id,actor_profile_id,command_type,idempotency_key,request_hash,source_entity_id,result_entity_id,result_payload)
  values(v_po.organization_id,v_po.organization_node_id,v_profile,'CREATE_MATCH_INVOICE',p_idempotency_key,v_hash,v_po.id,v_invoice,v_payload);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason,request_id)
  values(v_po.organization_id,v_profile,'PROCUREMENT_THREE_WAY_MATCH_'||v_match_status,'SUPPLIER_INVOICE',v_invoice,v_payload,'Supplier invoice recorded and three-way match executed.',p_idempotency_key);
  return v_payload||jsonb_build_object('idempotent_replay',false);
end;
$$;

-- Public command surface.
create or replace function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.create_submit_purchase_requisition($1,$2,$3,$4,$5); $$;
create or replace function public.approve_purchase_requisition(uuid,text,text,boolean)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.approve_procurement_entity('PURCHASE_REQUISITION',$1,$2,$3,$4); $$;
create or replace function public.create_submit_purchase_order(uuid,uuid,date,text,text)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.create_submit_purchase_order($1,$2,$3,$4,$5); $$;
create or replace function public.approve_purchase_order(uuid,text,text,boolean)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.approve_procurement_entity('PURCHASE_ORDER',$1,$2,$3,$4); $$;
create or replace function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.receive_purchase_order($1,$2,$3,$4,$5,$6); $$;
create or replace function public.create_match_supplier_invoice(uuid,text,date,jsonb,text)
returns jsonb language sql security invoker set search_path=''
as $$ select app_private.create_match_supplier_invoice($1,$2,$3,$4,$5); $$;

revoke all on function app_private.create_submit_purchase_requisition(uuid,text,date,jsonb,text) from public,anon;
revoke all on function app_private.approve_procurement_entity(text,uuid,text,text,boolean) from public,anon;
revoke all on function app_private.create_submit_purchase_order(uuid,uuid,date,text,text) from public,anon;
revoke all on function app_private.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) from public,anon;
revoke all on function app_private.create_match_supplier_invoice(uuid,text,date,jsonb,text) from public,anon;
grant execute on function app_private.create_submit_purchase_requisition(uuid,text,date,jsonb,text) to authenticated,service_role;
grant execute on function app_private.approve_procurement_entity(text,uuid,text,text,boolean) to authenticated,service_role;
grant execute on function app_private.create_submit_purchase_order(uuid,uuid,date,text,text) to authenticated,service_role;
grant execute on function app_private.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function app_private.create_match_supplier_invoice(uuid,text,date,jsonb,text) to authenticated,service_role;

revoke all on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) from public,anon;
revoke all on function public.approve_purchase_requisition(uuid,text,text,boolean) from public,anon;
revoke all on function public.create_submit_purchase_order(uuid,uuid,date,text,text) from public,anon;
revoke all on function public.approve_purchase_order(uuid,text,text,boolean) from public,anon;
revoke all on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) from public,anon;
revoke all on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) from public,anon;
grant execute on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) to authenticated,service_role;
grant execute on function public.approve_purchase_requisition(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function public.create_submit_purchase_order(uuid,uuid,date,text,text) to authenticated,service_role;
grant execute on function public.approve_purchase_order(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) to authenticated,service_role;

comment on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) is 'Controlled Release-1 requisition create+submit command. Requires PURCHASE_CREATE + PURCHASE_SUBMIT and scope.';
comment on function public.approve_purchase_requisition(uuid,text,text,boolean) is 'BOARD procurement approval command. Requester self-approval denied and conflict declaration required.';
comment on function public.create_submit_purchase_order(uuid,uuid,date,text,text) is 'Create and submit a PO only from an approved requisition and qualified supplier.';
comment on function public.approve_purchase_order(uuid,text,text,boolean) is 'BOARD PO approval command under active PROCUREMENT policy.';
comment on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) is 'Controlled receiving command. Posts RECEIPT inventory movement to authoritative stock ledger.';
comment on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) is 'FINANCE supplier invoice + authoritative three-way match command. Mismatch produces EXCEPTION, never silent match.';

-- 10) Migration assertions.
do $$
declare v_approve uuid;
begin
  select id into v_approve from public.permissions where code='PURCHASE_APPROVE';
  if (select count(*) from public.role_permissions where permission_id=v_approve)<>1 then raise exception 'PROCUREMENT_APPROVE_MAPPING_ASSERTION_FAILED'; end if;
  if not exists(select 1 from public.role_permissions rp join public.roles r on r.id=rp.role_id where rp.permission_id=v_approve and r.code='BOARD') then raise exception 'PROCUREMENT_BOARD_APPROVAL_MAPPING_MISSING'; end if;
  if (select count(*) from public.approval_policies where code in ('DEMO-PROC-REQUISITION','DEMO-PROC-PO') and status='ACTIVE')<>2 then raise exception 'PROCUREMENT_ACTIVE_POLICY_ASSERTION_FAILED'; end if;
  if has_function_privilege('anon','public.create_submit_purchase_requisition(uuid,text,date,jsonb,text)','EXECUTE')
     or has_function_privilege('anon','public.approve_purchase_requisition(uuid,text,text,boolean)','EXECUTE')
     or has_function_privilege('anon','public.create_submit_purchase_order(uuid,uuid,date,text,text)','EXECUTE')
     or has_function_privilege('anon','public.approve_purchase_order(uuid,text,text,boolean)','EXECUTE')
     or has_function_privilege('anon','public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text)','EXECUTE')
     or has_function_privilege('anon','public.create_match_supplier_invoice(uuid,text,date,jsonb,text)','EXECUTE') then
    raise exception 'PROCUREMENT_ANON_COMMAND_EXECUTE_FORBIDDEN';
  end if;
end $$;
