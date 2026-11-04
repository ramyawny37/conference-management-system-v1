begin;

-- Reservations keeps booking-time demographic snapshots, while current gender
-- and birth date remain owned by platform.people.  This read-only projection
-- overlays only those current Person fields and stores no duplicate facts.
create or replace view reservations.participants_canonical
with (security_invoker=true) as
select participant.*,person.gender,person.date_of_birth,
  case when exists(
    select 1 from public.conference_participations participation
    join reservations.events event on event.conference_id=participation.conference_id
      and event.scope_partition_id=participant.scope_partition_id
    where participation.person_id=participant.person_id
      and participation.guardian_participation_id is not null
  ) then 'child' else 'adult' end operational_category
from reservations.participants participant
left join platform.people person on person.id=participant.person_id;

revoke all on reservations.participants_canonical from public,anon,authenticated,service_role;

do $read_projection$
declare definition text; rewritten text;
begin
  definition:=pg_get_functiondef('reservations_private.read_scoped(uuid,text,jsonb)'::regprocedure);
  rewritten:=replace(definition,'reservations.participants p','reservations.participants_canonical p');
  if rewritten=definition or position('reservations.participants p' in rewritten)>0 then
    raise exception 'RESERVATIONS_CANONICAL_PERSON_READ_SHAPE_CHANGED' using errcode='55000';
  end if;
  execute rewritten;
end
$read_projection$;

create or replace function public.list_conference_participations(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_context jsonb; v_items jsonb; v_total bigint; v_active bigint; v_apologized bigint;
begin
  v_context:=platform_private.require_conference_participation_context(p_actor_device_id,p_conference_id,'conference.people.view',false);
  select count(*),count(*) filter(where participation.status='active'),count(*) filter(where participation.status='apologized'),
    coalesce(jsonb_agg(jsonb_build_object('participationId',participation.id,'conferenceId',participation.conference_id,
      'personId',participation.person_id,'status',participation.status,'revision',participation.revision,
      'guardianParticipationId',guardian.id,'guardianPersonId',guardian_person.id,'guardianFullName',guardian_person.full_name,
      'guardianParticipationStatus',guardian.status,'createdAt',participation.created_at,'updatedAt',participation.updated_at,
      'createdBy',participation.created_by,'updatedBy',participation.updated_by,
      'person',jsonb_build_object('personId',person.id,'fullName',person.full_name,'phone',person.phone,
        'gender',person.gender,'dateOfBirth',person.date_of_birth,'church',person.church),
      'bookings',coalesce(booking_links.items,'[]'::jsonb)) order by participation.created_at,participation.id),'[]'::jsonb)
  into v_total,v_active,v_apologized,v_items
  from public.conference_participations participation
  join platform.people person on person.id=participation.person_id
  left join public.conference_participations guardian on guardian.id=participation.guardian_participation_id
  left join platform.people guardian_person on guardian_person.id=guardian.person_id
  left join lateral(
    select jsonb_agg(jsonb_build_object('bookingId',booking.id,'bookingNumber',booking.booking_number,
      'bookingTypeId',booking.booking_type_id,
      'bookingTypeNameSnapshot',booking.booking_type_name_snapshot,'priceSnapshot',booking.price_snapshot,
      'attendanceSegmentsSnapshot',booking.attendance_segments_snapshot,
      'attendancePeriods',(
        select coalesce(jsonb_agg(jsonb_build_object('kind',segment.kind,'label',coalesce(period.label,segment.kind)) order by segment.ordinality),'[]'::jsonb)
        from unnest(booking.attendance_segments_snapshot) with ordinality segment(kind,ordinality)
        left join reservations.event_periods period on period.event_id=booking.event_id and period.scope_partition_id=booking.scope_partition_id and period.kind=segment.kind
      ),'createdAt',booking.created_at)
      order by booking.created_at desc,booking.id desc) items
    from reservations.events event
    join reservations.bookings booking on booking.event_id=event.id and booking.scope_partition_id=event.scope_partition_id
    join reservations.participants reservation_participant on reservation_participant.id=booking.participant_id and reservation_participant.scope_partition_id=booking.scope_partition_id
    where event.conference_id=p_conference_id and reservation_participant.person_id=participation.person_id
  ) booking_links on true
  where participation.conference_id=p_conference_id;
  return jsonb_build_object('conferenceId',p_conference_id,'totalCount',v_total,'activeCount',v_active,'apologizedCount',v_apologized,'items',v_items);
end $$;

revoke all on function public.list_conference_participations(uuid,uuid) from public,anon,authenticated,service_role;

commit;
;
