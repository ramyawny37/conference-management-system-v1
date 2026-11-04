begin;
do $migration$
declare d text; original text; patched text; op text; keylist text; marker text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='platform_private' and p.proname='route_canonical_conference_operation';
 if d is null then raise exception 'CANONICAL_DISPATCH_NOT_FOUND'; end if;
 original:=d;
 foreach op in array array['assign_conference_accommodation','move_conference_accommodation','remove_conference_accommodation'] loop
  marker:='elsif p_operation='||quote_literal(op)||' then';
  if position(marker in d)=0 then raise exception 'CANONICAL_DISPATCH_BRANCH_MISSING: %',op; end if;
  if op='assign_conference_accommodation' then
   keylist:='p_conference_id,p_room_id,p_participation_id,p_arrival_day,p_leave_day,p_bed_type,p_extra_bed_person_type';
  elsif op='move_conference_accommodation' then
   keylist:='p_conference_id,p_occupancy_id,p_expected_revision,p_room_id,p_arrival_day,p_leave_day,p_bed_type,p_extra_bed_person_type';
  else
   keylist:='p_conference_id,p_occupancy_id,p_expected_revision';
  end if;
  patched:=replace(d,marker,marker||E'\n    perform platform_private.require_accommodation_operation_leases(p_actor_device_id,(p_args->>''p_conference_id'')::uuid,'||quote_literal(op)||E',p_args);');
  if patched=d then raise exception 'CANONICAL_DISPATCH_PATCH_FAILED: %',op; end if;
  d:=patched;
  marker:='array['||array_to_string(array(select quote_literal(k) from unnest(string_to_array(keylist,',')) k),',')||']';
  if position(marker in d)=0 then raise exception 'CANONICAL_DISPATCH_KEYS_MISSING: %',op; end if;
  d:=replace(d,marker,left(marker,length(marker)-1)||',''p_room_lease_tokens'']');
 end loop;
 if d=original then raise exception 'CANONICAL_DISPATCH_UNCHANGED'; end if;
 execute d;
end $migration$;
commit;