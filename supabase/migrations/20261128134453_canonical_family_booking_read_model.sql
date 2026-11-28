begin;
create or replace function reservations_private.booking_family_context(p_booking_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
with member_row as (
 select m.* from reservations.public_registration_request_members m
 where m.booking_id=p_booking_id and m.review_state='approved'
 limit 1
), root_row as (
 select r.* from reservations.public_registration_request_members r
 join member_row m on r.request_id=m.request_id and r.ordinal=0
 where r.review_state='approved'
), guardian_row as (
 select g.* from reservations.public_registration_request_members g
 join member_row m on g.request_id=m.request_id and g.member_key=m.guardian_member_key
 where g.review_state='approved'
), dependents as (
 select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'memberKey',c.member_key,'fullName',c.full_name,'dateOfBirth',c.date_of_birth,
  'gender',c.gender,'role',c.role,'resolvedPersonId',c.resolved_person_id
 )) order by c.ordinal,c.id),'[]'::jsonb) items
 from reservations.public_registration_request_members c
 join member_row m on c.request_id=m.request_id and c.guardian_member_key=m.member_key
 where c.review_state='approved' and c.role='child_dependent'
)
select case when m.id is null then null else jsonb_strip_nulls(jsonb_build_object(
 'requestId',m.request_id,'memberKey',m.member_key,'role',m.role,
 'rootBookingId',root.booking_id,'guardianMemberKey',m.guardian_member_key,'guardianBookingId',g.booking_id,
 'dependents',d.items
)) end
from (select 1) seed left join member_row m on true left join root_row root on true left join guardian_row g on true cross join dependents d
$$;
revoke all on function reservations_private.booking_family_context(uuid) from public,anon,authenticated,service_role;

do $patch$
declare o oid:='reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure;d text;n text;
a text:='select b.*,to_jsonb(p) participant,to_jsonb(e) event,';
i text:='select b.*,reservations_private.booking_family_context(b.id) family_context,to_jsonb(p) participant,to_jsonb(e) event,';
begin select pg_get_functiondef(o) into d;
 if position('booking_family_context(b.id) family_context' in d)=0 then
  if position(a in d)=0 then raise exception 'RESERVATIONS_FAMILY_READ_MODEL_ANCHOR_MISMATCH'; end if;
  n:=replace(d,a,i);execute n;
 end if;
end $patch$;

do $patch$
declare o oid:='reservations_private.decide_public_registration_family_request(uuid,uuid,uuid,bigint,text,jsonb,text)'::regprocedure;d text;n text;
a text:='order by ordinal for update loop';
i text:='order by case role when ''adult'' then 0 when ''child_paid'' then 1 when ''child_dependent'' then 2 else 3 end,ordinal for update loop';
begin select pg_get_functiondef(o) into d;
 if position(i in d)=0 then
  if position(a in d)=0 then raise exception 'PUBLIC_REGISTRATION_FAMILY_ORDER_ANCHOR_MISMATCH'; end if;
  n:=replace(d,a,i);execute n;
 end if;
end $patch$;
commit;
