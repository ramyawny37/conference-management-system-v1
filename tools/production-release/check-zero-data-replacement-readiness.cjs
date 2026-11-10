'use strict';

// Fail-closed preflight for a zero-data Production replacement.
// Read-only: no network calls, SQL execution, migration repair or environment mutation.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const failures = [];
const checks = [];
function check(name, ok, detail) {
  checks.push({name, status: ok ? 'PASS' : 'BLOCKED', detail});
  if (!ok) failures.push(name);
}
const dev = 'gppwltrifgfxrkzvvxoe';
const prod = 'mpezfbvcdfxpgflehuot';
const lineage = JSON.parse(read('supabase/migrations/DEVELOPMENT_PLATFORM_FOUNDATION_LINEAGE.json'));
const legacy = JSON.parse(read('tools/production-release/controlled-production-manifest.json'));
const migrationDir = path.join(root, 'supabase/migrations');
const migrations = fs.readdirSync(migrationDir).filter(n => /^\d+_.+\.sql$/.test(n)).sort();
check('target_is_distinct', prod !== dev, 'Existing Production project; no third hosted project');
check('lineage_dev_only', lineage.project.ref === dev && lineage.baseline.kind === 'historical-established-schema', 'Development lineage is provenance, not an executable clean baseline');
check('active_migrations_need_foundation', migrations.length > 0 && migrations[0].startsWith('20260826110330_'), 'Active migration history starts after established pre-6.17 foundation');
check('legacy_package_not_clean_bootstrap', legacy.packageModel?.purpose === 'HISTORICAL_BOOTSTRAP_REPLAY_AND_INCREMENTAL_PROMOTION', 'Legacy promotion package cannot authorize a zero-data replacement');
const tool = read('tools/issue-development-initial-platform-bootstrap.cjs');
check('development_owner_issuer_not_reusable', tool.includes(dev) && tool.includes('INTENDED_USER_ID') && tool.includes('INTENDED_DEVICE_ID'), 'Hard-coded development owner issuer must never run against Production');
const audit = read('tools/production-release/canonical-clean-bootstrap-readonly-audit.sql');
check('read_only_audit_available', audit.includes('platform_owner') && audit.includes('relrowsecurity'), 'Structural/owner audit is available');
const bootstrap = path.join(root, 'tools/production-release/canonical-clean-bootstrap.sql');
check('clean_bootstrap_artifact', fs.existsSync(bootstrap), 'A verified complete foundation script is required');
if (fs.existsSync(bootstrap)) {
  const applicationBootstrap = fs.readFileSync(bootstrap, 'utf8');
  check('managed_foundation_separated',
    !/^CREATE\s+SCHEMA\s+"?public"?\s*;/im.test(applicationBootstrap) &&
    !/ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+"?supabase_admin"?/i.test(applicationBootstrap),
    'Application bootstrap preserves public and never rewrites supabase_admin defaults');
}
const preparation = read('tools/production-release/prepare-canonical-application-replacement.sql');
const authIntegration = read('tools/production-release/restore-canonical-managed-auth-integration.sql');
check('fail_closed_cutover_guards',
  preparation.includes('CUTOVER_OPERATIONAL_DATA_PRESENT') &&
  preparation.includes("destructive_replacement_scope constant text := 'ALL_APPLICATION_DATA'") &&
  preparation.includes('CUTOVER_REPLACEABLE_PLATFORM_STATE_AUTHORIZED') &&
  preparation.includes('CUTOVER_ALL_APPLICATION_DATA_DESTRUCTION_AUTHORIZED') &&
  preparation.includes('CUTOVER_MANAGED_DEPENDENCY_BLOCKED') &&
  preparation.includes('REVOKE ALL ON FUNCTIONS FROM postgres,anon,authenticated,service_role') &&
  !preparation.includes('ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin') &&
  !/^\s*(?:DELETE\s+FROM|TRUNCATE)\b/im.test(preparation) &&
  !/^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?"?(?:auth|storage|realtime|extensions)"?/im.test(preparation) &&
  !/^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?"?public"?/im.test(preparation),
  'Reviewed all-application replacement remains fail-closed, dependency-guarded, and preserves managed schemas');
check('canonical_managed_auth_integration',
  preparation.includes('CUTOVER_CANONICAL_AUTH_INTEGRATION_BLOCKED') &&
  preparation.includes('DROP TRIGGER auth_users_create_profile ON auth.users') &&
  preparation.includes('DROP TRIGGER platform_auth_user_provisioned ON auth.users') &&
  authIntegration.includes('CANONICAL_AUTH_INTEGRATION_PASS') &&
  authIntegration.includes('CANONICAL_AUTH_INTEGRATION_UNEXPECTED_TRIGGER'),
  'Two exact canonical auth hooks are detached and restored inside the replacement transaction');
const seed = read('tools/production-release/canonical-system-catalog-seed.sql');
check('seed_joins_outer_transaction', !/^\s*(BEGIN|COMMIT|ROLLBACK)\s*;/im.test(seed),
  'Catalog seed contains no nested transaction boundary');
const productionWorkflow = read('.github/workflows/execute-zero-data-production-clean-cutover.yml');
check('production_workflow_manual_only', productionWorkflow.includes('workflow_dispatch:') &&
  !/^\s*push\s*:/m.test(productionWorkflow), 'Production cutover is manual-only');
const evidence = path.join(root, 'tools/production-release/canonical-clean-bootstrap-evidence.json');
let approved = false;
if (fs.existsSync(evidence)) {
  try {
    const e = JSON.parse(fs.readFileSync(evidence, 'utf8'));
    approved = e.targetProjectRef === prod && e.dataMigration === false &&
      e.localBootstrap === 'PASS' && e.ownerDeviceLifecycle === 'PASS' &&
      e.securityAudit === 'PASS' && e.reviewed === true;
  } catch { approved = false; }
}
check('clean_bootstrap_evidence', approved, 'Verified local schema, owner/device, and security acceptance evidence required');
console.log(JSON.stringify({purpose:'zero-data-production-replacement',targetProjectRef:prod,sourceProjectRef:dev,readOnly:true,checks,ready:failures.length===0},null,2));
if (failures.length) process.exitCode = 1;
