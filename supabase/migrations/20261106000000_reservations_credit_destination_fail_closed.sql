-- Prevent unallocated credit consumption until the canonical payment writer
-- can atomically record the destination booking and the source credit debit.
do $$
declare definition text; patched text; anchor text; guard text;
begin
 definition:=pg_get_functiondef('reservations_private.redeem_person_credit_scoped(uuid,jsonb)'::regprocedure);
 anchor:='context:=reservations_private.resolve_event_scope(';
 guard:='raise exception ''RESERVATIONS_CREDIT_DESTINATION_REQUIRED'' using errcode=''55000''; ';
 if position(guard||anchor in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'CREDIT_REDEMPTION_CONTRACT_DRIFT'; end if;
 patched:=replace(definition,anchor,guard||anchor);
 if patched=definition then raise exception 'CREDIT_REDEMPTION_GUARD_NOT_INSTALLED'; end if;
 execute patched;
end $$;
