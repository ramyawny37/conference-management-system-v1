
do $migration$
declare
  definition text;
  create_marker text := 'select * into v_event from reservations.events where id=(v_context->>''eventId'')::uuid and scope_partition_id=(v_context->>''scopePartitionId'')::uuid for key share; insert into reservations.booking_types';
  create_replacement text := 'select * into v_event from reservations.events where id=(v_context->>''eventId'')::uuid and scope_partition_id=(v_context->>''scopePartitionId'')::uuid for key share; if jsonb_typeof(p_args->''p_eligible_attendance_segments'') is distinct from ''array'' or jsonb_array_length(p_args->''p_eligible_attendance_segments'')=0 or exists(select 1 from jsonb_array_elements_text(p_args->''p_eligible_attendance_segments'') segment(value) where not exists(select 1 from reservations.event_periods period where period.event_id=v_event.id and period.scope_partition_id=v_event.scope_partition_id and period.kind=segment.value)) then raise exception ''RESERVATIONS_BOOKING_TYPE_PERIOD_INVALID'' using errcode=''23514''; end if; insert into reservations.booking_types';
  update_marker text := 'if v_type.revision<>(p_args->>''p_expected_revision'')::bigint then raise exception ''RESERVATIONS_REVISION_CONFLICT'' using errcode=''40001''; end if;
  update reservations.booking_types';
  update_replacement text := 'if v_type.revision<>(p_args->>''p_expected_revision'')::bigint then raise exception ''RESERVATIONS_REVISION_CONFLICT'' using errcode=''40001''; end if; if jsonb_typeof(p_args->''p_eligible_attendance_segments'') is distinct from ''array'' or jsonb_array_length(p_args->''p_eligible_attendance_segments'')=0 or exists(select 1 from jsonb_array_elements_text(p_args->''p_eligible_attendance_segments'') segment(value) where not exists(select 1 from reservations.event_periods period where period.event_id=v_type.event_id and period.scope_partition_id=v_type.scope_partition_id and period.kind=segment.value)) then raise exception ''RESERVATIONS_BOOKING_TYPE_PERIOD_INVALID'' using errcode=''23514''; end if;
  update reservations.booking_types';
begin
  definition := pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if position('RESERVATIONS_BOOKING_TYPE_PERIOD_INVALID' in definition)>0 then
    return;
  end if;
  if position(create_marker in definition)=0 or position(update_marker in definition)=0 then
    raise exception 'RESERVATIONS_BOOKING_TYPE_PERIOD_CONTRACT_SHAPE_CHANGED';
  end if;
  definition := replace(definition,create_marker,create_replacement);
  definition := replace(definition,update_marker,update_replacement);
  execute definition;
end
$migration$;

;
