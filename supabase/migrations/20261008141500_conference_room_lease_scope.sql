begin;
create or replace function platform_private.require_conference_room_lease(
 p_actor_device_id uuid,p_conference_id uuid,p_room_id uuid,p_lease_token uuid
) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_conference_id is null or p_room_id is null
  or not exists(select 1 from public.conference_accommodation_rooms r
    where r.id=p_room_id and r.conference_id=p_conference_id) then
  raise exception 'ACCOMMODATION_ROOM_CONFERENCE_MISMATCH' using errcode='42501';
 end if;
 perform platform_private.require_owned_accommodation_room_lease(
  p_actor_device_id,p_room_id,p_lease_token
 );
end $$;
revoke all on function platform_private.require_conference_room_lease(uuid,uuid,uuid,uuid)
 from public,anon,authenticated;
commit;