CREATE OR REPLACE FUNCTION reservations_private.public_registration_identity_candidates(p_event_id uuid, p_full_name text, p_phone text, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with candidates as (select c.value candidate,c.ordinality ord from jsonb_array_elements(platform_private.reservations_person_identity_candidates(p_full_name,p_phone,p_limit)) with ordinality c(value,ordinality))
select coalesce(jsonb_agg(candidate||jsonb_build_object('hasEventBooking',exists(select 1 from reservations.events e join reservations.bookings b on b.event_id=e.id and b.scope_partition_id=e.scope_partition_id join reservations.participants rp on rp.id=b.participant_id and rp.scope_partition_id=b.scope_partition_id where e.id=p_event_id and rp.person_id=(candidate->>'personId')::uuid and b.lifecycle_status='active')) order by ord),'[]'::jsonb) from candidates
$function$
;

CREATE OR REPLACE FUNCTION reservations_private.get_public_registration_request(p_device_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype; v_context jsonb; v_type reservations.booking_types%rowtype;
begin
 select * into r from reservations.public_registration_requests where id=p_request_id;
 if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');
 select * into v_type from reservations.booking_types where id=r.booking_type_id and event_id=r.event_id;


 return jsonb_build_object(
  'request',jsonb_build_object(
   'requestId',r.id,'reference',r.request_reference,'state',r.state,'revision',r.revision,
   'eventId',r.event_id,'bookingTypeId',r.booking_type_id,'bookingTypeName',v_type.name,
   'currentBookingTypeActive',v_type.active,'currentPrice',v_type.price,
   'fullName',r.submitted_full_name,'phone',r.submitted_phone,'gender',r.submitted_gender,
   'dateOfBirth',r.submitted_date_of_birth,'church',r.submitted_church,'governorate',r.submitted_governorate,
   'cityOrVillage',r.submitted_city_or_village,'serviceSector',r.submitted_service_sector,
   'serviceSectorOther',r.submitted_service_sector_other,'notes',r.submitted_notes,
   'submittedAt',r.submitted_at,'updatedAt',r.updated_at
  )
 );
end $function$
;

CREATE OR REPLACE FUNCTION reservations_private.get_public_registration_family_request(p_device_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare base jsonb;r reservations.public_registration_requests%rowtype;items jsonb;begin base:=reservations_private.get_public_registration_request(p_device_id,p_request_id);select * into r from reservations.public_registration_requests where id=p_request_id;
select coalesce(jsonb_agg(jsonb_build_object('member',jsonb_strip_nulls(jsonb_build_object('memberKey',m.member_key,'ordinal',m.ordinal,'role',m.role,'guardianMemberKey',m.guardian_member_key,'bookingTypeId',m.booking_type_id,'bookingTypeName',bt.name,'currentPrice',bt.price,'fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other,'notes',m.notes,'resolvedPersonId',m.resolved_person_id,'bookingId',m.booking_id)),'identityCandidates',reservations_private.public_registration_identity_candidates(r.event_id,m.full_name,m.phone,10))order by m.ordinal),'[]'::jsonb)into items from reservations.public_registration_request_members m left join reservations.booking_types bt on bt.id=m.booking_type_id and bt.event_id=r.event_id where m.request_id=r.id;return base||jsonb_build_object('members',items);end $function$
;

CREATE OR REPLACE FUNCTION reservations_private.decide_public_registration_family_request(p_device_id uuid, p_operation_id uuid, p_request_id uuid, p_expected_revision bigint, p_decision text, p_resolutions jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;e reservations.events%rowtype;ctx jsonb;actor uuid;pm reservations.public_registration_request_members%rowtype;m reservations.public_registration_request_members%rowtype;res jsonb;choice text;pid uuid;br jsonb;bid uuid;age int;args jsonb;gp uuid;gpart uuid;cpart uuid;result jsonb;
begin select * into r from reservations.public_registration_requests where id=p_request_id for update;if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002';end if;ctx:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');actor:=(ctx->>'actorUserId')::uuid;
if p_decision in('reject','waitlist')then return reservations_private.decide_public_registration_request(p_device_id,p_operation_id,p_request_id,p_expected_revision,p_decision,null,p_reason);end if;if p_decision<>'approve' or jsonb_typeof(p_resolutions)<>'object' then raise exception 'PUBLIC_REGISTRATION_FAMILY_DECISION_INVALID' using errcode='22023';end if;
select * into e from reservations.events where id=r.event_id and scope_partition_id=(ctx->>'scopePartitionId')::uuid;select * into pm from reservations.public_registration_request_members where request_id=r.id and ordinal=0;res:=p_resolutions->pm.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;if choice is null or choice not in('existing','new') or (choice='existing' and pid is null) or (choice='new' and pid is not null) then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
result:=reservations_private.decide_public_registration_request(p_device_id,p_operation_id,p_request_id,p_expected_revision,case when choice='existing' then 'approve_existing' else 'approve_new' end,pid,p_reason);select resolved_person_id,booking_id into pid,bid from reservations.public_registration_requests where id=r.id;update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=bid where request_id=r.id and ordinal=0;
for m in select * from reservations.public_registration_request_members where request_id=r.id and ordinal>0 order by ordinal for update loop
 if m.resolved_person_id is not null then continue;end if;res:=p_resolutions->m.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;if choice is null or choice not in('existing','new') or (choice='existing' and pid is null) or (choice='new' and pid is not null) then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
 if choice='existing' and not exists(select 1 from jsonb_array_elements(platform_private.reservations_person_identity_candidates(m.full_name,m.phone,10))c where c->>'personId'=pid::text)then raise exception 'PUBLIC_REGISTRATION_PERSON_CANDIDATE_STALE' using errcode='40001';end if;
 if m.role<>'child_dependent' then
  if m.date_of_birth is null or m.date_of_birth>e.start_date then raise exception 'PUBLIC_REGISTRATION_DATE_OF_BIRTH_INVALID' using errcode='22023';end if;age:=extract(year from pg_catalog.age(e.start_date,m.date_of_birth))::int;args:=reservations_private.public_registration_booking_args(extensions.gen_random_uuid(),r.event_id,m.booking_type_id,m.full_name,m.phone,age,m.church,m.governorate,m.city_or_village,m.service_sector,m.service_sector_other,m.notes,m.gender,m.date_of_birth,case when choice='existing' then pid else null end);br:=reservations.mutate(p_device_id,'create_booking',args);if choice='new' and coalesce((br->>'identityResolutionRequired')::boolean,false)then br:=reservations.mutate(p_device_id,'create_booking',args||jsonb_build_object('p_identity_resolution_token',br->>'identityResolutionToken','p_identity_resolution_decision','different'));end if;bid:=nullif(br->>'bookingId','')::uuid;if bid is null then raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001';end if;select p.person_id into pid from reservations.bookings b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id where b.id=bid;update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=bid where id=m.id;if m.role='child_paid' then select gm.resolved_person_id into gp from reservations.public_registration_request_members gm where gm.request_id=r.id and gm.member_key=m.guardian_member_key;if gp is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;if e.conference_id is not null then select cp.id into gpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=gp and cp.status='active';if gpart is null then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by)values(e.conference_id,gp,'active',actor,actor)returning id into gpart;end if;select cp.id into cpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=pid;if cpart is null then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by)values(e.conference_id,pid,gpart,'active',actor,actor)returning id into cpart;elsif exists(select 1 from public.conference_participations where id=cpart and guardian_participation_id is distinct from gpart)then raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';end if;end if;end if;
 else
  if choice='new' then pid:=platform_private.create_reservations_dependent_person(p_device_id,actor,p_operation_id,r.event_id,jsonb_build_object('fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other));end if;select gm.resolved_person_id into gp from reservations.public_registration_request_members gm where gm.request_id=r.id and gm.member_key=m.guardian_member_key;if gp is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;if e.conference_id is not null then select cp.id into gpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=gp and cp.status='active';if gpart is null then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by)values(e.conference_id,gp,'active',actor,actor)returning id into gpart;end if;select cp.id into cpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=pid;if cpart is null then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by)values(e.conference_id,pid,gpart,'active',actor,actor)returning id into cpart;elsif exists(select 1 from public.conference_participations where id=cpart and guardian_participation_id is distinct from gpart)then raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';end if;end if;update reservations.public_registration_request_members set resolved_person_id=pid where id=m.id;
 end if;
end loop;result:=result||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id));update reservations.public_registration_requests set decision_result=result where id=r.id;return result;end $function$
;
revoke all on function reservations_private.public_registration_identity_candidates(uuid,text,text,integer) from public,anon,authenticated;
