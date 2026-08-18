import type { SupabaseClient } from "@supabase/supabase-js";
import type { PosDatabase } from "./pos";
import type { PosRefundReceiptRow } from "./pos-reversal";

type TableShape<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type PosPartialReturnLineRequest = {
  sales_transaction_line_id: string;
  quantity: number;
};

export type PosPartialReturnCommandRow = {
  id: string;
  organization_id: string | null;
  organization_node_id: string | null;
  organization_unit_id: string | null;
  original_sales_transaction_id: string;
  refund_pos_shift_id: string;
  requested_lines: PosPartialReturnLineRequest[];
  reason_code: string;
  reason_note: string | null;
  idempotency_key: string;
  refund_amount: number | null;
  sale_fully_returned: boolean;
  result_sales_return_id: string | null;
  result_refund_payment_intent_id: string | null;
  result_refund_payment_attempt_id: string | null;
  result_inventory_movement_id: string | null;
  result_journal_entry_id: string | null;
  result_cash_movement_id: string | null;
  result_refund_receipt_id: string | null;
  requested_by: string | null;
  created_at: string;
};

export type PosPartialReturnLineRow = {
  id: string;
  command_id: string;
  sales_return_id: string;
  organization_id: string;
  organization_node_id: string;
  organization_unit_id: string;
  original_sales_transaction_id: string;
  original_sales_transaction_line_id: string;
  quantity: number;
  base_quantity: number;
  gross_amount: number;
  discount_amount: number;
  tax_amount: number;
  refund_amount: number;
  cost_amount: number;
  created_at: string;
};

export type CashPosPartialReturnResult = {
  sales_return_id: string;
  refund_payment_intent_id: string;
  refund_payment_attempt_id: string;
  inventory_movement_id: string;
  journal_entry_id: string;
  cash_movement_id: string;
  refund_receipt_id: string;
  refund_amount: number;
  sale_fully_returned: boolean;
};

type PosPartialReturnFunctions = PosDatabase["public"]["Functions"] & {
  return_cash_pos_items: {
    Args: {
      p_sales_transaction_id: string;
      p_refund_pos_shift_id: string;
      p_lines: PosPartialReturnLineRequest[];
      p_reason_code: string;
      p_idempotency_key: string;
      p_reason_note?: string | null;
    };
    Returns: CashPosPartialReturnResult[];
  };
};

export type PosPartialReturnDatabase = Omit<PosDatabase, "public"> & {
  public: Omit<PosDatabase["public"], "Tables" | "Functions"> & {
    Tables: PosDatabase["public"]["Tables"] & {
      pos_partial_return_commands: TableShape<PosPartialReturnCommandRow>;
      pos_partial_return_lines: TableShape<PosPartialReturnLineRow>;
      pos_refund_receipts: TableShape<PosRefundReceiptRow>;
    };
    Functions: PosPartialReturnFunctions;
  };
};

export type PosPartialReturnClient = SupabaseClient<PosPartialReturnDatabase>;

export function asPosPartialReturnClient(client: unknown): PosPartialReturnClient {
  return client as PosPartialReturnClient;
}
