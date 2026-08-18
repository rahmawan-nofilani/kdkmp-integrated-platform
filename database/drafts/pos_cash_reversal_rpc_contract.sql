-- REVIEW DRAFT ONLY / NOT A MIGRATION
-- Must be replayed after pos_cash_reversal_controlled_flow.sql and
-- pos_cash_reversal_hardening.sql in a disposable local Supabase target.

create or replace function public.reverse_cash_pos_sale(
  p_sales_transaction_id uuid,
  p_refund_pos_shift_id uuid,
  p_reason_code text,
  p_idempotency_key text,
  p_reason_note text default null
)
returns table(
  sales_return_id uuid,
  refund_payment_intent_id uuid,
  refund_payment_attempt_id uuid,
  inventory_movement_id uuid,
  journal_entry_id uuid,
  cash_movement_id uuid,
  refund_receipt_id uuid
)
language plpgsql
security invoker
set search_path to ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_command public.pos_cash_reversal_commands%rowtype;
begin
  select * into v_profile
  from public.profiles
  where auth_user_id=(select auth.uid()) and status='ACTIVE'
  limit 1;

  if v_profile.id is null then
    raise exception 'ACTIVE_PROFILE_REQUIRED' using errcode='42501';
  end if;

  insert into public.pos_cash_reversal_commands(
    original_sales_transaction_id,refund_pos_shift_id,reason_code,reason_note,
    idempotency_key,requested_by
  ) values (
    p_sales_transaction_id,p_refund_pos_shift_id,p_reason_code,p_reason_note,
    p_idempotency_key,v_profile.id
  )
  returning * into v_command;

  if v_command.id is null then
    select * into v_command
    from public.pos_cash_reversal_commands
    where idempotency_key=p_idempotency_key
      and requested_by=v_profile.id
      and original_sales_transaction_id=p_sales_transaction_id
    limit 1;
  end if;

  if v_command.result_sales_return_id is null
     or v_command.result_refund_payment_intent_id is null
     or v_command.result_refund_payment_attempt_id is null
     or v_command.result_inventory_movement_id is null
     or v_command.result_journal_entry_id is null
     or v_command.result_cash_movement_id is null
     or v_command.result_refund_receipt_id is null then
    raise exception 'POS_CASH_REVERSAL_NOT_COMPLETED' using errcode='P0001';
  end if;

  return query select
    v_command.result_sales_return_id,
    v_command.result_refund_payment_intent_id,
    v_command.result_refund_payment_attempt_id,
    v_command.result_inventory_movement_id,
    v_command.result_journal_entry_id,
    v_command.result_cash_movement_id,
    v_command.result_refund_receipt_id;
end;
$$;

revoke all on function public.reverse_cash_pos_sale(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.reverse_cash_pos_sale(uuid,uuid,text,text,text) to authenticated,service_role;
