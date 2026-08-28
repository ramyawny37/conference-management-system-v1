const assert=require('assert');
const fs=require('fs');
const path=require('path');

const verifier=fs.readFileSync(path.join(__dirname,'../supabase/production-migrations/verify',
  '20260828132000_production_credential_enrollment_challenge_expiry_reconciliation_6_20_1.sql'),'utf8');
assert.match(verifier,/pg_get_function_result\(p\.oid\)='jsonb'/);
assert.match(verifier,/l\.lanname='plpgsql'/);
assert.match(verifier,/p\.prosecdef/);
assert.match(verifier,/p\.provolatile='v'/);
assert.match(verifier,/p\.proparallel='u'/);
assert.match(verifier,/not p\.proisstrict/);
assert.match(verifier,/search_path=pg_catalog, public/);
assert.match(verifier,/p\.proowner=.*user_device_authorizations/s);
assert.match(verifier,/acl\.grantee=0/);
assert.match(verifier,/rolname='anon'/);
assert.match(verifier,/rolname='authenticated'/);
assert.match(verifier,/rolname='service_role'/);
assert.match(verifier,/statement_timestamp\(\)\+interval''2minutes''/);
assert.doesNotMatch(verifier,/00:01:00|00:03:00|clock_timestamp|now\(\)\+interval''2minutes''/);

const canonical=source=>source.replace(/[\s]+/g,'').includes("statement_timestamp()+interval'2minutes'");
assert.strictEqual(canonical("statement_timestamp() + interval '2 minutes'"),true);
assert.strictEqual(canonical("statement_timestamp()+interval '1 minute'"),false);
assert.strictEqual(canonical("statement_timestamp()+interval '3 minutes'"),false);
assert.strictEqual(canonical("now()+interval '2 minutes'"),false);
assert.strictEqual(canonical("clock_timestamp()+interval '2 minutes'"),false);
console.log('production Step-3 verifier tests: passed');
