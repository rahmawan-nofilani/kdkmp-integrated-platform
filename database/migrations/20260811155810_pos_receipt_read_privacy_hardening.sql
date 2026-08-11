drop policy if exists pos_receipts_read on public.pos_receipts;
create policy pos_receipts_read on public.pos_receipts
for select to authenticated
using (
  public.has_permission('SALES_VIEW')
  and public.has_data_scope(organization_id,organization_node_id,organization_unit_id,null,null)
  and (
    exists(
      select 1 from public.profiles p
      where p.id=created_by and p.auth_user_id=(select auth.uid()) and p.status='ACTIVE'
    )
    or public.has_permission('REPORT_VIEW')
    or public.has_permission('AUDIT_VIEW')
  )
);
