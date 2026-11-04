begin;

do $repair$
declare
  signature regprocedure;
  definition text;
  broken_expression constant text:='p_conference::text,result,jsonb_build_object';
  corrected_expression constant text:='p_conference,result,jsonb_build_object';
begin
  foreach signature in array array[
    'public.assign_conference_house(uuid,uuid,uuid,uuid,boolean,bigint)'::regprocedure,
    'public.assign_conference_room(uuid,uuid,uuid,uuid,boolean,bigint)'::regprocedure
  ] loop
    definition:=pg_get_functiondef(signature);
    if position(broken_expression in definition)=0 then
      raise exception 'CONFERENCE_ASSIGNMENT_AUDIT_SCOPE_TYPE_DRIFT: %',signature
        using errcode='55000';
    end if;
    definition:=replace(definition,broken_expression,corrected_expression);
    if position(broken_expression in definition)>0
       or position(corrected_expression in definition)=0 then
      raise exception 'CONFERENCE_ASSIGNMENT_AUDIT_SCOPE_TYPE_REPAIR_FAILED: %',signature
        using errcode='55000';
    end if;
    execute definition;
  end loop;
end
$repair$;

comment on function public.assign_conference_house(uuid,uuid,uuid,uuid,boolean,bigint) is
'Protected, idempotent Conference house assignment. Audit scope_id preserves the canonical Conference UUID type.';
comment on function public.assign_conference_room(uuid,uuid,uuid,uuid,boolean,bigint) is
'Protected, idempotent Conference room assignment with overlap and occupancy guards. Audit scope_id preserves the canonical Conference UUID type.';

commit;;
