-- POS controlled partial return/refund — owner-approved MANAGER-only SALES_RETURN policy
--
-- Grants SALES_RETURN only to the MANAGER baseline role after the partial-return
-- backend, RLS/RPC, UI and fail-closed DEVELOPMENT smoke were verified.
-- Fails closed if any different baseline role already carries SALES_RETURN.
-- CASHIER must remain denied. No production changes are performed by this migration.
do $$
declare
  v_manager_role_id uuid;
  v_sales_return_permission_id uuid;
begin
  select id into v_manager_role_id
  from public.roles
  where code='MANAGER' and status='ACTIVE'
  limit 1;

  if v_manager_role_id is null then
    raise exception 'SALES_RETURN_MANAGER_ROLE_REQUIRED';
  end if;

  select id into v_sales_return_permission_id
  from public.permissions
  where code='SALES_RETURN' and is_privileged=true
  limit 1;

  if v_sales_return_permission_id is null then
    raise exception 'SALES_RETURN_PERMISSION_REQUIRED';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_sales_return_permission_id
      and r.code<>'MANAGER'
  ) then
    raise exception 'SALES_RETURN_NON_MANAGER_ROLE_MAPPING_CONFLICT';
  end if;

  insert into public.role_permissions(role_id,permission_id)
  select v_manager_role_id,v_sales_return_permission_id
  where not exists (
    select 1
    from public.role_permissions rp
    where rp.role_id=v_manager_role_id
      and rp.permission_id=v_sales_return_permission_id
  );

  if not exists (
    select 1
    from public.role_permissions rp
    where rp.role_id=v_manager_role_id
      and rp.permission_id=v_sales_return_permission_id
  ) then
    raise exception 'SALES_RETURN_MANAGER_GRANT_FAILED';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_sales_return_permission_id
      and r.code='CASHIER'
  ) then
    raise exception 'SALES_RETURN_CASHIER_MUST_REMAIN_DENIED';
  end if;
end
$$;
