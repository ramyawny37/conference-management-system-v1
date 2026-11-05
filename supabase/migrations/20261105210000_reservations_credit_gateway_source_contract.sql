-- Align canonical device gateway credit redemption arguments with source-allocated credit contract.
-- Idempotent, fail-closed migration: no alternative writer or permission changes.
do $$
declare definition text; rewritten text;
begin
 definition:=pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
 if position('when ''redeem_person_credit'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_event_id'',''p_person_id'',''p_settlement_id'',''p_expected_revision'',''p_amount'',''p_reason''])' in definition)>0 then return; end if;
 if position('when ''redeem_person_credit'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_event_id'',''p_person_id'',''p_expected_revision'',''p_amount'',''p_reason''])' in definition)=0 then raise exception 'CREDIT_GATEWAY_CONTRACT_DRIFT'; end if;
 rewritten:=replace(definition,
 'when ''redeem_person_credit'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_event_id'',''p_person_id'',''p_expected_revision'',''p_amount'',''p_reason''])',
 'when ''redeem_person_credit'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_event_id'',''p_person_id'',''p_settlement_id'',''p_expected_revision'',''p_amount'',''p_reason''])');
 execute rewritten;
end $$;
