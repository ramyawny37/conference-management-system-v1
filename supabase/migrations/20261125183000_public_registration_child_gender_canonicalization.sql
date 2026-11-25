begin;

alter table reservations.public_registration_request_members
  drop constraint public_registration_request_members_check1;
alter table reservations.public_registration_request_members
  drop constraint public_registration_request_members_gender_check;
alter table reservations.public_registration_request_members
  add constraint public_registration_request_members_canonical_gender_check
  check(gender in('male','female')) not valid;

create or replace function platform_private.create_reservations_dependent_person(
  p_device_id uuid,p_actor uuid,p_operation_id uuid,p_event_id uuid,p_profile jsonb
) returns uuid language plpgsql volatile security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_person_id uuid;v_authorization uuid;
begin
 perform platform_private.require_exact_jsonb_keys(p_profile,
  array['fullName','phone','gender','dateOfBirth','church','governorate','cityOrVillage','serviceSector'],
  array['serviceSectorOther']);
 select * into v_event from reservations.events where id=p_event_id for key share;
 if not found or nullif(btrim(p_profile->>'fullName'),'') is null
   or p_profile->>'gender' not in('male','female')
   or nullif(p_profile->>'dateOfBirth','') is null
   or (p_profile->>'dateOfBirth')::date>v_event.start_date then
  raise exception 'PUBLIC_REGISTRATION_DEPENDENT_IDENTITY_INVALID' using errcode='22023';
 end if;
 select id into v_authorization from platform.user_device_authorizations
  where device_id=p_device_id and user_id=p_actor and status='approved' and revoked_at is null limit 1;
 if v_authorization is null then raise exception 'PLATFORM_DEVICE_NOT_APPROVED' using errcode='42501';end if;
 insert into platform.people(full_name,phone,gender,date_of_birth,church,governorate,city_or_village,
  service_sector,service_sector_other,created_by,updated_by)
 values(btrim(p_profile->>'fullName'),nullif(btrim(p_profile->>'phone'),''),p_profile->>'gender',
  (p_profile->>'dateOfBirth')::date,nullif(btrim(p_profile->>'church'),''),
  nullif(btrim(p_profile->>'governorate'),''),nullif(btrim(p_profile->>'cityOrVillage'),''),
  nullif(btrim(p_profile->>'serviceSector'),''),nullif(btrim(p_profile->>'serviceSectorOther'),''),p_actor,p_actor)
 returning id into v_person_id;
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
  entity_type,entity_id,scope_type,new_values,metadata,operation_id,source)
 values(p_actor,v_authorization,'platform','reservations','platform.person.created','person',v_person_id,
  'platform',jsonb_build_object('id',v_person_id,'fullName',btrim(p_profile->>'fullName'),
  'gender',p_profile->>'gender','dateOfBirth',p_profile->>'dateOfBirth'),
  jsonb_build_object('eventId',p_event_id,'permissionKey','reservations.booking.create',
  'purpose','dependent-child'),p_operation_id,'rpc');
 return v_person_id;
end $$;
revoke all on function platform_private.create_reservations_dependent_person(uuid,uuid,uuid,uuid,jsonb)
 from public,anon,authenticated,service_role;

do $patch$
declare d text;old_text text:=
$$if v_guardian is null or (v_member->>'gender')<>'child' then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;$$;
new_text text:=
$$if v_guardian is null or (v_member->>'gender') not in('male','female') then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;$$;
begin
 d:=pg_get_functiondef('reservations.public_registration_submit_family(uuid,uuid,bytea,bytea,jsonb)'::regprocedure);
 if (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 then
  raise exception 'PUBLIC_REGISTRATION_CHILD_GENDER_WRITER_DRIFT';
 end if;
 execute replace(d,old_text,new_text);
end $patch$;

commit;
