begin;
do $migration$
declare d text; marker text; replacement text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='platform_private' and p.proname='route_canonical_conference_operation';
 if d is null then raise exception 'CANONICAL_DISPATCH_NOT_FOUND'; end if;
 marker:='then return public.mutate_conference_accommodation_structure(p_actor_device_id,replace(p_operation,''_accommodation_'',''_''),p_args);';
 if (length(d)-length(replace(d,marker,'')))<>length(marker) then
  raise exception 'ROOM_STRUCTURE_DISPATCH_MARKER_NOT_UNIQUE';
 end if;
 replacement:=$body$then
  if p_operation in ('update_accommodation_room','delete_accommodation_room') then
   if jsonb_typeof(p_args->'p_room_lease_tokens') is distinct from 'array'
      or jsonb_array_length(p_args->'p_room_lease_tokens')<>1 then
    raise exception 'ROOM_LEASE_TOKENS_REQUIRED' using errcode='42501';
   end if;
   if jsonb_typeof(p_args->'p_room_lease_tokens'->0) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(p_args->'p_room_lease_tokens'->0))<>2
      or not ((p_args->'p_room_lease_tokens'->0) ? 'roomId' and (p_args->'p_room_lease_tokens'->0) ? 'token')
      or (p_args->'p_room_lease_tokens'->0->>'roomId') is distinct from (p_args->>'p_room_id') then
    raise exception 'ROOM_LEASE_SCOPE_MISMATCH' using errcode='42501';
   end if;
   perform platform_private.require_conference_room_lease(
    p_actor_device_id,(p_args->>'p_conference_id')::uuid,(p_args->>'p_room_id')::uuid,
    (p_args->'p_room_lease_tokens'->0->>'token')::uuid);
   return public.mutate_conference_accommodation_structure(
    p_actor_device_id,replace(p_operation,'_accommodation_','_'),p_args-'p_room_lease_tokens');
  end if;
  return public.mutate_conference_accommodation_structure(p_actor_device_id,replace(p_operation,'_accommodation_','_'),p_args);$body$;
 d:=replace(d,marker,replacement);
 execute d;
end $migration$;
commit;
