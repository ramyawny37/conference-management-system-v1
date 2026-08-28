const assert=require('assert');
const fs=require('fs');
const path=require('path');
const runner=require('../scripts/production-migration-runner');

const root=path.join(__dirname,'..');
const constants=JSON.parse(fs.readFileSync(path.join(root,
  'supabase/production-migrations/catalog-contracts.json'),'utf8'));
const manifest=JSON.parse(fs.readFileSync(path.join(root,
  'supabase/production-migrations/manifest.json'),'utf8'));
const evidence=(run,label)=>JSON.parse(fs.readFileSync(path.join(root,
  `audit/phase-2al/evidence/${run}/${label}.json`),'utf8'));
const clone=value=>JSON.parse(JSON.stringify(value));

runner.validateManifest(manifest);
assert.strictEqual(constants.productionSemanticIdentities.source,
  'PHASE_2CG_PRODUCTION_READ_ONLY');
assert.strictEqual(constants.productionSemanticIdentities.functionOwner,'postgres');
assert.strictEqual(constants.productionSemanticIdentities.relationOwner,'postgres');
assert.strictEqual(constants.productionSemanticIdentities.aclGrantor,'postgres');
assert.deepStrictEqual(constants.productionSemanticIdentities.policyRoles,['authenticated']);

for(const label of constants.labels){
  const first=evidence('run-1-canonical',label);
  const second=evidence('run-2',label);
  assert.deepStrictEqual(first.hashes,second.hashes,`${label} component hashes`);
  assert.strictEqual(first.combined_sha256,second.combined_sha256,`${label} combined hash`);
  assert.strictEqual(runner.assertCatalogContract(manifest,label,first),true);
  assert.strictEqual(runner.assertCatalogContract(manifest,label,second),true);
}

const baseline=evidence('run-1-canonical','00-baseline');
const wrongFunctionOwner=clone(baseline);
wrongFunctionOwner.components.functions[0].owner='apple';
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongFunctionOwner),
  /FUNCTION_OWNER_MISMATCH/);
const wrongRelationOwner=clone(baseline);
wrongRelationOwner.components.security[0].owner='apple';
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongRelationOwner),
  /RELATION_OWNER_MISMATCH/);
const wrongFunctionGrantor=clone(baseline);
wrongFunctionGrantor.components.functions[0].acl[0].grantor='apple';
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongFunctionGrantor),
  /FUNCTION_ACL_GRANTOR_MISMATCH/);
const wrongRelationGrantor=clone(baseline);
wrongRelationGrantor.components.security[0].acl[0].grantor='apple';
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongRelationGrantor),
  /RELATION_ACL_GRANTOR_MISMATCH/);
const wrongPrivilegeShape=clone(baseline);
wrongPrivilegeShape.hashes.security='0'.repeat(64);
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongPrivilegeShape),
  /CATALOG_SECURITY_MISMATCH/);
const wrongPolicyRole=clone(baseline);
wrongPolicyRole.components.security[0].policies=[{name:'unexpected',roles:['anon']}];
assert.throws(()=>runner.assertCatalogContract(manifest,'00-baseline',wrongPolicyRole),
  /POLICY_ROLE_MISMATCH/);

assert.notStrictEqual(constants.states['00-baseline'].functions,
  constants.states['13-20260828150000'].functions,
  'current five-row pre-stream state must remain distinct from expected Step 13');
assert.strictEqual(runner.catalogLabelForEntry(manifest,manifest.migrations[0]),'00-baseline');
assert.strictEqual(runner.catalogLabelForEntry(manifest,manifest.migrations.at(-1),true),
  '13-20260828150000');
console.log('production catalog constants tests: passed');
