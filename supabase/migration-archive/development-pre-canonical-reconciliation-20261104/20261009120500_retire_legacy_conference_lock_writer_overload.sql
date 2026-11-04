begin;

-- Development exposed an older two-argument lock-writer overload that is not
-- present in the disposable baseline. It still authorizes through
-- conference_members owner/manager roles and must be retired before the
-- canonical three-argument lock cutover.
drop function if exists public.require_conference_section_lock_writer(uuid,uuid);

do $$
begin
  if to_regprocedure('public.require_conference_section_lock_writer(uuid,uuid)') is not null then
    raise exception 'LEGACY_CONFERENCE_LOCK_WRITER_OVERLOAD_REMAINS' using errcode='55000';
  end if;
end $$;

commit;
