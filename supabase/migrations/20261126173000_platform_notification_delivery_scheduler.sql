begin;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

select cron.schedule(
  'platform-notification-delivery-flush',
  '30 seconds',
  $cron$
  select net.http_post(
    url := project_url.decrypted_secret || '/functions/v1/platform-notifications',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'apikey',secret_key.decrypted_secret
    ),
    body := '{"operation":"flush"}'::jsonb,
    timeout_milliseconds := 10000
  )
  from vault.decrypted_secrets project_url
  cross join vault.decrypted_secrets secret_key
  where project_url.name='platform_project_url'
    and secret_key.name='platform_notification_secret_key';
  $cron$
);
commit;
