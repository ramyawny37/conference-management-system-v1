do $$
declare source text; old text;
begin
select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into source;
old := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes'']';
if source not like '%'||old||'%' then raise exception 'Update contract missing';end if;
execute replace(source,old,old||',array[''p_gender'']');
end $$;;
