begin;
do $$
declare v text;
begin
 select pg_get_functiondef('public.require_effective_module_permission(uuid,text,text,text,text)'::regprocedure) into v;
 if position('and grants.permission_id=v_permission.id' in v)=0 then
  raise exception 'MODULE_ACCESS_IMPLICATION_PREDECESSOR_MISMATCH' using errcode='55000'; end if;
 v:=replace(v,
 'where grants.user_id=v_actor and grants.permission_id=v_permission.id
      and grants.scope_type=''module''',
 'where grants.user_id=v_actor
      and grants.permission_id in (
        v_permission.id,
        case when p_permission_key=p_module_key||''.module.access'' then
          (select id from platform.permissions where code=p_module_key||''.module.manage'' and status=''active'')
        else v_permission.id end
      )
      and grants.scope_type=''module''');
 execute v;
end $$;
commit;