-- Retire browser-inaccessible legacy Public device mutators after canonical
-- Platform device enrollment became the only writable device authority.
-- Development data is disposable; no compatibility path is retained.

drop function public.register_or_refresh_current_device(uuid, text, text);
drop function public.request_current_device_authorization(uuid, uuid);
