begin;

create index event_guardian_children_event_idx
  on reservations.event_guardian_children(scope_partition_id,event_id);
create index event_guardian_children_booking_idx
  on reservations.event_guardian_children(scope_partition_id,child_booking_id)
  where child_booking_id is not null;
create index event_guardian_children_guardian_person_idx
  on reservations.event_guardian_children(guardian_person_id);
create index event_guardian_children_child_person_idx
  on reservations.event_guardian_children(child_person_id);
create index event_guardian_children_created_by_idx
  on reservations.event_guardian_children(created_by);

commit;
