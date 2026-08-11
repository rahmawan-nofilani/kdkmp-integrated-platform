create or replace function app_private.prevent_committed_po_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='DELETE' then
    if old.status in ('APPROVED','SENT','PARTIALLY_RECEIVED','RECEIVED','CLOSED') then
      raise exception 'committed_purchase_order_cannot_be_deleted';
    end if;
    return old;
  end if;

  if old.status in ('APPROVED','SENT','PARTIALLY_RECEIVED','RECEIVED','CLOSED') and (
    new.organization_id is distinct from old.organization_id or
    new.organization_node_id is distinct from old.organization_node_id or
    new.organization_unit_id is distinct from old.organization_unit_id or
    new.supplier_id is distinct from old.supplier_id or
    new.purchase_requisition_id is distinct from old.purchase_requisition_id or
    new.po_number is distinct from old.po_number or
    new.version_no is distinct from old.version_no or
    new.currency is distinct from old.currency or
    new.expected_delivery_date is distinct from old.expected_delivery_date or
    new.delivery_location_text is distinct from old.delivery_location_text or
    new.terms_snapshot is distinct from old.terms_snapshot or
    new.supplier_snapshot is distinct from old.supplier_snapshot
  ) then
    raise exception 'committed_purchase_order_content_is_immutable_create_new_version_or_controlled_change';
  end if;
  return new;
end; $$;

revoke all on function app_private.prevent_committed_po_mutation() from public,anon,authenticated;
