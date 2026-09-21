'use strict';
const assert=require('node:assert/strict');
const childProcess=require('node:child_process');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const test=require('node:test');
const vm=require('node:vm');
const readiness=require('../tools/release-preflight/verify-promotion-readiness.cjs');
const manifest=require('../tools/production-release/controlled-production-manifest.json');
const incrementalPackage=require('../tools/production-release/controlled-production-incremental-3.6.0.json');
const root=path.resolve(__dirname,'..');
const git=(args,options={})=>childProcess.execFileSync('git',args,{cwd:root,encoding:'utf8',...options}).trim();
function candidateCommit(base,replacements={}){
  const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'promotion-readiness-')),indexFile=path.join(temporary,'index'),env={...process.env,GIT_INDEX_FILE:indexFile,GIT_AUTHOR_NAME:'Promotion Readiness Test',GIT_AUTHOR_EMAIL:'promotion-readiness@example.invalid',GIT_COMMITTER_NAME:'Promotion Readiness Test',GIT_COMMITTER_EMAIL:'promotion-readiness@example.invalid'};
  try{
    git(['read-tree',base],{env});
    for(const [file,transform] of Object.entries(replacements)){
      const source=childProcess.execFileSync('git',['show',`${base}:${file}`],{cwd:root,encoding:'utf8'});
      const object=git(['hash-object','-w','--stdin'],{input:transform(source)});
      git(['update-index','--add','--cacheinfo','100644',object,file],{env});
    }
    const tree=git(['write-tree'],{env});
    return git(['commit-tree',tree,'-p',base],{input:'test: promotion marker guard fixture\n',env});
  }finally{fs.rmSync(temporary,{recursive:true,force:true});}
}
const releaseBase=()=>candidateCommit(git(['rev-parse','HEAD']),{
  'tools/production-release/controlled-production-manifest.json':()=>fs.readFileSync(path.join(root,'tools/production-release/controlled-production-manifest.json'),'utf8'),
  'supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql':()=>fs.readFileSync(path.join(root,'supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql'),'utf8'),
  'js/supabase/public-config.js':()=>fs.readFileSync(path.join(root,'js/supabase/public-config.js'),'utf8'),
  'service-worker.js':()=>fs.readFileSync(path.join(root,'service-worker.js'),'utf8'),
  'version.js':()=>fs.readFileSync(path.join(root,'version.js'),'utf8')
});
const nextPatch=version=>{const parts=version.split('.').map(Number);return `${parts[0]}.${parts[1]}.${parts[2]+1}`;};
function runtimeConfig(pathname){
  const source=fs.readFileSync(path.join(root,'js/supabase/public-config.js'),'utf8');
  const window={location:{pathname}};
  vm.runInNewContext(source,{window});
  return window.SUPABASE_RUNTIME_CONFIG;
}

test('shared public config selects only the exact preview environment',()=>{
  assert.match(runtimeConfig('/conference-management-system-v1/').url,/mpezfbvcdfxpgflehuot/);
  assert.match(runtimeConfig('/conference-management-system-development-preview/').url,/gppwltrifgfxrkzvvxoe/);
  assert.match(runtimeConfig('/arbitrary-hosted-path/').url,/mpezfbvcdfxpgflehuot/);
});

test('promotion rejects static, wrong-ref, and secret-bearing public configs',()=>{
  const base=releaseBase();
  const fixtures=[
    ()=>"window.SUPABASE_RUNTIME_CONFIG={url:'https://gppwltrifgfxrkzvvxoe.supabase.co',publishableKey:'sb_publishable_Ibnpk0i0faZMUCoFOr8MTQ_G-iujGEp'};\n",
    ()=>"window.SUPABASE_RUNTIME_CONFIG={url:'https://mpezfbvcdfxpgflehuot.supabase.co',publishableKey:'sb_publishable_lWUuYqgGiez3RB_Kh5hhyA_PylfyAlC'};\n",
    source=>source.replace('mpezfbvcdfxpgflehuot','wrongproductionref000'),
    source=>source+"\n// sb_secret_forbidden\n"
  ];
  for(const transform of fixtures){
    const candidate=candidateCommit(base,{'js/supabase/public-config.js':transform});
    assert.throws(()=>readiness.verifyRepository(candidate,base,true),/PROMOTION_PUBLIC_CONFIG_/);
  }
});

test('current main is an ancestor of the realigned develop history',()=>{
  assert.doesNotThrow(()=>git(['merge-base','--is-ancestor','origin/main','HEAD']));
});

test('controlled Production requirements include approved Reservations and Platform sources',()=>{
  for(const name of ['20260908153405_reservations_v1_foundation.sql','20260909120555_production_validated_phase1c_variable_disambiguation.sql','20260912192000_platform_module_entry_access_gate.sql','20260913173000_module_permission_catalog_arabic_labels.sql'])assert.ok(manifest.releaseRequirements.requiredMigrationFiles.includes(`supabase/migrations/${name}`));
  assert.ok(manifest.releaseRequirements.developmentOnlyMigrationFiles.includes('supabase/migrations/20260913141000_platform_private_recovery_rls_hardening.sql'));
  assert.equal(manifest.releaseRequirements.requiredMigrationFiles.includes('supabase/migrations/20260913141000_platform_private_recovery_rls_hardening.sql'),false);
  assert.equal(readiness.verifyManifest(),undefined);
});
test('controlled package separates bootstrap replay, established Production history, and future promotion',()=>{
  assert.deepEqual(manifest.packageModel.historicalBootstrapReplay,{entryCount:57,applyCount:43,supersededCount:14,terminalVersion:'20260907150000',executionSource:'entries'});
  assert.equal(manifest.packageModel.establishedProductionHistory.length,20);
  const incremental=manifest.packageModel.futureIncrementalPromotion;
  assert.equal(incremental.releaseVersion,'3.6.0');
  assert.equal(incremental.releaseSha,'9e35e7a5f0c4b36f529f481b5261814feea12ffb');
  assert.equal(incremental.entries.length,6);
  assert.deepEqual(incremental.entries.map(entry=>entry.order),[1,2,3,4,5,6]);
  assert.equal(new Set(incremental.entries.map(entry=>entry.sourceFile)).size,6);
  assert.equal(new Set(incremental.entries.map(entry=>entry.idempotencyKey)).size,6);
  for(const entry of incremental.entries){assert.equal(entry.executable,true);assert.equal(entry.action,'APPLY_ONCE');}
  assert.equal(incremental.edgeRelease.verifyJwt,true);
  assert.equal(incremental.edgeRelease.currentProductionVersion,3);
  assert.equal(incremental.edgeRelease.approvedDevelopmentVersion,16);
  assert.equal(incremental.edgeRelease.promotionRequired,false);
  assert.equal(incrementalPackage.productionProjectRef,'mpezfbvcdfxpgflehuot');
  assert.deepEqual(incrementalPackage.forbiddenProjectRefs,['gppwltrifgfxrkzvvxoe']);
  assert.deepEqual(incrementalPackage.executionEntries,incremental.entries);
  assert.equal(incrementalPackage.executionEntries.length,6);
  const authority=incrementalPackage.executionEntries.at(-1);
  assert.equal(authority.sourceFile,'supabase/migrations/20260920221928_canonical_platform_device_authority_reconciliation.sql');
  assert.match(authority.preconditionSql,/device_security_credentials_authorization_fk/);
  assert.match(authority.verificationSql,/device_security_credentials_platform_authorization_fk/);
  assert.match(authority.verificationSql,/device_authorization_admin_replacement_platform_device_fk' and not convalidated/);
  assert.match(authority.verificationSql,/system_owner_credential_recovery_platform_device_fk' and convalidated/);
  assert.match(authority.rollbackPolicy,/STOP_ON_FAILURE_AT_TRANSACTION_BOUNDARY/);
  assert.deepEqual(incrementalPackage.migrationClassification,incremental.migrationClassification);
  assert.deepEqual(incremental.migrationClassification.filter(entry=>entry.classification==='ALREADY_REPRESENTED_OR_SUPERSEDED'),[{
    sourceFile:'supabase/migrations/20260915201500_reservations_booking_create_read_path_reconciliation.sql',
    classification:'ALREADY_REPRESENTED_OR_SUPERSEDED',
    supersededBy:'supabase/migrations/20260915210000_reservations_booking_create_contract_cleanup.sql'
  }]);
  assert.equal(incrementalPackage.establishedProductionHistoryVerification.every(entry=>entry.executable===false),true);
  for(const entry of manifest.packageModel.establishedProductionHistory){assert.equal(entry.executable,false);assert.equal(manifest.entries.some(controlled=>controlled.version===entry.version),false);}
  const recovery=manifest.packageModel.establishedProductionHistory.find(entry=>entry.version==='20260913141000');
  assert.equal(recovery.representation,'ESTABLISHED_PRODUCTION_CONDITIONAL_RECONCILIATION');
  assert.match(recovery.sourcePolicy,/Development body remains excluded and is not replayable/);
  const productionApplied=[
    ['reservations_standalone_event_conference_link','20260914174552'],
    ['reservations_standalone_event_link_constraint_resolution_fix','20260914174615'],
    ['reservations_payment_history_relink_guard_fix','20260914174644'],
    ['reservations_create_booking_conference_projection_fix','20260914174659'],
    ['reservations_booking_projection_self_heal','20260914174722'],
    ['reservations_link_backfill_conference_people','20260914174748']
  ];
  for(const [name,productionVersion] of productionApplied){
    const established=manifest.packageModel.establishedProductionHistory.find(entry=>entry.name===name);
    assert.equal(established.version,productionVersion);
    assert.equal(established.executable,false);
    assert.match(established.sourceFile,new RegExp(`${name}\\.sql$`));
    assert.equal(incremental.entries.some(entry=>entry.name===name),false);
    const classification=incremental.migrationClassification.find(entry=>entry.sourceFile===established.sourceFile);
    assert.deepEqual(classification,{sourceFile:established.sourceFile,classification:'ESTABLISHED_PRODUCTION_HISTORY',productionVersion,logicalSourceVersion:established.logicalSourceVersion,executable:false});
  }
  assert.deepEqual(incremental.entries.map(entry=>entry.name),[
    'reservations_organization_booking_access_reconciliation',
    'reservations_booking_create_contract_cleanup',
    'reservations_authorization_architecture_reconciliation',
    'generic_module_permission_resource_administration',
    'reservations_report_event_authorization_scope',
    'canonical_platform_device_authority_reconciliation'
  ]);
});
test('canonical version markers remain internally consistent',()=>{
  const worker=fs.readFileSync(path.join(root,'service-worker.js'),'utf8');
  const version=fs.readFileSync(path.join(root,'version.js'),'utf8');
  const appVersion=(worker.match(/const APP_VERSION = '([^']+)'/)||[])[1];
  const releaseVersion=(version.match(/version: '([^']+)'/)||[])[1];
  assert.match(appVersion,/^\d+\.\d+\.\d+$/);assert.equal(appVersion,releaseVersion);
  assert.equal(readiness.isGreater('3.4.1','3.4.0'),true);assert.equal(readiness.isGreater('3.4.0','3.4.0'),false);assert.equal(readiness.isGreater('3.3.9','3.4.0'),false);
});
test('verifyRepository rejects an application version that was not advanced',()=>{
  const base=releaseBase(),candidate=candidateCommit(base);
  assert.throws(()=>readiness.verifyRepository(candidate,base,true),/PROMOTION_APPLICATION_VERSION_NOT_ADVANCED/);
});
test('verifyRepository rejects an unchanged Production cache revision',()=>{
  const base=releaseBase(),markers=readiness.extractMarkers(base),next=nextPatch(markers.appVersion);
  const candidate=candidateCommit(base,{
    'service-worker.js':source=>source.replace(`const APP_VERSION = '${markers.appVersion}';`,`const APP_VERSION = '${next}';`),
    'version.js':source=>source.replace(`version: '${markers.appVersion}'`,`version: '${next}'`)
  });
  assert.throws(()=>readiness.verifyRepository(candidate,base,true),/PROMOTION_CACHE_REVISION_NOT_ADVANCED/);
});
test('verifyRepository rejects an unchanged shell revision',()=>{
  const base=releaseBase(),markers=readiness.extractMarkers(base),next=nextPatch(markers.appVersion),nextCache=`${markers.productionCacheRevision}-next`;
  const candidate=candidateCommit(base,{
    'service-worker.js':source=>source.replace(`const APP_VERSION = '${markers.appVersion}';`,`const APP_VERSION = '${next}';`).replace(`: '${markers.productionCacheRevision}';\nconst CACHE_NAME`,`: '${nextCache}';\nconst CACHE_NAME`),
    'version.js':source=>source.replace(`version: '${markers.appVersion}'`,`version: '${next}'`)
  });
  assert.throws(()=>readiness.verifyRepository(candidate,base,true),/PROMOTION_SHELL_REVISION_NOT_ADVANCED/);
});
test('preflight has no network, credential, or deployment path',()=>{
  const source=fs.readFileSync(path.join(root,'tools/release-preflight/verify-promotion-readiness.cjs'),'utf8');
  assert.doesNotMatch(source,/globalThis\.fetch|https\.request|process\.env|supabase db push|deploy/i);
  assert.match(source,/PROMOTION_APPLICATION_VERSION_NOT_ADVANCED/);
  assert.match(source,/BASE_NOT_ANCESTOR_OF_CANDIDATE/);
  assert.match(source,/npm',\['run','check'\]/);
  assert.match(source,/reservations-reconciliation-rejected-architecture-guard/);
});
