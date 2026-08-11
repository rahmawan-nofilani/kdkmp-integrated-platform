insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
join public.permissions p on p.code='MEMBER_STATUS_CHANGE'
where r.code='MANAGER'
on conflict do nothing;