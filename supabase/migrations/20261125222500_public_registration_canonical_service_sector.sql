-- Canonicalize legacy public-registration service-sector labels and prevent noncanonical snapshots.
update reservations.public_registration_requests
set submitted_service_sector=case submitted_service_sector
 when 'أرامل' then 'widows' when 'بنات الأرامل' then 'widows-daughters'
 when 'تلمذة ابتدائي وإعدادي' then 'discipleship-primary-prep'
 when 'تلمذة ثانوي وجامعة' then 'discipleship-secondary-university'
 when 'العبادة والتسبيح' then 'worship' when 'الميديا' then 'media'
 when 'إعداد خدام' then 'servant-preparation' when 'المكتب الإداري' then 'administration'
 when 'أخرى' then 'other' else submitted_service_sector end
where submitted_service_sector in ('أرامل','بنات الأرامل','تلمذة ابتدائي وإعدادي','تلمذة ثانوي وجامعة','العبادة والتسبيح','الميديا','إعداد خدام','المكتب الإداري','أخرى');

update reservations.public_registration_request_members
set service_sector=case service_sector
 when 'أرامل' then 'widows' when 'بنات الأرامل' then 'widows-daughters'
 when 'تلمذة ابتدائي وإعدادي' then 'discipleship-primary-prep'
 when 'تلمذة ثانوي وجامعة' then 'discipleship-secondary-university'
 when 'العبادة والتسبيح' then 'worship' when 'الميديا' then 'media'
 when 'إعداد خدام' then 'servant-preparation' when 'المكتب الإداري' then 'administration'
 when 'أخرى' then 'other' else service_sector end
where service_sector in ('أرامل','بنات الأرامل','تلمذة ابتدائي وإعدادي','تلمذة ثانوي وجامعة','العبادة والتسبيح','الميديا','إعداد خدام','المكتب الإداري','أخرى');

alter table reservations.public_registration_requests
add constraint public_registration_requests_submitted_service_sector_canonical_check
check (submitted_service_sector in ('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other'));

alter table reservations.public_registration_request_members
add constraint public_registration_request_members_service_sector_canonical_check
check (service_sector in ('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other'));


create or replace function reservations.public_registration_submit_family(p_public_id uuid, p_submit_operation_id uuid, p_tracking_secret_digest bytea, p_fingerprint_digest bytea, p_members jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_channel reservations.public_registration_channels%rowtype;v_event reservations.events%rowtype;v_existing reservations.public_registration_requests%rowtype;
 v_request_id uuid:=extensions.gen_random_uuid();v_reference text;v_intent bytea;v_primary jsonb;v_member jsonb;v_key uuid;v_guardian uuid;v_role text;v_type uuid;v_count int;v_ordinal int:=0;v_sector text;v_sector_other text;
begin
 if p_submit_operation_id is null or p_tracking_secret_digest is null or octet_length(p_tracking_secret_digest)<>32 or jsonb_typeof(p_members)<>'array' then raise exception 'PUBLIC_REGISTRATION_SUBMISSION_INVALID' using errcode='22023';end if;
 v_count:=jsonb_array_length(p_members);if v_count<1 or v_count>12 then raise exception 'PUBLIC_REGISTRATION_FAMILY_SIZE_INVALID' using errcode='22023';end if;
 v_primary:=p_members->0;if coalesce(v_primary->>'role','')<>'primary' then raise exception 'PUBLIC_REGISTRATION_PRIMARY_REQUIRED' using errcode='22023';end if;
 select * into v_channel from reservations.public_registration_channels where public_id=p_public_id for key share;
 if not found or not v_channel.enabled then raise exception 'PUBLIC_REGISTRATION_UNAVAILABLE' using errcode='P0002';end if;
 perform reservations_private.public_registration_rate_limit(v_channel.id,p_fingerprint_digest,8);
 if v_channel.registration_mode<>'approval_required' or (v_channel.opens_at is not null and statement_timestamp()<v_channel.opens_at) or (v_channel.closes_at is not null and statement_timestamp()>=v_channel.closes_at) then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;
 select * into v_event from reservations.events where id=v_channel.event_id for key share;if not found or v_event.status<>'open' then raise exception 'PUBLIC_REGISTRATION_CLOSED' using errcode='P0001';end if;
 if nullif(btrim(v_primary->>'phone'),'') is null then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;
 v_intent:=extensions.digest(convert_to(p_members::text,'UTF8'),'sha256');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-identity:'||v_event.id::text||':'||platform_private.person_phone_key(v_primary->>'phone')||':'||(v_primary->>'dateOfBirth'),0));
 if exists(select 1 from reservations.public_registration_requests r left join reservations.bookings b on b.id=r.booking_id where r.event_id=v_event.id and platform_private.person_phone_key(r.submitted_phone)=platform_private.person_phone_key(v_primary->>'phone') and r.submitted_date_of_birth=(v_primary->>'dateOfBirth')::date and (r.state in('submitted','under_review') or (r.state='approved' and b.lifecycle_status='active'))) then raise exception 'PUBLIC_REGISTRATION_ALREADY_EXISTS' using errcode='23505';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('public-registration-submit:'||v_channel.id::text||':'||p_submit_operation_id::text,0));
 select * into v_existing from reservations.public_registration_requests where channel_id=v_channel.id and submit_operation_id=p_submit_operation_id;
 if found then if v_existing.submit_intent_digest<>v_intent or v_existing.tracking_secret_digest<>p_tracking_secret_digest then raise exception 'PUBLIC_REGISTRATION_IDEMPOTENCY_CONFLICT' using errcode='40001';end if;return jsonb_build_object('reference',v_existing.request_reference,'state',v_existing.state,'submittedAt',v_existing.submitted_at,'eventId',v_existing.event_id);end if;
 for v_member in select value from jsonb_array_elements(p_members) loop
   if (select array_agg(k order by k) from jsonb_object_keys(v_member) k)<>array['bookingTypeId','church','cityOrVillage','dateOfBirth','fullName','gender','governorate','guardianMemberKey','memberKey','notes','phone','role','serviceSector','serviceSectorOther']::text[] then raise exception 'PUBLIC_REGISTRATION_MEMBER_SHAPE_INVALID' using errcode='22023';end if;
   v_key:=(v_member->>'memberKey')::uuid;v_role:=v_member->>'role';v_guardian:=nullif(v_member->>'guardianMemberKey','')::uuid;v_type:=nullif(v_member->>'bookingTypeId','')::uuid;v_sector:=v_member->>'serviceSector';v_sector_other:=nullif(btrim(coalesce(v_member->>'serviceSectorOther','')),'');
   if v_role not in('primary','adult','child_paid','child_dependent') or (v_ordinal=0 and v_role<>'primary') or (v_ordinal>0 and v_role='primary') then raise exception 'PUBLIC_REGISTRATION_MEMBER_ROLE_INVALID' using errcode='22023';end if;
   if nullif(btrim(v_member->>'fullName'),'') is null or nullif(v_member->>'dateOfBirth','') is null or (v_member->>'gender') not in('male','female') then raise exception 'PUBLIC_REGISTRATION_MEMBER_IDENTITY_REQUIRED' using errcode='22023';end if;
   if v_sector not in('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other') or (v_sector='other' and v_sector_other is null) or (v_sector<>'other' and v_sector_other is not null) then raise exception 'PUBLIC_REGISTRATION_SERVICE_SECTOR_INVALID' using errcode='22023';end if;
   if v_role in('child_paid','child_dependent') then
     if v_guardian is null then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;
     if not exists(select 1 from jsonb_array_elements(p_members) with ordinality as g(value,ord) where (g.value->>'memberKey')::uuid=v_guardian and g.value->>'role' in('primary','adult') and g.ord<=v_ordinal) then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_INVALID' using errcode='22023';end if;
     if v_role='child_dependent' then if v_type is not null then raise exception 'PUBLIC_REGISTRATION_DEPENDENT_INVALID' using errcode='22023';end if;
     elsif v_type is null or not exists(select 1 from reservations.booking_types bt where bt.id=v_type and bt.event_id=v_event.id and bt.active) then raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';end if;
   else
     if v_guardian is not null or v_type is null or not exists(select 1 from reservations.booking_types bt where bt.id=v_type and bt.event_id=v_event.id and bt.active) then raise exception 'PUBLIC_REGISTRATION_BOOKING_TYPE_UNAVAILABLE' using errcode='22023';end if;
   end if;
   v_ordinal:=v_ordinal+1;
 end loop;
 v_reference:='PR-'||upper(substr(replace(v_request_id::text,'-',''),1,12));
 insert into reservations.public_registration_requests(id,channel_id,event_id,submit_operation_id,submit_intent_digest,request_reference,tracking_secret_digest,booking_type_id,submitted_full_name,submitted_phone,submitted_gender,submitted_date_of_birth,submitted_church,submitted_governorate,submitted_city_or_village,submitted_service_sector,submitted_service_sector_other,submitted_notes)
 values(v_request_id,v_channel.id,v_event.id,p_submit_operation_id,v_intent,v_reference,p_tracking_secret_digest,(v_primary->>'bookingTypeId')::uuid,btrim(v_primary->>'fullName'),btrim(v_primary->>'phone'),v_primary->>'gender',(v_primary->>'dateOfBirth')::date,coalesce(v_primary->>'church',''),coalesce(v_primary->>'governorate',''),coalesce(v_primary->>'cityOrVillage',''),v_primary->>'serviceSector',nullif(btrim(coalesce(v_primary->>'serviceSectorOther','')),''),nullif(v_primary->>'notes',''));
 v_ordinal:=0;
 for v_member in select value from jsonb_array_elements(p_members) loop
   insert into reservations.public_registration_request_members(request_id,member_key,ordinal,role,guardian_member_key,booking_type_id,full_name,phone,gender,date_of_birth,church,governorate,city_or_village,service_sector,service_sector_other,notes)
   values(v_request_id,(v_member->>'memberKey')::uuid,v_ordinal,v_member->>'role',nullif(v_member->>'guardianMemberKey','')::uuid,nullif(v_member->>'bookingTypeId','')::uuid,btrim(v_member->>'fullName'),btrim(coalesce(v_member->>'phone','')),v_member->>'gender',(v_member->>'dateOfBirth')::date,coalesce(v_member->>'church',''),coalesce(v_member->>'governorate',''),coalesce(v_member->>'cityOrVillage',''),v_member->>'serviceSector',nullif(btrim(coalesce(v_member->>'serviceSectorOther','')),''),nullif(v_member->>'notes',''));v_ordinal:=v_ordinal+1;
 end loop;
 return jsonb_build_object('reference',v_reference,'state','submitted','submittedAt',statement_timestamp(),'memberCount',v_count,'eventId',v_event.id);
end $function$;

revoke all on function reservations.public_registration_submit_family(uuid,uuid,bytea,bytea,jsonb) from public,anon,authenticated;
grant execute on function reservations.public_registration_submit_family(uuid,uuid,bytea,bytea,jsonb) to service_role;
