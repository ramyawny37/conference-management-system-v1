'use strict';

// Converts a pg_dump schema-only stream into the application-owned bootstrap.
// pg_dump emits stable, typed sections.  We classify whole sections by their
// catalog identity; no Production-specific search/replace is performed.

const MANAGED_SCHEMA = 'public';
const MANAGED_DEFAULT_ACL_ROLES = new Set(['supabase_admin']);

function splitDumpSections(sql) {
  const marker = /(?=^--\n-- Name: .*; Type: .*; Schema: .*; Owner: .*\n--\n)/gm;
  const starts = [...sql.matchAll(marker)].map(match => match.index);
  if (!starts.length) throw new Error('PG_DUMP_TYPED_SECTIONS_MISSING');
  const sections = [];
  sections.push({ header: null, body: sql.slice(0, starts[0]) });
  for (let index = 0; index < starts.length; index += 1) {
    const start = starts[index];
    const end = starts[index + 1] ?? sql.length;
    const body = sql.slice(start, end);
    const header = body.match(/^--\n-- Name: (.*); Type: ([^;]+); Schema: (.*); Owner: (.*)\n--\n/);
    if (!header) throw new Error('PG_DUMP_SECTION_HEADER_INVALID');
    sections.push({
      header: { name: header[1], type: header[2], schema: header[3], owner: header[4] },
      body,
    });
  }
  return sections;
}

function defaultAclRole(section) {
  const roles = [...section.body.matchAll(/ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+"([^"]+)"/gi)]
    .map(match => match[1]);
  return new Set(roles);
}

function buildApplicationBootstrap(sql) {
  if (!/^-- PostgreSQL database dump/m.test(sql)) throw new Error('PG_DUMP_HEADER_MISSING');
  const trailerMatch = sql.match(/^--\n-- PostgreSQL database dump complete\n--[\s\S]*$/m);
  if (!trailerMatch) throw new Error('PG_DUMP_TRAILER_MISSING');
  const trailer = trailerMatch[0].replace(/\n+$/, '\n');
  const sections = splitDumpSections(sql.slice(0, trailerMatch.index));
  const output = [];
  let managedSchemaSections = 0;
  let managedDefaultAclSections = 0;

  for (const section of sections) {
    if (!section.header) {
      output.push(section.body);
      continue;
    }
    const { name, type, schema } = section.header;
    if (type === 'SCHEMA' && schema === '-' && name === MANAGED_SCHEMA) {
      managedSchemaSections += 1;
      continue;
    }
    if (type === 'DEFAULT ACL') {
      const roles = defaultAclRole(section);
      if (roles.size !== 1) throw new Error('DEFAULT_ACL_SECTION_ROLE_AMBIGUOUS');
      const [role] = roles;
      if (MANAGED_DEFAULT_ACL_ROLES.has(role)) {
        managedDefaultAclSections += 1;
        continue;
      }
    }
    output.push(section.body);
  }

  if (managedSchemaSections !== 1) throw new Error('MANAGED_PUBLIC_SCHEMA_SECTION_COUNT_INVALID');
  if (managedDefaultAclSections === 0) throw new Error('MANAGED_DEFAULT_ACL_SECTIONS_MISSING');
  const artifact = output.join('') + trailer;
  if (/^CREATE\s+SCHEMA\s+"public";/mi.test(artifact)) throw new Error('MANAGED_PUBLIC_SCHEMA_REPLAY_REMAINS');
  if (/ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+"supabase_admin"/i.test(artifact)) {
    throw new Error('MANAGED_DEFAULT_ACL_REPLAY_REMAINS');
  }
  if (!/ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+"postgres"/i.test(artifact)) {
    throw new Error('APPLICATION_DEFAULT_ACL_REPLAY_MISSING');
  }
  if (!/^-- PostgreSQL database dump complete/m.test(artifact) || !/^\\unrestrict\s/m.test(artifact)) {
    throw new Error('PG_DUMP_TRAILER_NOT_PRESERVED');
  }
  return artifact;
}

module.exports = { buildApplicationBootstrap, splitDumpSections };
