create or replace function public.create_member(
  p_full_name text,
  p_member_number text default null,
  p_notes text default null,
  p_organization_node_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_member_id uuid;
  v_member_number text;
  v_node_id uuid := p_organization_node_id;
  v_scope_count integer;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  select * into v_profile from public.profiles where auth_user_id=(select auth.uid()) and status='ACTIVE' limit 1;
  if v_profile.id is null or v_profile.organization_id is null then raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501'; end if;
  if not public.has_permission('MEMBER_CREATE') then raise exception 'MEMBER_CREATE_DENIED' using errcode='42501'; end if;

  if v_node_id is null then
    select count(*), (array_agg(ds.organization_node_id order by ds.organization_node_id))[1]
      into v_scope_count, v_node_id
    from public.user_scope_assignments usa
    join public.data_scopes ds on ds.id=usa.data_scope_id
    where usa.profile_id=v_profile.id
      and usa.valid_from<=now()
      and (usa.valid_until is null or usa.valid_until>now())
      and ds.scope_type='COOPERATIVE_SCOPE'
      and ds.organization_id=v_profile.organization_id
      and ds.organization_node_id is not null;
    if v_scope_count<>1 then raise exception 'KDKMP_NODE_REQUIRED' using errcode='22023'; end if;
  end if;

  if not exists(select 1 from public.organization_nodes n where n.id=v_node_id and n.organization_id=v_profile.organization_id and n.node_type='KDKMP' and n.status='ACTIVE') then raise exception 'INVALID_KDKMP_NODE' using errcode='22023'; end if;
  if not public.has_data_scope(v_profile.organization_id,v_node_id) then raise exception 'MEMBER_SCOPE_DENIED' using errcode='42501'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'MEMBER_NAME_REQUIRED' using errcode='22023'; end if;

  v_member_number:=nullif(trim(p_member_number),'');
  insert into public.members(organization_id,organization_node_id,member_number,full_name,status,notes,created_by,updated_by)
  values(v_profile.organization_id,v_node_id,v_member_number,trim(p_full_name),'APPLICANT',nullif(trim(p_notes),''),v_profile.id,v_profile.id)
  returning id into v_member_id;

  insert into public.member_status_history(member_id,organization_id,organization_node_id,from_status,to_status,reason,changed_by)
  values(v_member_id,v_profile.organization_id,v_node_id,null,'APPLICANT','Membership record created',v_profile.id);

  insert into public.audit_logs(organization_id,actor_profile_id,action_code,entity_type,entity_id,after_data,reason)
  values(v_profile.organization_id,v_profile.id,'MEMBER_CREATED','MEMBER',v_member_id,jsonb_build_object('organization_node_id',v_node_id,'member_number',v_member_number,'full_name',trim(p_full_name),'status','APPLICANT'),'Member master created through controlled transaction');
  return v_member_id;
exception when unique_violation then raise exception 'MEMBER_NUMBER_ALREADY_EXISTS' using errcode='23505';
end;
$$;

revoke all on function public.create_member(text,text,text,uuid) from public,anon;
grant execute on function public.create_member(text,text,text,uuid) to authenticated;