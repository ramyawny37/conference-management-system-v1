begin;
alter table reservations.public_registration_request_members
 add column review_state text,
 add column submitted_at timestamptz,
 add column decided_at timestamptz,
 add column decided_by uuid,
 add column decided_by_device_id uuid,
 add column decision_reason text,
 add column submit_operation_id uuid,
 add column submit_intent_digest bytea,
 add column decision_operation_id uuid,
 add column decision_intent_digest bytea;
update reservations.public_registration_request_members m set
 review_state=case when m.resolved_person_id is not null then 'approved' when r.state='rejected' then 'rejected' when r.state='waitlisted' then 'waitlisted' else 'pending' end,
 submitted_at=r.submitted_at,
 decided_at=case when r.state in('approved','rejected','waitlisted') then r.decided_at end,
 decided_by=case when r.state in('approved','rejected','waitlisted') then r.decided_by end,
 decided_by_device_id=case when r.state in('approved','rejected','waitlisted') then r.decided_by_device_id end,
 decision_reason=case when r.state in('rejected','waitlisted') then r.decision_reason end
from reservations.public_registration_requests r where r.id=m.request_id;
alter table reservations.public_registration_request_members alter column review_state set not null,alter column review_state set default 'pending',alter column submitted_at set not null,alter column submitted_at set default statement_timestamp();
alter table reservations.public_registration_request_members add constraint public_registration_request_members_review_state_check check(review_state in('pending','approved','rejected','waitlisted'));
create unique index public_registration_request_members_submit_operation_uidx on reservations.public_registration_request_members(submit_operation_id) where submit_operation_id is not null;
create unique index public_registration_request_members_decision_operation_uidx on reservations.public_registration_request_members(decision_operation_id) where decision_operation_id is not null;
CREATE OR REPLACE FUNCTION platform_private.stage_public_registration_member_added_notification(p_request_id uuid, p_member_key uuid, p_operation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;m reservations.public_registration_request_members%rowtype;begin
 select * into r from reservations.public_registration_requests where id=p_request_id;select * into m from reservations.public_registration_request_members where request_id=p_request_id and member_key=p_member_key;
 if r.id is null or m.id is null then raise exception 'PUBLIC_REGISTRATION_NOTIFICATION_SCOPE_INVALID' using errcode='42501';end if;
 insert into platform.notification_outbox(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key)
 values('reservations.public_registration.member_added','reservations','public_registration_request',r.id::text,'event',r.event_id::text,'فرد جديد في طلب تسجيل','تمت إضافة '||m.full_name||' إلى طلب مقبول ويحتاج للمراجعة.','./#/reservations/registration-requests?eventId='||r.event_id::text||'&requestId='||r.id::text,'public-registration-member-added:'||p_operation_id::text) on conflict(dedupe_key)do nothing;
end $function$

;
CREATE OR REPLACE FUNCTION platform_private.stage_public_registration_member_decision_notification(p_request_id uuid, p_member_key uuid, p_operation_id uuid, p_state text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;m reservations.public_registration_request_members%rowtype;v_event_id uuid;v_destination_id uuid;v_public_id uuid;v_title text;v_body text;begin
 if p_state not in('approved','rejected','waitlisted')then raise exception 'PUBLIC_REGISTRATION_MEMBER_DECISION_INVALID' using errcode='22023';end if;
 select * into r from reservations.public_registration_requests where id=p_request_id;select * into m from reservations.public_registration_request_members where request_id=p_request_id and member_key=p_member_key;select public_id into v_public_id from reservations.public_registration_channels where id=r.channel_id;
 v_title:=case p_state when'approved'then'تم اعتماد فرد من طلبك' when'rejected'then'تم رفض فرد من طلبك' else'تم وضع فرد في قائمة الانتظار'end;
 v_body:=case p_state when'approved'then'تم اعتماد '||m.full_name||' ضمن طلب التسجيل.' when'rejected'then'تم رفض '||m.full_name||' ضمن طلب التسجيل.' else'تم وضع '||m.full_name||' في قائمة الانتظار.'end;
 insert into platform.notification_events(event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key)
 values('public_registration.decision','reservations','public_registration_request',r.id::text,'event',r.event_id::text,v_title,v_body,'./public-registration.html?event='||v_public_id::text,'public-registration-member-decision:'||p_operation_id::text)
 on conflict(dedupe_key)do update set dedupe_key=excluded.dedupe_key returning id into v_event_id;
 if nullif(btrim(r.submitted_phone),'')is not null then insert into platform.notification_destinations(notification_event_id,destination_kind,destination)values(v_event_id,'phone',r.submitted_phone)on conflict do nothing;select id into v_destination_id from platform.notification_destinations where notification_event_id=v_event_id and destination_kind='phone' and destination=r.submitted_phone;insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)values(v_event_id,v_destination_id,'whatsapp'),(v_event_id,v_destination_id,'sms')on conflict do nothing;end if;
 insert into platform.notification_destinations(notification_event_id,destination_kind,applicant_push_subscription_id)select v_event_id,'applicant_push_subscription',s.id from platform.notification_applicant_push_subscriptions s where s.request_id=r.id and s.active on conflict do nothing;
 insert into platform.notification_channel_deliveries(notification_event_id,destination_id,channel)select v_event_id,d.id,'web_push' from platform.notification_destinations d where d.notification_event_id=v_event_id and d.destination_kind='applicant_push_subscription' on conflict do nothing;
end $function$

;
CREATE OR REPLACE FUNCTION reservations_private.public_registration_members_json(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
'memberKey',m.member_key,'ordinal',m.ordinal,'role',m.role,'guardianMemberKey',m.guardian_member_key,'bookingTypeId',m.booking_type_id,
'fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,
'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other,'notes',m.notes,
'resolvedPersonId',m.resolved_person_id,'bookingId',m.booking_id,'reviewState',m.review_state,'submittedAt',m.submitted_at,'decidedAt',m.decided_at,
'decisionReason',m.decision_reason)) order by m.ordinal,m.id),'[]'::jsonb)
from reservations.public_registration_request_members m where m.request_id=p_request_id
$function$

;
CREATE OR REPLACE FUNCTION reservations.public_registration_add_family_member(p_public_id uuid, p_tracking_secret_digest bytea, p_fingerprint_digest bytea, p_operation_id uuid, p_member jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c reservations.public_registration_channels%rowtype;r reservations.public_registration_requests%rowtype;e reservations.events%rowtype;existing reservations.public_registration_request_members%rowtype;g reservations.public_registration_request_members%rowtype;k uuid;role text;guardian uuid;bt uuid;v_dob date;v_sector text;v_sector_other text;v_governorate text;v_intent bytea;v_ordinal int;
begin
 if p_operation_id is null or p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 or p_member is null or jsonb_typeof(p_member)<>'object' or(select array_agg(x order by x)from jsonb_object_keys(p_member)x)<>array['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther']::text[] then raise exception 'PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID' using errcode='22023';end if;
 select * into c from reservations.public_registration_channels where public_id=p_public_id for key share;if not found or not c.enabled then raise exception 'PUBLIC_REGISTRATION_UNAVAILABLE' using errcode='P0002';end if;perform reservations_private.public_registration_rate_limit(c.id,p_fingerprint_digest,8);
 select * into r from reservations.public_registration_requests where channel_id=c.id and tracking_secret_digest=p_tracking_secret_digest for update;if not found then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002';end if;if r.state<>'approved' then raise exception 'PUBLIC_REGISTRATION_FAMILY_ADD_STATE_INVALID' using errcode='22023';end if;
 select * into e from reservations.events where id=r.event_id for key share;if not found or e.status<>'open' then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;if(c.opens_at is not null and statement_timestamp()<c.opens_at)or(c.closes_at is not null and statement_timestamp()>=c.closes_at)then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;
 v_intent:=extensions.digest(convert_to(p_member::text,'UTF8'),'sha256');perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-family-add:'||r.id::text||':'||p_operation_id::text,0));
 select * into existing from reservations.public_registration_request_members where request_id=r.id and submit_operation_id=p_operation_id;if found then if existing.submit_intent_digest<>v_intent then raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001';end if;return jsonb_build_object('requestId',r.id,'reference',r.request_reference,'state',r.state,'members',reservations_private.public_registration_members_json(r.id));end if;
 if(select count(*)from reservations.public_registration_request_members where request_id=r.id)>=12 then raise exception 'PUBLIC_REGISTRATION_FAMILY_SIZE_INVALID' using errcode='22023';end if;
 k:=(p_member->>'memberKey')::uuid;role:=p_member->>'role';guardian:=nullif(p_member->>'guardianMemberKey','')::uuid;bt:=nullif(p_member->>'bookingTypeId','')::uuid;v_sector:=p_member->>'serviceSector';v_sector_other:=nullif(btrim(coalesce(p_member->>'serviceSectorOther','')),'');v_governorate:=nullif(btrim(p_member->>'governorate'),'');
 if role not in('adult','child_paid','child_dependent')then raise exception 'PUBLIC_REGISTRATION_MEMBER_ROLE_INVALID' using errcode='22023';end if;if nullif(btrim(p_member->>'fullName'),'')is null or nullif(p_member->>'dateOfBirth','')is null or(p_member->>'gender')not in('male','female')then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;v_dob:=(p_member->>'dateOfBirth')::date;perform reservations_private.require_public_registration_member_age(e.start_date,v_dob,role);
 if v_governorate is null or char_length(v_governorate)>120 then raise exception 'PUBLIC_REGISTRATION_GOVERNORATE_REQUIRED' using errcode='22023';end if;if v_sector not in('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other')or(v_sector='other' and v_sector_other is null)or(v_sector<>'other' and v_sector_other is not null)then raise exception 'PUBLIC_REGISTRATION_SERVICE_SECTOR_INVALID' using errcode='22023';end if;
 if role in('child_paid','child_dependent')then if guardian is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;select x.* into g from reservations.public_registration_request_members x where x.request_id=r.id and x.member_key=guardian and x.role in('primary','adult')and x.review_state='approved';if not found then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;if btrim(p_member->>'governorate')is distinct from btrim(g.governorate)or btrim(coalesce(p_member->>'church',''))is distinct from btrim(g.church)or btrim(coalesce(p_member->>'cityOrVillage',''))is distinct from btrim(g.city_or_village)or coalesce(p_member->>'serviceSector','')is distinct from g.service_sector or btrim(coalesce(p_member->>'serviceSectorOther',''))is distinct from btrim(coalesce(g.service_sector_other,''))then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_CONTEXT_MISMATCH' using errcode='22023';end if;if role='child_dependent'then if bt is not null then raise exception 'PUBLIC_REGISTRATION_DEPENDENT_INVALID' using errcode='22023';end if;elsif bt is null or not exists(select 1 from reservations.booking_types x where x.id=bt and x.event_id=e.id and x.active)then raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';end if;
 else if guardian is not null or bt is null or not exists(select 1 from reservations.booking_types x where x.id=bt and x.event_id=e.id and x.active)then raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';end if;end if;
 if exists(select 1 from reservations.public_registration_request_members x where x.request_id=r.id and x.member_key=k)then raise exception 'PUBLIC_REGISTRATION_ALREADY_EXISTS' using errcode='23505';end if;if nullif(btrim(coalesce(p_member->>'phone','')),'')is not null and exists(select 1 from reservations.public_registration_request_members x where x.request_id=r.id and platform_private.person_phone_key(x.phone)=platform_private.person_phone_key(p_member->>'phone'))then raise exception 'PUBLIC_REGISTRATION_ALREADY_EXISTS' using errcode='23505';end if;
 select coalesce(max(ordinal),-1)+1 into v_ordinal from reservations.public_registration_request_members where request_id=r.id;
 insert into reservations.public_registration_request_members(request_id,member_key,ordinal,role,guardian_member_key,booking_type_id,full_name,phone,gender,date_of_birth,church,governorate,city_or_village,service_sector,service_sector_other,notes,review_state,submitted_at,submit_operation_id,submit_intent_digest)values(r.id,k,v_ordinal,role,guardian,bt,btrim(p_member->>'fullName'),btrim(coalesce(p_member->>'phone','')),p_member->>'gender',v_dob,coalesce(p_member->>'church',''),btrim(p_member->>'governorate'),coalesce(p_member->>'cityOrVillage',''),v_sector,v_sector_other,nullif(p_member->>'notes',''),'pending',statement_timestamp(),p_operation_id,v_intent);
 update reservations.public_registration_requests set revision=revision+1,updated_at=statement_timestamp()where id=r.id;
 perform platform_private.stage_public_registration_member_added_notification(r.id,k,p_operation_id);
 return jsonb_build_object('requestId',r.id,'reference',r.request_reference,'state',r.state,'members',reservations_private.public_registration_members_json(r.id));
end $function$

;
CREATE OR REPLACE FUNCTION reservations.public_registration_status_family(p_public_id uuid, p_tracking_secret_digest bytea, p_fingerprint_digest bytea)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_base jsonb;v_request_id uuid;begin
 v_base:=reservations.public_registration_status(p_public_id,p_tracking_secret_digest,p_fingerprint_digest);
 select r.id into v_request_id from reservations.public_registration_requests r join reservations.public_registration_channels c on c.id=r.channel_id where c.public_id=p_public_id and r.tracking_secret_digest=p_tracking_secret_digest;
 if v_request_id is null then raise exception 'PUBLIC_REGISTRATION_NOT_FOUND' using errcode='P0002';end if;
 return v_base||jsonb_build_object('members',reservations_private.public_registration_members_json(v_request_id),
 'hasPendingMembers',exists(select 1 from reservations.public_registration_request_members m where m.request_id=v_request_id and m.review_state='pending'));
end $function$

;
CREATE OR REPLACE FUNCTION reservations_private.get_public_registration_family_request(p_device_id uuid, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare base jsonb;r reservations.public_registration_requests%rowtype;items jsonb;begin
 base:=reservations_private.get_public_registration_request(p_device_id,p_request_id);select * into r from reservations.public_registration_requests where id=p_request_id;
 select coalesce(jsonb_agg(jsonb_build_object('member',jsonb_strip_nulls(jsonb_build_object(
 'memberKey',m.member_key,'ordinal',m.ordinal,'role',m.role,'guardianMemberKey',m.guardian_member_key,'bookingTypeId',m.booking_type_id,'bookingTypeName',bt.name,'currentPrice',bt.price,
 'fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,
 'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other,'notes',m.notes,'resolvedPersonId',m.resolved_person_id,'bookingId',m.booking_id,
 'reviewState',m.review_state,'submittedAt',m.submitted_at,'decidedAt',m.decided_at,'decisionReason',m.decision_reason)),
 'identityCandidates',case when m.review_state in('pending','waitlisted') then reservations_private.public_registration_identity_candidates(r.event_id,m.full_name,m.phone,10) else '[]'::jsonb end) order by m.ordinal),'[]'::jsonb)
 into items from reservations.public_registration_request_members m left join reservations.booking_types bt on bt.id=m.booking_type_id and bt.event_id=r.event_id where m.request_id=r.id;
 return base||jsonb_build_object('members',items,'hasPendingMembers',exists(select 1 from reservations.public_registration_request_members x where x.request_id=r.id and x.review_state='pending'));
end $function$

;
CREATE OR REPLACE FUNCTION reservations_private.approve_public_registration_member(p_device_id uuid, p_operation_id uuid, p_request_id uuid, p_member_key uuid, p_choice text, p_person_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;m reservations.public_registration_request_members%rowtype;e reservations.events%rowtype;ctx jsonb;actor uuid;intent bytea;pid uuid:=p_person_id;br jsonb;bid uuid;age int;args jsonb;gp uuid;gpart uuid;cpart uuid;result jsonb;
begin
 if p_device_id is null or p_operation_id is null or p_request_id is null or p_member_key is null or p_choice not in('existing','new')or(p_choice='existing' and p_person_id is null)or(p_choice='new' and p_person_id is not null)then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
 select * into r from reservations.public_registration_requests where id=p_request_id for update;if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002';end if;
 ctx:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');actor:=(ctx->>'actorUserId')::uuid;
 select * into m from reservations.public_registration_request_members where request_id=r.id and member_key=p_member_key for update;if not found then raise exception 'PUBLIC_REGISTRATION_MEMBER_NOT_FOUND' using errcode='P0002';end if;
 intent:=extensions.digest(convert_to(jsonb_build_object('requestId',r.id,'memberKey',m.member_key,'choice',p_choice,'personId',p_person_id,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-member-decision:'||p_operation_id::text,0));
 if m.review_state='approved' then if m.decision_operation_id=p_operation_id and m.decision_intent_digest=intent then return jsonb_build_object('memberKey',m.member_key,'reviewState','approved','resolvedPersonId',m.resolved_person_id,'bookingId',m.booking_id);end if;raise exception 'PUBLIC_REGISTRATION_MEMBER_STATE_CONFLICT' using errcode='40001';end if;
 if m.review_state not in('pending','waitlisted')then raise exception 'PUBLIC_REGISTRATION_MEMBER_STATE_CONFLICT' using errcode='40001';end if;
 if p_choice='existing' and not exists(select 1 from jsonb_array_elements(reservations_private.public_registration_identity_candidates(r.event_id,m.full_name,m.phone,10))c where c->>'personId'=pid::text and coalesce((c->>'hasEventBooking')::boolean,false)=false)then raise exception 'PUBLIC_REGISTRATION_PERSON_CANDIDATE_STALE' using errcode='40001';end if;
 select * into e from reservations.events where id=r.event_id and scope_partition_id=(ctx->>'scopePartitionId')::uuid for key share;if not found then raise exception 'PUBLIC_REGISTRATION_EVENT_SCOPE_CONFLICT' using errcode='40001';end if;
 if m.role<>'child_dependent' then
  if m.date_of_birth is null or m.date_of_birth>e.start_date then raise exception 'PUBLIC_REGISTRATION_DATE_OF_BIRTH_INVALID' using errcode='22023';end if;age:=extract(year from pg_catalog.age(e.start_date,m.date_of_birth))::int;
  args:=reservations_private.public_registration_booking_args(p_operation_id,r.event_id,m.booking_type_id,m.full_name,m.phone,age,m.church,m.governorate,m.city_or_village,m.service_sector,m.service_sector_other,m.notes,m.gender,m.date_of_birth,case when p_choice='existing' then pid else null end);
  br:=reservations.mutate(p_device_id,'create_booking',args);if p_choice='new' and coalesce((br->>'identityResolutionRequired')::boolean,false)then if nullif(br->>'identityResolutionToken','')is null then raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001';end if;br:=reservations.mutate(p_device_id,'create_booking',args||jsonb_build_object('p_identity_resolution_token',br->>'identityResolutionToken','p_identity_resolution_decision','different'));end if;
  bid:=nullif(br->>'bookingId','')::uuid;if bid is null then raise exception 'PUBLIC_REGISTRATION_IDENTITY_RESOLUTION_STALE' using errcode='40001';end if;select p.person_id into pid from reservations.bookings b join reservations.participants p on p.id=b.participant_id and p.scope_partition_id=b.scope_partition_id where b.id=bid and b.event_id=r.event_id;if pid is null then raise exception 'PUBLIC_REGISTRATION_BOOKING_LINK_INVALID' using errcode='40001';end if;
 else
  if p_choice='new'then pid:=platform_private.create_reservations_dependent_person(p_device_id,actor,p_operation_id,r.event_id,jsonb_build_object('fullName',m.full_name,'phone',m.phone,'gender',m.gender,'dateOfBirth',m.date_of_birth,'church',m.church,'governorate',m.governorate,'cityOrVillage',m.city_or_village,'serviceSector',m.service_sector,'serviceSectorOther',m.service_sector_other));end if;
 end if;
 if m.role in('child_paid','child_dependent')then select gm.resolved_person_id into gp from reservations.public_registration_request_members gm where gm.request_id=r.id and gm.member_key=m.guardian_member_key and gm.review_state='approved';if gp is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;if e.conference_id is not null then select cp.id into gpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=gp and cp.status='active';if gpart is null then insert into public.conference_participations(conference_id,person_id,status,created_by,updated_by)values(e.conference_id,gp,'active',actor,actor)returning id into gpart;end if;select cp.id into cpart from public.conference_participations cp where cp.conference_id=e.conference_id and cp.person_id=pid;if cpart is null then insert into public.conference_participations(conference_id,person_id,guardian_participation_id,status,created_by,updated_by)values(e.conference_id,pid,gpart,'active',actor,actor)returning id into cpart;elsif exists(select 1 from public.conference_participations where id=cpart and guardian_participation_id is distinct from gpart)then raise exception 'PUBLIC_REGISTRATION_CHILD_GUARDIAN_CONFLICT' using errcode='40001';end if;end if;end if;
 update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=bid,review_state='approved',decided_at=statement_timestamp(),decided_by=actor,decided_by_device_id=p_device_id,decision_reason=nullif(btrim(coalesce(p_reason,'')),''),decision_operation_id=p_operation_id,decision_intent_digest=intent where id=m.id;
 result:=jsonb_strip_nulls(jsonb_build_object('memberKey',m.member_key,'reviewState','approved','resolvedPersonId',pid,'bookingId',bid,'bookingNumber',br->>'bookingNumber'));
 perform reservations_private.audit(ctx,'public_registration_member.approved','public_registration_request_member',m.id,p_operation_id,to_jsonb(m),result);return result;
end $function$

;
CREATE OR REPLACE FUNCTION reservations_private.decide_public_registration_added_member(p_device_id uuid, p_operation_id uuid, p_request_id uuid, p_member_key uuid, p_decision text, p_person_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;m reservations.public_registration_request_members%rowtype;ctx jsonb;actor uuid;intent bytea;result jsonb;target_state text;choice text;
begin
 select * into r from reservations.public_registration_requests where id=p_request_id for update;if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002';end if;if r.state<>'approved'then raise exception 'PUBLIC_REGISTRATION_FAMILY_ADD_STATE_INVALID' using errcode='22023';end if;
 ctx:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');actor:=(ctx->>'actorUserId')::uuid;select * into m from reservations.public_registration_request_members where request_id=r.id and member_key=p_member_key for update;if not found or m.ordinal=0 then raise exception 'PUBLIC_REGISTRATION_MEMBER_NOT_FOUND' using errcode='P0002';end if;
 if p_decision in('approve_existing','approve_new')then choice:=case when p_decision='approve_existing'then'existing'else'new'end;target_state:='approved';intent:=extensions.digest(convert_to(jsonb_build_object('requestId',r.id,'memberKey',m.member_key,'choice',choice,'personId',p_person_id,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text,'UTF8'),'sha256');
 elsif p_decision in('reject','waitlist')then target_state:=case when p_decision='reject'then'rejected'else'waitlisted'end;intent:=extensions.digest(convert_to(jsonb_build_object('requestId',r.id,'memberKey',m.member_key,'decision',p_decision,'reason',nullif(btrim(coalesce(p_reason,'')),''))::text,'UTF8'),'sha256');
 else raise exception 'PUBLIC_REGISTRATION_MEMBER_DECISION_INVALID' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-member-decision:'||p_operation_id::text,0));
 if m.decision_operation_id=p_operation_id then if m.decision_intent_digest is distinct from intent then raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001';end if;return jsonb_build_object('memberKey',m.member_key,'reviewState',m.review_state,'resolvedPersonId',m.resolved_person_id,'bookingId',m.booking_id,'requestId',r.id,'members',reservations_private.public_registration_members_json(r.id));end if;
 if exists(select 1 from reservations.public_registration_request_members x where x.decision_operation_id=p_operation_id and x.id<>m.id)then raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001';end if;
 if p_decision in('approve_existing','approve_new')then result:=reservations_private.approve_public_registration_member(p_device_id,p_operation_id,r.id,m.member_key,choice,p_person_id,p_reason);
 else
  if m.review_state not in('pending','waitlisted')then raise exception 'PUBLIC_REGISTRATION_MEMBER_STATE_CONFLICT' using errcode='40001';end if;
  update reservations.public_registration_request_members set review_state=target_state,decided_at=statement_timestamp(),decided_by=actor,decided_by_device_id=p_device_id,decision_reason=nullif(btrim(coalesce(p_reason,'')),''),decision_operation_id=p_operation_id,decision_intent_digest=intent where id=m.id;
  result:=jsonb_build_object('memberKey',m.member_key,'reviewState',target_state);perform reservations_private.audit(ctx,'public_registration_member.'||target_state,'public_registration_request_member',m.id,p_operation_id,to_jsonb(m),result);
 end if;
 update reservations.public_registration_requests set revision=revision+1,updated_at=statement_timestamp(),decision_result=coalesce(decision_result,'{}'::jsonb)||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id)) where id=r.id;
 perform platform_private.stage_public_registration_member_decision_notification(r.id,m.member_key,p_operation_id,target_state);
 return result||jsonb_build_object('requestId',r.id,'members',reservations_private.public_registration_members_json(r.id));
end $function$

CREATE OR REPLACE FUNCTION reservations_private.decide_public_registration_family_request(p_device_id uuid, p_operation_id uuid, p_request_id uuid, p_expected_revision bigint, p_decision text, p_resolutions jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r reservations.public_registration_requests%rowtype;pm reservations.public_registration_request_members%rowtype;m reservations.public_registration_request_members%rowtype;res jsonb;choice text;pid uuid;result jsonb;primary_result jsonb;child_operation uuid;
begin
 select * into r from reservations.public_registration_requests where id=p_request_id for update;if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002';end if;
 if p_decision in('reject','waitlist')then
  result:=reservations_private.decide_public_registration_request(p_device_id,p_operation_id,p_request_id,p_expected_revision,p_decision,null,p_reason);
  update reservations.public_registration_request_members set review_state=case when p_decision='reject'then'rejected'else'waitlisted'end,decided_at=statement_timestamp(),decision_reason=nullif(btrim(coalesce(p_reason,'')),'') where request_id=r.id and review_state='pending';
  return result||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id));
 end if;
 if p_decision<>'approve'or jsonb_typeof(p_resolutions)<>'object'then raise exception 'PUBLIC_REGISTRATION_FAMILY_DECISION_INVALID' using errcode='22023';end if;
 select * into pm from reservations.public_registration_request_members where request_id=r.id and ordinal=0 for update;
 res:=p_resolutions->pm.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;
 if choice is null or choice not in('existing','new')or(choice='existing'and pid is null)or(choice='new'and pid is not null)then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
 primary_result:=reservations_private.decide_public_registration_request(p_device_id,p_operation_id,p_request_id,p_expected_revision,case when choice='existing'then'approve_existing'else'approve_new'end,pid,p_reason);
 select resolved_person_id,booking_id into pid,child_operation from reservations.public_registration_requests where id=r.id;
 update reservations.public_registration_request_members set resolved_person_id=pid,booking_id=(select booking_id from reservations.public_registration_requests where id=r.id),review_state='approved',decided_at=statement_timestamp(),decision_operation_id=p_operation_id where id=pm.id;
 for m in select * from reservations.public_registration_request_members where request_id=r.id and ordinal>0 and review_state in('pending','waitlisted') order by ordinal for update loop
  res:=p_resolutions->m.member_key::text;choice:=res->>'decision';pid:=nullif(res->>'personId','')::uuid;
  if choice is null or choice not in('existing','new')or(choice='existing'and pid is null)or(choice='new'and pid is not null)then raise exception 'PUBLIC_REGISTRATION_MEMBER_RESOLUTION_REQUIRED' using errcode='22023';end if;
  child_operation:=extensions.gen_random_uuid();
  perform reservations_private.approve_public_registration_member(p_device_id,child_operation,r.id,m.member_key,choice,pid,p_reason);
 end loop;
 result:=primary_result||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id));
 update reservations.public_registration_requests set decision_result=result where id=r.id;return result;
end $function$

;
CREATE OR REPLACE FUNCTION public.public_registration_gateway(p_operation text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if p_operation='event' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId']);return reservations.public_registration_read((p_args->>'publicId')::uuid,decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='status_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','publicId','trackingSecretDigest']);return reservations.public_registration_status_family((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='recover_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['dateOfBirth','fingerprintDigest','fullName','newTrackingSecretDigest','phone','publicId']);return reservations.public_registration_recover_family((p_args->>'publicId')::uuid,p_args->>'fullName',p_args->>'phone',(p_args->>'dateOfBirth')::date,decode(replace(p_args->>'newTrackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'));
 elsif p_operation='submit_family' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','members','publicId','submitOperationId','trackingSecretDigest']);return reservations.public_registration_submit_family((p_args->>'publicId')::uuid,(p_args->>'submitOperationId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),p_args->'members');
 elsif p_operation='add_family_member' then perform platform_private.require_exact_jsonb_keys(p_args,array['fingerprintDigest','member','operationId','publicId','trackingSecretDigest']);return reservations.public_registration_add_family_member((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),decode(replace(p_args->>'fingerprintDigest',chr(92)||'x',''),'hex'),(p_args->>'operationId')::uuid,p_args->'member');
 elsif p_operation='upsert_push_subscription' then perform platform_private.require_exact_jsonb_keys(p_args,array['auth','endpoint','p256dh','publicId','trackingSecretDigest']);return reservations.public_registration_upsert_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint',p_args->>'p256dh',p_args->>'auth',p_args->>'userAgent');
 elsif p_operation='disable_push_subscription' then perform platform_private.require_exact_jsonb_keys(p_args,array['endpoint','publicId','trackingSecretDigest']);return reservations.public_registration_disable_push_subscription((p_args->>'publicId')::uuid,decode(replace(p_args->>'trackingSecretDigest',chr(92)||'x',''),'hex'),p_args->>'endpoint');
 end if;raise exception 'PUBLIC_REGISTRATION_OPERATION_NOT_ALLOWED' using errcode='22023';
end $function$
;

revoke all on function platform_private.stage_public_registration_member_added_notification(uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function platform_private.stage_public_registration_member_decision_notification(uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function reservations_private.public_registration_members_json(uuid) from public,anon,authenticated,service_role;
revoke all on function reservations.public_registration_add_family_member(uuid,bytea,bytea,uuid,jsonb) from public,anon,authenticated;
grant execute on function reservations.public_registration_add_family_member(uuid,bytea,bytea,uuid,jsonb) to service_role;
revoke all on function reservations.public_registration_status_family(uuid,bytea,bytea) from public,anon,authenticated;
grant execute on function reservations.public_registration_status_family(uuid,bytea,bytea) to service_role;
revoke all on function reservations_private.get_public_registration_family_request(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function reservations_private.approve_public_registration_member(uuid,uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function reservations_private.decide_public_registration_added_member(uuid,uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function reservations_private.decide_public_registration_family_request(uuid,uuid,uuid,bigint,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.public_registration_gateway(text,jsonb) from public,anon,authenticated;
grant execute on function public.public_registration_gateway(text,jsonb) to service_role;
do $route$ declare o oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure;d text;n text;a text:=E'    when \'decide_public_registration_family_request\' then';i text:=E'    when \'decide_public_registration_added_member\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_operation_id\',\'p_request_id\',\'p_member_key\',\'p_decision\'],array[\'p_person_id\',\'p_reason\']);\n      return reservations_private.decide_public_registration_added_member(v_session.device_id,(p_args->>\'p_operation_id\')::uuid,(p_args->>\'p_request_id\')::uuid,(p_args->>\'p_member_key\')::uuid,p_args->>\'p_decision\',nullif(p_args->>\'p_person_id\',\'\')::uuid,p_args->>\'p_reason\');\n    when \'decide_public_registration_family_request\' then';begin select pg_get_functiondef(o)into d;if position('decide_public_registration_added_member' in d)>0 then raise exception 'PUBLIC_REGISTRATION_MEMBER_DECISION_DISPATCH_ALREADY_PRESENT';end if;if position(a in d)=0 then raise exception 'PUBLIC_REGISTRATION_MEMBER_DECISION_DISPATCH_ANCHOR_MISMATCH';end if;n:=replace(d,a,i);execute n;end $route$;
commit;
