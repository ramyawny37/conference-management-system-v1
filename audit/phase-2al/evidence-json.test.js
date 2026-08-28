const assert=require('assert');
const fs=require('fs');
const {checkedStdout,parseJsonEvidence}=require('./evidence-json');

assert.deepStrictEqual(parseJsonEvidence('[{"name":"a"}]',{
  label:'CONSTRAINTS',expectedType:'array',allowEmpty:false}),[{name:'a'}]);
assert.deepStrictEqual(parseJsonEvidence('[]',{
  label:'OPTIONAL_EMPTY',expectedType:'array'}),[]);
assert.throws(()=>parseJsonEvidence(' \n\t ',{
  label:'WHITESPACE',expectedType:'array'}),/EVIDENCE_EMPTY_OUTPUT_WHITESPACE/);
assert.throws(()=>parseJsonEvidence('[',{
  label:'MALFORMED',expectedType:'array'}),/EVIDENCE_MALFORMED_JSON_MALFORMED/);
assert.throws(()=>parseJsonEvidence('{}',{
  label:'TYPE',expectedType:'array'}),/EVIDENCE_TYPE_MISMATCH_TYPE/);
assert.throws(()=>parseJsonEvidence('[]',{
  label:'REQUIRED',expectedType:'array',allowEmpty:false}),/EVIDENCE_EMPTY_SET_REQUIRED/);
assert.strictEqual(checkedStdout({status:0,stdout:'ok\n',stderr:''},'OK'),'ok\n');
assert.throws(()=>checkedStdout({status:1,stdout:'',stderr:'sql failed'},'PSQL'),
  /EVIDENCE_COMMAND_FAILED_PSQL: sql failed/);
assert.throws(()=>checkedStdout({status:1,stdout:'partial',stderr:'client failed'},'CLIENT'),
  /EVIDENCE_COMMAND_FAILED_CLIENT: client failed/);
const ordered='[{"relation":"a","name":"a"},{"relation":"b","name":"b"}]';
assert.strictEqual(JSON.stringify(parseJsonEvidence(ordered,{
  label:'ORDERED',expectedType:'array'})),ordered);
const collector=fs.readFileSync(require.resolve('./run-production-derivation'),'utf8');
assert.match(collector,/device_security_credentials_non_backup_policy/);
assert.match(collector,/privileged_device_audit_webauthn_policy/);
assert.match(collector,/CONSTRAINTS_6_20_4_CARDINALITY_/);
assert.match(collector,/coalesce\(json_agg[\s\S]*?'\[\]'::json\)/);
assert.match(collector,/PHASE2AL_EVIDENCE_ONLY/);
assert.match(collector,/if\(!evidenceOnly\)\{/);

console.log('evidence JSON collection tests: passed');
