-- Canonical admin correction path for submitted public-registration profile data.
CREATE OR REPLACE FUNCTION reservations_private.update_public_registration_member_profile(
 p_device_id uuid,p_operation_id uuid,p_request_id uuid,p_expected_revision bigint,p_member_key uuid,
 p_governorate text,p_church text,p_city_or_village text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
declare r reservations.public_registration_requests%rowtype;m reservations.public_registration_request_members%rowtype;ctx jsonb;oldv jsonb;newv jsonb;v_governorate text:=nullif(btrim(coalesce(p_governorate,'')),'');v_church text:=btrim(coalesce(p_church,''));v_city text:=btrim(coalesce(p_city_or_village,''));
begin
 if p_device_id is null or p_operation_id is null or p_request_id is null or p_member_key is null or p_expected_revision is null or v_governorate is null or char_length(v_governorate)>120 or char_length(v_church)>200 or char_length(v_city)>160 then raise exception 'PUBLIC_REGISTRATION_PROFILE_DATA_INVALID' using errcode='22023';end if;
 select * into r from reservations.public_registration_requests where id=p_request_id for update;if not found then raise exception 'PUBLIC_REGISTRATION_REQUEST_NOT_FOUND' using errcode='P0002';end if;
 ctx:=reservations_private.resolve_event_scope(p_device_id,r.event_id,'reservations.booking.create');
 if r.revision<>p_expected_revision then raise exception 'PUBLIC_REGISTRATION_REQUEST_REVISION_CONFLICT' using errcode='40001';end if;
 if r.state not in('submitted','under_review','waitlisted') then raise exception 'PUBLIC_REGISTRATION_REQUEST_STATE_INVALID' using errcode='22023';end if;
 select * into m from reservations.public_registration_request_members where request_id=r.id and member_key=p_member_key for update;if not found then raise exception 'PUBLIC_REGISTRATION_MEMBER_NOT_FOUND' using errcode='P0002';end if;
 oldv:=jsonb_build_object('memberKey',m.member_key,'governorate',m.governorate,'church',m.church,'cityOrVillage',m.city_or_village,'revision',r.revision);
 if m.role in('child_paid','child_dependent') then
   if not exists(select 1 from reservations.public_registration_request_members g where g.request_id=r.id and g.member_key=m.guardian_member_key and btrim(g.governorate)=v_governorate and btrim(g.church)=v_church and btrim(g.city_or_village)=v_city) then raise exception 'PUBLIC_REGISTRATION_GUARDIAN_CONTEXT_MISMATCH' using errcode='22023';end if;
 end if;
 update reservations.public_registration_request_members set governorate=v_governorate,church=v_church,city_or_village=v_city where id=m.id;
 if m.role in('primary','adult') then update reservations.public_registration_request_members set governorate=v_governorate,church=v_church,city_or_village=v_city where request_id=r.id and guardian_member_key=m.member_key;end if;
 if m.ordinal=0 then update reservations.public_registration_requests set submitted_governorate=v_governorate,submitted_church=v_church,submitted_city_or_village=v_city where id=r.id;end if;
 update reservations.public_registration_requests set revision=revision+1,updated_at=statement_timestamp() where id=r.id returning * into r;
 newv:=jsonb_build_object('memberKey',m.member_key,'governorate',v_governorate,'church',v_church,'cityOrVillage',v_city,'revision',r.revision);
 perform reservations_private.audit(ctx,'public_registration.profile_corrected','public_registration_request',r.id,p_operation_id,oldv,newv);
 return jsonb_build_object('requestId',r.id,'revision',r.revision,'members',reservations_private.public_registration_members_json(r.id));
end $function$;
revoke all on function reservations_private.update_public_registration_member_profile(uuid,uuid,uuid,bigint,uuid,text,text,text) from public,anon,authenticated;
