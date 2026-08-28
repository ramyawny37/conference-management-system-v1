-- LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY
-- LAB ONLY — NEVER EXECUTE AGAINST PRODUCTION OR DEVELOPMENT
do $lab_checkpoint$
declare changed integer;
begin
  if current_setting('server_version_num')::integer/10000 <> 17
    or inet_server_addr() is null
    or inet_server_addr() not in (inet '127.0.0.1',inet '::1')
    or current_database() !~ '^phase2a[[:alnum:]_]*$'
    or (select system_identifier::text from pg_control_system()) = '7662742571317219726' then
    raise exception 'LAB_ONLY_BOOTSTRAP_CHECKPOINT_TARGET_REFUSED';
  end if;
  if (select count(*) from auth.users
      where id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1'
        and email='ramyawny37@yahoo.com') <> 1
    or (select count(*) from public.system_user_access
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1') <> 1
    or not exists(select 1 from public.system_user_access
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1' and account_status='pending')
    or exists(select 1 from public.system_user_roles
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1')
    or exists(select 1 from public.conference_members
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1')
    or exists(select 1 from public.devices
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1') then
    raise exception 'LAB_ONLY_BOOTSTRAP_CHECKPOINT_PRECONDITION_FAILED';
  end if;
  if to_regclass('public.organization_members') is not null
    or to_regclass('public.user_device_authorizations') is not null
    or to_regclass('public.device_security_credentials') is not null
    or to_regclass('auth.sessions') is not null then
    raise exception 'LAB_ONLY_BOOTSTRAP_CHECKPOINT_UNEXPECTED_LATER_STATE';
  end if;

  update public.system_user_access
     set account_status='approved'
   where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1'
     and account_status='pending';
  get diagnostics changed = row_count;
  if changed <> 1 then raise exception 'LAB_ONLY_BOOTSTRAP_CHECKPOINT_ROW_COUNT_%',changed; end if;

  if (select count(*) from public.system_user_access
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1') <> 1
    or not exists(select 1 from public.system_user_access
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1' and account_status='approved')
    or exists(select 1 from public.system_user_roles
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1')
    or exists(select 1 from public.conference_members
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1')
    or exists(select 1 from public.devices
      where user_id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1') then
    raise exception 'LAB_ONLY_BOOTSTRAP_CHECKPOINT_POSTCONDITION_FAILED';
  end if;
end;
$lab_checkpoint$;
