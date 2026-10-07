begin;

create or replace function platform_private.require_resource_lease_writer(
 p_actor_device_id uuid,p_module_id text,p_resource_type text,p_resource_id text,p_scope text
) returns uuid language plpgsql security definer set search_path='' as $$
declare authority jsonb; actor_id uuid; permission_key text; room_uuid uuid;
begin
 if p_actor_device_id is null or p_resource_id is null or btrim(p_resource_id)='' then
   raise exception 'PLATFORM_RESOURCE_LEASE_ARGUMENT_INVALID' using errcode='22023';
 end if;
 permission_key:=platform_private.resource_lease_permission_key(p_module_id,p_resource_type,p_scope);
 if p_module_id='conference' and p_resource_type='accommodation_room' then
   if p_resource_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
     raise exception 'PLATFORM_RESOURCE_LEASE_RESOURCE_INVALID' using errcode='22023';
   end if;
   room_uuid:=p_resource_id::uuid;
   if not exists (select 1 from public.conference_accommodation_rooms where id=room_uuid) then
     raise exception 'ACCOMMODATION_ROOM_NOT_FOUND' using errcode='P0002';
   end if;
 end if;
 authority:=public.require_effective_module_permission(
   p_actor_device_id,p_module_id,permission_key,p_resource_type,p_resource_id
 );
 actor_id:=nullif(authority->>'actorUserId','')::uuid;
 if actor_id is null then raise exception 'PLATFORM_RESOURCE_LEASE_AUTHORITY_INVALID' using errcode='42501'; end if;
 return actor_id;
end $$;

revoke all on function platform_private.require_resource_lease_writer(uuid,text,text,text,text) from public,anon,authenticated;

commit;
