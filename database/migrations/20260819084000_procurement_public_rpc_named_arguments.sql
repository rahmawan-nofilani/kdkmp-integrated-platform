-- Release-1 DEVELOPMENT integration hardening.
-- Recreate the public Procurement wrappers with explicit argument names so
-- Supabase/PostgREST clients can call the controlled command engine by name.
-- Private command logic, permissions, SoD and approval policy are unchanged.

-- Public wrappers created in 20260819081500 used positional-only arguments.
-- Drop only those thin public wrappers and recreate them atomically with named args.
drop function if exists public.create_submit_purchase_requisition(uuid,text,date,jsonb,text);
drop function if exists public.approve_purchase_requisition(uuid,text,text,boolean);
drop function if exists public.create_submit_purchase_order(uuid,uuid,date,text,text);
drop function if exists public.approve_purchase_order(uuid,text,text,boolean);
drop function if exists public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text);
drop function if exists public.create_match_supplier_invoice(uuid,text,date,jsonb,text);

create function public.create_submit_purchase_requisition(
  p_organization_unit_id uuid,
  p_purpose text,
  p_required_date date,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.create_submit_purchase_requisition(
    p_organization_unit_id,p_purpose,p_required_date,p_lines,p_idempotency_key
  );
$$;

create function public.approve_purchase_requisition(
  p_purchase_requisition_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_conflict_declared boolean
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.approve_procurement_entity(
    'PURCHASE_REQUISITION',p_purchase_requisition_id,p_idempotency_key,p_reason,p_conflict_declared
  );
$$;

create function public.create_submit_purchase_order(
  p_purchase_requisition_id uuid,
  p_supplier_id uuid,
  p_expected_delivery_date date,
  p_delivery_location_text text,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.create_submit_purchase_order(
    p_purchase_requisition_id,p_supplier_id,p_expected_delivery_date,p_delivery_location_text,p_idempotency_key
  );
$$;

create function public.approve_purchase_order(
  p_purchase_order_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_conflict_declared boolean
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.approve_procurement_entity(
    'PURCHASE_ORDER',p_purchase_order_id,p_idempotency_key,p_reason,p_conflict_declared
  );
$$;

create function public.receive_purchase_order(
  p_purchase_order_id uuid,
  p_warehouse_id uuid,
  p_to_warehouse_node_id uuid,
  p_lines jsonb,
  p_idempotency_key text,
  p_supplier_delivery_reference text
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.receive_purchase_order(
    p_purchase_order_id,p_warehouse_id,p_to_warehouse_node_id,p_lines,p_idempotency_key,p_supplier_delivery_reference
  );
$$;

create function public.create_match_supplier_invoice(
  p_purchase_order_id uuid,
  p_invoice_number text,
  p_invoice_date date,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language sql
security invoker
set search_path=''
as $$
  select app_private.create_match_supplier_invoice(
    p_purchase_order_id,p_invoice_number,p_invoice_date,p_lines,p_idempotency_key
  );
$$;

revoke all on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) from public,anon;
revoke all on function public.approve_purchase_requisition(uuid,text,text,boolean) from public,anon;
revoke all on function public.create_submit_purchase_order(uuid,uuid,date,text,text) from public,anon;
revoke all on function public.approve_purchase_order(uuid,text,text,boolean) from public,anon;
revoke all on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) from public,anon;
revoke all on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) from public,anon;

grant execute on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) to authenticated,service_role;
grant execute on function public.approve_purchase_requisition(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function public.create_submit_purchase_order(uuid,uuid,date,text,text) to authenticated,service_role;
grant execute on function public.approve_purchase_order(uuid,text,text,boolean) to authenticated,service_role;
grant execute on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) to authenticated,service_role;

comment on function public.create_submit_purchase_requisition(uuid,text,date,jsonb,text) is
  'Controlled Release-1 requisition create+submit command. Named arguments support Supabase/PostgREST clients.';
comment on function public.approve_purchase_requisition(uuid,text,text,boolean) is
  'BOARD requisition approval command. Named arguments support Supabase/PostgREST clients.';
comment on function public.create_submit_purchase_order(uuid,uuid,date,text,text) is
  'Create+submit PO from an approved requisition. Named arguments support Supabase/PostgREST clients.';
comment on function public.approve_purchase_order(uuid,text,text,boolean) is
  'BOARD PO approval command under active PROCUREMENT policy. Named arguments support Supabase/PostgREST clients.';
comment on function public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text) is
  'Controlled receiving command into authoritative inventory ledger. Named arguments support Supabase/PostgREST clients.';
comment on function public.create_match_supplier_invoice(uuid,text,date,jsonb,text) is
  'FINANCE supplier invoice + three-way match command. Named arguments support Supabase/PostgREST clients.';

-- Fail closed if the API-facing argument contract or ACL regresses.
do $$
declare
  v_names text[];
begin
  select p.proargnames into v_names
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='approve_purchase_order'
    and pg_get_function_identity_arguments(p.oid)='uuid, text, text, boolean';
  if v_names is distinct from array['p_purchase_order_id','p_idempotency_key','p_reason','p_conflict_declared']::text[] then
    raise exception 'PROCUREMENT_APPROVE_PO_RPC_ARGUMENT_CONTRACT_INVALID';
  end if;

  select p.proargnames into v_names
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='receive_purchase_order'
    and pg_get_function_identity_arguments(p.oid)='uuid, uuid, uuid, jsonb, text, text';
  if v_names is distinct from array['p_purchase_order_id','p_warehouse_id','p_to_warehouse_node_id','p_lines','p_idempotency_key','p_supplier_delivery_reference']::text[] then
    raise exception 'PROCUREMENT_RECEIVE_RPC_ARGUMENT_CONTRACT_INVALID';
  end if;

  if has_function_privilege('anon','public.approve_purchase_order(uuid,text,text,boolean)','EXECUTE')
     or has_function_privilege('anon','public.receive_purchase_order(uuid,uuid,uuid,jsonb,text,text)','EXECUTE')
     or has_function_privilege('anon','public.create_match_supplier_invoice(uuid,text,date,jsonb,text)','EXECUTE') then
    raise exception 'PROCUREMENT_PUBLIC_RPC_ANON_EXECUTE_FORBIDDEN';
  end if;
end $$;
