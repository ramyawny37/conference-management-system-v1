begin;
do $$
declare v_definition text;
begin
 select pg_get_functiondef('public.create_canonical_conference(uuid,uuid,uuid,uuid,text,date,date)'::regprocedure) into v_definition;
 if position('public.module_permission_grants' in v_definition)=0 then
   raise exception 'CONFERENCE_CREATOR_GRANT_PREDECESSOR_MISMATCH' using errcode='55000';
 end if;
 v_definition:=replace(v_definition,
 $old$select 1 from public.module_permission_grants grants
        where grants.user_id=v_actor and grants.module_key='conference'
          and grants.permission_key=expected.permission_key
          and grants.resource_type='conference'
          and grants.resource_id=p_requested_conference_id::text
          and grants.revoked_at is null$old$,
 $new$select 1 from platform.permission_grants grants
        join platform.permissions permission on permission.id=grants.permission_id
        where grants.user_id=v_actor and permission.domain='conference'
          and permission.code=expected.permission_key
          and grants.scope_type='resource'
          and grants.resource_type='conference'
          and grants.resource_id=p_requested_conference_id::text
          and grants.revoked_at is null$new$);
 v_definition:=replace(v_definition,
 $old$insert into public.module_permission_grants(
      user_id,module_key,permission_key,resource_type,resource_id,
      granted_by,granted_by_device_id
    ) values(
      v_actor,'conference',v_permission,'conference',p_requested_conference_id::text,
      v_actor,p_actor_device_id
    ) returning grant_id into v_grant_id;$old$,
 $new$insert into platform.permission_grants(
      user_id,permission_id,scope_type,resource_type,resource_id,granted_by,metadata
    )
    select v_actor,permission.id,'resource','conference',p_requested_conference_id::text,
      v_actor,jsonb_build_object('source','conference_creator','actorDeviceId',p_actor_device_id)
    from platform.permissions permission
    where permission.domain='conference' and permission.code=v_permission and permission.status='active'
    returning id into v_grant_id;$new$);
 if position('public.module_permission_grants' in v_definition)>0 then
   raise exception 'CONFERENCE_CREATOR_GRANT_CUTOVER_INCOMPLETE' using errcode='55000';
 end if;
 execute v_definition;
end $$;
commit;