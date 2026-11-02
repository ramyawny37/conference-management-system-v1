begin;

-- Align the outer device dispatcher with the canonical reservations mutation contract.
-- The inner update identifies the event through the period ID and its scoped row.
-- No permissions, device authentication, or reservation mutation logic is replaced.
do $align$
declare
  v_definition text;
  v_original text;
  v_create_old text := 'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_starts_on'',''p_ends_on'',''p_display_order'']';
  v_create_new text := 'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']';
  v_update_old text := 'array[''p_operation_id'',''p_event_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_starts_on'',''p_ends_on'',''p_display_order'']';
  v_update_new text := 'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']';
begin
  v_definition := pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
  v_original := v_definition;
  if position(v_create_old in v_definition)=0 or position(v_update_old in v_definition)=0 then
    raise exception 'RESERVATIONS_PERIOD_OUTER_DISPATCH_SHAPE_CHANGED' using errcode='55000';
  end if;
  v_definition := replace(v_definition,v_create_old,v_create_new);
  v_definition := replace(v_definition,v_update_old,v_update_new);
  if v_definition=v_original then
    raise exception 'RESERVATIONS_PERIOD_OUTER_DISPATCH_NOT_CHANGED' using errcode='55000';
  end if;
  execute v_definition;
end $align$;

commit;
