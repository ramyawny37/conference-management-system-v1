-- READ ONLY: system role/permission catalog fingerprint. No IDs or personal data exported.
-- Run on Development and on the disposable clean bootstrap target.
-- The canonical clean bootstrap must explicitly seed these system definitions.
WITH catalog AS (
 SELECT 'roles'::text AS kind,
        concat_ws('|',code,domain,name,scope_type,is_system::text,is_assignable::text) AS item
 FROM platform.roles WHERE is_system
 UNION ALL
 SELECT 'permissions',
        concat_ws('|',code,domain,status,allowed_scope_mode,coalesce(allowed_resource_type,''),sensitive_mutation::text)
 FROM platform.permissions WHERE is_system
 UNION ALL
 SELECT 'role_permissions',
        concat_ws('|',r.code,p.code)
 FROM platform.role_permissions rp
 JOIN platform.roles r ON r.id=rp.role_id
 JOIN platform.permissions p ON p.id=rp.permission_id
 WHERE r.is_system AND p.is_system
)
SELECT kind,count(*) AS objects,
       md5(coalesce(string_agg(item,E'\n' ORDER BY item),'')) AS digest
FROM catalog GROUP BY kind ORDER BY kind;
