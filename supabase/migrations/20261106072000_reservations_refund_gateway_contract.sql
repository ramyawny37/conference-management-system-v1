do $$
declare definition text; anchor text;
begin
 definition:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
 anchor:='when ''cancel_booking'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_reason'',''p_non_refundable_amount'',''p_refunded_amount'',''p_credit_amount'',''p_pending_refund_amount'']);';
 if position('when ''disburse_refund'' then' in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'REFUND_GATEWAY_CONTRACT_DRIFT'; end if;
 execute replace(definition,anchor,anchor||E'\n    when ''disburse_refund'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_booking_id'',''p_amount'',''p_disbursed_on'',''p_payment_method'',''p_payment_method_other'',''p_reference'',''p_reason'']);');
end $$;