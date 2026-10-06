begin;

-- Canonical Conference core mutation has one owner and one signature.
-- Retire historical overloads before reasserting the final ACL boundary.
drop function if exists public.mutate_conference_core(
  uuid,uuid,bigint,text,date,date,text
);

do $$
declare
  v_final regprocedure:=
    to_regprocedure('public.mutate_conference_core(uuid,uuid,uuid,bigint,text,text,date,date,text)');
begin
  if v_final is null then
    raise exception 'CANONICAL_CONFERENCE_CORE_MUTATION_REQUIRED' using errcode='55000';
  end if;

  if (
    select count(*)
    from pg_proc procedure_row
    where procedure_row.pronamespace='public'::regnamespace
      and procedure_row.proname='mutate_conference_core'
  )<>1 then
    raise exception 'LEGACY_CONFERENCE_CORE_MUTATION_OVERLOAD_REMAINS' using errcode='55000';
  end if;

  if exists(
    select 1
    from aclexplode(coalesce(
      (select procedure_row.proacl from pg_proc procedure_row where procedure_row.oid=v_final),
      acldefault('f',(select procedure_row.proowner from pg_proc procedure_row where procedure_row.oid=v_final)
    ))) privilege
    where privilege.grantee in(
      0,'anon'::regrole,'authenticated'::regrole,'service_role'::regrole
    )
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'CANONICAL_CONFERENCE_CORE_MUTATION_DIRECT_EXECUTE_REMAINS' using errcode='55000';
  end if;
end $$;

commit;
