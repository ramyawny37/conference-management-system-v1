const assert=require('assert');
const identity=require('./lab-derivation-identity');

['phase2a','phase2abb_1','phase2a123','phase2a_test'].forEach(value=>
  assert.strictEqual(identity.isApprovedLabDatabaseName(value),true,value));
['phase2bb_1','phase2','phase2a-test','phase2a.test','','postgres','production',
  'mpezfbvcdfxpgflehuot','gppwltrifgfxrkzvvxoe',null].forEach(value=>
  assert.strictEqual(identity.isApprovedLabDatabaseName(value),false,String(value)));
assert.strictEqual(identity.normalizeUrlHostname('127.0.0.1'),'127.0.0.1');
assert.strictEqual(identity.normalizeUrlHostname('localhost'),'localhost');
assert.strictEqual(identity.normalizeUrlHostname('[::1]'),'::1');
assert.strictEqual(identity.normalizeUrlHostname('::1'),'::1');
['localhost','127.0.0.1','[::1]','::1'].forEach(value=>
  assert.strictEqual(identity.isApprovedUrlHostname(value),true,value));
['0.0.0.0','192.168.1.1','10.0.0.1','8.8.8.8','[8.8.8.8]','[::2]','::2',
  '[[::1]]','::1]','[::1',null,undefined,''].forEach(value=>
  assert.strictEqual(identity.isApprovedUrlHostname(value),false,String(value)));
['127.0.0.1','127.0.0.1/32','::1','::1/128'].forEach(value=>
  assert.strictEqual(identity.isApprovedLoopbackAddress(value),true,value));
['0.0.0.0','192.168.1.1','10.0.0.1','8.8.8.8','[::1]','[::2]','::2',
  null,undefined,''].forEach(value=>
  assert.strictEqual(identity.isApprovedLoopbackAddress(value),false,String(value)));
['postgresql://127.0.0.1:55440/phase2az_1','postgresql://localhost:55440/phase2az_1',
  'postgresql://[::1]:55440/phase2az_1'].forEach(value=>
  assert.strictEqual(identity.isApprovedLabUrl(value),true,value));
['postgresql://0.0.0.0/db','postgresql://192.168.1.1/db','postgresql://10.0.0.1/db',
  'postgresql://8.8.8.8/db','postgresql://mpezfbvcdfxpgflehuot.supabase.co/db',
  'postgresql://gppwltrifgfxrkzvvxoe.supabase.co/db',null].forEach(value=>
  assert.strictEqual(identity.isApprovedLabUrl(value),false,String(value)));
const canonical={database:'phase2acd_1',major:17,address:'127.0.0.1/32',
  currentUser:'postgres',sessionUser:'postgres',databaseOwner:'postgres'};
assert.strictEqual(identity.CANONICAL_BOOTSTRAP_ROLE,'postgres');
assert.strictEqual(identity.canonicalLabIdentityFailure(canonical),null);
for(const variant of [
  {...canonical,currentUser:'apple',sessionUser:'apple'},
  {...canonical,databaseOwner:'apple'},
  {...canonical,currentUser:'apple'},
  {...canonical,sessionUser:'apple'}
]) assert.strictEqual(identity.canonicalLabIdentityFailure(variant),
  'NONCANONICAL_LAB_BOOTSTRAP_OWNER');
console.log('lab derivation identity tests: passed');
