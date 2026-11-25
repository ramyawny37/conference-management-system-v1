begin;

create function reservations_private.list_public_registration_requests(
 p_device_id uuid,p_event_id uuid,p_state text,p_limit integer
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_limit integer:=coalesce(p_limit,100);
begin
 if p_event_id is null or v_limit<1 or v_limit>500 or (p_state is not null and p_state not in('submitted','under_review','approved','rejected','waitlisted')) then
  raise exception 'PUBLIC_REGISTRATION_ADMIN_ARGUMENT_INVALID' using errcode='22023'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
 return (select coalesce(jsonb_agg(jsonb_build_object(
  'requestId',r.id,'reference',r.request_reference,'state',r.state,'revision',r.revision,
  'fullName',r.submitted_full_name,'phone',r.submitted_phone,'bookingTypeId',r.booking_type_id,
  'bookingTypeName',bt.name,'submittedAt',r.submitted_at,'updatedAt',r.updated_at
 ) order by r.submitted_at,r.id),'[]'::jsonb)
 from (select * from reservations.public_registration_requests
       where event_id=p_event_id and (p_state is null or state=p_state)
       order by submitted_at,id limit v_limit) r
 join reservations.booking_types bt on bt.id=r.booking_type_id and bt.event_id=r.event_id);
end $$;

create function reservations_private.get_public_registration_request(
 p_device_id uuid,p_request_id uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r reservations.public_registration_requests%rowtype; v_context jsonb; v_candidates jsonb; v_type reservations.booking_types%rowtype;
begin
 select * into r from reservations.public_registration_requests where id=p_request_id;
 if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002'; end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');
 select * into v_type from reservations.booking_types where id=r.booking_type_id and event_id=r.event_id;

 select coalesce(jsonb_agg(candidate order by candidate->>'fullName',candidate->>'id'),'[]'::jsonb) into v_candidates
 from (
   select jsonb_build_object(
    'id',p.id,'fullName',p.full_name,'phone',p.phone,'church',p.church,'revision',p.revision,
    'hasEventBooking',exists(
      select 1 from reservations.participants rp join reservations.bookings b on b.participant_id=rp.id
      where rp.person_id=p.id and b.event_id=r.event_id
    )
   ) candidate
   from platform.people p
   where (lower(regexp_replace(btrim(p.full_name),'\\s+',' ','g'))=lower(regexp_replace(btrim(r.submitted_full_name),'\\s+',' ','g')))
      or (nullif(regexp_replace(coalesce(p.phone,''),'[^0-9]','','g'),'') is not null
          and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=regexp_replace(r.submitted_phone,'[^0-9]','','g'))
   order by p.updated_at desc,p.id limit 20
 ) x;

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
  ),
  'identityCandidates',v_candidates
 );
end $$;

revoke all on function reservations_private.list_public_registration_requests(uuid,uuid,text,integer) from public,anon,authenticated,service_role;
revoke all on function reservations_private.get_public_registration_request(uuid,uuid) from public,anon,authenticated,service_role;

do $patch$
declare v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure;
 v_def text; v_new text; v_anchor text:=E'    case p_operation\n    when \'search_people\' then';
 v_insert text:=E'    case p_operation\n    when \'list_public_registration_requests\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_event_id\',\'p_state\',\'p_limit\']);\n      return reservations_private.list_public_registration_requests(v_session.device_id,(p_args->>\'p_event_id\')::uuid,nullif(p_args->>\'p_state\',\'\'),(p_args->>\'p_limit\')::integer);\n    when \'get_public_registration_request\' then\n      perform platform_private.require_exact_jsonb_keys(p_args,array[\'p_request_id\']);\n      return reservations_private.get_public_registration_request(v_session.device_id,(p_args->>\'p_request_id\')::uuid);\n    when \'search_people\' then';
begin
 select pg_get_functiondef(v_oid) into v_def;
 if position('when ''list_public_registration_requests'' then' in v_def)>0 or position('when ''get_public_registration_request'' then' in v_def)>0 then
  raise exception 'PUBLIC_REGISTRATION_ADMIN_DISPATCH_ALREADY_PRESENT'; end if;
 if length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) then
  raise exception 'PUBLIC_REGISTRATION_ADMIN_DISPATCH_ANCHOR_MISMATCH'; end if;
 v_new:=replace(v_def,v_anchor,v_insert); execute v_new;
 select pg_get_functiondef(v_oid) into v_def;
 if position('when ''list_public_registration_requests'' then' in v_def)=0
    or position('when ''get_public_registration_request'' then' in v_def)=0
    or not has_function_privilege('service_role',v_oid,'execute')
    or has_function_privilege('anon',v_oid,'execute')
    or has_function_privilege('authenticated',v_oid,'execute') then
  raise exception 'PUBLIC_REGISTRATION_ADMIN_DISPATCH_POSTCONDITION_FAILED'; end if;
end $patch$;

commit;
