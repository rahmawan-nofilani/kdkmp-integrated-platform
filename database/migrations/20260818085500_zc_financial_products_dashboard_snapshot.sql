-- ZC financial-products dashboard snapshot
--
-- Collapse the four read requests used by /dashboard/financial-products into
-- one scoped RPC. The public endpoint remains SECURITY INVOKER. The private
-- helper is SECURITY DEFINER only to avoid repeated RLS traversal and explicitly
-- re-applies the current permission/scope contracts for each dataset.

create or replace function app_private.get_financial_products_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_profile_id uuid;
  v_organization_id uuid;
begin
  if v_auth_user_id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  select p.id, p.organization_id
  into v_profile_id, v_organization_id
  from public.profiles p
  where p.auth_user_id = v_auth_user_id
    and p.status = 'ACTIVE'
  limit 1;

  if v_profile_id is null or v_organization_id is null then
    raise exception using errcode = '42501', message = 'FINANCIAL_PRODUCT_CONTEXT_UNAVAILABLE';
  end if;

  if not app_private.has_permission('FINANCIAL_PRODUCT_VIEW') then
    raise exception using errcode = '42501', message = 'FINANCIAL_PRODUCT_VIEW_DENIED';
  end if;

  return jsonb_build_object(
    'templates', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select t.id, t.code, t.name, t.product_category, t.description,
               t.default_configuration, t.template_status
        from public.financial_product_templates t
        where t.template_status = 'ACTIVE'
        order by t.product_category, t.name, t.id
      ) x
    ), '[]'::jsonb),
    'products', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select p.id, p.code, p.name, p.product_category, p.template_code,
               p.legal_product_type, p.purpose_code, p.status,
               p.organization_unit_id, p.created_at
        from public.financial_products p
        where p.organization_id = v_organization_id
          and public.has_data_scope(
            p.organization_id,
            p.organization_node_id,
            p.organization_unit_id
          )
        order by p.created_at desc, p.id
      ) x
    ), '[]'::jsonb),
    'versions', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select v.id, v.financial_product_id, v.version_no, v.status,
               v.accounting_mapping_status, v.regulatory_validation_status,
               v.legal_basis, v.created_at
        from public.financial_product_versions v
        where v.organization_id = v_organization_id
          and public.has_data_scope(
            v.organization_id,
            v.organization_node_id,
            v.organization_unit_id
          )
        order by v.version_no desc, v.id
      ) x
    ), '[]'::jsonb),
    'authorizations', coalesce((
      select jsonb_agg(to_jsonb(x))
      from (
        select a.id, a.module_code, a.organization_unit_id, a.status,
               a.effective_date, a.expiry_date
        from public.regulatory_authorizations a
        where a.organization_id = v_organization_id
          and app_private.can_access_organization(a.organization_id)
          and app_private.has_permission('CONTROL_REVIEW')
          and (
            a.organization_unit_id is null
            or app_private.can_access_unit(a.organization_id, a.organization_unit_id)
          )
        order by a.module_code, a.organization_unit_id nulls first, a.id
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_financial_products_dashboard_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.get_financial_products_dashboard_snapshot();
$$;

revoke all on function app_private.get_financial_products_dashboard_snapshot() from public;
revoke all on function app_private.get_financial_products_dashboard_snapshot() from anon;
grant execute on function app_private.get_financial_products_dashboard_snapshot() to authenticated;
grant execute on function app_private.get_financial_products_dashboard_snapshot() to service_role;

revoke all on function public.get_financial_products_dashboard_snapshot() from public;
revoke all on function public.get_financial_products_dashboard_snapshot() from anon;
grant execute on function public.get_financial_products_dashboard_snapshot() to authenticated;
grant execute on function public.get_financial_products_dashboard_snapshot() to service_role;

comment on function app_private.get_financial_products_dashboard_snapshot() is
  'Private scoped financial-products snapshot. SECURITY DEFINER is bounded by auth.uid(), FINANCIAL_PRODUCT_VIEW, existing data-scope checks, and CONTROL_REVIEW for regulatory authorizations.';
comment on function public.get_financial_products_dashboard_snapshot() is
  'Authenticated SECURITY INVOKER wrapper for the scoped financial-products dashboard snapshot.';

do $$
declare
  v_private pg_proc%rowtype;
  v_public pg_proc%rowtype;
begin
  select * into v_private
  from pg_proc
  where oid = 'app_private.get_financial_products_dashboard_snapshot()'::regprocedure;

  select * into v_public
  from pg_proc
  where oid = 'public.get_financial_products_dashboard_snapshot()'::regprocedure;

  if not v_private.prosecdef then
    raise exception 'financial_products_snapshot_private_must_be_security_definer';
  end if;

  if v_public.prosecdef then
    raise exception 'financial_products_snapshot_public_must_be_security_invoker';
  end if;

  if not exists (
    select 1 from unnest(coalesce(v_private.proconfig, array[]::text[])) setting
    where setting in ('search_path=', 'search_path=""')
  ) then
    raise exception 'financial_products_snapshot_private_search_path_must_be_empty';
  end if;

  if not exists (
    select 1 from unnest(coalesce(v_public.proconfig, array[]::text[])) setting
    where setting in ('search_path=', 'search_path=""')
  ) then
    raise exception 'financial_products_snapshot_public_search_path_must_be_empty';
  end if;

  if has_function_privilege('anon', 'public.get_financial_products_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'anon_must_not_execute_financial_products_dashboard_snapshot';
  end if;

  if exists (
    select 1
    from aclexplode(coalesce(v_public.proacl, acldefault('f', v_public.proowner))) acl
    where acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'public_must_not_execute_financial_products_dashboard_snapshot';
  end if;

  if not has_function_privilege('authenticated', 'public.get_financial_products_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'authenticated_financial_products_dashboard_snapshot_execute_missing';
  end if;

  if not has_function_privilege('authenticated', 'app_private.get_financial_products_dashboard_snapshot()', 'EXECUTE') then
    raise exception 'authenticated_financial_products_dashboard_snapshot_private_execute_missing';
  end if;
end $$;
