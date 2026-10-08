begin;
create or replace function platform_private.require_accommodation_operation_leases(p_device uuid,p_conference uuid,p_operation text,p_args jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_source uuid; v_destination uuid; v_room uuid; v_token uuid; v_expected uuid[]; v_supplied uuid[]:=array[]::uuid[]; v_item jsonb;
begin
 if jsonb_typeof(p_args->'p_room_lease_tokens') is distinct from 'array' then
  raise exception 'ROOM_LEASE_TOKENS_REQUIRED' using errcode='42501';
 end if;
 if p_operation in ('move_conference_accommodation','remove_conference_accommodation') then
  select o.room_id into v_source from public.conference_accommodation_occupancies o
  where o.id=(p_args->>'p_occupancy_id')::uuid and o.conference_id=p_conference;
  if v_source is null then raise exception 'ACCOMMODATION_OCCUPANCY_NOT_FOUND' using errcode='22023'; end if;
 end if;
 if p_operation in ('assign_conference_accommodation','move_conference_accommodation') then
  v_destination:=(p_args->>'p_room_id')::uuid;
 end if;
 select array_agg(distinct room_id order by room_id) into v_expected
 from unnest(array[v_source,v_destination]) as room_id where room_id is not null;
 for v_item in select value from jsonb_array_elements(p_args->'p_room_lease_tokens') loop
  if jsonb_typeof(v_item) <> 'object' or
   (select count(*) from jsonb_object_keys(v_item))<>2 or
   not(v_item ? 'roomId' and v_item ? 'token') then
   raise exception 'ROOM_LEASE_TOKEN_INVALID' using errcode='22023';
  end if;
  v_room:=(v_item->>'roomId')::uuid;v_token:=(v_item->>'token')::uuid;
  if v_room=any(v_supplied) then raise exception 'ROOM_LEASE_DUPLICATE' using errcode='22023'; end if;
  v_supplied:=array_append(v_supplied,v_room);
 end loop;
 select array_agg(x order by x) into v_supplied from unnest(v_supplied) x;
 if v_expected is null or v_expected is distinct from v_supplied then
  raise exception 'ROOM_LEASE_SCOPE_MISMATCH' using errcode='42501';
 end if;
 for v_item in select value from jsonb_array_elements(p_args->'p_room_lease_tokens') order by value->>'roomId' loop
  perform platform_private.require_conference_room_lease(p_device,p_conference,(v_item->>'roomId')::uuid,(v_item->>'token')::uuid);
 end loop;
end $$;
revoke all on function platform_private.require_accommodation_operation_leases(uuid,uuid,text,jsonb) from public,anon,authenticated;
commit;