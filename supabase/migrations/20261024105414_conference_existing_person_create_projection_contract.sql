CREATE OR REPLACE FUNCTION public.create_conference_participation(p_actor_device_id uuid, p_operation_id uuid, p_conference_id uuid, p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_context jsonb; v_actor uuid; v_device_authorization uuid; v_request jsonb; v_prior public.conference_participation_operations%rowtype; v_row public.conference_participations%rowtype; v_person platform.people%rowtype; v_result jsonb;
begin
  if p_operation_id is null or p_person_id is null then raise exception 'CONFERENCE_PARTICIPATION_ARGUMENT_INVALID' using errcode='22023'; end if;
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.manage',true); v_actor:=(v_context->>'actorUserId')::uuid;
  v_device_authorization:=platform_private.validated_phase1c_device_authorization(v_actor,p_actor_device_id);
  v_request:=jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id);
  perform pg_advisory_xact_lock(hashtextextended(v_actor::text||':conference-participation:'||p_operation_id::text,0));
  select * into v_prior from public.conference_participation_operations where actor_user_id=v_actor and operation_id=p_operation_id;
  if found then if v_prior.operation<>'create' or v_prior.request<>v_request then raise exception 'CONFERENCE_PARTICIPATION_OPERATION_MISMATCH' using errcode='22023'; end if; select * into strict v_person from platform.people where id=p_person_id; return v_prior.result || jsonb_build_object('person',jsonb_build_object('personId',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'church',v_person.church)); end if;
  if not exists(select 1 from platform.people where id=p_person_id) then raise exception 'PLATFORM_PERSON_NOT_FOUND' using errcode='23503'; end if;
  if exists(select 1 from public.conference_participations where conference_id=p_conference_id and person_id=p_person_id) then raise exception 'CONFERENCE_PARTICIPATION_ALREADY_EXISTS' using errcode='23505'; end if;
  insert into public.conference_participations(conference_id,person_id,created_by,updated_by) values(p_conference_id,p_person_id,v_actor,v_actor) returning * into v_row;
  select * into strict v_person from platform.people where id=p_person_id;
  v_result:=jsonb_build_object('person',jsonb_build_object('personId',v_person.id,'fullName',v_person.full_name,'phone',v_person.phone,'gender',v_person.gender,'dateOfBirth',v_person.date_of_birth,'church',v_person.church),'participationId',v_row.id,'conferenceId',v_row.conference_id,'personId',v_row.person_id,'status',v_row.status,'revision',v_row.revision,'createdAt',v_row.created_at,'updatedAt',v_row.updated_at,'createdBy',v_row.created_by,'updatedBy',v_row.updated_by);
  insert into public.conference_participation_operations values(v_actor,p_operation_id,'create',v_request,v_result,statement_timestamp());
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,old_values,new_values,metadata,operation_id,source) values(v_actor,v_device_authorization,'platform','conference','conference.participation.created','conference_participation',v_row.id,'platform',null,jsonb_build_object('conferenceId',p_conference_id,'personId',p_person_id,'status','active','revision',1),jsonb_build_object('permissionKey','conference.people.manage','authoritySource',v_context->>'authoritySource','grantId',v_context->'grantId'),p_operation_id,'rpc');
  return v_result;
end $function$
;
