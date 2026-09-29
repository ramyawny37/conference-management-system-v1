begin;

do $$ begin
  if to_regclass('public.conferences') is null
     or to_regprocedure('public.require_current_approved_device(uuid)') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)') is null then
    raise exception 'CANONICAL_CONFERENCE_DISCOVERY_PREREQUISITE_REQUIRED' using errcode='55000';
  end if;
end $$;

create function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_conference public.conferences%rowtype; v_items jsonb:='[]'::jsonb;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences
    where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);
      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'conferenceId',v_conference.id,'organizationId',v_conference.organization_id,
        'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,
        'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,
        'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at));
    exception when insufficient_privilege then null;
    end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

revoke all on function public.list_accessible_conferences(uuid) from public,anon,authenticated,service_role;

do $$
declare v_signature regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;
  v_definition text; v_marker text:='if p_operation=''get_conference_core'' then';
  v_branch text:='if p_operation=''list_accessible_conferences'' then perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]); return public.list_accessible_conferences(p_actor_device_id); elsif p_operation=''get_conference_core'' then';
  v_occurrences integer;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''list_accessible_conferences''' in v_definition)<>0 then raise exception 'P6I_B1_CONFERENCE_DISCOVERY_ROUTE_ALREADY_EXISTS' using errcode='55000'; end if;
  v_occurrences:=(length(v_definition)-length(replace(v_definition,v_marker,'')))/length(v_marker);
  if v_occurrences<>1 then raise exception 'P6I_B1_CANONICAL_ROUTER_PRECONDITION_FAILED' using errcode='55000'; end if;
  execute replace(v_definition,v_marker,v_branch);
  v_definition:=pg_get_functiondef(v_signature);
  if position('p_operation=''list_accessible_conferences''' in v_definition)=0 or position('public.list_accessible_conferences(p_actor_device_id)' in v_definition)=0 then raise exception 'P6I_B1_CANONICAL_ROUTER_POSTCONDITION_FAILED' using errcode='55000'; end if;
end $$;

comment on function public.list_accessible_conferences(uuid) is
'Canonical Conference discovery through the validated Platform device-session router. Visibility reuses exact conference.access.view resolution and never derives from Conference membership or snapshots.';

commit;
