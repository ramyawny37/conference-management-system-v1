-- Canonical follow-up for already-applied member lifecycle migration.
-- Keeps original family-request approval replay deterministic per member.

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
  child_operation:=extensions.uuid_generate_v5(p_operation_id,m.member_key::text);
  perform reservations_private.approve_public_registration_member(p_device_id,child_operation,r.id,m.member_key,choice,pid,p_reason);
 end loop;
 result:=primary_result||jsonb_build_object('members',reservations_private.public_registration_members_json(r.id));
 update reservations.public_registration_requests set decision_result=result where id=r.id;return result;
end $function$

;