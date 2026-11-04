-- Keep reservation-time demographics in the reservation snapshot while
-- platform.people remains the only source of the person's current profile.

alter table reservations.participants
  add column if not exists gender_snapshot text,
  add column if not exists date_of_birth_snapshot date;

alter table reservations.participants
  drop constraint if exists participants_gender_snapshot_check;
alter table reservations.participants
  add constraint participants_gender_snapshot_check
  check (gender_snapshot is null or gender_snapshot in ('male','female'));

-- This is an initial snapshot only. Never derive a birth date from a historical age.
update reservations.participants participant
set gender_snapshot=person.gender,
    date_of_birth_snapshot=person.date_of_birth
from platform.people person
where person.id=participant.person_id
  and (participant.gender_snapshot is null or participant.date_of_birth_snapshot is null);

drop view if exists reservations.participants_canonical;
create view reservations.participants_canonical
with (security_invoker=true) as
select participant.*,
  participant.gender_snapshot gender,
  participant.date_of_birth_snapshot date_of_birth,
  case when exists(
    select 1 from public.conference_participations participation
    join reservations.events event on event.conference_id=participation.conference_id
      and event.scope_partition_id=participant.scope_partition_id
    where participation.person_id=participant.person_id
      and participation.guardian_participation_id is not null
  ) then 'child' else 'adult' end operational_category,
  person.revision person_revision,
  person.id canonical_person_id,
  person.full_name canonical_full_name,
  person.phone canonical_phone,
  person.gender canonical_gender,
  person.date_of_birth canonical_date_of_birth,
  person.church canonical_church,
  person.governorate canonical_governorate,
  person.city_or_village canonical_city_or_village,
  person.service_sector canonical_service_sector,
  person.service_sector_other canonical_service_sector_other
from reservations.participants participant
left join platform.people person on person.id=participant.person_id;

revoke all on reservations.participants_canonical from public,anon,authenticated,service_role;

do $migration$
declare d text; old_text text; new_text text;
begin
 d:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);

 old_text:='insert into reservations.participants(scope_partition_id,person_id,full_name,phone,age,church,governorate,city_or_village,service_sector,service_sector_other,notes,created_by,updated_by) values(v_event.scope_partition_id,v_person_id,btrim(p_args->>''p_full_name''),btrim(p_args->>''p_phone''),(p_args->>''p_age'')::integer,coalesce(p_args->>''p_church'',''''),btrim(p_args->>''p_governorate''),coalesce(p_args->>''p_city_or_village'',''''),p_args->>''p_service_sector'',nullif(btrim(p_args->>''p_service_sector_other''),''''),nullif(p_args->>''p_notes'',''''),v_actor,v_actor)';
 new_text:='insert into reservations.participants(scope_partition_id,person_id,full_name,phone,age,church,governorate,city_or_village,service_sector,service_sector_other,gender_snapshot,date_of_birth_snapshot,notes,created_by,updated_by) values(v_event.scope_partition_id,v_person_id,btrim(p_args->>''p_full_name''),btrim(p_args->>''p_phone''),(p_args->>''p_age'')::integer,coalesce(p_args->>''p_church'',''''),btrim(p_args->>''p_governorate''),coalesce(p_args->>''p_city_or_village'',''''),p_args->>''p_service_sector'',nullif(btrim(p_args->>''p_service_sector_other''),''''),nullif(p_args->>''p_gender'',''''),nullif(p_args->>''p_date_of_birth'','''')::date,nullif(p_args->>''p_notes'',''''),v_actor,v_actor)';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_CREATE_SNAPSHOT_CONTRACT_DRIFT';end if;
 d:=replace(d,old_text,new_text);

 old_text:='service_sector_other=nullif(btrim(p_args->>''p_service_sector_other''),''''),notes=nullif(p_args->>''p_notes'',''''),revision=revision+1';
 new_text:='service_sector_other=nullif(btrim(p_args->>''p_service_sector_other''),''''),gender_snapshot=case when p_args ? ''p_gender'' then nullif(p_args->>''p_gender'','''') else gender_snapshot end,date_of_birth_snapshot=case when p_args ? ''p_date_of_birth'' then nullif(p_args->>''p_date_of_birth'','''')::date else date_of_birth_snapshot end,notes=nullif(p_args->>''p_notes'',''''),revision=revision+1';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_UPDATE_SNAPSHOT_CONTRACT_DRIFT';end if;
 d:=replace(d,old_text,new_text);

 -- Changing a booking type must not silently rewrite the contracted historical price.
 old_text:='booking_type_id=v_type.id,booking_type_name_snapshot=v_type.name,price_snapshot=v_type.price,notes=';
 new_text:='booking_type_id=v_type.id,booking_type_name_snapshot=v_type.name,notes=';
 if position(old_text in d)=0 then raise exception 'MUTATE_SCOPED_PRICE_SNAPSHOT_CONTRACT_DRIFT';end if;
 d:=replace(d,old_text,new_text);

 execute d;
end $migration$;

revoke all on function reservations_private.mutate_scoped(uuid,text,jsonb) from public,anon,authenticated;
;
