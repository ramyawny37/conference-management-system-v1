-- The new audited phone-correction overload is private and reachable only through the canonical device dispatcher.
begin;
revoke all on function reservations_private.update_public_registration_member_profile(uuid,uuid,uuid,bigint,uuid,text,text,text,text)
  from public, anon, authenticated, service_role;
commit;
