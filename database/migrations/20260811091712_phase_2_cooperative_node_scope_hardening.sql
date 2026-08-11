alter table public.members add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.member_status_history add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.governance_bodies add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.governance_positions add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.governance_assignments add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.general_meetings add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.meeting_agendas add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.meeting_attendance add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.meeting_resolutions add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.shu_policies add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.shu_policy_versions add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;
alter table public.shu_periods add column organization_node_id uuid not null references public.organization_nodes(id) on delete restrict;

drop index if exists public.uq_members_org_member_number;
create unique index uq_members_node_member_number on public.members(organization_id,organization_node_id,member_number) where member_number is not null;
alter table public.governance_bodies drop constraint if exists governance_bodies_organization_id_code_key;
alter table public.governance_bodies add unique(organization_id,organization_node_id,code);
alter table public.general_meetings drop constraint if exists general_meetings_organization_id_code_key;
alter table public.general_meetings add unique(organization_id,organization_node_id,code);
alter table public.shu_policies drop constraint if exists shu_policies_organization_id_code_key;
alter table public.shu_policies add unique(organization_id,organization_node_id,code);
alter table public.shu_periods drop constraint if exists shu_periods_organization_id_fiscal_year_key;
alter table public.shu_periods add unique(organization_id,organization_node_id,fiscal_year);

create index idx_members_node_status on public.members(organization_node_id,status);
create index idx_governance_bodies_node_status on public.governance_bodies(organization_node_id,status);
create index idx_general_meetings_node_year on public.general_meetings(organization_node_id,period_year desc);
create index idx_shu_periods_node_year on public.shu_periods(organization_node_id,fiscal_year desc);

drop policy if exists members_select_scoped on public.members;
create policy members_select_scoped on public.members for select to authenticated using(public.has_permission('MEMBER_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists member_status_history_select_scoped on public.member_status_history;
create policy member_status_history_select_scoped on public.member_status_history for select to authenticated using(public.has_permission('MEMBER_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists governance_bodies_select_scoped on public.governance_bodies;
create policy governance_bodies_select_scoped on public.governance_bodies for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists governance_positions_select_scoped on public.governance_positions;
create policy governance_positions_select_scoped on public.governance_positions for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists governance_assignments_select_scoped on public.governance_assignments;
create policy governance_assignments_select_scoped on public.governance_assignments for select to authenticated using(public.has_permission('GOVERNANCE_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists general_meetings_select_scoped on public.general_meetings;
create policy general_meetings_select_scoped on public.general_meetings for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists meeting_agendas_select_scoped on public.meeting_agendas;
create policy meeting_agendas_select_scoped on public.meeting_agendas for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists meeting_attendance_select_scoped on public.meeting_attendance;
create policy meeting_attendance_select_scoped on public.meeting_attendance for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists meeting_resolutions_select_scoped on public.meeting_resolutions;
create policy meeting_resolutions_select_scoped on public.meeting_resolutions for select to authenticated using(public.has_permission('RAT_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists shu_policies_select_scoped on public.shu_policies;
create policy shu_policies_select_scoped on public.shu_policies for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists shu_policy_versions_select_scoped on public.shu_policy_versions;
create policy shu_policy_versions_select_scoped on public.shu_policy_versions for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id,organization_node_id));
drop policy if exists shu_periods_select_scoped on public.shu_periods;
create policy shu_periods_select_scoped on public.shu_periods for select to authenticated using(public.has_permission('SHU_VIEW') and public.has_data_scope(organization_id,organization_node_id));

drop function if exists public.create_member(text,text,text);

create or replace function public.create_member(p_full_name text,p_member_number text default null,p_notes text default null,p_organization_node_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_member_id uuid; v_member_number text; v_node_id uuid:=p_organization_node_id; v_scope_count integer;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_CREATE') then raise exception 'MEMBER_CREATE_DENIED' using errcode='42501'; end if;
  if v_node_id is null then
    select count(*), min(ds.organization_node_id) into v_scope_count,v_node_id from public.user_scope_assignments usa join public.data_scopes ds on ds.id=usa.data_scope_id where usa.profile_id=v_profile.id and usa.valid_from<=now() and (usa.valid_until is null or usa.valid_until>now()) and ds.scope_type='COOPERATIVE_SCOPE' and ds.organization_id=v_profile.organization_id and ds.organization_node_id is not null;
    if v_scope_count<>1 then raise exception 'KDKMP_NODE_REQUIRED' using errcode='22023'; end if;
  end if;
  if not exists(select 1 from public.organization_nodes n where n.id=v_node_id and n.organization_id=v_profile.organization_id and n.node_type='KDKMP' and n.status='ACTIVE') then raise exception 'INVALID_KDKMP_NODE' using errcode='22023'; end if;
  if not public.has_data_scope(v_profile.organization_id,v_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
  v_member_number:=nullif(trim(p_member_number),'');
  insert into public.members(organization_id,organization_node_id,member_number,full_name,status,notes,created_by,updated_by) values(v_profile.organization_id,v_node_id,v_member_number,trim(p_full_name),'APPLICANT',nullif(trim(p_notes),''),v_profile.id,v_profile.id) returning id into v_member_id;
  insert into public.member_status_history(member_id,organization_id,organization_node_id,from_status,to_status,reason,changed_by) values(v_member_id,v_profile.organization_id,v_node_id,null,'APPLICANT','Membership record created',v_profile.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason) values(v_profile.organization_id,v_profile.id,'MEMBER_CREATED','MEMBER',v_member_id,jsonb_build_object('organization_node_id',v_node_id,'member_number',v_member_number,'full_name',trim(p_full_name),'status','APPLICANT'),'Member master created through controlled transaction');
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
  if not public.has_data_scope(v_member.organization_id,v_member.organization_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
  v_number:=nullif(trim(p_member_number),'');
  update public.members set full_name=trim(p_full_name),member_number=v_number,notes=nullif(trim(p_notes),''),updated_by=v_profile.id,updated_at=now() where id=p_member_id;
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason) values(v_member.organization_id,v_profile.id,'MEMBER_UPDATED','MEMBER',p_member_id,jsonb_build_object('organization_node_id',v_member.organization_node_id,'member_number',v_member.member_number,'full_name',v_member.full_name,'status',v_member.status),jsonb_build_object('organization_node_id',v_member.organization_node_id,'member_number',v_number,'full_name',trim(p_full_name),'status',v_member.status),'Member master basic data updated');
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
  if not public.has_data_scope(v_member.organization_id,v_member.organization_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if p_new_status=v_member.status then raise exception 'MEMBER_STATUS_UNCHANGED' using errcode='22023'; end if;
  select r.* into v_rule from public.member_status_transition_rules r where r.from_status=v_member.status and r.to_status=p_new_status and r.enabled=true and r.policy_status='ACTIVE' and (r.organization_id=v_member.organization_id or r.organization_id is null) order by (r.organization_id=v_member.organization_id) desc limit 1;
  if v_rule.id is null then raise exception 'MEMBER_STATUS_TRANSITION_NOT_ALLOWED' using errcode='22023'; end if;
  v_reason:=nullif(trim(p_reason),''); if v_rule.requires_reason and v_reason is null then raise exception 'MEMBER_STATUS_REASON_REQUIRED' using errcode='22023'; end if;
  update public.members set status=p_new_status,membership_date=case when p_new_status='ACTIVE' and membership_date is null then current_date else membership_date end,termination_date=case when p_new_status in ('RESIGNED','TERMINATED') then current_date else termination_date end,updated_by=v_profile.id,updated_at=now() where id=p_member_id;
  insert into public.member_status_history(member_id,organization_id,organization_node_id,from_status,to_status,reason,changed_by) values(p_member_id,v_member.organization_id,v_member.organization_node_id,v_member.status,p_new_status,v_reason,v_profile.id);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason) values(v_member.organization_id,v_profile.id,'MEMBER_STATUS_CHANGED','MEMBER',p_member_id,jsonb_build_object('organization_node_id',v_member.organization_node_id,'status',v_member.status),jsonb_build_object('organization_node_id',v_member.organization_node_id,'status',p_new_status),v_reason);
end; $$;

revoke all on function public.create_member(text,text,text,uuid) from public,anon;
grant execute on function public.create_member(text,text,text,uuid) to authenticated;