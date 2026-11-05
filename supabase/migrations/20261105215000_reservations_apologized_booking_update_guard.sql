-- Guard the canonical booking update against changes after apology.
do $$
declare definition text; patched text; anchor text; guard text;
begin
 definition := pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 anchor := 'if v_booking.revision<>(p_args->>''p_expected_revision'')::bigint then raise exception ''RESERVATIONS_REVISION_CONFLICT'' using errcode=''40001''; end if;';
 guard := 'if v_booking.lifecycle_status<>''active'' then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;';
 if position(anchor||' '||guard in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'BOOKING_UPDATE_CONTRACT_DRIFT'; end if;
 patched := replace(definition,anchor,anchor||' '||guard);
 if patched=definition then raise exception 'BOOKING_UPDATE_GUARD_NOT_INSTALLED'; end if;
 execute patched;
end $$;
