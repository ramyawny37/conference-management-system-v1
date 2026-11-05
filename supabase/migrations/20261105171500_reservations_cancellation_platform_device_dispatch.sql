-- Development-only canonical reservations dispatch integration.
-- The gateway validates exact keys before forwarding to existing scoped operations.
do $$
declare source_sql text;
begin
  source_sql := pg_get_functiondef('platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)'::regprocedure);
  if position('when ''cancel_booking'' then' in source_sql) > 0 then return; end if;
  if position('when ''delete_booking'' then' in source_sql) = 0 then
    raise exception 'RESERVATIONS_DISPATCH_CONTRACT_DRIFT';
  end if;
  source_sql := replace(source_sql,
    'when ''delete_booking'' then',
    'when ''cancel_booking'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_booking_id'',''p_expected_revision'',''p_reason'',''p_non_refundable_amount'',''p_refunded_amount'',''p_credit_amount'',''p_pending_refund_amount'']); when ''redeem_person_credit'' then perform platform_private.require_exact_jsonb_keys(p_args,array[''p_operation_id'',''p_event_id'',''p_person_id'',''p_expected_revision'',''p_amount'',''p_reason'']); when ''get_cancellation_financial_summary'' then perform platform_private.require_exact_jsonb_keys(p_args,case when p_args ? ''p_event_id'' then array[''p_event_id''] else array[]::text[] end); when ''delete_booking'' then');
  source_sql := replace(source_sql,
    '''get_booking_accommodation'' then',
    '''get_booking_accommodation'',''get_booking_settlement'' then');
  source_sql := replace(source_sql,
    '''get_report_booking_page'') then',
    '''get_report_booking_page'',''get_booking_settlement'',''get_cancellation_financial_summary'') then');
  execute source_sql;
end $$;
