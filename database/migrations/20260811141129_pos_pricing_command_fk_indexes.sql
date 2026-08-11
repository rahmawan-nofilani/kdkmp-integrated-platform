create index if not exists idx_pos_payment_commands_organization_id on public.pos_payment_commands(organization_id);
create index if not exists idx_pos_payment_commands_organization_node_id on public.pos_payment_commands(organization_node_id);
create index if not exists idx_pos_payment_commands_organization_unit_id on public.pos_payment_commands(organization_unit_id);
create index if not exists idx_pos_payment_commands_result_attempt on public.pos_payment_commands(result_payment_attempt_id);
create index if not exists idx_pos_payment_commands_result_intent on public.pos_payment_commands(result_payment_intent_id);

create index if not exists idx_pos_sale_commands_customer_member on public.pos_sale_commands(customer_member_id);
create index if not exists idx_pos_sale_commands_organization_id on public.pos_sale_commands(organization_id);
create index if not exists idx_pos_sale_commands_organization_node_id on public.pos_sale_commands(organization_node_id);
create index if not exists idx_pos_sale_commands_organization_unit_id on public.pos_sale_commands(organization_unit_id);
create index if not exists idx_pos_sale_commands_result_sale on public.pos_sale_commands(result_sale_id);
create index if not exists idx_pos_sale_commands_terminal on public.pos_sale_commands(terminal_id);

create index if not exists idx_pos_sale_line_commands_inventory_item on public.pos_sale_line_commands(inventory_item_id);
create index if not exists idx_pos_sale_line_commands_organization_id on public.pos_sale_line_commands(organization_id);
create index if not exists idx_pos_sale_line_commands_organization_node_id on public.pos_sale_line_commands(organization_node_id);
create index if not exists idx_pos_sale_line_commands_organization_unit_id on public.pos_sale_line_commands(organization_unit_id);
create index if not exists idx_pos_sale_line_commands_result_line on public.pos_sale_line_commands(result_line_id);
create index if not exists idx_pos_sale_line_commands_sale_line on public.pos_sale_line_commands(sales_transaction_line_id);
create index if not exists idx_pos_sale_line_commands_uom on public.pos_sale_line_commands(uom_id);

create index if not exists idx_pos_shift_commands_organization_id on public.pos_shift_commands(organization_id);
create index if not exists idx_pos_shift_commands_organization_node_id on public.pos_shift_commands(organization_node_id);
create index if not exists idx_pos_shift_commands_organization_unit_id on public.pos_shift_commands(organization_unit_id);
create index if not exists idx_pos_shift_commands_result_shift on public.pos_shift_commands(result_shift_id);
create index if not exists idx_pos_shift_commands_terminal on public.pos_shift_commands(terminal_id);

create index if not exists idx_sales_price_entries_inventory_item on public.sales_price_entries(inventory_item_id);
create index if not exists idx_sales_price_entries_organization_node_id on public.sales_price_entries(organization_node_id);
create index if not exists idx_sales_price_entries_organization_unit_id on public.sales_price_entries(organization_unit_id);
create index if not exists idx_sales_price_entries_uom on public.sales_price_entries(uom_id);
create index if not exists idx_sales_price_lists_organization_unit_id on public.sales_price_lists(organization_unit_id);
