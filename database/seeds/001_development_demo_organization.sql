-- DEVELOPMENT / DEMO DATA ONLY
-- This seed is intentionally synthetic and must not be presented as real KDKMP data.
-- It is idempotent and does not hardcode generated UUIDs.

DO $$
DECLARE
  v_org uuid;
  v_platform uuid;
  v_province uuid;
  v_regency uuid;
  v_district uuid;
  v_village uuid;
  v_kdkmp uuid;
  v_office uuid;
  v_retail uuid;
  v_warehouse uuid;
  v_savings_loans uuid;
BEGIN
  insert into public.organizations (code, name, status)
  values ('DEMO-KDKMP-DEV', 'DEMO — KDKMP Development', 'ACTIVE')
  on conflict (code) do update
    set name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_org;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, null, 'PLATFORM', 'DEMO-PLATFORM', 'DEMO Platform', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_platform;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, v_platform, 'PROVINCE', 'DEMO-PROVINCE', 'DEMO Province', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_province;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, v_province, 'REGENCY_CITY', 'DEMO-REGENCY', 'DEMO Regency', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_regency;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, v_regency, 'DISTRICT', 'DEMO-DISTRICT', 'DEMO District', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_district;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, v_district, 'VILLAGE', 'DEMO-VILLAGE', 'DEMO Village', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_village;

  insert into public.organization_nodes
    (organization_id, parent_id, node_type, code, name, status)
  values (v_org, v_village, 'KDKMP', 'DEMO-KDKMP', 'DEMO — KDKMP', 'ACTIVE')
  on conflict (organization_id, code) do update
    set parent_id = excluded.parent_id,
        name = excluded.name,
        status = excluded.status,
        updated_at = now()
  returning id into v_kdkmp;

  insert into public.organization_units
    (organization_id, organization_node_id, code, name, unit_type, status)
  values (v_org, v_kdkmp, 'DEMO-OFFICE', 'DEMO — Kantor', 'OFFICE', 'ACTIVE')
  on conflict (organization_id, code) do update
    set organization_node_id = excluded.organization_node_id,
        name = excluded.name,
        unit_type = excluded.unit_type,
        status = excluded.status,
        updated_at = now()
  returning id into v_office;

  insert into public.organization_units
    (organization_id, organization_node_id, code, name, unit_type, status)
  values (v_org, v_kdkmp, 'DEMO-RETAIL', 'DEMO — Gerai', 'RETAIL', 'ACTIVE')
  on conflict (organization_id, code) do update
    set organization_node_id = excluded.organization_node_id,
        name = excluded.name,
        unit_type = excluded.unit_type,
        status = excluded.status,
        updated_at = now()
  returning id into v_retail;

  insert into public.organization_units
    (organization_id, organization_node_id, code, name, unit_type, status)
  values (v_org, v_kdkmp, 'DEMO-WAREHOUSE', 'DEMO — Gudang', 'WAREHOUSE', 'ACTIVE')
  on conflict (organization_id, code) do update
    set organization_node_id = excluded.organization_node_id,
        name = excluded.name,
        unit_type = excluded.unit_type,
        status = excluded.status,
        updated_at = now()
  returning id into v_warehouse;

  insert into public.organization_units
    (organization_id, organization_node_id, code, name, unit_type, status)
  values (v_org, v_kdkmp, 'DEMO-SAVINGS-LOANS', 'DEMO — Simpan Pinjam', 'SAVINGS_LOANS', 'ACTIVE')
  on conflict (organization_id, code) do update
    set organization_node_id = excluded.organization_node_id,
        name = excluded.name,
        unit_type = excluded.unit_type,
        status = excluded.status,
        updated_at = now()
  returning id into v_savings_loans;

  insert into public.data_scopes (organization_id, organization_node_id, scope_type, name)
  select v_org, v_kdkmp, 'COOPERATIVE_SCOPE', 'DEMO — KDKMP Cooperative Scope'
  where not exists (
    select 1 from public.data_scopes ds
    where ds.organization_id = v_org
      and ds.organization_node_id = v_kdkmp
      and ds.scope_type = 'COOPERATIVE_SCOPE'
      and ds.name = 'DEMO — KDKMP Cooperative Scope'
  );

  insert into public.data_scopes
    (organization_id, organization_node_id, organization_unit_id, scope_type, name)
  select v_org, v_kdkmp, x.unit_id, 'UNIT_SCOPE', 'DEMO — Unit Scope — ' || x.unit_code
  from (values
    (v_office, 'DEMO-OFFICE'),
    (v_retail, 'DEMO-RETAIL'),
    (v_warehouse, 'DEMO-WAREHOUSE'),
    (v_savings_loans, 'DEMO-SAVINGS-LOANS')
  ) as x(unit_id, unit_code)
  where not exists (
    select 1 from public.data_scopes ds
    where ds.scope_type = 'UNIT_SCOPE'
      and ds.organization_unit_id = x.unit_id
  );

  insert into public.data_scopes (organization_id, scope_type, name)
  select v_org, x.scope_type, x.name
  from (values
    ('OWN_DATA_ONLY', 'DEMO — Own Data Only'),
    ('ASSIGNED_RECORDS_ONLY', 'DEMO — Assigned Records Only')
  ) as x(scope_type, name)
  where not exists (
    select 1 from public.data_scopes ds
    where ds.organization_id = v_org
      and ds.scope_type = x.scope_type
      and ds.name = x.name
  );

  insert into public.feature_modules
    (organization_id, organization_unit_id, module_code, enabled)
  values (v_org, v_savings_loans, 'SAVINGS_LOANS', true)
  on conflict (organization_id, organization_unit_id, module_code) do update
    set enabled = excluded.enabled,
        updated_at = now();

  insert into public.regulatory_authorizations
    (organization_id, organization_unit_id, module_code, authorization_type, status, notes)
  select
    v_org,
    v_savings_loans,
    'SAVINGS_LOANS',
    'OPERATING_AUTHORIZATION',
    'PENDING_VALIDATION',
    'DEMO DATA — regulatory basis and authorization details are pending legal/regulatory validation.'
  where not exists (
    select 1 from public.regulatory_authorizations ra
    where ra.organization_id = v_org
      and ra.organization_unit_id = v_savings_loans
      and ra.module_code = 'SAVINGS_LOANS'
      and ra.authorization_type = 'OPERATING_AUTHORIZATION'
  );
END
$$;
