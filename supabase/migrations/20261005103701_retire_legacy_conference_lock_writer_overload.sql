begin;

drop function if exists public.require_conference_section_lock_writer(uuid,uuid);

do $$
begin
  if to_regprocedure('public.require_conference_section_lock_writer(uuid,uuid)') is not null then
    raise exception 'LEGACY_CONFERENCE_LOCK_WRITER_OVERLOAD_REMAINS' using errcode='55000';
  end if;
end $$;

commit;;
