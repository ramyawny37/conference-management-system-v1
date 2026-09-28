begin;

-- U2B REVISION: 29 business catalog rows in the existing Platform engine only.
-- No new framework objects, grants, memberships, or runtime checks.
-- Resource IDs are canonical public.conferences.id::text, never Organization IDs.
-- Templates remain library-scoped consumers pending a separate scope decision.
lock table public.module_permission_catalog in share row exclusive mode;

do $$
declare
  expected record;
begin
  if not exists(select 1 from public.platform_modules where module_key='conference' and status='active')
     or to_regclass('public.module_permission_grants') is null
     or to_regprocedure('public.require_current_approved_device(uuid)') is null
     or to_regprocedure('public.require_module_permission(uuid,text,text,text,text)') is null
     or to_regprocedure('public.validate_module_permission_catalog(text,text,text,text,text)') is null
     or to_regprocedure('public.require_effective_module_permission(uuid,text,text,text,text)') is null then
    raise exception 'CONFERENCE_PLATFORM_PERMISSION_FOUNDATION_REQUIRED' using errcode='55000';
  end if;

  for expected in
    select * from (values
      ('conference.access.view','View Conference access','Discover the granted Conference and read its access metadata; section data requires its own permission.','resource','conference',false),
      ('conference.lifecycle.create','Create Conferences','Create a Conference; existing Conference membership alone does not grant this module-level capability.','module',null,true),
      ('conference.lifecycle.manage','Manage Conference details','Edit metadata and complete the granted Conference.','resource','conference',true),
      ('conference.lifecycle.archive','Archive Conferences','Archive or restore the archive of the granted Conference.','resource','conference',true),
      ('conference.lifecycle.delete','Delete Conferences','Delete the granted Conference subject to its lifecycle protections.','resource','conference',true),
      ('conference.data.export','Export Conference data','Export or back up data for the granted Conference; never authorizes other Conferences.','resource','conference',true),
      ('conference.data.restore','Restore Conference data','Restore data for the granted Conference; creation and other Conferences require separate authority.','resource','conference',true),
      ('conference.members.view','View Conference members','Read the membership directory of the granted Conference.','resource','conference',false),
      ('conference.members.manage','Manage Conference access','Administer user access only for the granted Conference; does not confer Platform module administration.','resource','conference',true),
      ('conference.sync.write','Synchronize Conference changes','Synchronize authorized changes to the granted Conference; never bypasses section or revision checks.','resource','conference',true),
      ('conference.conflict.resolve','Resolve Conference conflicts','Resolve synchronization conflicts for authorized data in the granted Conference.','resource','conference',true),
      ('conference.people.view','View people','Read people data within the granted Conference.','resource','conference',false),
      ('conference.people.manage','Manage people','Manage people data within the granted Conference.','resource','conference',true),
      ('conference.accommodation.view','View accommodation','Read accommodation data within the granted Conference.','resource','conference',false),
      ('conference.accommodation.manage','Manage accommodation','Manage accommodation data within the granted Conference.','resource','conference',true),
      ('conference.transport.view','View transport','Read transport data within the granted Conference.','resource','conference',false),
      ('conference.transport.manage','Manage transport','Manage transport data within the granted Conference.','resource','conference',true),
      ('conference.accounts.view','View accounts','Read accounts data within the granted Conference.','resource','conference',false),
      ('conference.accounts.manage','Manage accounts','Manage accounts data within the granted Conference.','resource','conference',true),
      ('conference.restaurant.view','View restaurant','Read restaurant data within the granted Conference.','resource','conference',false),
      ('conference.restaurant.manage','Manage restaurant','Manage restaurant data within the granted Conference.','resource','conference',true),
      ('conference.air_conditioning.view','View air conditioning','Read air conditioning data within the granted Conference.','resource','conference',false),
      ('conference.air_conditioning.manage','Manage air conditioning','Manage air conditioning data within the granted Conference.','resource','conference',true),
      ('conference.reports.view','View reports','Read reports data within the granted Conference.','resource','conference',false),
      ('conference.reports.export','Export reports','Export and print reports data within the granted Conference.','resource','conference',true),
      ('conference.cards.view','View cards','Read cards data within the granted Conference.','resource','conference',false),
      ('conference.cards.export','Export cards','Export and print cards data within the granted Conference.','resource','conference',true),
      ('conference.search.view','View search','Read search data within the granted Conference.','resource','conference',false),
      ('conference.settings.view','View settings','Read settings data within the granted Conference.','resource','conference',false)
    ) catalog(permission_key,display_name,description,scope_mode,resource_type,sensitive)
  loop
    if exists(
      select 1 from public.module_permission_catalog c
      where c.permission_key=expected.permission_key
        and (c.module_key<>'conference' or c.status<>'active'
          or c.display_name<>expected.display_name or c.description<>expected.description
          or c.allowed_scope_mode<>expected.scope_mode
          or c.allowed_resource_type is distinct from expected.resource_type
          or c.sensitive_mutation<>expected.sensitive
          or c.catalog_version<>1 or c.retired_at is not null)
    ) then
      raise exception 'CONFERENCE_PERMISSION_CATALOG_CONFLICT: %',expected.permission_key using errcode='55000';
    end if;

    insert into public.module_permission_catalog(
      permission_key,module_key,display_name,description,status,
      allowed_scope_mode,allowed_resource_type,sensitive_mutation,catalog_version
    ) values (
      expected.permission_key,'conference',expected.display_name,expected.description,'active',
      expected.scope_mode,expected.resource_type,expected.sensitive,1
    ) on conflict (permission_key) do nothing;
  end loop;
end $$;

commit;
