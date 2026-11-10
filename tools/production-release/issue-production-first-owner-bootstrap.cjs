'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

const EXPECTED_EMAIL = 'ramyawny37@gmail.com';
const EXPECTED_RELATION_COUNT = 88;
const EXPECTED_RELATION_FINGERPRINT = '97a500834dce377bdf487f4d6b8428ce';

function fail(message) { throw new Error(message); }

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) fail(name + ' is required');
  return value;
}

function sqlLiteral(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

function secureTerminal() {
  let fd;
  try {
    fd = fs.openSync('/dev/tty', 'w');
  } catch (_) {
    fail('A controlling secure terminal is required');
  }
  if (!fs.fstatSync(fd).isCharacterDevice()) {
    fs.closeSync(fd);
    fail('Token destination must be a terminal character device');
  }
  return fd;
}

function sanitizePsqlError(stderr) {
  return String(stderr || 'unknown psql failure')
    .replace(/postgres(?:ql)?:\/\/[^\s]+/gi, '[REDACTED_DATABASE_URL]')
    .replace(/password=[^\s]+/gi, 'password=[REDACTED]')
    .replace(/PGPASSWORD=[^\s]+/gi, 'PGPASSWORD=[REDACTED]')
    .trim()
    .slice(0, 1200);
}

function psql(databaseUrl, sql, capture = true) {
  const result = spawnSync(
    'psql',
    [databaseUrl, '-X', '-v', 'ON_ERROR_STOP=1', '-Atq'],
    {
      input: sql,
      encoding: 'utf8',
      stdio: ['pipe', capture ? 'pipe' : 'ignore', 'pipe'],
      env: {
        ...process.env,
        PGOPTIONS: '-c statement_timeout=15000 -c lock_timeout=5000',
      },
    }
  );

  if (result.error) fail('Unable to execute psql: ' + result.error.message);
  if (result.status !== 0) {
    fail('Production bootstrap database operation failed: ' + sanitizePsqlError(result.stderr));
  }
  return capture ? String(result.stdout || '').trim() : '';
}

function main() {
  if (process.argv.length !== 2) fail('Command-line arguments are forbidden');
  if (process.env.PRODUCTION_FIRST_OWNER_BOOTSTRAP_ENABLED !== 'true') {
    fail('PRODUCTION_FIRST_OWNER_BOOTSTRAP_ENABLED must equal true');
  }

  const databaseUrl = required('PRODUCTION_DATABASE_URL');
  const terminal = secureTerminal();

  const identitySql = [
    "with app_relations as (",
    " select n.nspname||'.'||c.relname as relation_name,c.relkind::text as relation_kind",
    " from pg_class c join pg_namespace n on n.oid=c.relnamespace",
    " where n.nspname in ('public','platform','platform_private','reservations','reservations_private')",
    " and c.relkind in ('r','p','v','m','f')",
    ")",
    "select json_build_object(",
    " 'relationCount',(select count(*) from app_relations),",
    " 'relationFingerprint',(select md5(coalesce(string_agg(relation_name||':'||relation_kind,E'\\n' order by relation_name,relation_kind),'')) from app_relations),",
    " 'expectedUserCount',(select count(*) from auth.users where lower(email)=lower(" + sqlLiteral(EXPECTED_EMAIL) + ") and email_confirmed_at is not null and deleted_at is null),",
    " 'owners',(select count(*) from platform.user_roles ur join platform.roles r on r.id=ur.role_id where r.domain='platform' and r.code='platform_owner' and ur.revoked_at is null),",
    " 'completed',(select count(*) from public.system_bootstrap_state where singleton_id=1 and completed_at is not null),",
    " 'secrets',(select count(*) from public.system_bootstrap_secret)",
    ")::text;"
  ].join('\n');

  const identity = JSON.parse(psql(databaseUrl, identitySql));

  if (
    Number(identity.relationCount) !== EXPECTED_RELATION_COUNT ||
    identity.relationFingerprint !== EXPECTED_RELATION_FINGERPRINT
  ) {
    fail('Production canonical database fingerprint check failed');
  }
  if (Number(identity.expectedUserCount) !== 1) {
    fail('Expected confirmed Production owner identity was not found uniquely');
  }
  if (
    Number(identity.owners) !== 0 ||
    Number(identity.completed) !== 0 ||
    Number(identity.secrets) !== 0
  ) {
    fail('Production first-owner bootstrap is not in pristine issuable state');
  }

  const userId = psql(
    databaseUrl,
    "select id::text from auth.users where lower(email)=lower(" +
      sqlLiteral(EXPECTED_EMAIL) +
      ") and email_confirmed_at is not null and deleted_at is null;"
  );
  if (!/^[0-9a-f-]{36}$/i.test(userId)) {
    fail('Production owner identity resolution failed');
  }

  const tokenBytes = crypto.randomBytes(32);
  const token = tokenBytes.toString('base64url');

  const writeSql = [
    'begin;',
    "select pg_advisory_xact_lock(hashtextextended('first-system-bootstrap',0));",
    'do $bootstrap$',
    'begin',
    " if exists(select 1 from platform.user_roles ur join platform.roles r on r.id=ur.role_id where r.domain='platform' and r.code='platform_owner' and ur.revoked_at is null)",
    ' or exists(select 1 from public.system_bootstrap_state where singleton_id=1 and completed_at is not null)',
    ' or exists(select 1 from public.system_bootstrap_secret) then',
    "  raise exception 'BOOTSTRAP_STATE_CHANGED';",
    ' end if;',
    'end $bootstrap$;',
    'insert into public.system_bootstrap_secret(singleton_id,secret_hash,intended_user_id)',
    'values(1,extensions.crypt(' + sqlLiteral(token) + ",extensions.gen_salt('bf',12))," + sqlLiteral(userId) + '::uuid);',
    'commit;'
  ].join('\n');

  psql(databaseUrl, writeSql, false);

  fs.writeSync(
    terminal,
    '\nONE-TIME PRODUCTION FIRST-OWNER SETUP TOKEN\n' +
      token +
      '\nEnter it immediately in Production -> إعداد النظام لأول مرة.\n' +
      'This plaintext is not stored in the repository or database.\n'
  );

  tokenBytes.fill(0);
  fs.closeSync(terminal);
}

try {
  main();
} catch (error) {
  console.error(String((error && error.message) || error));
  process.exitCode = 1;
}
