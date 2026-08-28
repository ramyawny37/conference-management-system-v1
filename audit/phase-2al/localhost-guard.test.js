const assert=require('assert');
const fs=require('fs');
const path=require('path');
const identityPolicy=require('./lab-derivation-identity');

['127.0.0.1','localhost','::1','[::1]'].forEach(host=>
  assert.strictEqual(identityPolicy.isApprovedUrlHostname(host),true));
['0.0.0.0','192.168.1.10','10.0.0.5','8.8.8.8','db.mpezfbvcdfxpgflehuot.supabase.co',
  'db.gppwltrifgfxrkzvvxoe.supabase.co',''].forEach(host=>
  assert.strictEqual(identityPolicy.isApprovedUrlHostname(host),false));
assert.strictEqual(identityPolicy.isApprovedLabUrl(
  'postgresql://mpezfbvcdfxpgflehuot.supabase.co/db'),false);
assert.strictEqual(identityPolicy.isApprovedLabUrl(
  'postgresql://gppwltrifgfxrkzvvxoe.supabase.co/db'),false);

for(const file of ['bootstrap-identity-fixture.sql','post-5-0-bootstrap-approval-checkpoint.sql']){
  const sql=fs.readFileSync(path.join(__dirname,file),'utf8');
  assert.match(sql,/inet_server_addr\(\) is null/);
  assert.match(sql,/inet_server_addr\(\) not in \(inet '127\.0\.0\.1',inet '::1'\)/);
  assert.doesNotMatch(sql,/inet_server_addr\(\)::text/);
  assert.match(sql,/7662742571317219726/);
}

const runner=fs.readFileSync(path.join(__dirname,'run-baseline.js'),'utf8');
assert.match(runner,/require\('\.\/lab-derivation-identity'\)/);
assert.match(runner,/identityPolicy\.isApprovedLabUrl\(url\)/);
assert.match(runner,/canonicalLabIdentityFailure\(identity\)/);
assert.ok(runner.indexOf('canonicalLabIdentityFailure(identity)')<runner.indexOf("'-f',fixture"),
  'canonical owner rejection must execute before the baseline fixture');
const derivation=fs.readFileSync(path.join(__dirname,'run-production-derivation.js'),'utf8');
assert.match(derivation,/canonicalLabIdentityFailure\(identity\)/);
console.log('lab localhost guards: passed');
