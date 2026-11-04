begin;

-- One verified session boundary and one module switch replace every historical
-- execute_device_operation_pre_* generation. Module routers remain the owners
-- of their permission, idempotency and revision rules.
create or replace function platform.execute_device_operation(
  p_user_id uuid,p_session_id uuid,p_token_hash bytea,
  p_module text,p_operation text,p_args jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','platform','platform_private','reservations','reservations_private','warehouse','warehouse_private' as $$
declare v_session platform_private.device_sessions%rowtype; v_result jsonb;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'PLATFORM_OPERATION_BACKEND_REQUIRED' using errcode='42501';
  end if;
  if p_user_id is null or p_session_id is null or octet_length(p_token_hash)<>32
     or p_module not in('platform','conference','reservations','warehouse')
     or p_args is null or jsonb_typeof(p_args)<>'object' then
    raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023';
  end if;
  if p_args ? 'p_actor_device_id' or p_args ? 'p_actor_user_id'
     or p_args ? 'actor_device_id' or p_args ? 'actor_user_id'
     or p_args ? 'device_id'
     or p_args ? 'scope_partition_id' or p_args ? 'p_scope_partition_id'
     or p_args ? 'p_conference_person_id' or p_args ? 'conference_person_id'
     or (p_args ? 'p_device_id' and not(
       p_module='platform' and p_operation='approve_pending_device_authorization'
     )) then
    raise exception 'ACTOR_DEVICE_OVERRIDE_DENIED' using errcode='22023';
  end if;

  select session.* into v_session
  from platform_private.device_sessions session
  join platform.device_key_bindings binding on binding.id=session.binding_id
  join platform.user_device_authorizations device_auth on device_auth.id=session.device_authorization_id
  join platform.devices device on device.id=session.device_id
  join platform.profiles profile on profile.user_id=session.user_id
  where session.id=p_session_id and session.user_id=p_user_id
    and session.token_hash=p_token_hash and session.purpose='PLATFORM_DEVICE_SESSION'
    and session.revoked_at is null and session.expires_at>statement_timestamp()
    and binding.user_id=session.user_id and binding.device_id=session.device_id
    and binding.device_authorization_id=session.device_authorization_id
    and binding.public_key_thumbprint=session.public_key_thumbprint
    and binding.algorithm='ECDSA_P256_SHA256' and binding.lifecycle_status='active'
    and binding.revoked_at is null and binding.retired_at is null
    and device_auth.user_id=session.user_id and device_auth.device_id=session.device_id
    and device_auth.status='approved' and device_auth.revoked_at is null
    and device.lifecycle_status='active' and device.retired_at is null
    and device.compromised_at is null and profile.account_status='approved';
  if not found then raise exception 'DEVICE_SESSION_INVALID' using errcode='42501'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',p_user_id,'role','service_role')::text,true);
  perform set_config('platform.phase1c_context',jsonb_build_object(
    'purpose','PLATFORM_DEVICE_SESSION_DISPATCH','session_id',v_session.id,
    'user_id',v_session.user_id,'device_id',v_session.device_id,
    'authorization_id',v_session.device_authorization_id,'binding_id',v_session.binding_id,
    'token_hash',encode(p_token_hash,'hex'))::text,true);

  if p_operation='check_module_access' then
    if p_module not in('conference','reservations','warehouse') then
      raise exception 'PLATFORM_OPERATION_NOT_ALLOWED' using errcode='42501';
    end if;
    perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    perform public.require_effective_module_permission(v_session.device_id,p_module,p_module||'.module.access',null,null);
    return jsonb_build_object('status','allowed','moduleKey',p_module);
  end if;

  if p_module='conference' then
    return platform.execute_conference_device_operation(
      p_user_id,p_session_id,p_token_hash,p_operation,p_args
    );
  end if;

  if p_module='platform' then
    case p_operation
    when 'get_user_management_actor_capabilities' then
      perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
      return public.get_user_management_actor_capabilities(v_session.device_id);
    when 'search_user_management_users' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_query','p_account_status','p_limit']);
      return public.search_user_management_users(v_session.device_id,p_args->>'p_query',p_args->>'p_account_status',(p_args->>'p_limit')::integer);
    when 'get_user_management_overview' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
      return public.get_user_management_overview(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
    when 'get_user_management_devices' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
      return public.get_user_management_devices(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
    when 'get_user_management_account' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id']);
      return public.get_user_management_account(v_session.device_id,(p_args->>'p_target_user_id')::uuid);
    when 'device_guarded_manage_system_user' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_target_user_id','p_operation_id','p_action'],array['p_requested_value']);
      return public.device_guarded_manage_system_user(v_session.device_id,(p_args->>'p_target_user_id')::uuid,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',case when p_args ? 'p_requested_value' then (p_args->>'p_requested_value')::boolean end);
    when 'list_pending_device_authorizations' then
      perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
      return platform.list_pending_device_authorizations();
    when 'approve_pending_device_authorization' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_authorization_id','p_device_id','p_reason']);
      return platform.approve_pending_device_authorization((p_args->>'p_authorization_id')::uuid,(p_args->>'p_device_id')::uuid,p_args->>'p_reason');
    when 'apply_library_template_content_operation' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_template_type','p_template_id','p_action','p_base_revision','p_payload']);
      return public.apply_library_template_content_operation(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_template_type',p_args->>'p_template_id',p_args->>'p_action',(p_args->>'p_base_revision')::bigint,p_args->'p_payload');
    when 'list_module_permission_grants' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_target_user_id']);
    when 'search_module_permission_candidates' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_query','p_limit']);
    when 'list_module_permission_catalog_for_administration' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key']);
    when 'list_module_permission_resources_for_administration' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_module_key','p_resource_type']);
    when 'manage_catalog_module_grant' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_action','p_target_user_id','p_module_key','p_permission_key','p_resource_type','p_resource_id','p_grant_id','p_revocation_reason']);
    when 'manage_foundation_module_grant' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_action','p_target_user_id','p_module_key','p_permission_key','p_grant_id','p_revocation_reason']);
      return public.manage_foundation_module_grant(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_action',(p_args->>'p_target_user_id')::uuid,p_args->>'p_module_key',p_args->>'p_permission_key',(p_args->>'p_grant_id')::uuid,p_args->>'p_revocation_reason');
    when 'recover_revoke_final_module_manager' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_module_key','p_target_user_id','p_target_grant_id','p_recovery_reason']);
      return public.recover_revoke_final_module_manager(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_module_key',(p_args->>'p_target_user_id')::uuid,(p_args->>'p_target_grant_id')::uuid,p_args->>'p_recovery_reason');
    else raise exception 'PLATFORM_OPERATION_NOT_ALLOWED' using errcode='42501';
    end case;
    return platform_private.route_permission_administration(p_user_id,p_operation,p_args);
  end if;

  if p_module='reservations' then
    case p_operation
    when 'get_effective_capabilities' then
      if p_args ? 'p_conference_id' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']);
      else perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type']); end if;
      return reservations.read(v_session.device_id,p_operation,p_args);
    when 'list_conference_options','get_booking_creation_context' then
      perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]);
    when 'list_events' then
      if p_args ? 'p_scope_type' then
        perform platform_private.require_exact_jsonb_keys(p_args,array['p_scope_type','p_status','p_limit']);
        if p_args->>'p_scope_type'<>'standalone' then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023'; end if;
      else perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id','p_status','p_limit']); end if;
    when 'get_event','list_event_periods','list_booking_types' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']);
    when 'get_dashboard_summary' then
      if p_args ? 'p_event_id' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id']);
      else perform platform_private.require_exact_jsonb_keys(p_args,array['p_conference_id']); end if;
    when 'list_bookings' then
      perform platform_private.require_exact_jsonb_keys(p_args,case when nullif(p_args->>'p_event_id','') is null then array['p_conference_id','p_event_id','p_limit'] else array['p_event_id','p_limit'] end);
    when 'get_booking_detail','list_booking_payments','get_operational_state','get_booking_accommodation' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_booking_id']);
    when 'search_participants_bookings' then
      perform platform_private.require_exact_jsonb_keys(p_args,case when nullif(p_args->>'p_event_id','') is null then array['p_conference_id','p_query','p_event_id','p_limit'] else array['p_query','p_event_id','p_limit'] end);
    when 'list_attendance','get_report_source_data' then
      perform platform_private.require_exact_jsonb_keys(p_args,case when nullif(p_args->>'p_event_id','') is null then array['p_conference_id','p_event_id','p_limit'] else array['p_event_id','p_limit'] end);
    when 'get_report_booking_page' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_event_id','p_limit','p_after_created_at','p_after_booking_id']);
    when 'create_event' then
      if p_args ? 'p_scope_type' then
        perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_scope_type','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
        if p_args->>'p_scope_type'<>'standalone' then raise exception 'PLATFORM_OPERATION_ARGUMENT_INVALID' using errcode='22023'; end if;
      else perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']); end if;
    when 'update_event' then
      if p_args ? 'p_conference_id' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_conference_id','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']);
      else perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_name','p_start_date','p_end_date','p_location','p_capacity','p_status','p_notes']); end if;
    when 'delete_event' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision']);
    when 'create_event_period' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_kind','p_starts_on','p_ends_on','p_display_order']);
    when 'update_event_period' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_period_id','p_expected_revision','p_kind','p_starts_on','p_ends_on','p_display_order']);
    when 'delete_event_period' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_period_id','p_expected_revision']);
    when 'reorder_event_periods' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_period_ids']);
    when 'create_booking_type' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']);
    when 'update_booking_type' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_booking_type_id','p_expected_revision','p_name','p_code','p_price','p_active','p_display_order','p_eligible_attendance_segments']);
    when 'create_booking' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']);
    when 'update_participant_booking' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_booking_type_id','p_full_name','p_phone','p_age','p_church','p_governorate','p_city_or_village','p_service_sector','p_service_sector_other','p_notes']);
    when 'delete_booking' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision']);
    when 'record_payment' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_amount','p_payment_date','p_payment_method','p_payment_method_other','p_reference','p_notes']);
    when 'void_payment' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_payment_id','p_void_reason']);
    when 'update_attendance' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_segment','p_attended','p_attendance_date','p_notes']);
    when 'update_operational_review' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_booking_id','p_expected_revision','p_review_status']);
    when 'link_standalone_event_to_conference' then
      perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_event_id','p_expected_revision','p_conference_id']);
      return reservations_private.link_standalone_event_to_conference(v_session.device_id,p_args);
    else raise exception 'RESERVATIONS_OPERATION_NOT_ALLOWED' using errcode='42501';
    end case;
    if p_operation in('list_conference_options','get_booking_creation_context','get_booking_accommodation','get_dashboard_summary','list_events','get_event','list_event_periods','list_booking_types','list_bookings','get_booking_detail','search_participants_bookings','list_booking_payments','list_attendance','get_operational_state','get_report_source_data','get_report_booking_page') then
      return reservations.read(v_session.device_id,p_operation,p_args);
    end if;
    return reservations.mutate(v_session.device_id,p_operation,p_args);
  end if;

  case p_operation
  when 'discover_parties' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_role','p_include_inactive']); v_result:=warehouse.discover_parties(v_session.device_id,p_args->>'p_role',(p_args->>'p_include_inactive')::boolean);
  when 'list_permission_administration_stores' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_include_inactive']); v_result:=warehouse.list_permission_administration_stores(v_session.device_id,(p_args->>'p_include_inactive')::boolean);
  when 'get_beneficiary_balance' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_party_id']); v_result:=warehouse.get_beneficiary_balance(v_session.device_id,(p_args->>'p_party_id')::uuid);
  when 'create_party' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_payload']); v_result:=warehouse.create_party(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->'p_payload');
  when 'update_party' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_party_id','p_expected_revision','p_payload']); v_result:=warehouse.update_party(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_party_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  when 'list_stores' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_store_id']); select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_result from warehouse.list_stores(v_session.device_id,(p_args->>'p_store_id')::uuid) x;
  when 'list_item_master' then perform platform_private.require_exact_jsonb_keys(p_args,array[]::text[]); v_result:=warehouse.list_item_master(v_session.device_id);
  when 'view_stock' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_store_id']); v_result:=warehouse.view_stock(v_session.device_id,(p_args->>'p_store_id')::uuid);
  when 'discover_stores' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_include_inactive']); v_result:=warehouse.discover_stores(v_session.device_id,(p_args->>'p_include_inactive')::boolean);
  when 'list_documents' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_document_kind','p_store_id','p_status','p_before_created_at','p_before_id','p_limit']); v_result:=warehouse.list_documents(v_session.device_id,p_args->>'p_document_kind',(p_args->>'p_store_id')::uuid,p_args->>'p_status',(p_args->>'p_before_created_at')::timestamptz,(p_args->>'p_before_id')::uuid,(p_args->>'p_limit')::integer);
  when 'get_document' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_document_id']); v_result:=warehouse.get_document(v_session.device_id,(p_args->>'p_document_id')::uuid);
  when 'list_approval_queue' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_before_created_at','p_before_id','p_limit']); v_result:=warehouse.list_approval_queue(v_session.device_id,(p_args->>'p_before_created_at')::timestamptz,(p_args->>'p_before_id')::uuid,(p_args->>'p_limit')::integer);
  when 'list_reversal_requests' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_status','p_before_created_at','p_before_id','p_limit']); v_result:=warehouse.list_reversal_requests(v_session.device_id,p_args->>'p_status',(p_args->>'p_before_created_at')::timestamptz,(p_args->>'p_before_id')::uuid,(p_args->>'p_limit')::integer);
  when 'list_history' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_store_id','p_document_id','p_item_id','p_document_kind','p_from','p_to','p_before_sequence','p_limit']); v_result:=warehouse.list_history(v_session.device_id,(p_args->>'p_store_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_item_id')::uuid,p_args->>'p_document_kind',(p_args->>'p_from')::timestamptz,(p_args->>'p_to')::timestamptz,(p_args->>'p_before_sequence')::bigint,(p_args->>'p_limit')::integer);
  when 'list_balances' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_store_id','p_before_item_id','p_limit']); v_result:=warehouse.list_balances(v_session.device_id,(p_args->>'p_store_id')::uuid,(p_args->>'p_before_item_id')::uuid,(p_args->>'p_limit')::integer);
  when 'create_store' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_name','p_type','p_address','p_notes']); v_result:=warehouse.create_store(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_name',p_args->>'p_type',p_args->>'p_address',p_args->>'p_notes');
  when 'update_store' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_store_id','p_expected_revision','p_name','p_type','p_address','p_status','p_notes']); v_result:=warehouse.update_store(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_store_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_name',p_args->>'p_type',p_args->>'p_address',p_args->>'p_status',p_args->>'p_notes');
  when 'upsert_item_master' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_entity_kind','p_entity_id','p_expected_revision','p_payload']); v_result:=warehouse.upsert_item_master(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_entity_kind',(p_args->>'p_entity_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  when 'upsert_item_units' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_item_id','p_expected_revision','p_units']); v_result:=warehouse.upsert_item_units(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_item_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_units');
  when 'create_receipt_draft','create_issue_draft','create_transfer_draft' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_payload']);
    if p_operation='create_receipt_draft' then v_result:=warehouse.create_receipt_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->'p_payload');
    elsif p_operation='create_issue_draft' then v_result:=warehouse.create_issue_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->'p_payload');
    else v_result:=warehouse.create_transfer_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->'p_payload'); end if;
  when 'create_adjustment_draft' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_adjustment_kind','p_payload']); v_result:=warehouse.create_adjustment_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_adjustment_kind',p_args->'p_payload');
  when 'update_document_draft' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_document_kind','p_document_id','p_expected_revision','p_payload']); v_result:=warehouse.update_document_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_document_kind',(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->'p_payload');
  when 'cancel_document_draft' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_document_kind','p_document_id','p_expected_revision','p_reason']); v_result:=warehouse.cancel_document_draft(v_session.device_id,(p_args->>'p_operation_id')::uuid,p_args->>'p_document_kind',(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_reason');
  when 'submit_adjustment_for_approval','post_receipt','post_issue','post_transfer','post_adjustment' then
    perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_document_id','p_expected_revision']);
    if p_operation='submit_adjustment_for_approval' then v_result:=warehouse.submit_adjustment_for_approval(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint);
    elsif p_operation='post_receipt' then v_result:=warehouse.post_receipt(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint);
    elsif p_operation='post_issue' then v_result:=warehouse.post_issue(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint);
    elsif p_operation='post_transfer' then v_result:=warehouse.post_transfer(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint);
    else v_result:=warehouse.post_adjustment(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint); end if;
  when 'decide_adjustment_approval' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_document_id','p_expected_revision','p_decision','p_reason']); v_result:=warehouse.decide_adjustment_approval(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_document_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_decision',p_args->>'p_reason');
  when 'create_reversal_request' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_original_document_id','p_reason']); v_result:=warehouse.create_reversal_request(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_original_document_id')::uuid,p_args->>'p_reason');
  when 'submit_reversal_request' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_request_id','p_expected_revision','p_reason']); v_result:=warehouse.submit_reversal_request(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_request_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_reason');
  when 'decide_reversal_approval' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_request_id','p_expected_revision','p_decision','p_reason']); v_result:=warehouse.decide_reversal_approval(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_request_id')::uuid,(p_args->>'p_expected_revision')::bigint,p_args->>'p_decision',p_args->>'p_reason');
  when 'post_reversal' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_operation_id','p_request_id','p_expected_revision']); v_result:=warehouse.post_reversal(v_session.device_id,(p_args->>'p_operation_id')::uuid,(p_args->>'p_request_id')::uuid,(p_args->>'p_expected_revision')::bigint);
  when 'authorize_report_export' then perform platform_private.require_exact_jsonb_keys(p_args,array['p_store_id']); v_result:=warehouse.authorize_report_export(v_session.device_id,(p_args->>'p_store_id')::uuid);
  else raise exception 'WAREHOUSE_OPERATION_NOT_ALLOWED' using errcode='42501';
  end case;
  return v_result;
end $$;

revoke all on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function platform.execute_device_operation(uuid,uuid,bytea,text,text,jsonb)
  to service_role;

do $$
declare v_signature regprocedure;
begin
  for v_signature in
    select procedure.oid::regprocedure
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='platform'
      and procedure.proname like 'execute_device_operation_pre_%'
  loop
    execute format('drop function %s',v_signature);
  end loop;
  if exists(
    select 1 from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where namespace.nspname='platform'
      and procedure.proname like 'execute_device_operation_pre_%'
  ) then raise exception 'PLATFORM_DISPATCHER_PREDECESSOR_RETIREMENT_INCOMPLETE' using errcode='55000'; end if;
end $$;

commit;
