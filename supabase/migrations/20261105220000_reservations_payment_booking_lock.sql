-- Serialize payment recording with booking apology on the same canonical booking row.
do $$
declare definition text; patched text; before_guard text; select_anchor text; after_guard text;
begin
 definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 before_guard:='if exists(select 1 from reservations.bookings where id=(p_args->>''p_booking_id'')::uuid and lifecycle_status<>''active'') then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if; ';
 select_anchor:='for key share; if not found then raise exception ''RESERVATIONS_BOOKING_NOT_FOUND'' using errcode=''P0002''; end if;';
 after_guard:='if v_booking.lifecycle_status<>''active'' then raise exception ''RESERVATIONS_BOOKING_APOLOGIZED_IMMUTABLE'' using errcode=''55000''; end if;';
 if position('for update; if not found then raise exception ''RESERVATIONS_BOOKING_NOT_FOUND'' using errcode=''P0002''; end if; '||after_guard in definition)>0 then return; end if;
 if position(before_guard in definition)=0 or position(select_anchor in definition)=0 then raise exception 'PAYMENT_BOOKING_LOCK_CONTRACT_DRIFT'; end if;
 patched:=replace(definition,before_guard,'');
 patched:=replace(patched,select_anchor,'for update; if not found then raise exception ''RESERVATIONS_BOOKING_NOT_FOUND'' using errcode=''P0002''; end if; '||after_guard);
 if patched=definition then raise exception 'PAYMENT_BOOKING_LOCK_NOT_INSTALLED'; end if;
 execute patched;
end $$;
