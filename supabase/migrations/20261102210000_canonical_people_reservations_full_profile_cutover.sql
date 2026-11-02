-- Complete the reservations cutover to the single canonical platform.people profile.
-- Historical reservation snapshots remain local to reservations.participants.

create or replace view reservations.participants_canonical
with (security_invoker=true) as
select participant.*,person.gender,person.date_of_birth,
  case when exists(
    select 1 from public.conference_participations participation
    join reservations.events event on event.conference_id=participation.conference_id
      and event.scope_partition_id=participant.scope_partition_id
    where participation.person_id=participant.person_id
      and participation.guardian_participation_id is not null
  ) then 'child' else 'adult' end operational_category,
  person.revision person_revision
from reservations.participants participant
left join platform.people person on person.id=participant.person_id;

revoke all on reservations.participants_canonical from public,anon,authenticated,service_role;

create or replace function platform_private.update_canonical_person(
  p_device_id uuid,p_actor uuid,p_person_id uuid,p_expected_revision bigint,
  p_patch jsonb,p_operation_id uuid,p_module text,p_permission text,p_metadata jsonb
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare v_person platform.people%rowtype;v_authorization uuid;v_allowed text[];
begin
 if p_module='conference' and p_permission='conference.people.manage' then
  v_allowed:=array['fullName','phone','church','gender','dateOfBirth','governorate','cityOrVillage','serviceSector','serviceSectorOther'];
 elsif p_module='reservations' and p_permission='reservations.people.manage' then
  v_allowed:=array['fullName','phone','church','gender','dateOfBirth','governorate','cityOrVillage','serviceSector','serviceSectorOther'];
 else raise exception 'PERSON_UPDATE_MODULE_INVALID' using errcode='42501';end if;
 if p_actor is null or p_person_id is null or p_expected_revision is null or p_expected_revision<1 or p_patch is null or jsonb_typeof(p_patch)<>'object' or not (p_patch ? 'fullName') then raise exception 'PERSON_UPDATE_ARGUMENT_INVALID' using errcode='22023';end if;
 if exists(select 1 from jsonb_object_keys(p_patch) k where not k=any(v_allowed)) then raise exception 'PERSON_UPDATE_ARGUMENT_UNKNOWN' using errcode='22023';end if;
 if length(btrim(coalesce(p_patch->>'fullName','')))=0 or length(btrim(p_patch->>'fullName'))>240
   or p_patch ? 'gender' and nullif(p_patch->>'gender','') is not null and p_patch->>'gender' not in('male','female')
   or p_patch ? 'dateOfBirth' and nullif(p_patch->>'dateOfBirth','') is not null and (p_patch->>'dateOfBirth')::date>current_date
   or p_patch ? 'serviceSector' and length(btrim(coalesce(p_patch->>'serviceSector','')))>120
   or p_patch ? 'serviceSectorOther' and length(btrim(coalesce(p_patch->>'serviceSectorOther','')))>240 then raise exception 'PERSON_UPDATE_ARGUMENT_INVALID' using errcode='22023';end if;
 v_authorization:=platform_private.validated_phase1c_device_authorization(p_actor,p_device_id);
 if v_authorization is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
 if p_module='conference' then
  if nullif(p_metadata->>'conferenceId','') is null then raise exception 'CONFERENCE_PERSON_SCOPE_REQUIRED' using errcode='42501';end if;
  perform platform_private.require_conference_participation_context(p_device_id,(p_metadata->>'conferenceId')::uuid,'conference.people.manage',true);
  if not exists(select 1 from public.conference_participations where conference_id=(p_metadata->>'conferenceId')::uuid and person_id=p_person_id) then raise exception 'CONFERENCE_PERSON_NOT_PARTICIPATING' using errcode='42501';end if;
 else perform public.require_effective_module_permission(p_device_id,p_module,p_permission,null,null);end if;
 update platform.people set
  full_name=btrim(p_patch->>'fullName'),
  phone=case when p_patch ? 'phone' then nullif(btrim(coalesce(p_patch->>'phone','')),'') else phone end,
  church=case when p_patch ? 'church' then nullif(btrim(coalesce(p_patch->>'church','')),'') else church end,
  gender=case when p_patch ? 'gender' then nullif(p_patch->>'gender','') else gender end,
  date_of_birth=case when p_patch ? 'dateOfBirth' then nullif(p_patch->>'dateOfBirth','')::date else date_of_birth end,
  governorate=case when p_patch ? 'governorate' then nullif(btrim(coalesce(p_patch->>'governorate','')),'') else governorate end,
  city_or_village=case when p_patch ? 'cityOrVillage' then nullif(btrim(coalesce(p_patch->>'cityOrVillage','')),'') else city_or_village end,
  service_sector=case when p_patch ? 'serviceSector' then nullif(btrim(coalesce(p_patch->>'serviceSector','')),'') else service_sector end,
  service_sector_other=case when p_patch ? 'serviceSectorOther' then nullif(btrim(coalesce(p_patch->>'serviceSectorOther','')),'') else service_sector_other end,
  revision=revision+1,updated_at=statement_timestamp(),updated_by=p_actor
 where id=p_person_id and revision=p_expected_revision returning * into v_person;
 if not found then raise exception 'PERSON_REVISION_CONFLICT' using errcode='40001';end if;
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,new_values,metadata,operation_id,source)
 values(p_actor,v_authorization,'platform',p_module,'platform.person.updated','person',p_person_id,'platform',
  jsonb_build_object('id',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,'church',v_person.church,'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'governorate',v_person.governorate,'cityOrVillage',v_person.city_or_village,'serviceSector',v_person.service_sector,'serviceSectorOther',v_person.service_sector_other),
  coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('expectedRevision',p_expected_revision,'permissionKey',p_permission),p_operation_id,'rpc');
 return jsonb_build_object('personId',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,'church',v_person.church,'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'governorate',v_person.governorate,'cityOrVillage',v_person.city_or_village,'serviceSector',v_person.service_sector,'serviceSectorOther',v_person.service_sector_other,'revision',v_person.revision);
end $function$;

revoke all on function platform_private.update_canonical_person(uuid,uuid,uuid,bigint,jsonb,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function platform_private.update_canonical_person(uuid,uuid,uuid,bigint,jsonb,uuid,text,text,jsonb) to service_role;

do $migration$
declare d text; old_text text; new_text text;
begin
 d:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 old_text:='insert into platform.people(full_name,phone,church,gender,date_of_birth,created_by,updated_by) values(btrim(p_args->>''p_full_name''),nullif(btrim(coalesce(p_args->>''p_phone'','''')),''''),nullif(btrim(coalesce(p_args->>''p_church'','''')),''''),nullif(p_args->>''p_gender'',''''),nullif(p_args->>''p_date_of_birth'','''')::date,v_actor,v_actor)';
 new_text:='insert into platform.people(full_name,phone,church,gender,date_of_birth,governorate,city_or_village,service_sector,service_sector_other,created_by,updated_by) values(btrim(p_args->>''p_full_name''),nullif(btrim(coalesce(p_args->>''p_phone'','''')),''''),nullif(btrim(coalesce(p_args->>''p_church'','''')),''''),nullif(p_args->>''p_gender'',''''),nullif(p_args->>''p_date_of_birth'','''')::date,nullif(btrim(coalesce(p_args->>''p_governorate'','''')),''''),nullif(btrim(coalesce(p_args->>''p_city_or_village'','''')),''''),nullif(btrim(coalesce(p_args->>''p_service_sector'','''')),''''),nullif(btrim(coalesce(p_args->>''p_service_sector_other'','''')),''''),v_actor,v_actor)';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_NEW_PERSON_CONTRACT_DRIFT';end if; d:=replace(d,old_text,new_text);
 old_text:='jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'') || case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end || case when p_args ? ''p_date_of_birth'' then jsonb_build_object(''dateOfBirth'',p_args->>''p_date_of_birth'') else ''{}''::jsonb end';
 new_text:='jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'',''governorate'',p_args->>''p_governorate'',''cityOrVillage'',p_args->>''p_city_or_village'',''serviceSector'',p_args->>''p_service_sector'',''serviceSectorOther'',p_args->>''p_service_sector_other'') || case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end || case when p_args ? ''p_date_of_birth'' then jsonb_build_object(''dateOfBirth'',p_args->>''p_date_of_birth'') else ''{}''::jsonb end';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_CREATE_UPDATE_CONTRACT_DRIFT';end if; d:=replace(d,old_text,new_text);
 old_text:='array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender''])';
 new_text:='array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender'',''p_date_of_birth'',''p_person_update_revision''])';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_UPDATE_KEYS_CONTRACT_DRIFT';end if; d:=replace(d,old_text,new_text);
 old_text:='if p_args ? ''p_gender'' and nullif(p_args->>''p_gender'','''') is not null and (select gender from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)) is distinct from (p_args->>''p_gender'') then perform public.require_effective_module_permission(p_device_id,''reservations'',''reservations.people.manage'',null,null); perform platform_private.update_canonical_person(p_device_id,v_actor,(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id),(select revision from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)),jsonb_build_object(''fullName'',(select full_name from platform.people where id=(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id)),''gender'',p_args->>''p_gender''),v_operation_id,''reservations'',''reservations.people.manage'',jsonb_build_object(''eventId'',v_booking.event_id)); end if;';
 new_text:='if p_args ? ''p_person_update_revision'' then if (p_args->>''p_person_update_revision'') is null or (p_args->>''p_person_update_revision'') !~ ''^[0-9]+$'' then raise exception ''PERSON_REVISION_REQUIRED'' using errcode=''22023''; end if; perform platform_private.update_canonical_person(p_device_id,v_actor,(select person_id from reservations.participants where id=v_booking.participant_id and scope_partition_id=v_booking.scope_partition_id),(p_args->>''p_person_update_revision'')::bigint,jsonb_build_object(''fullName'',p_args->>''p_full_name'',''phone'',p_args->>''p_phone'',''church'',p_args->>''p_church'',''governorate'',p_args->>''p_governorate'',''cityOrVillage'',p_args->>''p_city_or_village'',''serviceSector'',p_args->>''p_service_sector'',''serviceSectorOther'',p_args->>''p_service_sector_other'') || case when p_args ? ''p_gender'' then jsonb_build_object(''gender'',p_args->>''p_gender'') else ''{}''::jsonb end || case when p_args ? ''p_date_of_birth'' then jsonb_build_object(''dateOfBirth'',p_args->>''p_date_of_birth'') else ''{}''::jsonb end,v_operation_id,''reservations'',''reservations.people.manage'',jsonb_build_object(''eventId'',v_booking.event_id)); end if;';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_UPDATE_PERSON_CONTRACT_DRIFT';end if; d:=replace(d,old_text,new_text);
 execute d;

 d:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
 old_text:='array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender''])';
 new_text:='array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_booking_type_id'',''p_full_name'',''p_phone'',''p_age'',''p_church'',''p_governorate'',''p_city_or_village'',''p_service_sector'',''p_service_sector_other'',''p_notes''],array[''p_gender'',''p_date_of_birth'',''p_person_update_revision''])';
 if position(old_text in d)=0 then raise exception 'DEVICE_DISPATCH_UPDATE_KEYS_CONTRACT_DRIFT';end if; execute replace(d,old_text,new_text);
end $migration$;

revoke all on function reservations_private.mutate_scoped(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb) from public,anon,authenticated;
