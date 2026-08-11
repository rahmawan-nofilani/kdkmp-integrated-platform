create table public.member_status_commands (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete restrict,
  requested_status text not null,
  reason text,
  requested_by uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
alter table public.member_status_commands enable row level security;
revoke all on public.member_status_commands from anon,authenticated;
grant insert on public.member_status_commands to authenticated;
create policy member_status_commands_insert_scoped on public.member_status_commands for insert to authenticated
with check(public.has_permission('MEMBER_STATUS_CHANGE') and exists(select 1 from public.members m where m.id=member_id and public.has_data_scope(m.organization_id,m.organization_node_id)));

create or replace function app_private.member_before_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_node_id uuid:=new.organization_node_id; v_scope_count integer;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_CREATE') then raise exception 'MEMBER_CREATE_DENIED' using errcode='42501'; end if;
  if v_node_id is null then
    select count(*),(array_agg(ds.organization_node_id order by ds.organization_node_id))[1] into v_scope_count,v_node_id
    from public.user_scope_assignments usa join public.data_scopes ds on ds.id=usa.data_scope_id
    where usa.profile_id=v_profile.id and usa.valid_from<=now() and (usa.valid_until is null or usa.valid_until>now()) and ds.scope_type='COOPERATIVE_SCOPE' and ds.organization_id=v_profile.organization_id and ds.organization_node_id is not null;
    if v_scope_count<>1 then raise exception 'KDKMP_NODE_REQUIRED' using errcode='22023'; end if;
  end if;
  if not exists(select 1 from public.organization_nodes n where n.id=v_node_id and n.organization_id=v_profile.organization_id and n.node_type='KDKMP' and n.status='ACTIVE') then raise exception 'INVALID_KDKMP_NODE' using errcode='22023'; end if;
  if not public.has_data_scope(v_profile.organization_id,v_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(new.full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
  new.organization_id:=v_profile.organization_id; new.organization_node_id:=v_node_id; new.full_name:=trim(new.full_name); new.member_number:=nullif(trim(new.member_number),''); new.notes:=nullif(trim(new.notes),'');
  new.status:='APPLICANT'; new.membership_date:=null; new.termination_date:=null; new.created_by:=v_profile.id; new.updated_by:=v_profile.id; new.created_at:=now(); new.updated_at:=now();
  return new;
end; $$;

create or replace function app_private.member_after_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.member_status_history(member_id,organization_id,organization_node_id,from_status,to_status,reason,changed_by) values(new.id,new.organization_id,new.organization_node_id,null,'APPLICANT','Membership record created',new.created_by);
  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason) values(new.organization_id,new.created_by,'MEMBER_CREATED','MEMBER',new.id,jsonb_build_object('organization_node_id',new.organization_node_id,'member_number',new.member_number,'full_name',new.full_name,'status',new.status),'Member master created through controlled transaction');
  return new;
end; $$;

create or replace function app_private.member_before_update() returns trigger language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_status_command boolean:=coalesce(current_setting('app.member_status_command',true),'')='allowed';
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not v_status_command then
    if not public.has_permission('MEMBER_UPDATE') then raise exception 'MEMBER_UPDATE_DENIED' using errcode='42501'; end if;
    if not public.has_data_scope(old.organization_id,old.organization_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
    if new.organization_id is distinct from old.organization_id or new.organization_node_id is distinct from old.organization_node_id or new.status is distinct from old.status or new.membership_date is distinct from old.membership_date or new.termination_date is distinct from old.termination_date or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then raise exception 'PROTECTED_MEMBER_FIELDS_CANNOT_BE_UPDATED_DIRECTLY' using errcode='42501'; end if;
    if nullif(trim(new.full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;
    new.full_name:=trim(new.full_name); new.member_number:=nullif(trim(new.member_number),''); new.notes:=nullif(trim(new.notes),''); new.updated_by:=v_profile.id; new.updated_at:=now();
  end if;
  return new;
end; $$;

create or replace function app_private.member_after_update() returns trigger language plpgsql security definer set search_path='' as $$
declare v_reason text:=nullif(current_setting('app.member_status_reason',true),'');
begin
  if new.status is distinct from old.status then
    insert into public.member_status_history(member_id,organization_id,organization_node_id,from_status,to_status,reason,changed_by) values(new.id,new.organization_id,new.organization_node_id,old.status,new.status,v_reason,new.updated_by);
    insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason) values(new.organization_id,new.updated_by,'MEMBER_STATUS_CHANGED','MEMBER',new.id,jsonb_build_object('organization_node_id',new.organization_node_id,'status',old.status),jsonb_build_object('organization_node_id',new.organization_node_id,'status',new.status),v_reason);
  elsif new.full_name is distinct from old.full_name or new.member_number is distinct from old.member_number or new.notes is distinct from old.notes then
    insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,before_data,after_data,reason) values(new.organization_id,new.updated_by,'MEMBER_UPDATED','MEMBER',new.id,jsonb_build_object('member_number',old.member_number,'full_name',old.full_name,'status',old.status),jsonb_build_object('member_number',new.member_number,'full_name',new.full_name,'status',new.status),'Member master basic data updated');
  end if;
  return new;
end; $$;

create or replace function app_private.member_status_command_before_insert() returns trigger language plpgsql security definer set search_path='' as $$
declare v_profile public.profiles%rowtype; v_member public.members%rowtype; v_rule public.member_status_transition_rules%rowtype; v_reason text;
begin
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_STATUS_CHANGE') then raise exception 'MEMBER_STATUS_CHANGE_DENIED' using errcode='42501'; end if;
  select * into v_member from public.members where id=new.member_id;
  if v_member.id is null then raise exception 'MEMBER_NOT_FOUND' using errcode='P0002'; end if;
  if not public.has_data_scope(v_member.organization_id,v_member.organization_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if new.requested_status=v_member.status then raise exception 'MEMBER_STATUS_UNCHANGED' using errcode='22023'; end if;
  select r.* into v_rule from public.member_status_transition_rules r where r.from_status=v_member.status and r.to_status=new.requested_status and r.enabled=true and r.policy_status='ACTIVE' and (r.organization_id=v_member.organization_id or r.organization_id is null) order by (r.organization_id=v_member.organization_id) desc limit 1;
  if v_rule.id is null then raise exception 'MEMBER_STATUS_TRANSITION_NOT_ALLOWED' using errcode='22023'; end if;
  v_reason:=nullif(trim(new.reason),''); if v_rule.requires_reason and v_reason is null then raise exception 'MEMBER_STATUS_REASON_REQUIRED' using errcode='22023'; end if;
  new.reason:=v_reason; new.requested_by:=v_profile.id; new.created_at:=now();
  perform set_config('app.member_status_command','allowed',true); perform set_config('app.member_status_reason',coalesce(v_reason,''),true);
  update public.members set status=new.requested_status,membership_date=case when new.requested_status='ACTIVE' and membership_date is null then current_date else membership_date end,termination_date=case when new.requested_status in ('RESIGNED','TERMINATED') then current_date else termination_date end,updated_by=v_profile.id,updated_at=now() where id=new.member_id;
  perform set_config('app.member_status_command','',true); perform set_config('app.member_status_reason','',true);
  return new;
end; $$;

revoke all on function app_private.member_before_insert() from public,anon,authenticated;
revoke all on function app_private.member_after_insert() from public,anon,authenticated;
revoke all on function app_private.member_before_update() from public,anon,authenticated;
revoke all on function app_private.member_after_update() from public,anon,authenticated;
revoke all on function app_private.member_status_command_before_insert() from public,anon,authenticated;

create trigger trg_member_before_insert before insert on public.members for each row execute function app_private.member_before_insert();
create trigger trg_member_after_insert after insert on public.members for each row execute function app_private.member_after_insert();
create trigger trg_member_before_update before update on public.members for each row execute function app_private.member_before_update();
create trigger trg_member_after_update after update on public.members for each row execute function app_private.member_after_update();
create trigger trg_member_status_command_before_insert before insert on public.member_status_commands for each row execute function app_private.member_status_command_before_insert();

drop function if exists public.create_member(text,text,text,uuid);
drop function if exists public.update_member_basic(uuid,text,text,text);
drop function if exists public.change_member_status(uuid,text,text);
grant insert(full_name,member_number,notes,organization_node_id) on public.members to authenticated;
grant update(full_name,member_number,notes) on public.members to authenticated;
create policy members_insert_scoped on public.members for insert to authenticated with check(public.has_permission('MEMBER_CREATE') and public.has_data_scope(organization_id,organization_node_id));
create policy members_update_basic_scoped on public.members for update to authenticated using(public.has_permission('MEMBER_UPDATE') and public.has_data_scope(organization_id,organization_node_id)) with check(public.has_permission('MEMBER_UPDATE') and public.has_data_scope(organization_id,organization_node_id));

create or replace function public.create_member(p_full_name text,p_member_number text default null,p_notes text default null,p_organization_node_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$ declare v_id uuid; begin insert into public.members(full_name,member_number,notes,organization_node_id) values(p_full_name,p_member_number,p_notes,p_organization_node_id) returning id into v_id; return v_id; exception when unique_violation then raise exception 'MEMBER_NUMBER_ALREADY_EXISTS' using errcode='23505'; end; $$;
create or replace function public.update_member_basic(p_member_id uuid,p_full_name text,p_member_number text default null,p_notes text default null) returns void language plpgsql security invoker set search_path='' as $$ begin update public.members set full_name=p_full_name,member_number=p_member_number,notes=p_notes where id=p_member_id; if not found then raise exception 'MEMBER_NOT_FOUND' using errcode='P0002'; end if; exception when unique_violation then raise exception 'MEMBER_NUMBER_ALREADY_EXISTS' using errcode='23505'; end; $$;
create or replace function public.change_member_status(p_member_id uuid,p_new_status text,p_reason text default null) returns void language plpgsql security invoker set search_path='' as $$ begin insert into public.member_status_commands(member_id,requested_status,reason) values(p_member_id,p_new_status,p_reason); end; $$;
revoke all on function public.create_member(text,text,text,uuid) from public,anon; revoke all on function public.update_member_basic(uuid,text,text,text) from public,anon; revoke all on function public.change_member_status(uuid,text,text) from public,anon;
grant execute on function public.create_member(text,text,text,uuid) to authenticated; grant execute on function public.update_member_basic(uuid,text,text,text) to authenticated; grant execute on function public.change_member_status(uuid,text,text) to authenticated;
comment on table public.member_status_commands is 'Immutable command evidence for controlled membership status transitions. Direct members.status updates remain prohibited for authenticated users.';