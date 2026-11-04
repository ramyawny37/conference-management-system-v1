do $$
declare source text; old text;
begin
select pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure) into source;
old := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes'']';
if source not like '%'||old||'%' then raise exception 'Contract not found'; end if;
execute replace(source,old,old||',array[''p_gender'']');
end $$;;
