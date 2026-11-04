begin;
drop function public.require_module_permission(uuid,text,text,text,text);
drop function public.validate_module_permission_catalog(text,text,text,text,text);
drop table public.module_grant_audit_log;
drop table public.module_grant_operations;
drop table public.module_permission_grants;
drop table public.module_permission_catalog;
commit;