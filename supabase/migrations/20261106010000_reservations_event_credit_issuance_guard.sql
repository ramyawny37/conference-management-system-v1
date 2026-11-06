-- Fail closed on credit issuance while the legacy account is partition-scoped,
-- not event-scoped. Preserve cash refunds and pending refunds.
do $$
declare definition text; patched text; anchor text; guard text;
begin
 definition:=pg_get_functiondef('reservations_private.cancel_booking_scoped(uuid,jsonb)'::regprocedure);
 anchor:='pending:=coalesce((p_args->>''p_pending_refund_amount'')::numeric,0);';
 guard:='if credited>0 then raise exception ''RESERVATIONS_EVENT_CREDIT_ISOLATION_REQUIRED'' using errcode=''55000''; end if;';
 if position(anchor||E'\n  '||guard in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'CANCELLATION_CREDIT_ALLOCATION_CONTRACT_DRIFT'; end if;
 patched:=replace(definition,anchor,anchor||E'\n  '||guard);
 if patched=definition then raise exception 'EVENT_CREDIT_GUARD_NOT_INSTALLED'; end if;
 execute patched;
end $$;
