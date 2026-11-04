do $$
declare source text; old text; replacement text;
begin
select pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure) into source;
old := 'array[''p_person_id'',''p_person_update_revision'']';
replacement := 'array[''p_person_id'',''p_person_update_revision'',''p_gender'']';
if source not like '%'||old||'%' then raise exception 'Contract not found'; end if;
execute replace(source,old,replacement);
end $$;;
