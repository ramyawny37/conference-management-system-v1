'use strict';
const assert=require('assert'),fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(__dirname,'..');
const policySource=fs.readFileSync(path.join(root,'js/sync/diagnostics-privacy-policy.js'),'utf8');
function policy(capabilities,environment){
  const sandbox={window:null,BrowserStorageNamespace:{environment:environment||'production'},UserManagementReadService:{getCachedActorCapabilities:()=>capabilities||null}};
  sandbox.window=sandbox;vm.runInNewContext(policySource,sandbox);return sandbox.DiagnosticsPrivacyPolicy;
}
assert.strictEqual(policy({canManageAccount:true}).canExportRescue(),true);
assert.strictEqual(policy({}).canExportRescue(),false);
assert.strictEqual(policy({},'development').isDevelopment(),true);
assert.strictEqual(policy({},'production').isDevelopment(),false);
const index=fs.readFileSync(path.join(root,'index.html'),'utf8');
const worker=fs.readFileSync(path.join(root,'service-worker.js'),'utf8');
['targeted-stuck-operation-recovery.js','experimental-conference-reset.js','debug-binding-report-ui.js','migration-repair.js'].forEach(asset=>{assert.strictEqual(index.includes(asset),false);assert.strictEqual(worker.includes(asset),false);});
const access=fs.readFileSync(path.join(root,'js/sync/access-diagnostics-ui.js'),'utf8');
assert.match(access,/DEVICE_FIELDS=\['stage','rpc','errorCode','sqlstate','httpStatus','sanitizedMessage'/);
assert.doesNotMatch(access,/email|password|access_token|refresh_token|user_metadata/i);
const signup=fs.readFileSync(path.join(root,'js/supabase/auth.js'),'utf8');
assert.match(signup,/sanitizedMessage/);
assert.doesNotMatch(signup,/diagnostics\s*:\s*\{[^}]*email/is);
console.log('diagnostics privacy contract tests: passed');
