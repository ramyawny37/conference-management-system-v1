begin;
create or replace function platform_private.stage_public_registration_request_notification()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare v_public_id uuid;
begin
  select c.public_id into v_public_id
  from reservations.public_registration_channels c
  where c.id=new.channel_id and c.event_id=new.event_id;
  if v_public_id is null then
    raise exception 'PUBLIC_REGISTRATION_NOTIFICATION_SCOPE_INVALID' using errcode='42501';
  end if;
  insert into platform.notification_outbox(
    event_type,module_key,resource_type,resource_id,scope_type,scope_id,title,body,target_url,dedupe_key
  ) values (
    'reservations.public_registration.submitted','reservations','public_registration_request',
    new.request_reference,'event',new.event_id::text,'طلب تسجيل جديد',
    'وصل طلب تسجيل جديد ويحتاج للمراجعة.',
    './#/reservations/registration-requests?eventId='||new.event_id::text,
    'public-registration:'||v_public_id::text||':'||new.submit_operation_id::text
  ) on conflict(dedupe_key) do nothing;
  return new;
end
$$;
revoke all on function platform_private.stage_public_registration_request_notification() from public,anon,authenticated,service_role;

update platform.notification_events
set target_url='./#/reservations/registration-requests?eventId='||scope_id
where module_key='reservations'
  and event_type='reservations.public_registration.submitted'
  and scope_type='event'
  and scope_id is not null
  and target_url is distinct from './#/reservations/registration-requests?eventId='||scope_id;

update platform.notification_outbox
set target_url='./#/reservations/registration-requests?eventId='||scope_id
where module_key='reservations'
  and event_type='reservations.public_registration.submitted'
  and scope_type='event'
  and scope_id is not null
  and target_url is distinct from './#/reservations/registration-requests?eventId='||scope_id;
commit;
