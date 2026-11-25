begin;

do $patch$
declare
  d text;
  old_args text := $$args:=jsonb_strip_nulls(jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_event_id',r.event_id,'p_booking_type_id',m.booking_type_id,'p_full_name',m.full_name,'p_phone',m.phone,'p_age',age,'p_church',m.church,'p_governorate',m.governorate,'p_city_or_village',m.city_or_village,'p_service_sector',m.service_sector,'p_service_sector_other',m.service_sector_other,'p_notes',m.notes,'p_gender',m.gender,'p_date_of_birth',m.date_of_birth,'p_person_id',case when choice='existing' then pid else null end));$$;
  new_args text := $$args:=jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_event_id',r.event_id,'p_booking_type_id',m.booking_type_id,'p_full_name',m.full_name,'p_phone',m.phone,'p_age',age,'p_church',m.church,'p_governorate',m.governorate,'p_city_or_village',m.city_or_village,'p_service_sector',m.service_sector,'p_service_sector_other',m.service_sector_other,'p_notes',m.notes,'p_gender',m.gender,'p_date_of_birth',m.date_of_birth)||case when choice='existing' then jsonb_build_object('p_person_id',pid) else '{}'::jsonb end;$$;
  old_gender text := $$jsonb_build_object('fullName',m.full_name,'phone',m.phone,'gender','child','dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other)$$;
  new_gender text := $$jsonb_build_object('fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other)$$;
begin
  d:=pg_get_functiondef('reservations_private.decide_public_registration_family_request(uuid,uuid,uuid,bigint,text,jsonb,text)'::regprocedure);
  if (length(d)-length(replace(d,old_args,'')))/length(old_args)<>1 then
    raise exception 'PUBLIC_REGISTRATION_FAMILY_BOOKING_ARGUMENT_DRIFT';
  end if;
  d:=replace(d,old_args,new_args);
  if (length(d)-length(replace(d,old_gender,'')))/length(old_gender)<>1 then
    raise exception 'PUBLIC_REGISTRATION_DEPENDENT_GENDER_DRIFT';
  end if;
  execute replace(d,old_gender,new_gender);
end $patch$;

commit;
