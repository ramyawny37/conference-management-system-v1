begin;

create function public.list_conference_activity(p_actor_device_id uuid,p_conference_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform public.require_effective_module_permission(p_actor_device_id,'conference','conference.settings.view','conference',p_conference_id::text);
  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',e.id,'action',e.action,
    'section',case when e.action like 'conference.branding.%' then 'settings' when e.action like 'conference.accommodation.%' then 'accommodation' when e.action like 'conference.output.%' then 'cards' else 'conference' end,
    'title',case e.action
      when 'conference.branding.changed' then 'تم تعديل هوية المؤتمر'
      when 'conference.output.card_shared' then 'تمت مشاركة كارت'
      when 'conference.output.card_printed' then 'تمت طباعة كارت'
      when 'conference.output.cards_printed' then 'تمت طباعة الكروت'
      else 'تم تحديث بيانات المؤتمر' end,
    'createdAt',e.occurred_at
  ) order by e.occurred_at desc),'[]'::jsonb) into result
  from (select * from platform.audit_events where module='conference'
    and metadata->>'conferenceId'=p_conference_id::text
    and action in('conference.core.updated','conference.lifecycle.completed','conference.branding.changed','conference.participation.created','conference.participation.status_changed','conference.participation.guardian_changed','conference.participation.deleted','conference.accommodation.assigned','conference.accommodation.moved','conference.accommodation.removed','conference.accommodation.pricing_updated','conference.accommodation.pricing_room_excluded','conference.accommodation.pricing_room_included','conference.transport.assignment_set','conference.transport.assignment_removed','conference.restaurant.participation_override_removed','conference.air_conditioning.configuration_changed','conference.finance.changed','conference.output.card_shared','conference.output.card_printed','conference.output.cards_printed')
    order by occurred_at desc limit 200) e;
  return jsonb_build_object('conferenceId',p_conference_id,'items',result);
end $$;

create function public.record_conference_output_event(p_actor_device_id uuid,p_conference_id uuid,p_event text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ctx jsonb;session_ctx jsonb;actor uuid;authz uuid;event_id uuid;
begin
  if p_event not in('card_shared','card_printed','cards_printed') then raise exception 'CONFERENCE_OUTPUT_EVENT_INVALID' using errcode='22023';end if;
  session_ctx:=nullif(pg_catalog.current_setting('platform.phase1c_context',true),'')::jsonb;actor:=(session_ctx->>'user_id')::uuid;
  if session_ctx->>'purpose'<>'PLATFORM_DEVICE_SESSION_DISPATCH' or (session_ctx->>'device_id')::uuid is distinct from p_actor_device_id then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  authz:=platform_private.validated_phase1c_device_authorization(actor,p_actor_device_id);if authz is null then raise exception 'APPROVED_DEVICE_SESSION_REQUIRED' using errcode='42501';end if;
  ctx:=public.require_effective_module_permission(p_actor_device_id,'conference','conference.cards.export','conference',p_conference_id::text);
  insert into platform.audit_events(actor_user_id,actor_device_authorization_id,domain,module,action,entity_type,entity_id,scope_type,metadata,source)
  values(actor,authz,'platform','conference','conference.output.'||p_event,'conference',p_conference_id,'platform',jsonb_build_object('conferenceId',p_conference_id,'permissionKey','conference.cards.export','authoritySource',ctx->>'authoritySource','grantId',ctx->'grantId'),'rpc') returning id into event_id;
  return jsonb_build_object('recorded',true,'eventId',event_id);
end $$;

revoke all on function public.list_conference_activity(uuid,uuid),public.record_conference_output_event(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.list_conference_activity(uuid,uuid),public.record_conference_output_event(uuid,uuid,text) to service_role;

do $$ declare sig regprocedure:='platform_private.route_canonical_conference_operation(uuid,uuid,bytea,uuid,text,jsonb)'::regprocedure;d text;
  marker text:='if p_operation=''get_conference_branding'' then';
  branch text:='if p_operation=''list_conference_activity'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'']);return public.list_conference_activity(p_actor_device_id,(p_args->>''p_conference_id'')::uuid);elsif p_operation=''record_conference_output_event'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_conference_id'',''p_event'']);return public.record_conference_output_event(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,p_args->>''p_event'');elsif p_operation=''get_conference_branding'' then';
begin d:=pg_get_functiondef(sig);if position(marker in d)=0 then raise exception 'C1B_ROUTER_PRECONDITION_FAILED' using errcode='55000';end if;execute replace(d,marker,branch);end $$;

commit;
