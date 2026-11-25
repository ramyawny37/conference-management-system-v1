begin;

create or replace function reservations_private.public_registration_booking_args(
  p_operation_id uuid,
  p_event_id uuid,
  p_booking_type_id uuid,
  p_full_name text,
  p_phone text,
  p_age integer,
  p_church text,
  p_governorate text,
  p_city_or_village text,
  p_service_sector text,
  p_service_sector_other text,
  p_notes text,
  p_gender text,
  p_date_of_birth date,
  p_person_id uuid default null
) returns jsonb
language sql
immutable
set search_path=''
as $$
  select jsonb_build_object(
    'p_operation_id',p_operation_id,
    'p_event_id',p_event_id,
    'p_booking_type_id',p_booking_type_id,
    'p_full_name',p_full_name,
    'p_phone',p_phone,
    'p_age',p_age,
    'p_church',p_church,
    'p_governorate',p_governorate,
    'p_city_or_village',p_city_or_village,
    'p_service_sector',p_service_sector,
    'p_service_sector_other',p_service_sector_other,
    'p_notes',p_notes,
    'p_gender',p_gender,
    'p_date_of_birth',p_date_of_birth
  ) || case when p_person_id is null then '{}'::jsonb else jsonb_build_object('p_person_id',p_person_id) end
$$;

do $patch$
declare
  d text;
  old_single text := $$v_booking_args:=jsonb_strip_nulls(jsonb_build_object(
    'p_operation_id',p_operation_id,'p_event_id',r.event_id,'p_booking_type_id',r.booking_type_id,
    'p_full_name',r.submitted_full_name,'p_phone',r.submitted_phone,'p_age',v_age,
    'p_church',r.submitted_church,'p_governorate',r.submitted_governorate,
    'p_city_or_village',r.submitted_city_or_village,'p_service_sector',r.submitted_service_sector,
    'p_service_sector_other',r.submitted_service_sector_other,'p_notes',r.submitted_notes,
    'p_gender',r.submitted_gender,'p_date_of_birth',r.submitted_date_of_birth,
    'p_person_id',case when p_decision='approve_existing' then p_person_id else null end
  ));$$;
  new_single text := $$v_booking_args:=reservations_private.public_registration_booking_args(
    p_operation_id,r.event_id,r.booking_type_id,r.submitted_full_name,r.submitted_phone,v_age,
    r.submitted_church,r.submitted_governorate,r.submitted_city_or_village,r.submitted_service_sector,
    r.submitted_service_sector_other,r.submitted_notes,r.submitted_gender,r.submitted_date_of_birth,
    case when p_decision='approve_existing' then p_person_id else null end
  );$$;
  old_family text := $$args:=jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_event_id',r.event_id,'p_booking_type_id',m.booking_type_id,'p_full_name',m.full_name,'p_phone',m.phone,'p_age',age,'p_church',m.church,'p_governorate',m.governorate,'p_city_or_village',m.city_or_village,'p_service_sector',m.service_sector,'p_service_sector_other',m.service_sector_other,'p_notes',m.notes,'p_gender',m.gender,'p_date_of_birth',m.date_of_birth)||case when choice='existing' then jsonb_build_object('p_person_id',pid) else '{}'::jsonb end;$$;
  new_family text := $$args:=reservations_private.public_registration_booking_args(extensions.gen_random_uuid(),r.event_id,m.booking_type_id,m.full_name,m.phone,age,m.church,m.governorate,m.city_or_village,m.service_sector,m.service_sector_other,m.notes,m.gender,m.date_of_birth,case when choice='existing' then pid else null end);$$;
begin
  d:=pg_get_functiondef('reservations_private.decide_public_registration_request(uuid,uuid,uuid,bigint,text,uuid,text)'::regprocedure);
  if (length(d)-length(replace(d,old_single,'')))/length(old_single)<>1 then raise exception 'PUBLIC_REGISTRATION_SINGLE_BOOKING_ARGS_DRIFT'; end if;
  execute replace(d,old_single,new_single);

  d:=pg_get_functiondef('reservations_private.decide_public_registration_family_request(uuid,uuid,uuid,bigint,text,jsonb,text)'::regprocedure);
  if (length(d)-length(replace(d,old_family,'')))/length(old_family)<>1 then raise exception 'PUBLIC_REGISTRATION_FAMILY_BOOKING_ARGS_DRIFT'; end if;
  execute replace(d,old_family,new_family);
end $patch$;

revoke all on function reservations_private.public_registration_booking_args(uuid,uuid,uuid,text,text,integer,text,text,text,text,text,text,text,date,uuid) from public,anon,authenticated;
grant execute on function reservations_private.public_registration_booking_args(uuid,uuid,uuid,text,text,integer,text,text,text,text,text,text,text,date,uuid) to postgres,service_role;

commit;
