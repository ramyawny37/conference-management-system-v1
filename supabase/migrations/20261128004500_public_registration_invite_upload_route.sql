begin;
create function reservations_private.authorize_public_registration_invite_image_upload(p_device_id uuid,p_event_id uuid,p_mime_type text,p_size integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb;
begin
 if p_event_id is null or p_mime_type not in('image/jpeg','image/png','image/webp') or p_size is null or p_size<1 or p_size>5242880 then
  raise exception 'PUBLIC_REGISTRATION_INVITE_IMAGE_INVALID' using errcode='22023';
 end if;
 v_context:=reservations_private.resolve_event_scope(p_device_id,p_event_id,'reservations.booking.create');
 return jsonb_build_object('eventId',p_event_id,'authorized',true);
end $$;
revoke all on function reservations_private.authorize_public_registration_invite_image_upload(uuid,uuid,text,integer) from public,anon,authenticated,service_role;

do $patch$ declare v_oid oid:='platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure; d text; a text; i text;
begin
 select pg_get_functiondef(v_oid) into d;
 if position('when ''upload_public_registration_invite_image'' then' in d)>0 then raise exception 'PUBLIC_REGISTRATION_INVITE_UPLOAD_ROUTE_ALREADY_PRESENT'; end if;
 a:='when ''get_public_registration_settings'' then';
 i:='when ''upload_public_registration_invite_image'' then
      perform platform_private.require_exact_jsonb_keys(p_args,array[''p_event_id'',''p_mime_type'',''p_size'']);
      return reservations_private.authorize_public_registration_invite_image_upload(v_session.device_id,(p_args->>''p_event_id'')::uuid,p_args->>''p_mime_type'',(p_args->>''p_size'')::integer);
    when ''get_public_registration_settings'' then';
 if position(a in d)=0 then raise exception 'PUBLIC_REGISTRATION_INVITE_UPLOAD_ROUTE_ANCHOR_MISSING'; end if;
 d:=replace(d,a,i); execute d;
end $patch$;
commit;