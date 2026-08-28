const assert=require('assert');
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
const runner=require('../../scripts/production-migration-runner');

const root=path.resolve(__dirname,'../..');
const dir=path.join(root,'supabase/production-migrations');
const manifest=JSON.parse(fs.readFileSync(path.join(dir,'manifest.json'),'utf8'));
const row=entry=>({version:entry.version,name:entry.name,
  digest:crypto.createHash('md5').update(fs.readFileSync(path.join(dir,entry.file),'utf8')).digest('hex')});

for(const stepNumber of [3,4,5,7,8]){
  const committed=manifest.migrations.slice(0,stepNumber).map(row);
  const latest=manifest.migrations[stepNumber-1];
  const next=manifest.migrations[stepNumber];
  const historyBefore=JSON.stringify(committed);
  const mutations={migration:0,history:0,ledger:0};
  let calls=0;
  const failed=runner.verifyLatestCommitted(manifest,committed,entry=>{
    calls++;assert.strictEqual(entry.version,latest.version);return false;
  });
  assert.strictEqual(failed.status,'COMMITTED_POST_VERIFICATION_FAILED');
  assert.strictEqual(calls,1);
  assert.deepStrictEqual(mutations,{migration:0,history:0,ledger:0});
  assert.strictEqual(JSON.stringify(committed),historyBefore);
  assert.throws(()=>runner.selectNext(manifest,latest.version,committed),
    /PRODUCTION_MIGRATION_REPLAY_FORBIDDEN/);
  const recovered=runner.verifyLatestCommitted(manifest,committed,entry=>{
    calls++;assert.strictEqual(entry.version,latest.version);return true;
  });
  assert.strictEqual(recovered.status,'COMMITTED_VERIFICATION_RECOVERED');
  assert.strictEqual(recovered.next.version,next.version);
  assert.strictEqual(runner.selectNext(manifest,next.version,committed).version,next.version);
  assert.deepStrictEqual(mutations,{migration:0,history:0,ledger:0});
  assert.strictEqual(JSON.stringify(committed),historyBefore);
  console.log(`Step ${stepNumber}|COMMITTED_VERIFICATION_RECOVERED|NO_REPLAY|NO_LEDGER`);
}
