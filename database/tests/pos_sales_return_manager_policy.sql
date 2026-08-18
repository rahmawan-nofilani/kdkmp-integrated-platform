\set ON_ERROR_STOP on

DO $$
DECLARE
  v_total int;
  v_manager int;
  v_cashier int;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.permissions
    WHERE code='SALES_RETURN' AND is_privileged=true
  ) THEN
    RAISE EXCEPTION 'SALES_RETURN_PRIVILEGED_PERMISSION_REQUIRED';
  END IF;

  SELECT count(*) INTO v_total
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id=rp.permission_id
  WHERE p.code='SALES_RETURN';

  SELECT count(*) INTO v_manager
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id=rp.permission_id
  JOIN public.roles r ON r.id=rp.role_id
  WHERE p.code='SALES_RETURN' AND r.code='MANAGER';

  SELECT count(*) INTO v_cashier
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.id=rp.permission_id
  JOIN public.roles r ON r.id=rp.role_id
  WHERE p.code='SALES_RETURN' AND r.code='CASHIER';

  IF v_total <> 1 THEN
    RAISE EXCEPTION 'SALES_RETURN_EXPECTED_EXACTLY_ONE_BASELINE_MAPPING, got %', v_total;
  END IF;

  IF v_manager <> 1 THEN
    RAISE EXCEPTION 'SALES_RETURN_MANAGER_MAPPING_REQUIRED';
  END IF;

  IF v_cashier <> 0 THEN
    RAISE EXCEPTION 'SALES_RETURN_CASHIER_MUST_REMAIN_DENIED';
  END IF;
END
$$;

SELECT
  r.code AS role_code,
  p.code AS permission_code,
  p.is_privileged
FROM public.role_permissions rp
JOIN public.roles r ON r.id=rp.role_id
JOIN public.permissions p ON p.id=rp.permission_id
WHERE p.code='SALES_RETURN'
ORDER BY r.code;
