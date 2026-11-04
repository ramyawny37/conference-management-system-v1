-- Canonical create_booking replay must be checked before a consumed identity token.
-- Preserve the existing begin_operation authorization, scope and intent contract.
do $migration$
declare
  definition text;
  lock_anchor text := 'perform pg_advisory_xact_lock(hashtextextended(''reservations-person-name:''';
  late_anchor text := 'v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; v_number:=reservations_private.allocate_booking_number';
  replay_clause text := 'v_replay:=reservations_private.begin_operation(v_operation_id,v_context,p_operation,p_args); if v_replay is not null then return v_replay; end if; ';
begin
  definition := pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  if (length(definition)-length(replace(definition,lock_anchor,'')))/length(lock_anchor) <> 1
     or (length(definition)-length(replace(definition,late_anchor,'')))/length(late_anchor) <> 1
     or position(lock_anchor in definition) >= position(late_anchor in definition)
     or position('RESERVATIONS_PERSON_IDENTITY_RESOLUTION_STALE' in definition) <= position(lock_anchor in definition) then
    raise exception 'RESERVATIONS_IDENTITY_REPLAY_CONTRACT_DRIFT';
  end if;
  definition := replace(definition,lock_anchor,replay_clause||lock_anchor);
  definition := replace(definition,late_anchor,'v_number:=reservations_private.allocate_booking_number');
  execute definition;
end
$migration$;
