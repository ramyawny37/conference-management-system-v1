create or replace function platform.execute_device_operation_pre_module_entry_access_gate(p_user_id uuid,p_session_id uuid,p_token_hash bytea,p_module text,p_operation text,p_args jsonb) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public','platform','platform_private','reservations','reservations_private' as $$
declare v_session platform_private.device_sessions%rowtype; v_intercept boolean:=false;
begin
 if p_module='reservations' then
  v_intercept:=case
   when p_operation='list_events' then true
   when p_operation in ('list_bookings','list_booking_types') then true
   when p_operation='get_dashboard_summary' then coalesce(p_args ? 'p_event_id',false)
   when p_operation='create_event' then coalesce(p_args ? 'p_scope_type',false)
   when p_operation='update_event' then coalesce(not p_args ? 'p_conference_id',false)
   when p_operation='link_standalone_event_to_conference' then true
   else false end;
 end if;
 if not v_intercept then return platform.execute_device_operation_pre_reservations_standalone_dispatch(p_user_id,p_session_id,p_token_hash,p_module,p_operation,p_args); end if;
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501'; end if;
 if p_args is null or jsonb_typeof(p_args)<>'object' or p_args ?| array['organization_id','p_organization_id','scope_partition_id','p_scope_partition_id','device_id','p_device_id','actor_user_id','p_actor_user_id','actor_device_id','p_actor_device_id','p_conference_person_id','conference_person_id'] then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023'; end if;
 case p_operation
  when 'list_events' then
   if p_args ? 'p_scope_type' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type','p_status','p_limit']); if p_args->>'p_scope_type'<>'standalone' then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023'; end if;
   else perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_status','p_limit']); end if;
  when 'list_bookings' then
   if p_args ? 'p_conference_id' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_event_id','p_limit']); else perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id','p_limit']); end if;
  when 'list_booking_types' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']);
  when 'get_dashboard_summary' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']);
  when 'create_event' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']); if p_args->>'p_scope_type'<>'standalone' then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  when 'update_event' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
  when 'link_standalone_event_to_conference' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_conference_id']);
 end case;
 select s.* into v_session from platform_private.device_sessions s join platform.device_key_bindings b on b.id=s.binding_id join platform.user_device_authorizations a on a.id=s.device_authorization_id join platform.devices d on d.id=s.device_id join platform.profiles p on p.user_id=s.user_id where s.id=p_session_id and s.user_id=p_user_id and s.token_hash=p_token_hash and s.purpose='PLATFORM_DEVICE_SESSION' and s.revoked_at is null and s.expires_at>statement_timestamp() and b.user_id=s.user_id and b.device_id=s.device_id and b.device_authorization_id=s.device_authorization_id and b.public_key_thumbprint=s.public_key_thumbprint and b.algorithm='ECDSA_P256_SHA256' and b.lifecycle_status='active' and b.revoked_at is null and b.retired_at is null and a.user_id=s.user_id and a.device_id=s.device_id and a.status='approved' and a.revoked_at is null and d.lifecycle_status='active' and d.retired_at is null and d.compromised_at is null and p.account_status='approved';
 if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user_id,'role','service_role')::text,true);
 perform set_config('platform.phase1c_context',jsonb_build_object('purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,'user_id',v_session.user_id,'device_id',v_session.device_id,'authorization_id',v_session.device_authorization_id,'binding_id',v_session.binding_id,'token_hash',encode(p_token_hash,'hex'))::text,true);
 if p_operation in ('list_events','list_bookings','list_booking_types','get_dashboard_summary') then return reservations.read(v_session.device_id,p_operation,p_args); end if;
 if p_operation='link_standalone_event_to_conference' then return reservations_private.link_standalone_event_to_conference(v_session.device_id,p_args); end if;
 return reservations.mutate(v_session.device_id,p_operation,p_args);
end $$;;
