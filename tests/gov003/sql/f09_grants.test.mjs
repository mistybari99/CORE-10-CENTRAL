// GOV-003 feature 09 grant-and-policy-review: positive + adversarial SQL suite (fresh DBs, real psql backends).
// Run: node --test tests/gov003/sql/f09_grants.test.mjs   (Postgres at 127.0.0.1:55432, trust auth)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { freshDb, dropDb, exec, rows, one, execAsync, lit, uuidLit } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, U } from '../lib/ids.mjs';
import {
  canonicalJson, sha256Hex, normalizeSnapshot, diffSnapshots, verifyBaselineIntegrity, assertNoCallerSuppliedComparison, assertAdvisoryDiff,
} from '../../../internal/gov003/server/grant-diff.mjs';
import { assertAdvisoryOnly } from '../../../internal/gov003/server/risk.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const FIX = (f) => readFileSync(join(here, '..', 'fixtures', f), 'utf8');
const DB = 'g3_f089_f09';   // clean-catalog database
const DBB = 'g3_f089_f09b'; // scratch database where deliberate bad grants/policies are applied as superuser
const S = 'c10_gov003_demo';
const as = (sub) => ({ role: 'c10g3_backend', sub });
const owner = { role: 'c10g3_owner' };
const OWNER1 = U.bizOwnerB1; const OWNER1B = U.bizOwnerB1Second; const TOWN = U.tenantOwnerT1;
const codeOf = (fn) => { try { fn(); } catch (e) { return e.code; } return 'NO_ERROR'; };

const snap = (db, sub, idem, t = T1, b = B1, claimed = null) =>
  rows(db, `select * from ${S}.take_snapshot(${uuidLit(t)}, ${uuidLit(b)}, ${lit(idem)}, ${uuidLit(claimed)})`, as(sub));
const base = (db, sub, idem, t = T1, b = B1, claimed = null, snapId = null) =>
  rows(db, `select * from ${S}.record_baseline(${uuidLit(t)}, ${uuidLit(b)}, ${lit(idem)}, ${uuidLit(claimed)}, ${uuidLit(snapId)})`, as(sub));
const diff = (db, sub, idem, t = T1, b = B1, claimed = null, baselineId = null) =>
  rows(db, `select * from ${S}.diff_against_baseline(${uuidLit(t)}, ${uuidLit(b)}, ${lit(idem)}, ${uuidLit(claimed)}, ${uuidLit(baselineId)})`, as(sub));
const chainOk = (db, sub, t, b) => one(db, `select * from ${S}.verify_chain(${uuidLit(t)}, ${uuidLit(b)})`, as(sub));
const inventory = (db) => JSON.parse(exec(db, `select ${S}._catalog_inventory()::text`, owner).trim());

function dump(db) {
  const r = spawnSync('pg_dump', ['-s', '-n', 'c10_gov003_demo', '-h', process.env.PGHOST || '127.0.0.1', '-p', process.env.PGPORT || '55432',
    '-U', process.env.PGUSER || 'postgres', db], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error || r.status !== 0) return null;
  return r.stdout.split('\n').filter((l) => !l.startsWith('--') && !l.startsWith('\\restrict') && !l.startsWith('\\unrestrict')).join('\n');
}
// A catalog fingerprint taken with plain pg_catalog queries, independent of the module under test.
const rawCatalog = (db) => one(db, `select md5(concat_ws('|',
  (select coalesce(string_agg(p.oid::regprocedure::text || coalesce(p.proacl::text, '-') || p.prosecdef || coalesce(p.proconfig::text, '-') || md5(p.prosrc), ',' order by p.oid::regprocedure::text), '') from pg_proc p where p.pronamespace = '${S}'::regnamespace),
  (select coalesce(string_agg(c.relname || coalesce(c.relacl::text, '-') || c.relrowsecurity || c.relforcerowsecurity || coalesce(c.reloptions::text, '-'), ',' order by c.relname), '') from pg_class c where c.relnamespace = '${S}'::regnamespace),
  (select coalesce(string_agg(a.attrelid::regclass::text || a.attname || a.attacl::text, ',' order by a.attrelid::regclass::text, a.attname), '') from pg_attribute a join pg_class c on c.oid = a.attrelid where c.relnamespace = '${S}'::regnamespace and a.attacl is not null),
  (select coalesce(string_agg(pol::text, ',' order by pol.polname::text), '') from pg_policy pol join pg_class c on c.oid = pol.polrelid where c.relnamespace = '${S}'::regnamespace),
  (select coalesce(string_agg(t.tgname || t.tgenabled::text || t.tgrelid::regclass::text, ',' order by t.tgrelid::regclass::text, t.tgname), '') from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = '${S}'::regnamespace and not t.tgisinternal),
  (select nspacl::text from pg_namespace where oid = '${S}'::regnamespace),
  (select coalesce(string_agg(d::text, ','), '') from pg_default_acl d),
  (select coalesce(string_agg(r::text, ',' order by rolname), '') from pg_roles r where rolname like 'c10g3%'),
  (select coalesce(string_agg(roleid::regrole::text || member::regrole::text, ',' order by roleid::regrole::text, member::regrole::text), '') from pg_auth_members))) as h`).h;

const only = ['000', '010', '020', '030', '040', '080', '090'];
before(() => {
  freshDb(DB, { only });
  exec(DB, FIX('f08_09_events.sql'));
  exec(DB, FIX('f08_09_protected_state.sql'));
});
after(() => { dropDb(DB); dropDb(DBB); });

test('RPCs are backend-only; the inventory, facts, classifier and comparator are owner-only (no caller-side comparison oracle)', () => {
  const pub = [`${S}.take_snapshot(uuid,uuid,text,uuid)`, `${S}.record_baseline(uuid,uuid,text,uuid,uuid)`, `${S}.diff_against_baseline(uuid,uuid,text,uuid,uuid)`];
  const internal = [`${S}._catalog_inventory()`, `${S}._catalog_facts(jsonb)`, `${S}._finding_class(text,text,text,jsonb,jsonb,boolean)`, `${S}.catalog_diff(jsonb,jsonb)`];
  const ok = (role, fn) => one(DB, `select has_function_privilege(${lit(role)}, ${lit(fn)}, 'execute') as p`).p;
  const pubExec = (fn) => one(DB, `select exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = ${lit(fn)}::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE') as p`).p;
  for (const f of pub) {
    assert.equal(ok('c10g3_backend', f), true);
    for (const r of ['c10g3_app', 'c10g3_reader']) assert.equal(ok(r, f), false, `${r} ${f}`);
    assert.equal(pubExec(f), false);
  }
  for (const f of internal) {
    for (const r of ['c10g3_backend', 'c10g3_app', 'c10g3_reader']) assert.equal(ok(r, f), false, `${r} ${f}`);
    assert.equal(pubExec(f), false);
  }
  const bl = JSON.stringify(inventory(DB));
  assert.equal(codeOf(() => exec(DB, `select ${S}.catalog_diff(${lit(bl)}::jsonb, ${lit(bl)}::jsonb)`, as(OWNER1))), '42501',
    'a caller must not be able to run a comparison against a baseline of their own choosing');
  assert.equal(codeOf(() => exec(DB, `select ${S}._catalog_inventory()`, as(OWNER1))), '42501');
});

test('no parameter lets a caller supply the baseline or the comparison (signatures and call attempts)', () => {
  const sigs = rows(DB, `select proname, pg_get_function_arguments(oid) as args from pg_proc where pronamespace = '${S}'::regnamespace
      and proname in ('take_snapshot','record_baseline','diff_against_baseline')`, owner);
  assert.equal(sigs.length, 3);
  for (const s of sigs) assert.doesNotMatch(s.args, /jsonb|json\b/i, `${s.proname}(${s.args}) must not accept caller JSON`);
  const fake = lit(JSON.stringify({ format: 'g3cat-v1', schema_privileges: [], functions: [], relations: [], policies: [] }));
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.diff_against_baseline(${uuidLit(T1)}, ${uuidLit(B1)}, 'fabricate-0001', null, null, ${fake}::jsonb)`, as(OWNER1))), '42883');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.diff_against_baseline(p_tenant => ${uuidLit(T1)}, p_business => ${uuidLit(B1)}, p_idem => 'fabricate-0002', p_baseline => ${fake}::jsonb)`, as(OWNER1))), '42883');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.record_baseline(${uuidLit(T1)}, ${uuidLit(B1)}, 'fabricate-0003', null, null, ${fake}::jsonb)`, as(OWNER1))), '42883');
  // Node-side API guard rejects the same kind of request before it ever reaches SQL
  assert.throws(() => assertNoCallerSuppliedComparison({ tenant_id: T1, baseline: {}, no_differences: true }), /G3A03/);
  assert.equal(assertNoCallerSuppliedComparison({ tenant_id: T1, business_id: B1, baseline_id: 'x' }), true);
});

test('snapshot / baseline / diff are DENIED to forged, unauthenticated, site-staff, investor, revoked, support, foreign-tenant and other-business callers (nothing stored)', () => {
  const calls = {
    snapshot: (sub, claimed, t = T1, b = B1) => snap(DB, sub, 'denied-snap-0001', t, b, claimed),
    baseline: (sub, claimed, t = T1, b = B1) => base(DB, sub, 'denied-base-0001', t, b, claimed),
    diff: (sub, claimed, t = T1, b = B1) => diff(DB, sub, 'denied-diff-0001', t, b, claimed),
  };
  for (const [name, f] of Object.entries(calls)) {
    for (const [label, sub] of [['staff', U.staffS1], ['investor', U.investorB1], ['revoked', U.revokedB1], ['support', U.support], ['T2 owner', U.t2Owner], ['owner of B2', U.bizOwnerB2]]) {
      assert.equal(codeOf(() => f(sub, null)), 'G3A02', `${name} / ${label}`);
    }
    assert.equal(codeOf(() => f(U.unknown, null)), 'G3A05', `${name} / unknown`);
    assert.equal(codeOf(() => f(OWNER1, TOWN)), 'G3A01', `${name} / forged actor`);
    assert.equal(codeOf(() => f(OWNER1, null, T1, B3)), 'G3A02', `${name} / business of another tenant`);
    assert.equal(codeOf(() => f(OWNER1, null, T2, B3)), 'G3A02', `${name} / foreign tenant`);
  }
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.take_snapshot(${uuidLit(T1)}, ${uuidLit(B1)}, 'denied-snap-0002')`, { role: 'c10g3_backend' })), 'G3A05');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.take_snapshot(${uuidLit(T1)}, ${uuidLit(B1)}, 'denied-snap-0002')`, { role: 'c10g3_app', sub: OWNER1 })), '42501');
  assert.equal(codeOf(() => snap(DB, OWNER1, 'short')), 'G3A03');
  for (const t of ['catalog_snapshots', 'catalog_baselines', 'catalog_diffs']) assert.equal(one(DB, `select count(*)::int as n from ${S}.${t}`, owner).n, 0, t);
});

let snap1;
test('owner snapshot: read-only inventory, canonical digest identical to the Node digest, stored per business with that business\'s audit receipt', () => {
  const r = snap(DB, OWNER1, 'snap-idem-0001')[0];
  snap1 = r;
  assert.equal(r.replayed, false); assert.ok(r.item_count > 40);
  const row = one(DB, `select * from ${S}.v_catalog_snapshots where snapshot_id = ${uuidLit(r.snapshot_id)}`, as(OWNER1));
  assert.equal(row.format_version, 'g3cat-v1'); assert.equal(row.purpose, 'snapshot'); assert.equal(row.taken_by, OWNER1, 'actor derived server-side');
  assert.equal(row.inventory_sha256, sha256Hex(canonicalJson(row.inventory)), 'SQL canonical_json and Node canonicalJson are byte-identical');
  assert.equal(canonicalJson(normalizeSnapshot(row.inventory)), canonicalJson(row.inventory), 'inventory is already in canonical order');
  const inv = row.inventory;
  assert.equal(inv.schema, 'c10_gov003_demo');
  assert.ok(inv.schema_privileges.some((g) => g.grantee === 'c10g3_backend' && g.privilege === 'USAGE'));
  const ae = inv.functions.find((f) => f.signature.startsWith('append_event('));
  assert.equal(ae.security_definer, true);
  assert.ok(ae.config.some((c) => c.startsWith('search_path=')));
  assert.ok(ae.grants.some((g) => g.grantee === 'c10g3_backend' && g.privilege === 'EXECUTE'));
  assert.ok(!ae.grants.some((g) => g.grantee === 'PUBLIC' || g.grantee === 'c10g3_app'), 'append_event is not executable by PUBLIC/app');
  const ev = inv.relations.find((x) => x.name === 'audit_events');
  assert.equal(ev.rls_enabled, true);
  assert.ok(!ev.grants.some((g) => g.grantee === 'c10g3_backend' && ['INSERT', 'UPDATE', 'DELETE'].includes(g.privilege)), 'backend has no write rights on audit_events');
  assert.deepEqual(ev.triggers.map((t) => t.name).sort(), ['g3_insert_guard', 'g3_no_truncate', 'g3_no_update_delete']);
  assert.ok(inv.relations.find((x) => x.name === 'v_audit_events').options.includes('security_invoker=true'));
  const pol = inv.policies.find((p) => p.table === 'audit_events' && p.name === 'audit_events_read');
  assert.equal(pol.permissive, true); assert.deepEqual(pol.roles, ['c10g3_backend', 'c10g3_reader']); assert.match(pol.using, /can_read_business/);
  const rc = one(DB, `select e.source_domain, e.action, e.actor_id, e.business_id, e.payload from ${S}.v_audit_events e where e.receipt_id = ${uuidLit(r.receipt_id)}`, as(OWNER1));
  assert.equal(rc.source_domain, 'gov003.grants'); assert.equal(rc.action, 'grant.snapshot_taken'); assert.equal(rc.actor_id, OWNER1); assert.equal(rc.business_id, B1);
  assert.equal(rc.payload.artifact_sha256, r.inventory_sha256); assert.equal(rc.payload.entity_ref, r.snapshot_id); assert.equal(rc.payload.note_code, 'advisory_only');
});

test('snapshot idempotency: same key + same actor returns the stored snapshot; another actor with that key conflicts; two simultaneous sessions store ONE', async () => {
  const again = snap(DB, OWNER1, 'snap-idem-0001')[0];
  assert.equal(again.replayed, true); assert.equal(again.snapshot_id, snap1.snapshot_id); assert.equal(again.receipt_id, snap1.receipt_id);
  assert.equal(codeOf(() => snap(DB, OWNER1B, 'snap-idem-0001')), 'G3C01');
  const mk = () => execAsync(DB, `select snapshot_id, replayed from ${S}.take_snapshot(${uuidLit(T1)}, ${uuidLit(B1)}, 'snap-race-0001')`, as(OWNER1));
  const [a, b] = await Promise.all([mk(), mk()]);
  assert.ok(a.ok && b.ok, `${a.error?.message} ${b.error?.message}`);
  const [ra, rb] = [a.out.trim().split('|'), b.out.trim().split('|')];
  assert.equal(ra[0], rb[0], 'both sessions see the same snapshot');
  assert.deepEqual([ra[1], rb[1]].sort(), ['f', 't']);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.catalog_snapshots where request_idem = 'snap-race-0001'`, owner).n, 1);
});

let baseline1;
test('baseline: server-side inventory, approved_by derived from the session, append-only, chained by sequence; a foreign snapshot cannot be approved', () => {
  const r = base(DB, OWNER1, 'base-idem-0001')[0];
  baseline1 = r;
  assert.equal(r.baseline_seq, 1); assert.equal(r.replayed, false);
  const row = one(DB, `select * from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(r.baseline_id)}`, as(OWNER1));
  assert.equal(row.approved_by, OWNER1); assert.equal(row.supersedes, null);
  assert.equal(row.inventory_sha256, sha256Hex(canonicalJson(row.inventory)));
  assert.deepEqual(verifyBaselineIntegrity(row), { ok: true, reasons: [] });
  const rc = one(DB, `select e.action, e.source_domain, e.actor_id from ${S}.v_audit_events e where e.receipt_id = ${uuidLit(r.receipt_id)}`, as(OWNER1));
  assert.deepEqual(rc, { action: 'grant.baseline_approved', source_domain: 'gov003.grants', actor_id: OWNER1 });
  assert.equal(base(DB, OWNER1, 'base-idem-0001')[0].replayed, true);
  assert.equal(codeOf(() => base(DB, OWNER1B, 'base-idem-0001')), 'G3C01');
  // approve a previously stored snapshot of the SAME business => seq 2, supersedes seq 1
  const r2 = base(DB, OWNER1B, 'base-idem-0002', T1, B1, null, snap1.snapshot_id)[0];
  assert.equal(r2.baseline_seq, 2); assert.equal(r2.snapshot_id, snap1.snapshot_id); assert.equal(r2.inventory_sha256, snap1.inventory_sha256);
  assert.equal(one(DB, `select supersedes from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(r2.baseline_id)}`, as(OWNER1)).supersedes, r.baseline_id);
  // a snapshot of another tenant's business (or an unknown id) cannot be approved by a T1 owner
  const t2snap = snap(DB, U.t2Owner, 'snap-t2-0001', T2, B3)[0];
  assert.equal(codeOf(() => base(DB, OWNER1, 'base-idem-0003', T1, B1, null, t2snap.snapshot_id)), 'G3A02');
  assert.equal(codeOf(() => base(DB, OWNER1, 'base-idem-0004', T1, B1, null, '00000000-0000-4000-8000-000000000000')), 'G3A02');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.catalog_baselines`, owner).n, 2);
});

test('stored evidence is append-only for every principal; the advisory label cannot be changed', () => {
  for (const t of ['catalog_snapshots', 'catalog_baselines', 'catalog_diffs']) {
    assert.equal(codeOf(() => exec(DB, `update ${S}.${t} set tenant_id = tenant_id`, as(OWNER1))), '42501', `${t} update`);
    assert.equal(codeOf(() => exec(DB, `delete from ${S}.${t}`, as(OWNER1))), '42501', `${t} delete`);
    assert.equal(codeOf(() => exec(DB, `insert into ${S}.${t} (tenant_id) values (${uuidLit(T1)})`, as(OWNER1))), '42501', `${t} insert (backend)`);
    assert.equal(codeOf(() => exec(DB, `insert into ${S}.${t} (tenant_id) values (${uuidLit(T1)})`, owner)), 'G3H01', `${t} insert (owner outside append path)`);
  }
  for (const t of ['catalog_snapshots', 'catalog_baselines']) {
    assert.equal(codeOf(() => exec(DB, `update ${S}.${t} set tenant_id = tenant_id`, owner)), 'G3H01', `${t} update (owner bypass attempt)`);
    assert.equal(codeOf(() => exec(DB, `delete from ${S}.${t}`, owner)), 'G3H01', `${t} delete (owner bypass attempt)`);
  }
  assert.equal(codeOf(() => exec(DB, `begin; select set_config('c10_gov003.writer','append_path',true);
    insert into ${S}.catalog_diffs (diff_id, tenant_id, business_id, baseline_id, snapshot_id, label, diff, diff_sha256, finding_count, max_severity, requested_by, request_idem, event_id, receipt_id)
    select gen_random_uuid(), b.tenant_id, b.business_id, b.baseline_id, b.snapshot_id, 'ENFORCED', '{}', repeat('0', 64), 0, 'none', b.approved_by, 'label-test-001', b.event_id, b.receipt_id from ${S}.catalog_baselines b limit 1; rollback;`, owner)), '23514');
});

test('clean state: diff against the approved baseline finds nothing, raises no signal, and equals the Node diff', () => {
  const d = diff(DB, TOWN, 'diff-idem-0001')[0];
  assert.equal(d.finding_count, 0); assert.equal(d.max_severity, 'none'); assert.equal(d.signal_id, null); assert.equal(d.replayed, false);
  assert.equal(d.baseline_id, one(DB, `select baseline_id from ${S}.v_catalog_baselines where baseline_seq = 2`, as(OWNER1)).baseline_id, 'latest approved baseline is used');
  const row = one(DB, `select * from ${S}.v_catalog_diffs where diff_id = ${uuidLit(d.diff_id)}`, as(OWNER1));
  assert.equal(row.label, 'ADVISORY'); assert.equal(row.requested_by, TOWN);
  const bl = one(DB, `select inventory from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(d.baseline_id)}`, as(OWNER1)).inventory;
  const cur = one(DB, `select inventory from ${S}.v_catalog_snapshots where snapshot_id = ${uuidLit(d.snapshot_id)}`, as(OWNER1)).inventory;
  assert.equal(canonicalJson(row.diff), canonicalJson(diffSnapshots(bl, cur)), 'SQL and Node diffs are identical');
  assert.equal(row.diff_sha256, sha256Hex(canonicalJson(row.diff)));
  assert.equal(diff(DB, TOWN, 'diff-idem-0001')[0].replayed, true);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signals where rule_id = 'grant_policy_diff'`, owner).n, 0);
  // T2 has no approved baseline: its diff is refused with a clear code, never defaulted to someone else's
  assert.equal(codeOf(() => diff(DB, U.t2Owner, 'diff-t2-0001', T2, B3)), 'G3C03');
  assert.equal(codeOf(() => diff(DB, OWNER1, 'diff-idem-0002', T1, B1, null, '00000000-0000-4000-8000-000000000000')), 'G3A02', 'unknown baseline id');
});

test('READ-ONLY PROOF: snapshot + baseline + diff leave the catalog byte-identical (two inventories, pg_dump, and an independent pg_catalog fingerprint)', () => {
  const inv0 = canonicalJson(inventory(DB)); const dump0 = dump(DB); const raw0 = rawCatalog(DB);
  snap(DB, OWNER1B, 'ro-snap-0001'); base(DB, OWNER1B, 'ro-base-0001'); diff(DB, OWNER1B, 'ro-diff-0001'); diff(DB, TOWN, 'ro-diff-0002');
  const inv1 = canonicalJson(inventory(DB)); const dump1 = dump(DB); const raw1 = rawCatalog(DB);
  assert.equal(inv1, inv0, 'inventory must be byte-identical before and after');
  assert.equal(raw1, raw0, 'independent catalog fingerprint must be identical');
  if (dump0 === null) console.warn('pg_dump unavailable: skipped the dump comparison'); else {
    assert.ok(dump0.length > 5000); assert.equal(dump1, dump0, 'pg_dump -s must be identical before and after');
  }
});

test('every snapshot/baseline/diff has a business-scoped audit receipt; the chain verifies', () => {
  const evs = rows(DB, `select action, source_domain, actor_id, business_id, tenant_id from ${S}.v_audit_events where source_domain = 'gov003.grants'`, as(OWNER1));
  assert.ok(evs.length >= 8);
  assert.ok(evs.every((e) => e.tenant_id === T1 && e.business_id === B1));
  assert.deepEqual([...new Set(evs.map((e) => e.action))].sort(), ['grant.baseline_approved', 'grant.diff_recorded', 'grant.snapshot_taken']);
  assert.equal(chainOk(DB, OWNER1, T1, B1).ok, true); assert.equal(chainOk(DB, U.t2Owner, T2, B3).ok, true);
});

test('tenant isolation: T1 snapshots/baselines/diffs are invisible and uncountable to everyone except T1 owners; T2 sees only its own', () => {
  for (const v of ['v_catalog_snapshots', 'v_catalog_baselines', 'v_catalog_diffs']) {
    assert.ok(rows(DB, `select * from ${S}.${v}`, as(OWNER1)).length >= 1, v);
    for (const [label, sub] of [['staff', U.staffS1], ['investor', U.investorB1], ['revoked', U.revokedB1], ['support', U.support], ['owner of B2', U.bizOwnerB2], ['unknown', U.unknown]]) {
      assert.deepEqual(one(DB, `select count(*)::int as n from ${S}.${v} where business_id = ${uuidLit(B1)}`, as(sub)), { n: 0 }, `${label} ${v}`);
    }
    assert.ok(rows(DB, `select tenant_id from ${S}.${v}`, as(U.t2Owner)).every((r) => r.tenant_id === T2), `T2 owner only sees T2 rows in ${v}`);
    assert.ok(rows(DB, `select tenant_id from ${S}.${v}`, as(OWNER1)).every((r) => r.tenant_id === T1));
  }
  assert.equal(rows(DB, `select * from ${S}.v_catalog_snapshots`, as(U.t2Owner)).length, 1);
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.catalog_snapshots`, { role: 'c10g3_app', sub: OWNER1 })), '42501');
});

test('Node/SQL comparator parity over a battery of deliberate catalog mutations (every advisory rule GP01..GP32)', () => {
  const baseDoc = inventory(DB);
  const clone = (o) => JSON.parse(JSON.stringify(o));
  const fn = (d, prefix) => d.functions.find((f) => f.signature.startsWith(prefix));
  const rel = (d, name) => d.relations.find((r) => r.name === name);
  const pairs = [];
  const add = (name, expectRules, mutateCur, mutateBase = () => {}) => {
    const b = clone(baseDoc); const c = clone(baseDoc); mutateBase(b); mutateCur(c); pairs.push({ name, expectRules, b, c });
  };
  add('no change', [], () => {});
  add('EXECUTE to PUBLIC on definer', ['GP01_EXEC_PUBLIC_OR_APP'], (d) => fn(d, 'append_event(').grants.push({ grantee: 'PUBLIC', privilege: 'EXECUTE', grantable: false }));
  add('EXECUTE to app on internal appender', ['GP01_EXEC_PUBLIC_OR_APP'], (d) => fn(d, '_append_audit(').grants.push({ grantee: 'c10g3_app', privilege: 'EXECUTE', grantable: false }));
  add('EXECUTE to reader on definer', ['GP02_EXEC_DEFINER_WIDENED'], (d) => fn(d, 'review_signal(').grants.push({ grantee: 'c10g3_reader', privilege: 'EXECUTE', grantable: false }));
  add('EXECUTE to reader on invoker fn', ['GP03_EXEC_GRANT_ADDED'], (d) => fn(d, 'utc_iso(').grants.push({ grantee: 'c10g3_reader', privilege: 'EXECUTE', grantable: false }));
  add('grantable flipped', ['GP03_EXEC_GRANT_ADDED'], (d) => { fn(d, 'append_event(').grants.find((g) => g.grantee === 'c10g3_backend').grantable = true; });
  add('function grant removed', ['GP04_GRANT_REMOVED'], (d) => { const f = fn(d, 'append_event('); f.grants = f.grants.filter((g) => g.grantee !== 'c10g3_backend'); });
  add('INSERT on audit_events to backend', ['GP05_WRITE_GRANT_ADDED'], (d) => rel(d, 'audit_events').grants.push({ grantee: 'c10g3_backend', privilege: 'INSERT', grantable: false }));
  add('SELECT on audit_chain_heads to PUBLIC', ['GP06_READ_GRANT_WIDENED'], (d) => rel(d, 'audit_chain_heads').grants.push({ grantee: 'PUBLIC', privilege: 'SELECT', grantable: false }));
  add('SELECT on tenants to reader', ['GP07_TABLE_GRANT_ADDED'], (d) => rel(d, 'tenants').grants.push({ grantee: 'c10g3_reader', privilege: 'SELECT', grantable: false }));
  add('table grant removed', ['GP04_GRANT_REMOVED'], (d) => { const r = rel(d, 'audit_events'); r.grants = r.grants.filter((g) => g.grantee !== 'c10g3_reader'); });
  add('schema CREATE to PUBLIC', ['GP08_SCHEMA_PRIVILEGE_WIDENED'], (d) => d.schema_privileges.push({ grantee: 'PUBLIC', privilege: 'CREATE', grantable: false }));
  add('schema USAGE to other role', ['GP09_SCHEMA_GRANT_ADDED'], (d) => d.schema_privileges.push({ grantee: 'c10g3_x', privilege: 'USAGE', grantable: false }));
  add('column UPDATE grant', ['GP05_WRITE_GRANT_ADDED'], (d) => rel(d, 'tenants').column_grants.push({ column: 'name', grantee: 'c10g3_backend', privilege: 'UPDATE', grantable: false }));
  add('column SELECT grant', ['GP07_TABLE_GRANT_ADDED'], (d) => rel(d, 'tenants').column_grants.push({ column: 'name', grantee: 'c10g3_reader', privilege: 'SELECT', grantable: false }));
  add('new definer function', ['GP15_DEFINER_FUNCTION_ADDED'], (d) => d.functions.push({ signature: 'sneaky()', owner: 'c10g3_owner', security_definer: true, config: [], grants: [] }));
  add('new invoker function / removed function', ['GP16_FUNCTION_ADDED_OR_REMOVED'], (d) => { d.functions.push({ signature: 'plain()', owner: 'c10g3_owner', security_definer: false, config: [], grants: [] }); d.functions = d.functions.filter((f) => !f.signature.startsWith('utc_iso(')); });
  add('definer flag flipped', ['GP17_FUNCTION_ATTRIBUTE_CHANGED'], (d) => { fn(d, 'actor_id(').security_definer = false; });
  add('search_path removed', ['GP17_FUNCTION_ATTRIBUTE_CHANGED'], (d) => { fn(d, 'actor_id(').config = []; });
  add('relation added / removed', ['GP10_RELATION_ADDED', 'GP11_RELATION_REMOVED'], (d) => { d.relations.push({ name: 'shadow', kind: 'r', owner: 'c10g3_owner', rls_enabled: false, rls_forced: false, options: [], grants: [], column_grants: [], triggers: [] }); d.relations = d.relations.filter((r) => r.name !== 'error_catalog'); });
  add('RLS disabled', ['GP12_RLS_DISABLED'], (d) => { rel(d, 'tenants').rls_enabled = false; });
  add('relation owner changed', ['GP13_RELATION_ATTRIBUTE_CHANGED'], (d) => { rel(d, 'tenants').owner = 'postgres'; });
  add('view lost security_invoker', ['GP14_VIEW_INVOKER_LOST'], (d) => { rel(d, 'v_audit_events').options = []; });
  add('permissive OR policy added', ['GP20_PERMISSIVE_POLICY_ADDED'], (d) => d.policies.push({ table: 'audit_events', name: 'bad_or', command: 'r', permissive: true, roles: ['PUBLIC'], using: 'true', check: null }));
  add('restrictive policy added', ['GP21_RESTRICTIVE_POLICY_ADDED'], (d) => d.policies.push({ table: 'audit_events', name: 'only_r', command: 'r', permissive: false, roles: ['c10g3_reader'], using: 'true', check: null }));
  const restrictive = { table: 'audit_events', name: 'only_r', command: 'r', permissive: false, roles: ['c10g3_reader'], using: 'true', check: null };
  add('restrictive policy removed', ['GP22_RESTRICTIVE_POLICY_REMOVED'], () => {}, (b) => b.policies.push(clone(restrictive)));
  add('permissive policy removed', ['GP23_POLICY_REMOVED'], (d) => { d.policies = d.policies.filter((p) => p.name !== 'audit_events_read'); });
  add('policy qual changed', ['GP24_POLICY_CHANGED'], (d) => { d.policies.find((p) => p.name === 'audit_events_read').using = 'true'; });
  add('restrictive -> permissive', ['GP25_POLICY_MADE_PERMISSIVE'], (d) => d.policies.push({ ...clone(restrictive), permissive: true }), (b) => b.policies.push(clone(restrictive)));
  add('trigger removed', ['GP30_TRIGGER_REMOVED'], (d) => { const r = rel(d, 'audit_events'); r.triggers = r.triggers.filter((t) => t.name !== 'g3_no_update_delete'); });
  add('trigger disabled', ['GP31_TRIGGER_DISABLED'], (d) => { rel(d, 'audit_events').triggers.find((t) => t.name === 'g3_no_update_delete').enabled = 'D'; });
  add('trigger added', ['GP32_TRIGGER_ADDED_OR_RESTORED'], (d) => rel(d, 'audit_events').triggers.push({ name: 'extra', enabled: 'O', function: 'x' }));
  const sql = pairs.map((p) => `select ${S}.catalog_diff(${lit(JSON.stringify(p.b))}::jsonb, ${lit(JSON.stringify(p.c))}::jsonb)::text;`).join('\n');
  const outs = exec(DB, sql, owner).trim().split('\n');
  assert.equal(outs.length, pairs.length);
  const seen = new Set();
  pairs.forEach((p, i) => {
    const sqlDiff = JSON.parse(outs[i]); const jsDiff = diffSnapshots(p.b, p.c);
    assert.equal(canonicalJson(sqlDiff), canonicalJson(jsDiff), `parity: ${p.name}`);
    assert.equal(sqlDiff.label, 'ADVISORY'); assertAdvisoryDiff(jsDiff);
    for (const r of p.expectRules) { assert.ok(jsDiff.findings.some((f) => f.rule === r), `${p.name} must raise ${r}`); seen.add(r); }
    if (p.expectRules.length === 0) { assert.equal(sqlDiff.finding_count, 0); assert.equal(sqlDiff.max_severity, 'none'); }
  });
  assert.equal(seen.size, 26, 'all advisory rules except the unreachable GP99 fallback are exercised');
});

// ---------------------------------------------------------------------------------------------------
// Scratch database: deliberate bad grants / policies applied AS SUPERUSER; the module must flag them.
// ---------------------------------------------------------------------------------------------------
let bBaseline; let firstDiff;
test('scratch DB: reviewed baseline of the CURRENT core grants is recorded and a clean diff is empty', () => {
  freshDb(DBB, { only });
  exec(DBB, FIX('f08_09_events.sql'));
  exec(DBB, FIX('f08_09_protected_state.sql'));
  bBaseline = base(DBB, OWNER1, 'b-base-idem-0001')[0];
  assert.equal(bBaseline.baseline_seq, 1);
  const d = diff(DBB, TOWN, 'b-diff-idem-0001')[0];
  assert.equal(d.finding_count, 0);
});

test('deliberate bad GRANTs and a permissive OR policy are flagged as ADVISORY, with a signal, receipt and evidence link', () => {
  const catalogBefore = canonicalJson(inventory(DBB)); // clean
  exec(DBB, FIX('f08_09_bad_catalog.sql'));            // superuser: 2x EXECUTE grants, INSERT grant, permissive policy
  const afterBad = canonicalJson(inventory(DBB));
  assert.notEqual(afterBad, catalogBefore, 'the deliberate change is visible in the catalog');
  const d = diff(DBB, TOWN, 'b-diff-idem-0002')[0];
  firstDiff = d;
  assert.equal(d.finding_count, 4); assert.equal(d.max_severity, 'high'); assert.ok(d.signal_id);
  const row = one(DBB, `select * from ${S}.v_catalog_diffs where diff_id = ${uuidLit(d.diff_id)}`, as(OWNER1));
  assert.equal(row.label, 'ADVISORY');
  const byRule = (r) => row.diff.findings.filter((f) => f.rule === r);
  const pubExec = byRule('GP01_EXEC_PUBLIC_OR_APP');
  assert.equal(pubExec.length, 2);
  assert.ok(pubExec.some((f) => f.key.startsWith('function_grant|append_event(') && f.key.endsWith('|PUBLIC|EXECUTE')));
  assert.ok(pubExec.some((f) => f.key.startsWith('function_grant|_append_audit(') && f.key.endsWith('|c10g3_app|EXECUTE')));
  assert.equal(byRule('GP05_WRITE_GRANT_ADDED')[0].key, 'relation_grant|audit_events|c10g3_backend|INSERT');
  assert.equal(byRule('GP20_PERMISSIVE_POLICY_ADDED')[0].key, 'policy|audit_events|bad_permissive_or');
  assert.ok(row.diff.findings.every((f) => f.severity === 'high' && f.change === 'added'));
  // Node recomputation from the two stored inventories equals the stored diff
  const bl = one(DBB, `select inventory from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(d.baseline_id)}`, as(OWNER1)).inventory;
  const cur = one(DBB, `select inventory from ${S}.v_catalog_snapshots where snapshot_id = ${uuidLit(d.snapshot_id)}`, as(OWNER1)).inventory;
  assert.equal(canonicalJson(row.diff), canonicalJson(diffSnapshots(bl, cur)));
  // the advisory signal (feature 08 rule grant_policy_diff)
  const sg = one(DBB, `select * from ${S}.v_risk_signals where signal_id = ${uuidLit(d.signal_id)}`, as(OWNER1));
  assert.equal(sg.rule_id, 'grant_policy_diff'); assert.equal(sg.severity, 'high'); assert.equal(sg.confidence_pct, 90);
  assert.equal(sg.status, 'open'); assert.equal(sg.disposition, 'advisory_review_only'); assert.equal(sg.source_domain, 'gov003.grants');
  assertAdvisoryOnly({ disposition: sg.disposition, reason: sg.reason });
  assert.match(sg.reason, /No permission was changed automatically/);
  const ev = rows(DBB, `select evidence_kind, ref from ${S}.v_risk_signal_evidence where signal_id = ${uuidLit(d.signal_id)}`, as(OWNER1));
  assert.deepEqual(ev, [{ evidence_kind: 'catalog_diff', ref: d.diff_id }]);
  const rc = one(DBB, `select e.source_domain, e.action, e.payload from ${S}.v_audit_events e where e.receipt_id = ${uuidLit(sg.receipt_id)}`, as(OWNER1));
  assert.equal(rc.source_domain, 'gov003.risk'); assert.equal(rc.action, 'risk.signal_raised'); assert.equal(rc.payload.reason_code, 'grant_policy_diff');
  // a repeat of the identical situation does not duplicate the signal
  const again = diff(DBB, TOWN, 'b-diff-idem-0003')[0];
  assert.equal(again.signal_id, d.signal_id);
  assert.equal(one(DBB, `select count(*)::int as n from ${S}.risk_signals where rule_id = 'grant_policy_diff'`, owner).n, 1);
  // other tenants/roles see nothing of it
  assert.equal(one(DBB, `select count(*)::int as n from ${S}.v_catalog_diffs`, as(U.t2Owner)).n, 0);
  assert.equal(one(DBB, `select count(*)::int as n from ${S}.v_risk_signals where rule_id = 'grant_policy_diff'`, as(U.investorB1)).n, 0);
});

test('the module NEVER repairs: after flagging, the bad grants and the policy are still in the catalog, byte-identical before/after the diff', () => {
  const inv0 = canonicalJson(inventory(DBB)); const dump0 = dump(DBB); const raw0 = rawCatalog(DBB);
  diff(DBB, OWNER1B, 'b-diff-idem-0004'); snap(DBB, OWNER1B, 'b-snap-idem-0001'); base(DBB, OWNER1B, 'b-base-idem-0002', T1, B1, null, null);
  assert.equal(canonicalJson(inventory(DBB)), inv0); assert.equal(rawCatalog(DBB), raw0);
  if (dump0 !== null) assert.equal(dump(DBB), dump0);
  assert.equal(one(DBB, `select exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a where p.proname = 'append_event' and a.grantee = 0) as p`).p, true, 'PUBLIC EXECUTE still present');
  assert.equal(one(DBB, `select count(*)::int as n from pg_policy where polname = 'bad_permissive_or'`).n, 1, 'policy still present');
  assert.equal(one(DBB, `select has_table_privilege('c10g3_backend', '${S}.audit_events', 'insert') as p`).p, true, 'INSERT grant still present');
  // baseline #2 (just approved by an owner) now absorbs the bad state: an explicit, audited, human decision
  assert.equal(one(DBB, `select baseline_seq from ${S}.v_catalog_baselines order by baseline_seq desc limit 1`, as(OWNER1)).baseline_seq, 2);
  assert.equal(diff(DBB, OWNER1B, 'b-diff-idem-0005')[0].finding_count, 0, 'after owner approval the diff is clean against the new baseline');
  // ...while diffing against baseline #1 explicitly still flags it
  assert.equal(diff(DBB, OWNER1B, 'b-diff-idem-0006', T1, B1, null, bBaseline.baseline_id)[0].finding_count, 4);
});

test('the independent reviewer rule applies to grant-diff signals: the owner who ran the diff cannot dismiss it; another owner can, with a receipt', () => {
  const sigId = firstDiff.signal_id;
  const rev = (sub, dec, why, idem) => rows(DBB, `select * from ${S}.review_signal(${uuidLit(sigId)}, ${lit(dec)}, ${lit(why)}, ${lit(idem)})`, as(sub));
  assert.equal(codeOf(() => rev(TOWN, 'dismiss', 'accepted_risk', 'grantrev-idem-01')), 'G3A06', 'requester of the diff is an evidence actor');
  assert.equal(codeOf(() => rev(U.staffS1, 'dismiss', 'accepted_risk', 'grantrev-idem-01')), 'G3A02');
  const ok = rev(OWNER1, 'acknowledge', 'followup_required', 'grantrev-idem-02')[0];
  assert.equal(ok.decision, 'acknowledge'); assert.ok(ok.receipt_id);
  assert.equal(codeOf(() => rev(OWNER1B, 'dismiss', 'accepted_risk', 'grantrev-idem-03')), 'G3C02');
});

test('more deliberate changes (RLS off, trigger disabled, invoker lost, search_path dropped, new definer fn, schema CREATE, column UPDATE, restrictive policy, revoked grant) are all flagged', () => {
  exec(DBB, `
    alter table ${S}.tenants disable row level security;
    alter table ${S}.audit_receipts disable trigger g3_no_update_delete;
    alter view ${S}.v_audit_events reset (security_invoker);
    alter function ${S}.actor_id() reset search_path;
    set role c10g3_owner;
    create function ${S}.sneaky() returns int language sql security definer as 'select 1';
    reset role;
    grant create on schema ${S} to c10g3_app;
    grant update (name) on ${S}.tenants to c10g3_backend;
    create policy only_restrictive on ${S}.audit_receipts as restrictive for select to c10g3_reader using (true);
    revoke execute on function ${S}.canonical_json(jsonb) from c10g3_reader;`);
  const d = diff(DBB, OWNER1, 'b-diff-idem-0007', T1, B1, null, bBaseline.baseline_id)[0];
  const row = one(DBB, `select diff from ${S}.v_catalog_diffs where diff_id = ${uuidLit(d.diff_id)}`, as(OWNER1));
  const rules = new Set(row.diff.findings.map((f) => f.rule));
  for (const r of ['GP12_RLS_DISABLED', 'GP31_TRIGGER_DISABLED', 'GP14_VIEW_INVOKER_LOST', 'GP17_FUNCTION_ATTRIBUTE_CHANGED', 'GP15_DEFINER_FUNCTION_ADDED',
    'GP08_SCHEMA_PRIVILEGE_WIDENED', 'GP05_WRITE_GRANT_ADDED', 'GP21_RESTRICTIVE_POLICY_ADDED', 'GP04_GRANT_REMOVED', 'GP01_EXEC_PUBLIC_OR_APP', 'GP20_PERMISSIVE_POLICY_ADDED']) {
    assert.ok(rules.has(r), `expected ${r}; got ${[...rules].join(',')}`);
  }
  assert.equal(row.diff.max_severity, 'high'); assert.ok(row.diff.finding_count >= 14);
  assert.ok(row.diff.findings.some((f) => f.rule === 'GP21_RESTRICTIVE_POLICY_ADDED' && f.severity === 'low'), 'a restrictive policy is only low severity');
  assert.ok(row.diff.findings.some((f) => f.rule === 'GP04_GRANT_REMOVED' && f.severity === 'low'));
  assertAdvisoryDiff(row.diff);
  assert.equal(canonicalJson(row.diff), canonicalJson(diffSnapshots(
    one(DBB, `select inventory from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(bBaseline.baseline_id)}`, as(OWNER1)).inventory,
    one(DBB, `select inventory from ${S}.v_catalog_snapshots where snapshot_id = ${uuidLit(d.snapshot_id)}`, as(OWNER1)).inventory)));
  // still not repaired
  assert.equal(one(DBB, `select relrowsecurity as r from pg_class where oid = '${S}.tenants'::regclass`).r, false);
});

test('a tampered stored baseline is rejected (digest mismatch) and Node verifyBaselineIntegrity agrees; fabricated bare JSON is never a baseline', () => {
  const good = one(DBB, `select * from ${S}.v_catalog_baselines where baseline_id = ${uuidLit(bBaseline.baseline_id)}`, as(OWNER1));
  assert.deepEqual(verifyBaselineIntegrity(good), { ok: true, reasons: [] });
  const forged = { ...good, inventory: { ...good.inventory, policies: [] } };
  assert.deepEqual(verifyBaselineIntegrity(forged), { ok: false, reasons: ['digest_mismatch'] });
  assert.equal(verifyBaselineIntegrity(good.inventory).ok, false, 'a bare inventory document is not a baseline');
  assert.equal(verifyBaselineIntegrity({ ...good, approved_by: null }).ok, false);
  // An owner-role (DBA-level) forgery that keeps the old digest but claims a clean inventory is caught by the integrity check
  exec(DBB, `begin; select set_config('c10_gov003.writer','append_path',true);
    insert into ${S}.catalog_baselines (baseline_id, tenant_id, business_id, baseline_seq, snapshot_id, approved_by, inventory, inventory_sha256, supersedes, event_id, receipt_id, request_idem)
    select gen_random_uuid(), tenant_id, business_id, 99, snapshot_id, approved_by, inventory #- '{policies}', inventory_sha256, baseline_id, event_id, receipt_id, 'forged-baseline-01'
      from ${S}.catalog_baselines where baseline_id = ${uuidLit(bBaseline.baseline_id)}; commit;`, owner);
  assert.equal(codeOf(() => diff(DBB, OWNER1, 'b-diff-idem-0008')), 'G3A04', 'latest baseline is the forged row: integrity failure, not a silent pass');
  const forgedId = one(DBB, `select baseline_id from ${S}.catalog_baselines where request_idem = 'forged-baseline-01'`, owner).baseline_id;
  assert.equal(codeOf(() => diff(DBB, OWNER1, 'b-diff-idem-0009', T1, B1, null, forgedId)), 'G3A04');
  assert.ok(diff(DBB, OWNER1, 'b-diff-idem-0010', T1, B1, null, bBaseline.baseline_id)[0].finding_count >= 14, 'the genuine baseline still works');
});

test('static fence: grant-review functions contain no GRANT/REVOKE/ALTER/CREATE POLICY/DROP/dynamic SQL and write only their own append-only tables', () => {
  const names = ['_catalog_inventory', '_catalog_facts', '_finding_class', 'catalog_diff', 'take_snapshot', 'record_baseline', 'diff_against_baseline'];
  const srcs = rows(DB, `select proname, prosrc from pg_proc where pronamespace = '${S}'::regnamespace and proname = any (array[${names.map(lit).join(',')}])`, owner);
  assert.equal(srcs.length, names.length);
  const allowed = new Set([`${S}.catalog_snapshots`, `${S}.catalog_baselines`, `${S}.catalog_diffs`]);
  for (const { proname, prosrc } of srcs) {
    const code = prosrc.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
    assert.doesNotMatch(code, /\b(grant|revoke|alter|drop|truncate|create|execute|copy|delete|update|policy)\b/i, `${proname} must not run DDL/privilege/dynamic SQL`);
    for (const m of code.matchAll(/insert\s+into\s+([a-z0-9_.]+)/gi)) assert.ok(allowed.has(m[1]), `${proname} writes ${m[1]}`);
  }
  // ... and the delivered SQL file itself never issues them inside any function body (only revoke/grant on its own EXECUTE lists at file level)
  const file = readFileSync(join(here, '..', '..', '..', 'internal', 'gov003', 'sql', '090_grant_review.sql'), 'utf8');
  const bodies = [...file.matchAll(/\$\$([\s\S]*?)\$\$/g)].map((m) => m[1].replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''"));
  assert.ok(bodies.length >= 7);
  for (const b of bodies) assert.doesNotMatch(b, /\b(grant|revoke|alter|drop|truncate|create|execute|copy)\b/i);
});
