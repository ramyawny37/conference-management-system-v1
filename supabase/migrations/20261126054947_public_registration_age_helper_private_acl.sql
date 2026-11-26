-- Internal age validation is owned by the canonical security-definer writer.
REVOKE ALL ON FUNCTION reservations_private.require_public_registration_member_age(date,date,text) FROM PUBLIC, anon, authenticated, service_role;
