begin;

alter table reservations.event_periods add column if not exists label text;
update reservations.event_periods
set label=case kind when 'conference' then 'المؤتمر' when 'caravans' then 'القوافل' else kind end
where label is null or btrim(label)='';
alter table reservations.event_periods alter column label set not null;
alter table reservations.event_periods drop constraint if exists reservations_event_periods_label_check;
alter table reservations.event_periods add constraint reservations_event_periods_label_check
check(length(btrim(label)) between 1 and 120);

do $rewrite$
declare definition text; original text;
begin
  definition:=pg_get_functiondef('reservations_private.mutate_scoped(uuid,text,jsonb)'::regprocedure);
  original:=definition;
  definition:=replace(definition,
    'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_event_id'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');
  definition:=replace(definition,
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_starts_on'',''p_ends_on'',''p_display_order'']',
    'array[''p_operation_id'',''p_period_id'',''p_expected_revision'',''p_kind'',''p_label'',''p_starts_on'',''p_ends_on'',''p_display_order'']');
  definition:=replace(definition,
    'coalesce(p_args->>''p_kind'','''')!~''^[a-z][a-z0-9_-]{0,39}$'' or ',
    '(coalesce(p_args->>''p_kind'','''')!~''^[a-z][a-z0-9_-]{0,39}$'' or length(btrim(coalesce(p_args->>''p_label'',''''))) not between 1 and 120) or ');
  definition:=replace(definition,
    'event_id,kind,starts_on,ends_on,display_order,created_by,updated_by)',
    'event_id,kind,label,starts_on,ends_on,display_order,created_by,updated_by)');
  definition:=replace(definition,
    'v_event.id,p_args->>''p_kind'',(p_args->>''p_starts_on'')::date',
    'v_event.id,p_args->>''p_kind'',btrim(p_args->>''p_label''),(p_args->>''p_starts_on'')::date');
  definition:=replace(definition,
    'set kind=p_args->>''p_kind'',starts_on=',
    'set kind=p_args->>''p_kind'',label=btrim(p_args->>''p_label''),starts_on=');
  if definition=original or position('p_args->>''p_label''' in definition)=0 then
    raise exception 'RESERVATIONS_PERIOD_LABEL_MUTATION_SHAPE_CHANGED' using errcode='55000';
  end if;
  execute definition;
end $rewrite$;

commit;
;
