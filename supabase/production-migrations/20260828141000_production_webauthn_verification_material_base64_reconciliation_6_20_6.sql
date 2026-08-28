-- Generated dedicated Production stream migration.
-- Project: mpezfbvcdfxpgflehuot; Development ref is forbidden: gppwltrifgfxrkzvvxoe.
-- Semantic release: 6.20.6; intentional delta: CANONICAL_SEMANTIC_EQUIVALENT.
do $production_gate$
declare latest record;
begin
  if current_setting('server_version_num')::integer<170000
    or current_setting('server_version_num')::integer>=180000 then
    raise exception 'PRODUCTION_STREAM_POSTGRES_17_REQUIRED';
  end if;
  select version,name into latest from supabase_migrations.schema_migrations
    order by version desc limit 1;
  if latest.version is distinct from '20260828140000'
    or latest.name is distinct from 'production_webauthn_time_boundary_reconciliation_6_20_5' then
    raise exception 'PRODUCTION_STREAM_EXACT_PREDECESSOR_REQUIRED';
  end if;
  if (select count(*)<>1 or coalesce(bool_or(enabled),true)
      from public.webauthn_privileged_device_feature) then
    raise exception 'PRODUCTION_STREAM_WEBAUTHN_MUST_BE_DISABLED';
  end if;
  if (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)
      from public.device_authorization_enforcement) then
    raise exception 'PRODUCTION_STREAM_DEVICE_ENFORCEMENT_MUST_BE_DISABLED';
  end if;
end;
$production_gate$;
CREATE OR REPLACE FUNCTION public.get_system_owner_device_challenge_verification_material(
  p_actor_user_id uuid,p_actor_device_id uuid,p_session_id uuid,p_challenge_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog, public AS $$
DECLARE challenge public.device_possession_challenges%rowtype;
  credential public.device_security_credentials%rowtype;
BEGIN
  PERFORM public.require_platform_device_backend();
  SELECT * INTO challenge FROM public.device_possession_challenges challenges
    WHERE challenges.id=p_challenge_id AND challenges.user_id=p_actor_user_id
      AND challenges.actor_device_id=p_actor_device_id AND challenges.session_id=p_session_id;
  IF NOT FOUND OR challenge.credential_id IS NULL OR challenge.verified_at IS NOT NULL
    OR challenge.consumed_at IS NOT NULL OR challenge.failed_at IS NOT NULL
    OR challenge.expires_at<=statement_timestamp() THEN
    RAISE EXCEPTION 'PLATFORM_DEVICE_CHALLENGE_NOT_VERIFIABLE' USING errcode='42501';
  END IF;
  credential:=public.require_system_owner_webauthn_actor(
    p_actor_user_id,p_actor_device_id,challenge.credential_id);
  RETURN jsonb_build_object('credentialId',credential.id,
    'credentialExternalId',encode(credential.webauthn_credential_id,'base64'),
    'publicKeyCose',translate(encode(credential.public_key_cose,'base64'),E'\n\r',''),
    'signCount',credential.sign_count,'transports',credential.transports,
    'purpose',challenge.purpose,'targetUserId',challenge.target_user_id,
    'targetDeviceId',challenge.target_device_id,'operationId',challenge.operation_id,
    'environment',challenge.environment,'expectedOrigin',challenge.expected_origin,
    'expectedRpId',challenge.expected_rp_id);
END;
$$;

do $production_post$
begin
  if (select count(*)<>1 or coalesce(bool_or(enabled),true)
      from public.webauthn_privileged_device_feature)
    or (select count(*)<>1 or coalesce(bool_or(enforcement_enabled),true)
      from public.device_authorization_enforcement) then
    raise exception 'PRODUCTION_STREAM_INERT_POSTCONDITION_FAILED';
  end if;
end;
$production_post$;
