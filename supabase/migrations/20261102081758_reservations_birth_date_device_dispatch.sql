do $$ declare s text;begin
select pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure) into s;
if position('''p_person_update_revision'',''p_gender'']' in s)=0 then raise exception 'dispatcher contract changed';end if;
execute replace(s,'''p_person_update_revision'',''p_gender'']','''p_person_update_revision'',''p_gender'',''p_date_of_birth'']');
end $$;;
