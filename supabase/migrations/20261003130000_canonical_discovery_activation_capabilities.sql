begin;

create or replace function public.list_accessible_conferences(p_actor_device_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_conference public.conferences%rowtype;
  v_items jsonb:='[]'::jsonb;
  v_can_sync boolean;
  v_can_accommodation_manage boolean;
  v_can_transport_manage boolean;
begin
  perform public.require_current_approved_device(p_actor_device_id);
  for v_conference in select conferences.* from public.conferences conferences
    where conferences.deleted_at is null order by conferences.created_at,conferences.id loop
    begin
      perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.access.view','conference',v_conference.id::text);

      v_can_sync:=false;
      v_can_accommodation_manage:=false;
      v_can_transport_manage:=false;
      begin
        perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.sync.write','conference',v_conference.id::text);
        v_can_sync:=true;
      exception when insufficient_privilege then null;
      end;
      begin
        perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.accommodation.manage','conference',v_conference.id::text);
        v_can_accommodation_manage:=true;
      exception when insufficient_privilege then null;
      end;
      begin
        perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.transport.manage','conference',v_conference.id::text);
        v_can_transport_manage:=true;
      exception when insufficient_privilege then null;
      end;

      v_items:=v_items||jsonb_build_array(jsonb_build_object(
        'conferenceId',v_conference.id,'organizationId',v_conference.organization_id,
        'name',v_conference.name,'startDate',v_conference.start_date,'endDate',v_conference.end_date,
        'status',v_conference.status,'completedAt',v_conference.completed_at,'revision',v_conference.revision,
        'createdAt',v_conference.created_at,'updatedAt',v_conference.updated_at,
        'capabilities',jsonb_build_object(
          'edit',v_can_sync and v_can_accommodation_manage and v_can_transport_manage,
          'sync',v_can_sync)));
    exception when insufficient_privilege then null;
    end;
  end loop;
  return jsonb_build_object('conferences',v_items);
end $$;

revoke all on function public.list_accessible_conferences(uuid) from public,anon,authenticated,service_role;

comment on function public.list_accessible_conferences(uuid) is
'Canonical Conference discovery plus transitional activation capabilities. Visibility requires conference.access.view; sync and the shared edit gate derive independently from exact canonical permissions.';

commit;
