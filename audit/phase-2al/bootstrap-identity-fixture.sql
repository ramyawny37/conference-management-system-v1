-- LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY
-- LAB ONLY — NEVER EXECUTE AGAINST PRODUCTION OR DEVELOPMENT
-- UUID/email below are literals already embedded in canonical migration 5.3.0;
-- they were not copied from a hosted database.
do $lab_identity_guard$
begin
  if current_setting('server_version_num')::integer/10000 <> 17
    or inet_server_addr() is null
    or inet_server_addr() not in (inet '127.0.0.1',inet '::1')
    or current_database() !~ '^phase2a[[:alnum:]_]*$'
    or (select system_identifier::text from pg_control_system()) = '7662742571317219726' then
    raise exception 'LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY_TARGET_REFUSED';
  end if;
  if exists(select 1 from auth.users) then
    raise exception 'LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY_EXPECTED_EMPTY_AUTH_USERS';
  end if;
end;
$lab_identity_guard$;

insert into auth.users(id,email,raw_user_meta_data)
values('630c56a1-f6b0-4e49-a4ab-ef426d8966d1','ramyawny37@yahoo.com','{}'::jsonb);

do $lab_identity_post$
begin
  if (select count(*) from auth.users) <> 1
    or not exists(select 1 from auth.users
      where id='630c56a1-f6b0-4e49-a4ab-ef426d8966d1'
        and email='ramyawny37@yahoo.com' and raw_user_meta_data='{}'::jsonb) then
    raise exception 'LAB_ONLY_SYNTHETIC_BOOTSTRAP_IDENTITY_INSERT_FAILED';
  end if;
end;
$lab_identity_post$;
