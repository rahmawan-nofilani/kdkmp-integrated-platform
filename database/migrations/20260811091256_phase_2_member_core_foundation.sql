create table public.members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  member_number text,
  full_name text not null,
  status text not null default 'APPLICANT' check (status in ('APPLICANT','UNDER_REVIEW','ACTIVE','SUSPENDED','INACTIVE','RESIGNED','TERMINATED','ARCHIVED')),
  membership_date date,
  termination_date date,
  notes text,
  created_by uuid references public.profiles(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index uq_members_org_member_number on public.members(organization_id, member_number) where member_number is not null;
create index idx_members_org_status on public.members(organization_id, status);
create index idx_members_org_name on public.members(organization_id, full_name);

create table public.member_status_history (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  from_status text,
  to_status text not null check (to_status in ('APPLICANT','UNDER_REVIEW','ACTIVE','SUSPENDED','INACTIVE','RESIGNED','TERMINATED','ARCHIVED')),
  effective_at timestamptz not null default now(),
  reason text,
  changed_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index idx_member_status_history_member on public.member_status_history(member_id, effective_at desc);
create index idx_member_status_history_org on public.member_status_history(organization_id, effective_at desc);

create table public.member_status_transition_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete restrict,
  from_status text not null,
  to_status text not null,
  enabled boolean not null default true,
  requires_reason boolean not null default false,
  policy_status text not null default 'ACTIVE' check (policy_status in ('DRAFT','ACTIVE','SUSPENDED','ARCHIVED')),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index uq_member_transition_scope on public.member_status_transition_rules(coalesce(organization_id, '00000000-0000-0000-0000-000000000000'::uuid), from_status, to_status);

insert into public.member_status_transition_rules(from_status,to_status,requires_reason,description) values
('APPLICANT','UNDER_REVIEW',false,'Architecture default; subject to final cooperative policy validation.'),
('UNDER_REVIEW','ACTIVE',false,'Architecture default; subject to final cooperative policy validation.'),
('UNDER_REVIEW','INACTIVE',true,'Architecture default; subject to final cooperative policy validation.'),
('ACTIVE','SUSPENDED',true,'Architecture default; subject to final cooperative policy validation.'),
('ACTIVE','INACTIVE',true,'Architecture default; subject to final cooperative policy validation.'),
('ACTIVE','RESIGNED',true,'Architecture default; subject to final cooperative policy validation.'),
('ACTIVE','TERMINATED',true,'Architecture default; subject to final cooperative policy validation.'),
('SUSPENDED','ACTIVE',true,'Architecture default; subject to final cooperative policy validation.'),
('SUSPENDED','INACTIVE',true,'Architecture default; subject to final cooperative policy validation.'),
('SUSPENDED','TERMINATED',true,'Architecture default; subject to final cooperative policy validation.'),
('INACTIVE','ACTIVE',true,'Architecture default; subject to final cooperative policy validation.'),
('INACTIVE','ARCHIVED',true,'Architecture default; subject to final cooperative policy validation.'),
('RESIGNED','ARCHIVED',true,'Architecture default; subject to final cooperative policy validation.'),
('TERMINATED','ARCHIVED',true,'Architecture default; subject to final cooperative policy validation.');

alter table public.members enable row level security;
alter table public.member_status_history enable row level security;
alter table public.member_status_transition_rules enable row level security;

revoke all on public.members from anon, authenticated;
revoke all on public.member_status_history from anon, authenticated;
revoke all on public.member_status_transition_rules from anon, authenticated;
grant select on public.members to authenticated;
grant select on public.member_status_history to authenticated;
grant select on public.member_status_transition_rules to authenticated;

create policy members_select_scoped on public.members for select to authenticated using (public.has_permission('MEMBER_VIEW') and public.has_data_scope(organization_id));
create policy member_status_history_select_scoped on public.member_status_history for select to authenticated using (public.has_permission('MEMBER_VIEW') and public.has_data_scope(organization_id));
create policy member_transition_rules_select_scoped on public.member_status_transition_rules for select to authenticated using (organization_id is null or public.has_data_scope(organization_id));

create or replace function public.create_member(p_full_name text, p_member_number text default null, p_notes text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_profile public.profiles%rowtype; v_member_id uuid; v_member_number text;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_CREATE') then raise exception 'MEMBER_CREATE_DENIED' using errcode='42501'; end if;
  if not public.has_data_scope(v_profile.organization_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
  v_member_number := nullif(trim(p_member_number),'');
  insert into public.members(organization_id,member_number,full_name,status,notes,created_by,updated_by)
  values(v_profile.organization_id,v_member_number,trim(p_full_name),'APPLICANT',nullif(trim(p_notes),''),v_profile.id,v_profile.id) returning id into v_member_id;
  insert into public.member_status_history(member_id,organization_id,from_status,to_status,reason,changed_by)
  values(v_member_id,v_profile.organization_id,null,'APPLICANT','Membership record created',v_profile.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_profile.organization_id,v_profile.id,'MEMBER_CREATED','MEMBER',v_member_id,jsonb_build_object('member_number',v_member_number,'full_name',trim(p_full_name),'status','APPLICANT'),'Member master created through controlled transaction');
  return v_member_id;
exception when unique_violation then raise exception 'MEMBER_NUMBER_ALREADY_EXISTS' using errcode='23505';
end; $$;

create or replace function public.update_member_basic(p_member_id uuid,p_full_name text,p_member_number text default null,p_notes text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_member public.members%rowtype; v_number text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_UPDATE') then raise exception 'MEMBER_UPDATE_DENIED' using errcode='42501'; end if;
  select * into v_member from public.members where id=p_member_id;
  if v_member.id is null then raise exception 'MEMBER_NOT_FOUND' using errcode='P0002'; end if;
  if not public.has_data_scope(v_member.organization_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
  v_number:=nullif(trim(p_member_number),'');
  update public.members set full_name=trim(p_full_name),member_number=v_number,notes=nullif(trim(p_notes),''),updated_by=v_profile.id,updated_at=now() where id=p_member_id;
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason)
  values(v_member.organization_id,v_profile.id,'MEMBER_UPDATED','MEMBER',p_member_id,jsonb_build_object('member_number',v_member.member_number,'full_name',v_member.full_name,'status',v_member.status),jsonb_build_object('member_number',v_number,'full_name',trim(p_full_name),'status',v_member.status),'Member master basic data updated');
exception when unique_violation then raise exception 'MEMBER_NUMBER_ALREADY_EXISTS' using errcode='23505';
end; $$;

create or replace function public.change_member_status(p_member_id uuid,p_new_status text,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_member public.members%rowtype; v_rule public.member_status_transition_rules%rowtype; v_reason text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_STATUS_CHANGE') then raise exception 'MEMBER_STATUS_CHANGE_DENIED' using errcode='42501'; end if;
  select * into v_member from public.members where id=p_member_id;
  if v_member.id is null then raise exception 'MEMBER_NOT_FOUND' using errcode='P0002'; end if;
  if not public.has_data_scope(v_member.organization_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if p_new_status=v_member.status then raise exception 'MEMBER_STATUS_UNCHANGED' using errcode='22023'; end if;
  select r.* into v_rule from public.member_status_transition_rules r where r.from_status=v_member.status and r.to_status=p_new_status and r.enabled=true and r.policy_status='ACTIVE' and (r.organization_id=v_member.organization_id or r.organization_id is null) order by (r.organization_id=v_member.organization_id) desc limit 1;
  if v_rule.id is null then raise exception 'MEMBER_STATUS_TRANSITION_NOT_ALLOWED' using errcode='22023'; end if;
  v_reason:=nullif(trim(p_reason),'');
  if v_rule.requires_reason and v_reason is null then raise exception 'MEMBER_STATUS_REASON_REQUIRED' using errcode='22023'; end if;
  update public.members set status=p_new_status,membership_date=case when p_new_status='ACTIVE' and membership_date is null then current_date else membership_date end,termination_date=case when p_new_status in ('RESIGNED','TERMINATED') then current_date else termination_date end,updated_by=v_profile.id,updated_at=now() where id=p_member_id;
  insert into public.member_status_history(member_id,organization_id,from_status,to_status,reason,changed_by) values(p_member_id,v_member.organization_id,v_member.status,p_new_status,v_reason,v_profile.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason) values(v_member.organization_id,v_profile.id,'MEMBER_STATUS_CHANGED','MEMBER',p_member_id,jsonb_build_object('status',v_member.status),jsonb_build_object('status',p_new_status),v_reason);
end; $$;

revoke all on function public.create_member(text,text,text) from public, anon;
revoke all on function public.update_member_basic(uuid,text,text,text) from public, anon;
revoke all on function public.change_member_status(uuid,text,text) from public, anon;
grant execute on function public.create_member(text,text,text) to authenticated;
grant execute on function public.update_member_basic(uuid,text,text,text) to authenticated;
grant execute on function public.change_member_status(uuid,text,text) to authenticated;

comment on table public.members is 'Cooperative Core member master. Sensitive identity details are intentionally not stored here in Phase 2 foundation.';
comment on table public.member_status_transition_rules is 'Configurable membership lifecycle. Initial rules are architecture defaults and remain subject to final AD/ART and regulatory validation.';