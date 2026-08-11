insert into public.roles (code, name, description, is_privileged)
values
 ('MANAGER','Manager','Operational controller of the cooperative application',true),
 ('ADMIN','Admin','Operational administration staff',false),
 ('MEMBER','Anggota','Cooperative member self-service access',false),
 ('COURIER','Kurir','Delivery assignment execution',false),
 ('SUPERVISOR','Pengawas','Read, review, control and audit role',true),
 ('BOARD','Pengurus','Governance and approval role',true),
 ('CASHIER','Kasir','POS cashier operator',false),
 ('WAREHOUSE_OPERATOR','Petugas Gudang','Warehouse operational role',false),
 ('PROCUREMENT_OFFICER','Petugas Pengadaan','Procurement operational role',false),
 ('FINANCE_OFFICER','Petugas Keuangan','Finance operational role',true),
 ('TELLER','Teller','Savings and loan teller role',true),
 ('LOAN_OFFICER','Petugas Pinjaman','Loan origination and review role',true),
 ('COMPLIANCE_OFFICER','Petugas Kepatuhan','Compliance review role',true)
on conflict (code) do nothing;

insert into public.permissions (code, domain, description, is_privileged)
values
 ('USER_VIEW','IDENTITY','View users',false),
 ('USER_CREATE','IDENTITY','Create operational users',true),
 ('USER_UPDATE','IDENTITY','Update operational users',true),
 ('USER_SUSPEND','IDENTITY','Suspend user access',true),
 ('USER_ARCHIVE','IDENTITY','Archive inactive users without deleting history',true),
 ('ROLE_VIEW','IDENTITY','View roles',false),
 ('ROLE_ASSIGN','IDENTITY','Assign allowed roles',true),
 ('PERMISSION_VIEW','IDENTITY','View permissions',false),
 ('PERMISSION_GRANT','IDENTITY','Grant permissions within delegation boundary',true),
 ('SCOPE_ASSIGN','IDENTITY','Assign data scopes',true),
 ('MEMBER_VIEW','COOPERATIVE','View members within scope',false),
 ('MEMBER_CREATE','COOPERATIVE','Create member record',false),
 ('MEMBER_UPDATE','COOPERATIVE','Update allowed member data',false),
 ('MEMBER_STATUS_CHANGE','COOPERATIVE','Change membership lifecycle status',true),
 ('PRODUCT_VIEW','CATALOG','View product catalog',false),
 ('PRODUCT_CREATE','CATALOG','Create product',false),
 ('PRODUCT_UPDATE','CATALOG','Update current product data',false),
 ('INVENTORY_VIEW','INVENTORY','View inventory',false),
 ('INVENTORY_RECEIVE','INVENTORY','Receive inventory',false),
 ('INVENTORY_TRANSFER','INVENTORY','Transfer inventory',false),
 ('INVENTORY_ADJUST','INVENTORY','Request or execute approved inventory adjustment',true),
 ('STOCK_OPNAME','INVENTORY','Perform stock opname',true),
 ('PURCHASE_CREATE','PROCUREMENT','Create purchase request/order within workflow',false),
 ('PURCHASE_SUBMIT','PROCUREMENT','Submit purchase for approval',false),
 ('PURCHASE_APPROVE','PROCUREMENT','Approve purchase under approval policy',true),
 ('SALES_CREATE','SALES','Create sales transaction',false),
 ('SALES_VOID','SALES','Void sale through controlled process',true),
 ('PAYMENT_CREATE','FINANCE','Create payment transaction',true),
 ('PAYMENT_APPROVE','FINANCE','Approve payment under policy',true),
 ('SAVINGS_VIEW','FINANCIAL_SERVICES','View savings account under scope',true),
 ('SAVINGS_DEPOSIT','FINANCIAL_SERVICES','Post permitted savings deposit',true),
 ('SAVINGS_WITHDRAW','FINANCIAL_SERVICES','Process permitted savings withdrawal',true),
 ('LOAN_VIEW','FINANCIAL_SERVICES','View loan under scope',true),
 ('LOAN_CREATE','FINANCIAL_SERVICES','Create loan application',true),
 ('LOAN_REVIEW','FINANCIAL_SERVICES','Review loan application',true),
 ('LOAN_APPROVE','FINANCIAL_SERVICES','Approve loan under policy',true),
 ('LOAN_DISBURSE','FINANCIAL_SERVICES','Disburse approved loan',true),
 ('LOAN_COLLECT','FINANCIAL_SERVICES','Record collection/repayment activity',true),
 ('FINANCIAL_PRODUCT_CREATE','FINANCIAL_SERVICES','Create financial product draft',true),
 ('FINANCIAL_PRODUCT_APPROVE','FINANCIAL_SERVICES','Approve financial product after required checks',true),
 ('REPORT_VIEW','REPORTING','View allowed reports',false),
 ('REPORT_EXPORT','REPORTING','Export allowed reports',false),
 ('AUDIT_VIEW','AUDIT','View audit trail under scope',true),
 ('RISK_VIEW','RISK','View risk register',true),
 ('RISK_UPDATE','RISK','Update risk management records',true),
 ('CONTROL_REVIEW','CONTROL','Review internal controls',true),
 ('DOCUMENT_VIEW','DOCUMENT','View authorized documents',false),
 ('DOCUMENT_CREATE','DOCUMENT','Upload/create authorized documents',false),
 ('APPROVAL_VIEW','GOVERNANCE','View approval queue',true),
 ('APPROVAL_DECIDE','GOVERNANCE','Make allowed approval decision',true)
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code = 'MANAGER' and p.code in (
 'USER_VIEW','USER_CREATE','USER_UPDATE','USER_SUSPEND','USER_ARCHIVE','ROLE_VIEW','ROLE_ASSIGN','PERMISSION_VIEW','SCOPE_ASSIGN',
 'MEMBER_VIEW','MEMBER_CREATE','MEMBER_UPDATE','PRODUCT_VIEW','PRODUCT_CREATE','PRODUCT_UPDATE','INVENTORY_VIEW','INVENTORY_RECEIVE','INVENTORY_TRANSFER','STOCK_OPNAME',
 'PURCHASE_CREATE','PURCHASE_SUBMIT','SALES_CREATE','REPORT_VIEW','REPORT_EXPORT','AUDIT_VIEW','RISK_VIEW','RISK_UPDATE','CONTROL_REVIEW','DOCUMENT_VIEW','DOCUMENT_CREATE','APPROVAL_VIEW',
 'SAVINGS_VIEW','LOAN_VIEW','LOAN_CREATE','LOAN_REVIEW','FINANCIAL_PRODUCT_CREATE'
) on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='ADMIN' and p.code in ('MEMBER_VIEW','MEMBER_CREATE','MEMBER_UPDATE','PRODUCT_VIEW','PRODUCT_CREATE','PRODUCT_UPDATE','INVENTORY_VIEW','PURCHASE_CREATE','SALES_CREATE','REPORT_VIEW','DOCUMENT_VIEW','DOCUMENT_CREATE')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='MEMBER' and p.code in ('PRODUCT_VIEW','DOCUMENT_VIEW') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='SUPERVISOR' and p.code in ('REPORT_VIEW','AUDIT_VIEW','RISK_VIEW','CONTROL_REVIEW','DOCUMENT_VIEW','MEMBER_VIEW','INVENTORY_VIEW','LOAN_VIEW','SAVINGS_VIEW') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='BOARD' and p.code in ('REPORT_VIEW','AUDIT_VIEW','RISK_VIEW','DOCUMENT_VIEW','APPROVAL_VIEW','APPROVAL_DECIDE','LOAN_VIEW','SAVINGS_VIEW') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='CASHIER' and p.code in ('PRODUCT_VIEW','SALES_CREATE') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='WAREHOUSE_OPERATOR' and p.code in ('INVENTORY_VIEW','INVENTORY_RECEIVE','INVENTORY_TRANSFER','STOCK_OPNAME') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='TELLER' and p.code in ('SAVINGS_VIEW','SAVINGS_DEPOSIT','SAVINGS_WITHDRAW','LOAN_VIEW','LOAN_COLLECT') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='LOAN_OFFICER' and p.code in ('LOAN_VIEW','LOAN_CREATE','LOAN_REVIEW','MEMBER_VIEW','DOCUMENT_VIEW') on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.code='COMPLIANCE_OFFICER' and p.code in ('LOAN_VIEW','SAVINGS_VIEW','AUDIT_VIEW','RISK_VIEW','CONTROL_REVIEW','DOCUMENT_VIEW','FINANCIAL_PRODUCT_APPROVE') on conflict do nothing;
