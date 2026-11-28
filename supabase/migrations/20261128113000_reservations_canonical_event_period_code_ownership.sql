begin;

do $rewrite$
declare definition text; original text;
begin
  definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  original:=definition;

  definition:=replace(definition,
    'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_event_id'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');

  definition:=replace(definition,
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');

  definition:=replace(definition,
    'select * into v_event from reservations.events where id=(v_context->>''eventId'')::uuid and scope_partition_id=(v_context->>''scopePartitionId'')::uuid for key share; if ((coalesce(p_args->>''p_kind'','''')!~''^[a-z][a-z0-9_-]{0,39}$'' or length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120) or length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120)',
    'select * into v_event from reservations.events where id=(v_context->>''eventId'')::uuid and scope_partition_id=(v_context->>''scopePartitionId'')::uuid for update; if length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120');

  definition:=replace(definition,
    'if ((coalesce(p_args->>''p_kind'','''')!~''^[a-z][a-z0-9_-]{0,39}$'' or length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120) or length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120)',
    'if length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120');

  definition:=replace(definition,
    'values(v_event.scope_partition_id,v_event.id,p_args->>''p_kind'',btrim(p_args->>''p_label''),(p_args->>''p_starts_on'')::date',
    'values(v_event.scope_partition_id,v_event.id,(select 'period_'||(coalesce(max((pg_catalog.regexp_match(existing.kind,'^period_([0-9]+),btrim(p_args->>''p_label''),(p_args->>''p_starts_on'')::date');

  definition:=replace(definition,
    'update reservations.event_periods set kind=p_args->>''p_kind'',label=btrim(p_args->>''p_label''),starts_on=',
    'update reservations.event_periods set label=btrim(p_args->>''p_label''),starts_on=');

  if definition=original
     or position('pg_catalog.regexp_match(existing.kind,''^period_([0-9]+)
     or position('set kind=p_args->>''p_kind''' in definition)>0
     or position('''p_event_id'',''p_kind'',''p_label''' in definition)>0
     or position('''p_expected_revision'',''p_kind'',''p_label''' in definition)>0 then
    raise exception 'RESERVATIONS_CANONICAL_PERIOD_CODE_REWRITE_INCOMPLETE' using errcode='55000';
  end if;
  execute definition;
end $rewrite$;

do $dispatcher$
declare definition text; original text;
begin
  definition:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
  original:=definition;
  definition:=replace(definition,
    'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_event_id'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');
  definition:=replace(definition,
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');
  if definition=original
     or position('''p_event_id'',''p_kind'',''p_label''' in definition)>0
     or position('''p_expected_revision'',''p_kind'',''p_label''' in definition)>0 then
    raise exception 'PLATFORM_CANONICAL_PERIOD_CODE_REWRITE_INCOMPLETE' using errcode='55000';
  end if;
  execute definition;
end $dispatcher$;

commit;
