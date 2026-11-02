-- Reservations gender contract cutover (Development only).
-- Guard every source rewrite: an upstream contract change must fail closed.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
  v_count integer;
begin
  select pg_get_functiondef('platform_private.update_canonical_person(uuid,uuid,uuid,bigint,jsonb,uuid,text,text,jsonb)'::regprocedure) into v_def;
  v_old := 'v_allowed:=array[''fullName'',''phone'',''church''];';
  v_new := 'v_allowed:=array[''fullName'',''phone'',''church'',''gender''];';
  v_count := (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);
  if v_count<>1 then raise exception 'RESERVATIONS_GENDER_PERSON_CONTRACT_CHANGED'; end if;
  execute replace(v_def,v_old,v_new);

  select pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure) into v_def;
  v_old := 'array[''p_person_id'',''p_person_update_revision'']';
  v_new := 'array[''p_person_id'',''p_person_update_revision'',''p_gender'']';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_CREATE_DISPATCH_CHANGED'; end if;
  v_def:=replace(v_def,v_old,v_new);
  v_old := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes'']';
  v_new := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender'']';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_UPDATE_DISPATCH_CHANGED'; end if;
  execute replace(v_def,v_old,v_new);

  select pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure) into v_def;
  v_old := 'array[''p_person_id'',''p_person_update_revision'']';
  v_new := 'array[''p_person_id'',''p_person_update_revision'',''p_gender'']';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_CREATE_MUTATION_CHANGED'; end if;
  v_def:=replace(v_def,v_old,v_new);
  v_old := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes'']';
  v_new := 'array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender'']';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_UPDATE_MUTATION_CHANGED'; end if;
  v_def:=replace(v_def,v_old,v_new);
  -- Update canonical people only through the permission- and revision-checked helper.
  v_old := 'jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'')';
  v_new := 'jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'') || case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_PERSON_PATCH_CHANGED'; end if;
  v_def:=replace(v_def,v_old,v_new);
  v_old := 'insert into platform.people(full_name,phone,church,created_by,updated_by) values(';
  v_new := 'insert into platform.people(full_name,phone,church,gender,created_by,updated_by) values(';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'RESERVATIONS_GENDER_PERSON_INSERT_CHANGED'; end if;
  v_def:=replace(v_def,v_old,v_new);
  -- The values insertion is guarded independently to avoid silently shifting columns.
  v_old := 'v_actor,v_actor) returning id into v_person_id;';
  v_new := 'v_actor,v_actor) returning id into v_person_id;';
  -- Full INSERT values rewrite is deliberately deferred until source is inspected.
  raise exception 'RESERVATIONS_GENDER_MIGRATION_NOT_READY: inspect INSERT values and update permissions before applying';
end
$migration$;