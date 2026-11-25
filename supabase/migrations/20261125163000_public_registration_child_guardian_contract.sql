begin;
alter table reservations.public_registration_request_members drop constraint if exists public_registration_request_members_check;
alter table reservations.public_registration_request_members drop constraint if exists public_registration_request_members_booking_guardian_check;
alter table reservations.public_registration_request_members add constraint public_registration_request_members_booking_guardian_check check(
 (role in('primary','adult') and guardian_member_key is null and booking_type_id is not null)
 or(role='child_paid' and guardian_member_key is not null and booking_type_id is not null)
 or(role='child_dependent' and guardian_member_key is not null and booking_type_id is null)
);
CREATE OR REPLACE FUNCTION reservations.public_registration_submit_family(p_public_id uuid, p_submit_operation_id uuid, p_tracking_secret_digest bytea, p_fingerprint_digest bytea, p_members jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_channel reservations.public_registration_channels%rowtype;v_event reservations.events%rowtype;v_existing reservations.public_registration_requests%rowtype;
 v_request_id uuid:=extensions.gen_random_uuid();v_reference text;v_intent bytea;v_primary jsonb;v_member jsonb;v_key uuid;v_guardian uuid;v_role text;v_type uuid;v_count int;v_ordinal int:=0;
begin
 if p_submit_operation_id is null or p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 or jsonb_typeof(p_members)<>'array' then raise exception 'PUBLIC_REGISTRATION_SUBMISSION_INVALID' using errcode='22023';end if;
 v_count:=jsonb_array_length(p_members);if v_count<1 or v_count>12 then raise exception 'PUBLIC_REGISTRATION_FAMILY_SIZE_INVALID' using errcode='22023';end if;
 v_primary:=p_members->0;if coalesce(v_primary->>'role','')<>'primary' then raise exception 'PUBLIC_REGISTRATION_PRIMARY_REQUIRED' using errcode='22023';end if;
 select * into v_channel from reservations.public_registration_channels where public_id=p_public_id for key share;
 if not found or not v_channel.enabled then raise exception 'PUBLIC_REGISTRATION_UNAVAILABLE' using errcode='P0002';end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,8);
 if v_channel.registration_mode<>'approval_required' or (v_channel.opens_at is not null and statement_timestamp()<v_channel.opens_at) or (v_channel.closes_at is not null and statement_timestamp()>=v_channel.closes_at) then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;
 select * into v_event from reservations.events where id=v_channel.event_id for key share;if not found or v_event.status<>'open' then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;
 v_intent:=extensions.digest(convert_to(p_members::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-submit:'||v_channel.id::text||':'||p_submit_operation_id::text,0));
 select * into v_existing from reservations.public_registration_requests where channel_id=v_channel.id and submit_operation_id=p_submit_operation_id;
 if found then if v_existing.submit_intent_digest<>v_intent or v_existing.tracking_secret_digest<>p_tracking_secret_digest then raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001';end if;return jsonb_build_object('reference',v_existing.request_reference,'state',v_existing.state,'submittedAt',v_existing.submitted_at);end if;
 for v_member in select value from jsonb_array_elements(p_members) loop
   if (select array_agg(k order by k) from jsonb_object_keys(v_member) k)<>array['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther']::text[] then raise exception 'PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID' using errcode='22023';end if;
   v_key:=(v_member->>'memberKey')::uuid;v_role:=v_member->>'role';v_guardian:=nullif(v_member->>'guardianMemberKey','')::uuid;v_type:=nullif(v_member->>'bookingTypeId','')::uuid;
   if v_role not in('primary','adult','child_paid','child_dependent') or (v_ordinal=0 and v_role<>'primary') or (v_ordinal>0 and v_role='primary') then raise exception 'PUBLIC_REGISTRATION_MEMBER_ROLE_INVALID' using errcode='22023';end if;
   if nullif(btrim(v_member->>'fullName'),'') is null or nullif(v_member->>'dateOfBirth','') is null then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;
   if v_role in('child_paid','child_dependent') then
     if v_guardian is null or (v_member->>'gender')<>'child' then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;
     if not exists(select 1 from jsonb_array_elements(p_members) with ordinality as g(value,ord) where (g.value->>'memberKey')::uuid=v_guardian and g.value->>'role' in('primary','adult') and g.ord<=v_ordinal) then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;
     if v_role='child_dependent' then
       if v_type is not null then raise exception 'PUBLIC_REGISTRATION_DEPENDENT_INVALID' using errcode='22023';end if;
     elsif v_type is null or not exists(select 1 from reservations.booking_types bt where bt.id=v_type and bt.event_id=v_event.id and bt.active) then
       raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';
     end if;
   else
     if v_guardian is not null or v_type is null or not exists(select 1 from reservations.booking_types bt where bt.id=v_type and bt.event_id=v_event.id and bt.active) then raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';end if;
   end if;
   v_ordinal:=v_ordinal+1;
 end loop;
 v_reference:='PR-'||upper(substr(replace(v_request_id::text,'-',''),1,12));
 insert into reservations.public_registration_requests(id,channel_id,event_id,submit_operation_id,submit_intent_digest,request_reference,tracking_secret_digest,booking_type_id,submitted_full_name,submitted_phone,submitted_gender,submitted_date_of_birth,submitted_church,submitted_governorate,submitted_city_or_village,submitted_service_sector,submitted_service_sector_other,submitted_notes)
 values(v_request_id,v_channel.id,v_event.id,p_submit_operation_id,v_intent,v_reference,p_tracking_secret_digest,(v_primary->>'bookingTypeId')::uuid,btrim(v_primary->>'fullName'),btrim(v_primary->>'phone'),v_primary->>'gender',(v_primary->>'dateOfBirth')::date,coalesce(v_primary->>'church',''),coalesce(v_primary->>'governorate',''),coalesce(v_primary->>'cityOrVillage',''),coalesce(v_primary->>'serviceSector',''),nullif(v_primary->>'serviceSectorOther',''),nullif(v_primary->>'notes',''));
 v_ordinal:=0;
 for v_member in select value from jsonb_array_elements(p_members) loop
   insert into reservations.public_registration_request_members(request_id,member_key,ordinal,role,guardian_member_key,booking_type_id,full_name,phone,gender,date_of_birth,church,governorate,city_or_village,service_sector,service_sector_other,notes)
   values(v_request_id,(v_member->>'memberKey')::uuid,v_ordinal,v_member->>'role',nullif(v_member->>'guardianMemberKey','')::uuid,nullif(v_member->>'bookingTypeId','')::uuid,btrim(v_member->>'fullName'),btrim(coalesce(v_member->>'phone','')),v_member->>'gender',(v_member->>'dateOfBirth')::date,coalesce(v_member->>'church',''),coalesce(v_member->>'governorate',''),coalesce(v_member->>'cityOrVillage',''),coalesce(v_member->>'serviceSector',''),nullif(v_member->>'serviceSectorOther',''),nullif(v_member->>'notes',''));v_ordinal:=v_ordinal+1;
 end loop;
 return jsonb_build_object('reference',v_reference,'state','submitted','submittedAt',statement_timestamp(),'memberCount',v_count);
end $function$
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
select * into e from reservations.events where id=r.event_id and scope_partition_id=(ctx->>'scopePartitionId')::uuid;select * into pm from reservations.public_registration_request_members where request_id=r.id and ordinal=0;res:=p_resolutions->pm.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;if choice not in('existing','new')or(choice='existing' and pid is null)or(choice='new' and pid is not null)then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
result:=reservations_private.decide_public_registration_request(p_device_id,p_operation_id,p_request_id,p_expected_revision,case when choice='existing' then 'approve_existing' else 'approve_new' end,pid,p_reason);select resolved_person_id,booking_id into pid,bid from reservations.public_registration_requests where id=r.id;update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=bid where request_id=r.id and ordinal=0;
for m in select * from reservations.public_registration_request_members where request_id=r.id and ordinal>0 order by ordinal for update loop
 if m.resolved_person_id is not null then continue;end if;res:=p_resolutions->m.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;if choice not in('existing','new')or(choice='existing' and pid is null)or(choice='new' and pid is not null)then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
 if choice='existing' and not exists(select 1 from jsonb_array_elements(platform_private.reservations_person_identity_candidates(m.full_name,m.phone,10))c where c->>'personId'=pid::text)then raise exception 'PUBLIC_REGISTRATION_PERSON_CANDIDATE_STALE' using errcode='40001';end if;
 if m.role<>'child_dependent' then
  if m.date_of_birth is null or m.date_of_birth>e.start_date then raise exception 'PUBLIC_REGISTRATION_DATE_OF_BIRTH_INVALID' using errcode='22023';end if;age:=extract(year from pg_catalog.age(e.start_date,m.date_of_birth))::int;args:=jsonb_strip_nulls(jsonb_build_object('p_operation_id',extensions.gen_random_uuid(),'p_event_id',r.event_id,'p_booking_type_id',m.booking_type_id,'p_full_name',m.full_name,'p_phone',m.phone,'p_age',age,'p_church',m.church,'p_governorate',m.governorate,'p_city_or_village',m.city_or_village,'p_service_sector',m.service_sector,'p_service_sector_other',m.service_sector_other,'p_notes',m.notes,'p_gender',m.gender,'p_date_of_birth',m.date_of_birth,'p_person_id',case when choice='existing' then pid else null end));br:=reservations.mutate(p_device_id,'create_booking',args);if choice='new' and coalesce((br->>'identityResolutionRequired')::boolean,false)then br:=reservations.mutate(p_device_id,'create_booking',args||jsonb_build_object('p_identity_resolution_token',br->>'identityResolutionToken','p_identity_resolution_decision','different'));end if;bid:=nullif(br->>'bookingId','')::uuid;if bid is null then raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001';end if;select p.person_id into pid from reservations.bookings b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id where b.id=bid;update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=bid where id=m.id;if m.role='child_paid' then select gm.resolved_person_id into gp from reservations.public_registration_request_members gm where gm.request_id=r.id and gm.member_key=m.guardian_member_key;if gp is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;select cp.id into gpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=gp and cp.status='active';if gpart is null then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by)values(e.conference_id,gp,'active',actor,actor)returning id into gpart;end if;select cp.id into cpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=pid;if cpart is null then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by)values(e.conference_id,pid,gpart,'active',actor,actor)returning id into cpart;elsif exists(select 1 from public.conference_participations where id=cpart and guardian_participation_id is distinct from gpart)then raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';end if;end if;
 else
  if choice='new' then insert into platform.people(full_name,phone,gender,date_of_birth,church,governorate,city_or_village,service_sector,service_sector_other,created_by,updated_by)values(m.full_name,nullif(m.phone,''),'child',m.date_of_birth,nullif(m.church,''),nullif(m.governorate,''),nullif(m.city_or_village,''),nullif(m.service_sector,''),m.service_sector_other,actor,actor)returning id into pid;end if;select gm.resolved_person_id into gp from reservations.public_registration_request_members gm where gm.request_id=r.id and gm.member_key=m.guardian_member_key;if gp is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;select cp.id into gpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=gp and cp.status='active';if gpart is null then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by)values(e.conference_id,gp,'active',actor,actor)returning id into gpart;end if;select cp.id into cpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=pid;if cpart is null then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by)values(e.conference_id,pid,gpart,'active',actor,actor)returning id into cpart;elsif exists(select 1 from public.conference_participations where id=cpart and guardian_participation_id is distinct from gpart)then raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';end if;update reservations.public_registration_request_members set resolved_person_id=pid where id=m.id;
 end if;
end loop;result:=result||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id));update reservations.public_registration_requests set decision_result=result where id=r.id;return result;end $function$
;
commit;
