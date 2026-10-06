begin;
insert into platform.permissions(code,domain,description,is_system,status,allowed_scope_mode,allowed_resource_type,sensitive_mutation)
values
('conference.module.access','conference','Conference module entry.',true,'active','module',null,false),
('conference.module.manage','conference','Conference module administration.',true,'active','module',null,true),
('warehouse.module.access','warehouse','Warehouse module entry.',true,'active','module',null,false),
('warehouse.module.manage','warehouse','Warehouse module administration.',true,'active','module',null,true),
('reservations.module.access','reservations','Reservations module entry.',true,'active','module',null,false),
('reservations.module.manage','reservations','Reservations module administration.',true,'active','module',null,true)
on conflict(code) do nothing;
commit;