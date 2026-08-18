\set ON_ERROR_STOP on

-- Repository replay must encode the approved baseline policy exactly:
-- MANAGER owns SALES_VOID; CASHIER and every other baseline role do not.
do $$
declare
  v_manager_count integer;
  v_non_manager_count integer;
  v_cashier_count integer;
begin
  select count(*) into v_manager_count
  from public.role_permissions rp
  join public.roles r on r.id=rp.role_id
  join public.permissions p on p.id=rp.permission_id
  where p.code='SALES_VOID' and r.code='MANAGER';

  select count(*) into v_non_manager_count
  from public.role_permissions rp
  join public.roles r on r.id=rp.role_id
  join public.permissions p on p.id=rp.permission_id
  where p.code='SALES_VOID' and r.code<>'MANAGER';

  select count(*) into v_cashier_count
  from public.role_permissions rp
  join public.roles r on r.id=rp.role_id
  join public.permissions p on p.id=rp.permission_id
  where p.code='SALES_VOID' and r.code='CASHIER';

  if v_manager_count<>1 then
    raise exception 'expected exactly one MANAGER SALES_VOID mapping, got %',v_manager_count;
  end if;
  if v_non_manager_count<>0 then
    raise exception 'expected zero non-MANAGER SALES_VOID mappings, got %',v_non_manager_count;
  end if;
  if v_cashier_count<>0 then
    raise exception 'CASHIER must remain denied SALES_VOID';
  end if;
end $$;
