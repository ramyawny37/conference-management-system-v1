do $$
declare d text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='platform' and p.proname='execute_conference_device_operation_phase1c_core';
 if position('manage_foundation_module_grant' in d)=0 or position('recover_revoke_final_module_manager' in d)=0 then raise exception 'LEGACY_PERMISSION_BRANCHES_NOT_FOUND'; end if;
 d:=regexp_replace(d,E"\\n  when 'manage_foundation_module_grant'.*?v_result:=public\\.manage_foundation_module_grant\\([^;]+;","",'s');
 d:=regexp_replace(d,E"\\n  when 'recover_revoke_final_module_manager'.*?v_result:=public\\.recover_revoke_final_module_manager\\([^;]+;","",'s');
 execute d;
end $$;