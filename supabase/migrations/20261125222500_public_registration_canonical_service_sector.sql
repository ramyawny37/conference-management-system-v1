-- Canonicalize legacy public-registration service-sector labels and prevent noncanonical snapshots.
update reservations.public_registration_requests
set submitted_service_sector=case submitted_service_sector
 when 'أرامل' then 'widows' when 'بنات الأرامل' then 'widows-daughters'
 when 'تلمذة ابتدائي وإعدادي' then 'discipleship-primary-prep'
 when 'تلمذة ثانوي وجامعة' then 'discipleship-secondary-university'
 when 'العبادة والتسبيح' then 'worship' when 'الميديا' then 'media'
 when 'إعداد خدام' then 'servant-preparation' when 'المكتب الإداري' then 'administration'
 when 'أخرى' then 'other' else submitted_service_sector end
where submitted_service_sector in ('أرامل','بنات الأرامل','تلمذة ابتدائي وإعدادي','تلمذة ثانوي وجامعة','العبادة والتسبيح','الميديا','إعداد خدام','المكتب الإداري','أخرى');

update reservations.public_registration_request_members
set service_sector=case service_sector
 when 'أرامل' then 'widows' when 'بنات الأرامل' then 'widows-daughters'
 when 'تلمذة ابتدائي وإعدادي' then 'discipleship-primary-prep'
 when 'تلمذة ثانوي وجامعة' then 'discipleship-secondary-university'
 when 'العبادة والتسبيح' then 'worship' when 'الميديا' then 'media'
 when 'إعداد خدام' then 'servant-preparation' when 'المكتب الإداري' then 'administration'
 when 'أخرى' then 'other' else service_sector end
where service_sector in ('أرامل','بنات الأرامل','تلمذة ابتدائي وإعدادي','تلمذة ثانوي وجامعة','العبادة والتسبيح','الميديا','إعداد خدام','المكتب الإداري','أخرى');

alter table reservations.public_registration_requests
add constraint public_registration_requests_submitted_service_sector_canonical_check
check (submitted_service_sector in ('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other'));

alter table reservations.public_registration_request_members
add constraint public_registration_request_members_service_sector_canonical_check
check (service_sector in ('widows','widows-daughters','discipleship-primary-prep','discipleship-secondary-university','worship','media','servant-preparation','administration','other'));

