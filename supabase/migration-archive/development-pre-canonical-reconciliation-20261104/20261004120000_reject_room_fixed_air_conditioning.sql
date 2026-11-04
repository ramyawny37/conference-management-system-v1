begin;

do $$ begin
  if to_regclass('public.conference_air_conditioning_room_overrides') is null then
    raise exception 'P6I_B4B2_AIR_CONDITIONING_FOUNDATION_REQUIRED' using errcode='55000';
  end if;
end $$;

alter table public.conference_air_conditioning_room_overrides
  add constraint conference_air_conditioning_room_fixed_unsupported
  check (pricing_basis is distinct from 'FIXED');

do $$
declare
  signature regprocedure := 'public.mutate_conference_air_conditioning(uuid,uuid,uuid,text,uuid,text,bigint,jsonb)'::regprocedure;
  definition text;
  marker text := 's:=nullif(current_setting(''platform.phase1c_context'',true),'''')::jsonb;';
  rejection text := 'if p_scope=''ROOM'' and p_action=''SET'' and p_configuration->>''pricingBasis''=''FIXED'' then raise exception ''CONFERENCE_AIR_CONDITIONING_ROOM_FIXED_UNSUPPORTED'' using errcode=''22023'';end if;' || marker;
begin
  definition := pg_get_functiondef(signature);
  if position(marker in definition)=0 then
    raise exception 'P6I_B4B2_AIR_CONDITIONING_MUTATION_PRECONDITION_FAILED' using errcode='55000';
  end if;
  execute replace(definition,marker,rejection);
end $$;

commit;
