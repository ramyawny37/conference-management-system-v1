begin;

-- The applicant-push Edge Function sends userAgent to the canonical gateway.
-- The original Production gateway allowlist omitted that field, so every
-- otherwise-valid subscription attempt failed before the upsert RPC ran.
do $patch$
declare
  v_oid oid := 'public.public_registration_gateway(text,jsonb)'::regprocedure;
  v_definition text;
  v_old text := 'array[''auth'',''endpoint'',''p256dh'',''publicId'',''trackingSecretDigest'']';
  v_new text := 'array[''auth'',''endpoint'',''p256dh'',''publicId'',''trackingSecretDigest'',''userAgent'']';
begin
  select pg_get_functiondef(v_oid) into v_definition;

  if position(v_new in v_definition) > 0 then
    return;
  end if;

  if (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'PUBLIC_REGISTRATION_PUSH_GATEWAY_USER_AGENT_PATCH_PRECONDITION_FAILED';
  end if;

  execute replace(v_definition, v_old, v_new);
end
$patch$;

commit;
