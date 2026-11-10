'use strict';
// Extracts application schema ONLY from a privileged, read-only Development connection.
// This is an offline operator tool, never a browser/Edge Function dependency.
// No connection string, passwords, Auth rows, or business data are written to disk.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DEV_REF = 'gppwltrifgfxrkzvvxoe';
const PROD_REF = 'mpezfbvcdfxpgflehuot';
const SCHEMAS = ['public', 'platform', 'platform_private', 'reservations', 'reservations_private'];
function fail(message) { console.error('BLOCKED: ' + message); process.exit(1); }
if (process.argv.length !== 2) fail('No command-line arguments are supported');
const connection = process.env.DEVELOPMENT_DATABASE_URL;
if (!connection) fail('DEVELOPMENT_DATABASE_URL is required; do not store it in the repository');
let parsed;
try { parsed = new URL(connection); } catch { fail('Invalid Development database URL'); }
if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) fail('PostgreSQL URL required');
const decodedUser = decodeURIComponent(parsed.username || '');
const directHost = parsed.hostname === 'db.' + DEV_REF + '.supabase.co';
const sharedSessionPooler = parsed.hostname.endsWith('.pooler.supabase.com') && (parsed.port || '5432') === '5432' && decodedUser === 'postgres.' + DEV_REF;
if (!directHost && !sharedSessionPooler) fail('Only the explicit Development project direct connection or its session pooler is allowed');
if (!parsed.username || !parsed.pathname || parsed.pathname === '/') fail('Database username and name required');
if (parsed.search || parsed.hash) fail('URL query parameters are not supported');
if (!parsed.password) fail('Database password required');
const binary = process.env.PG_DUMP_BIN || 'pg_dump';
if (process.env.PG_DUMP_BIN && !path.isAbsolute(binary)) fail('PG_DUMP_BIN must be an absolute executable path');
const version = spawnSync(binary, ['--version'], { encoding: 'utf8', timeout: 10000 });
if (version.error || version.status !== 0) fail('pg_dump executable not available');
const args = [
  '--schema-only', '--no-owner',
  '--format=plain', '--quote-all-identifiers', '--no-comments',
  ...SCHEMAS.map(s => '--schema=' + s),
];
const result = spawnSync(binary, args, {
  encoding: 'utf8', timeout: 120000, maxBuffer: 40 * 1024 * 1024,
  env: (() => { const env = { ...process.env, PGHOST: parsed.hostname, PGPORT: parsed.port || '5432', PGUSER: decodeURIComponent(parsed.username), PGDATABASE: decodeURIComponent(parsed.pathname.slice(1)), PGPASSWORD: decodeURIComponent(parsed.password), PGSSLMODE: 'require', PGOPTIONS: '-c default_transaction_read_only=on' }; delete env.DEVELOPMENT_DATABASE_URL; delete env.PGHOSTADDR; delete env.PGSERVICE; delete env.PGSERVICEFILE; delete env.PGOPTIONS; env.PGOPTIONS = '-c default_transaction_read_only=on'; return env; })(),
});
if (result.error || result.status !== 0) {
  fail('Schema-only dump failed; verify permissions, version, connectivity (details withheld to avoid leaking credentials)');
}
const sql = result.stdout;
if (!sql || sql.length < 1000) fail('Unexpectedly small schema dump');
if (!/^-- PostgreSQL database dump/m.test(sql)) fail('Output is not a recognizable PostgreSQL schema dump');
if (!/CREATE SCHEMA|CREATE TABLE|CREATE FUNCTION|CREATE VIEW/i.test(sql)) fail('No application schema objects found');
if (!/^\s*GRANT\s/im.test(sql) || !/^\s*ALTER\s+DEFAULT\s+PRIVILEGES\s/im.test(sql)) fail('ACL grants/default privileges missing from schema dump');
if (/^\s*(COPY|INSERT|UPDATE|DELETE|TRUNCATE)\b/im.test(sql)) fail('Data manipulation found in schema-only output');
if (/^\s*(CREATE|ALTER)\s+(ROLE|USER)\b/im.test(sql)) fail('Role creation in schema output is forbidden');
if (sql.includes(connection) || (parsed.password && sql.includes(parsed.password))) fail('Credentials detected in dump');
if (/^\s*(CREATE|ALTER)\s+(DATABASE|TABLESPACE)\b/im.test(sql)) fail('Database-level DDL in application schema output');
const digest = crypto.createHash('sha256').update(sql).digest('hex');
const outputDir = path.resolve(__dirname, '../../.release-local');
fs.mkdirSync(outputDir, { recursive: true, mode: 0o700 });
const output = path.join(outputDir, 'development-application-schema-only.sql');
fs.writeFileSync(output, sql, { mode: 0o600, flag: 'w' });
console.log(JSON.stringify({
  status: 'EXTRACTED_NOT_VALIDATED',
  sourceProjectRef: DEV_REF,
  targetProjectRef: PROD_REF,
  dataIncluded: false,
  aclIncluded: true,
  bytes: Buffer.byteLength(sql),
  sha256: digest,
  file: '.release-local/development-application-schema-only.sql',
  next: 'Review role dependencies, managed schemas and grants; verify all parity assertions in disposable local database. DO NOT apply directly to Production.',
}, null, 2));
