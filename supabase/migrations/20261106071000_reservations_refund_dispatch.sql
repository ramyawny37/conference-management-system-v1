do $$
declare definition text; anchor text;
begin
 definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
 anchor:='if p_operation=''cancel_booking'' then return reservations_private.cancel_booking_scoped(p_device_id,p_args); end if;';
 if position('if p_operation=''disburse_refund'' then' in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'REFUND_DISPATCH_ANCHOR_DRIFT'; end if;
 execute replace(definition,anchor,anchor||E'\n if p_operation=''disburse_refund'' then return reservations_private.disburse_refund_scoped(p_device_id,p_args); end if;');
end $$;