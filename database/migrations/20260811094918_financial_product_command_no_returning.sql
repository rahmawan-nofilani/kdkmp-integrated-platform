drop function if exists public.create_financial_product_draft(text,text,text,text,text,text,uuid);

create or replace function public.create_financial_product_draft(
  p_template_code text,
  p_product_code text,
  p_product_name text,
  p_legal_product_type text default null,
  p_purpose_code text default null,
  p_description text default null,
  p_organization_unit_id uuid default null
)
returns void
language plpgsql
security invoker
set search_path=''
as $$
begin
  insert into public.financial_product_draft_commands(
    template_code,organization_unit_id,product_code,product_name,legal_product_type,purpose_code,description
  ) values(
    p_template_code,p_organization_unit_id,p_product_code,p_product_name,p_legal_product_type,p_purpose_code,p_description
  );
end;
$$;

revoke all on function public.create_financial_product_draft(text,text,text,text,text,text,uuid) from public,anon;
grant execute on function public.create_financial_product_draft(text,text,text,text,text,text,uuid) to authenticated;