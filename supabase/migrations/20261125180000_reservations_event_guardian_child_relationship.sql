begin;

create table reservations.event_guardian_children (
  id uuid primary key default extensions.gen_random_uuid(),
  scope_partition_id uuid not null,
  event_id uuid not null,
  guardian_person_id uuid not null references platform.people(id) on delete restrict,
  child_person_id uuid not null references platform.people(id) on delete restrict,
  child_role text not null check (child_role in ('child_paid','child_dependent')),
  child_booking_id uuid,
  request_member_id uuid not null references reservations.public_registration_request_members(id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  created_by uuid not null references platform.profiles(user_id),
  constraint event_guardian_children_event_fk foreign key(scope_partition_id,event_id)
    references reservations.events(scope_partition_id,id) on delete restrict,
  constraint event_guardian_children_booking_fk foreign key(scope_partition_id,child_booking_id)
    references reservations.bookings(scope_partition_id,id) on delete restrict,
  constraint event_guardian_children_people_distinct check(guardian_person_id<>child_person_id),
  constraint event_guardian_children_role_booking_check check(
    (child_role='child_paid' and child_booking_id is not null)
    or(child_role='child_dependent' and child_booking_id is null)
  ),
  unique(event_id,child_person_id),
  unique(request_member_id)
);
create index event_guardian_children_guardian_idx
  on reservations.event_guardian_children(event_id,guardian_person_id,child_person_id);
alter table reservations.event_guardian_children enable row level security;
alter table reservations.event_guardian_children force row level security;
revoke all on reservations.event_guardian_children from public,anon,authenticated,service_role;

create or replace function platform_private.create_reservations_dependent_person(
  p_device_id uuid,p_actor uuid,p_operation_id uuid,p_event_id uuid,p_profile jsonb
) returns uuid language plpgsql volatile security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_person_id uuid;v_authorization uuid;
begin
 perform platform_private.require_exact_jsonb_keys(p_profile,
  array['fullName','phone','gender','dateOfBirth','church','governorate','cityOrVillage','serviceSector'],
  array['serviceSectorOther']);
 select * into v_event from reservations.events where id=p_event_id for key share;
 if not found or nullif(btrim(p_profile->>'fullName'),'') is null or p_profile->>'gender'<>'child'
   or nullif(p_profile->>'dateOfBirth','') is null
   or (p_profile->>'dateOfBirth')::date>v_event.start_date then
  raise exception 'PUBLIC_REGISTRATION_DEPENDENT_IDENTITY_INVALID' using errcode='22023';
 end if;
 select id into v_authorization from platform.user_device_authorizations
  where device_id=p_device_id and user_id=p_actor and status='approved' and revoked_at is null limit 1;
 if v_authorization is null then raise exception 'PLATFORM_DEVICE_NOT_APPROVED' using errcode='42501';end if;
 insert into platform.people(full_name,phone,gender,date_of_birth,church,governorate,city_or_village,
  service_sector,service_sector_other,created_by,updated_by)
 values(btrim(p_profile->>'fullName'),nullif(btrim(p_profile->>'phone'),''),'child',
  (p_profile->>'dateOfBirth')::date,nullif(btrim(p_profile->>'church'),''),
  nullif(btrim(p_profile->>'governorate'),''),nullif(btrim(p_profile->>'cityOrVillage'),''),
  nullif(btrim(p_profile->>'serviceSector'),''),nullif(btrim(p_profile->>'serviceSectorOther'),''),p_actor,p_actor)
 returning id into v_person_id;
 insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,
  entity_type,entity_id,scope_type,new_values,metadata,operation_id,source)
 values(p_actor,v_authorization,'platform','reservations','platform.person.created','person',v_person_id,
  'platform',jsonb_build_object('id',v_person_id,'fullName',btrim(p_profile->>'fullName'),
  'gender','child','dateOfBirth',p_profile->>'dateOfBirth'),
  jsonb_build_object('eventId',p_event_id,'permissionKey','reservations.booking.create',
  'purpose','dependent-child'),p_operation_id,'rpc');
 return v_person_id;
end $$;
revoke all on function platform_private.create_reservations_dependent_person(uuid,uuid,uuid,uuid,jsonb)
 from public,anon,authenticated,service_role;

create or replace function reservations_private.capture_public_registration_guardian_child()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_event reservations.events%rowtype;v_guardian uuid;v_actor uuid;v_existing reservations.event_guardian_children%rowtype;
begin
 if new.role not in('child_paid','child_dependent') or new.resolved_person_id is null then return new;end if;
 select e.* into v_event from reservations.public_registration_requests r
  join reservations.events e on e.id=r.event_id where r.id=new.request_id for key share;
 select resolved_person_id into v_guardian from reservations.public_registration_request_members
  where request_id=new.request_id and member_key=new.guardian_member_key;
 if v_guardian is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;
 if new.role='child_paid' and (new.booking_id is null or not exists(
  select 1 from reservations.bookings b join reservations.participants p
   on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id
  where b.id=new.booking_id and b.event_id=v_event.id and b.scope_partition_id=v_event.scope_partition_id
   and p.person_id=new.resolved_person_id)) then
  raise exception 'PUBLIC_REGISTRATION_CHILD_BOOKING_INVALID' using errcode='22023';
 end if;
 select r.decided_by into v_actor from reservations.public_registration_requests r where r.id=new.request_id;
 insert into reservations.event_guardian_children(scope_partition_id,event_id,guardian_person_id,
  child_person_id,child_role,child_booking_id,request_member_id,created_by)
 values(v_event.scope_partition_id,v_event.id,v_guardian,new.resolved_person_id,new.role,new.booking_id,new.id,v_actor)
 on conflict(event_id,child_person_id) do nothing;
 select * into v_existing from reservations.event_guardian_children
  where event_id=v_event.id and child_person_id=new.resolved_person_id;
 if v_existing.guardian_person_id is distinct from v_guardian or v_existing.child_role<>new.role
   or v_existing.request_member_id<>new.id then
  raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';
 end if;
 return new;
end $$;
revoke all on function reservations_private.capture_public_registration_guardian_child()
 from public,anon,authenticated,service_role;
create trigger public_registration_guardian_child_capture
after update of resolved_person_id,booking_id on reservations.public_registration_request_members
for each row when(new.resolved_person_id is not null and new.role in('child_paid','child_dependent'))
execute function reservations_private.capture_public_registration_guardian_child();

do $patch$
declare d text;old_text text:=
$$if choice='new' then insert into platform.people(full_name,phone,gender,date_of_birth,church,governorate,city_or_village,service_sector,service_sector_other,created_by,updated_by)values(m.full_name,nullif(m.phone,''),'child',m.date_of_birth,nullif(m.church,''),nullif(m.governorate,''),nullif(m.city_or_village,''),nullif(m.service_sector,''),m.service_sector_other,actor,actor)returning id into pid;end if;$$;
new_text text:=
$$if choice='new' then pid:=platform_private.create_reservations_dependent_person(p_device_id,actor,p_operation_id,r.event_id,jsonb_build_object('fullName',m.full_name,'phone',m.phone,'gender','child','dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other));end if;$$;
begin
 d:=pg_get_functiondef('reservations_private.decide_public_registration_family_request(uuid,uuid,uuid,bigint,text,jsonb,text)'::regprocedure);
 if (length(d)-length(replace(d,old_text,'')))/length(old_text)<>1 then
  raise exception 'PUBLIC_REGISTRATION_DEPENDENT_PERSON_WRITER_DRIFT';
 end if;
 execute replace(d,old_text,new_text);
end $patch$;

commit;
