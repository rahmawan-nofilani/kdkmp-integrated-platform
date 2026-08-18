import type { SupabaseClient } from "@supabase/supabase-js";
import type { PosDatabase } from "./pos";

type TableShape<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type PosCashReversalCommandRow = {
  id: string;
  organization_id: string | null;
  organization_node_id: string | null;
  organization_unit_id: string | null;
  original_sales_transaction_id: string;
  refund_pos_shift_id: string;
  reason_code: string;
  reason_note: string | null;
  idempotency_key: string;
  result_sales_return_id: string | null;
  result_refund_payment_intent_id: string | null;
  result_refund_payment_attempt_id: string | null;
  result_inventory_movement_id: string | null;
  result_journal_entry_id: string | null;
  result_cash_movement_id: string | null;
  requested_by: string | null;
  created_at: string;
};

export type CashPosReversalResult = {
  sales_return_id: string;
  refund_payment_intent_id: string;
  refund_payment_attempt_id: string;
  inventory_movement_id: string;
  journal_entry_id: string;
  cash_movement_id: string;
};

type PosReversalFunctions = PosDatabase["public"]["Functions"] & {
  reverse_cash_pos_sale: {
    Args: {
      p_sales_transaction_id: string;
      p_refund_pos_shift_id: string;
      p_reason_code: string;
      p_idempotency_key: string;
      p_reason_note?: string | null;
    };
    Returns: CashPosReversalResult[];
  };
};

export type PosReversalDatabase = Omit<PosDatabase, "public"> & {
  public: Omit<PosDatabase["public"], "Tables" | "Functions"> & {
    Tables: PosDatabase["public"]["Tables"] & {
      pos_cash_reversal_commands: TableShape<PosCashReversalCommandRow>;
    };
    Functions: PosReversalFunctions;
  };
};

export type PosReversalClient = SupabaseClient<PosReversalDatabase>;

export function asPosReversalClient(client: unknown): PosReversalClient {
  return client as PosReversalClient;
}
