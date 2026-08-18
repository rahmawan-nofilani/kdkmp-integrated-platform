-- POS CASH Reversal — owner-approved MANAGER-only SALES_VOID policy
--
-- This migration codifies the DEVELOPMENT policy approved after the controlled
-- CASH reversal backend, RLS/RPC, UI, and permission smoke checks were verified.
-- It grants SALES_VOID only to the MANAGER baseline role and fails closed if a
-- different baseline role already carries SALES_VOID at this migration point.
-- It does not grant CASHIER and does not change ACCOUNTING_POST or other roles.

do $$
declare
  v_manager_role_id uuid;
  v_sales_void_permission_id uuid;
begin
  select id into v_manager_role_id
  from public.roles
  where code='MANAGER' and status='ACTIVE'
  limit 1;

  if v_manager_role_id is null then
    raise exception 'SALES_VOID_MANAGER_ROLE_REQUIRED';
  end if;

  select id into v_sales_void_permission_id
  from public.permissions
  where code='SALES_VOID' and is_privileged=true
  limit 1;

  if v_sales_void_permission_id is null then
    raise exception 'SALES_VOID_PERMISSION_REQUIRED';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_sales_void_permission_id
      and r.code<>'MANAGER'
  ) then
    raise exception 'SALES_VOID_NON_MANAGER_ROLE_MAPPING_CONFLICT';
  end if;

  insert into public.role_permissions(role_id,permission_id)
  select v_manager_role_id,v_sales_void_permission_id
  where not exists (
    select 1
    from public.role_permissions rp
    where rp.role_id=v_manager_role_id
      and rp.permission_id=v_sales_void_permission_id
  );

  if not exists (
    select 1
    from public.role_permissions rp
    where rp.role_id=v_manager_role_id
      and rp.permission_id=v_sales_void_permission_id
  ) then
    raise exception 'SALES_VOID_MANAGER_GRANT_FAILED';
  end if;

  if exists (
    select 1
    from public.role_permissions rp
    join public.roles r on r.id=rp.role_id
    where rp.permission_id=v_sales_void_permission_id
      and r.code='CASHIER'
  ) then
    raise exception 'SALES_VOID_CASHIER_MUST_REMAIN_DENIED';
  end if;
end
$$;
