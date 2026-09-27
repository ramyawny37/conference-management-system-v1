begin;

-- Stabilize event-derived ownership and every relationship used by the guards.
lock table reservations.events, reservations.booking_types,
  reservations.participants, reservations.bookings
in share row exclusive mode;

do $$
declare
  v_orphan boolean;
  v_partition boolean;
  v_conflict boolean;
  v_ambiguous boolean;
begin
  -- Start with affected legacy bookings, never the Event's whole type catalog.
  -- Validate every booking of their participants before assigning ownership.
  with target_bookings as (
    select b.* from reservations.bookings b
    join reservations.events e on e.id=b.event_id
    where b.organization_id is null and e.organization_id is not null
  ), target_participants as (
    select distinct participant_id id from target_bookings
  ), domain_bookings as (
    select b.* from reservations.bookings b
    where b.id in (select id from target_bookings)
       or b.participant_id in (select id from target_participants)
  ), relationships as (
    select b.id, b.organization_id booking_org, b.scope_partition_id booking_partition,
      e.id event_id, e.organization_id event_org, e.scope_partition_id event_partition,
      p.id participant_id, p.organization_id participant_org, p.scope_partition_id participant_partition,
      t.id type_id, t.event_id type_event, t.organization_id type_org, t.scope_partition_id type_partition
    from domain_bookings b
    left join reservations.events e on e.id=b.event_id
    left join reservations.participants p on p.id=b.participant_id
    left join reservations.booking_types t on t.id=b.booking_type_id
  )
  select
    exists(select 1 from relationships where event_id is null or participant_id is null or type_id is null),
    exists(select 1 from relationships where booking_partition is distinct from event_partition
      or participant_partition is distinct from booking_partition
      or type_partition is distinct from booking_partition),
    exists(select 1 from relationships where type_event is distinct from event_id
      or (booking_org is not null and booking_org is distinct from event_org)
      or (participant_org is not null and participant_org is distinct from event_org)
      or (type_org is not null and type_org is distinct from event_org)
      -- Assigning a shared participant/type would invalidate a standalone booking.
      or event_org is null),
    exists(select 1 from relationships where participant_id in (select id from target_participants)
      group by participant_id having count(distinct event_org)>1)
  into v_orphan,v_partition,v_conflict,v_ambiguous;

  if v_orphan then
    raise exception 'RESERVATIONS_LEGACY_ORGANIZATION_ORPHAN' using errcode='55000';
  end if;
  if v_ambiguous then
    raise exception 'RESERVATIONS_LEGACY_PARTICIPANT_ORGANIZATION_AMBIGUOUS' using errcode='55000';
  end if;
  if v_partition then
    raise exception 'RESERVATIONS_LEGACY_ORGANIZATION_PARTITION_MISMATCH' using errcode='55000';
  end if;
  if v_conflict then
    raise exception 'RESERVATIONS_LEGACY_ORGANIZATION_CONFLICT' using errcode='55000';
  end if;
end $$;

update reservations.booking_types d
set organization_id=e.organization_id
from reservations.bookings b
join reservations.events e on e.id=b.event_id
where b.organization_id is null
  and e.organization_id is not null
  and d.id=b.booking_type_id
  and d.event_id=b.event_id
  and d.scope_partition_id=b.scope_partition_id
  and b.scope_partition_id=e.scope_partition_id
  and d.organization_id is null;

with participant_ownership as (
  select p.id participant_id,min(e.organization_id::text)::uuid organization_id
  from reservations.participants p
  join reservations.bookings b on b.participant_id=p.id
  join reservations.events e on e.id=b.event_id
  where p.organization_id is null
    and e.organization_id is not null
    and exists (
      select 1 from reservations.bookings target
      join reservations.events authoritative on authoritative.id=target.event_id
      where target.participant_id=p.id
        and target.organization_id is null
        and authoritative.organization_id is not null
    )
  group by p.id
  having count(distinct e.organization_id)=1
)
update reservations.participants p
set organization_id=o.organization_id
from participant_ownership o
where p.id=o.participant_id
  and p.organization_id is null;

-- Repair bookings last so participant/type eligibility still sees the original
-- NULL-owned booking domain throughout this transaction.
update reservations.bookings d
set organization_id=e.organization_id
from reservations.events e
where e.id=d.event_id
  and d.organization_id is null
  and e.organization_id is not null;

commit;
