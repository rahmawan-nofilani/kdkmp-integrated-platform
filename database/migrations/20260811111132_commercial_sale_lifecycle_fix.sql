create or replace function app_private.prevent_completed_sale_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='DELETE' then
    if old.status in ('COMPLETED','VOID_PENDING','VOIDED','RETURNED') then raise exception 'committed_sale_cannot_be_deleted'; end if;
    return old;
  end if;
  if old.status in ('COMPLETED','VOID_PENDING','VOIDED','RETURNED') and (
    new.organization_id is distinct from old.organization_id or
    new.organization_node_id is distinct from old.organization_node_id or
    new.organization_unit_id is distinct from old.organization_unit_id or
    new.terminal_id is distinct from old.terminal_id or
    new.pos_shift_id is distinct from old.pos_shift_id or
    new.sale_number is distinct from old.sale_number or
    new.sale_type is distinct from old.sale_type or
    new.customer_member_id is distinct from old.customer_member_id or
    new.customer_reference is distinct from old.customer_reference or
    new.currency is distinct from old.currency or
    new.subtotal is distinct from old.subtotal or
    new.discount_amount is distinct from old.discount_amount or
    new.tax_amount is distinct from old.tax_amount or
    new.payment_intent_id is distinct from old.payment_intent_id or
    new.inventory_movement_id is distinct from old.inventory_movement_id or
    new.journal_entry_id is distinct from old.journal_entry_id or
    new.receipt_reference is distinct from old.receipt_reference or
    new.local_transaction_id is distinct from old.local_transaction_id or
    new.device_id is distinct from old.device_id or
    new.client_sequence is distinct from old.client_sequence or
    new.idempotency_key is distinct from old.idempotency_key or
    new.correlation_id is distinct from old.correlation_id or
    new.sold_at is distinct from old.sold_at or
    new.completed_at is distinct from old.completed_at
  ) then raise exception 'committed_sale_content_is_immutable_use_void_or_return_flow'; end if;
  return new;
end; $$;
revoke all on function app_private.prevent_completed_sale_mutation() from public,anon,authenticated;

create or replace function app_private.prevent_completed_sale_line_mutation()
returns trigger language plpgsql security definer set search_path=''
as $$ declare s text; begin select status into s from public.sales_transactions where id=old.sales_transaction_id; if s in ('COMPLETED','VOID_PENDING','VOIDED','RETURNED') then raise exception 'committed_sale_line_is_immutable'; end if; return new; end; $$;
revoke all on function app_private.prevent_completed_sale_line_mutation() from public,anon,authenticated;
