// Feature 11 incident-evidence-preservation: scoped cases, immutable evidence manifest, holds, independent Owner review,
// purge refusal (G3H02) and Story C. Disposable databases only (g3_f1011_*). Simulated sub claims are NOT signed GoTrue evidence.
// A hold flag in a mutable database is an engineering control, not a legal-hold certification (legal decisions: Owner/counsel gate).
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, execAsync, adminExec, lit, uuidLit } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, S1, S3, U } from '../lib/ids.mjs';
import {
  sha256Hex, buildManifest, verifyManifest, emptyManifestDigest, purgeDecision, protectionReasons, validateEvidenceInput,
  LEGAL_NOTICE, claimsLegalCompliance,
} from '../../../internal/gov003/server/evidence-manifest.mjs';

const DB = 'g3_f1011_incident';
const DB_TAMPER = 'g3_f1011_incident_tamper';
const ONLY = ['000', '010', '020', '030', '040', '110'];
const be = (sub) => ({ role: 'c10g3_backend', sub });
const rd = (sub) => ({ role: 'c10g3_reader', sub });
const own = { role: 'c10g3_owner' };
const A = U.bizOwnerB1; const B = U.bizOwnerB1Second; const TO = U.tenantOwnerT1;
let n = 0;
const key = (p = 'inc') => `${p}-${String(++n).padStart(6, '0')}`;
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const errOf = (fn) => { try { fn(); } catch (e) { return e; } return null; };
const ISO = (c) => `to_char(${c} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
const NOTICE_RE = /not a legal-hold certification.*Owner\/counsel gate/;
const FUTURE = "now() + interval '30 days'";

const sqlOpen = (o = {}) => `select * from c10_gov003_demo.open_incident(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_site => ${uuidLit(o.site ?? null)}, p_case_ref => ${lit(o.ref)}, p_severity => ${lit(o.sev ?? 'high')}, p_category => ${lit(o.cat ?? 'security')},
  p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlAdd = (o = {}) => `select * from c10_gov003_demo.add_evidence(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_case_ref => ${lit(o.ref)}, p_evidence_ref => ${lit(o.ev)}, p_kind => ${lit(o.kind ?? 'log_extract')}, p_sha256 => ${lit(o.sha)},
  p_byte_length => ${o.len ?? 10}::bigint, p_source_ref => ${lit(o.src ?? 'src:fixture')}, p_retain_until => ${o.retain ?? 'null::timestamptz'},
  p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlHold = (o = {}) => `select * from c10_gov003_demo.set_hold(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_case_ref => ${lit(o.ref)}, p_evidence_ref => ${lit(o.ev ?? null)}, p_hold_ref => ${lit(o.hold)}, p_reason_category => ${lit(o.reason ?? 'security_incident')},
  p_retention_until => ${o.until ?? FUTURE}, p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlReview = (o = {}) => `select * from c10_gov003_demo.review_hold(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_case_ref => ${lit(o.ref)}, p_hold_ref => ${lit(o.hold)}, p_decision => ${lit(o.decision ?? 'approved')}, p_note_code => ${lit(o.note ?? 'reviewed_ok')},
  p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlRelease = (o = {}) => `select * from c10_gov003_demo.release_hold(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_case_ref => ${lit(o.ref)}, p_hold_ref => ${lit(o.hold)}, p_reason_code => ${lit(o.reason ?? 'owner_released')},
  p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlPurge = (o = {}) => `select * from c10_gov003_demo.purge_evidence_attempt(p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)},
  p_case_ref => ${lit(o.ref)}, p_evidence_ref => ${lit(o.ev)}, p_reason_code => ${lit(o.reason ?? 'retention_expiry')},
  p_idem => ${lit(o.idem ?? key())}, p_claimed_actor => ${uuidLit(o.claimed ?? null)})`;
const sqlManifest = (o = {}) => `select * from c10_gov003_demo.verify_manifest(${uuidLit(o.t ?? T1)}, ${uuidLit(o.b ?? B1)}, ${lit(o.ref)}, ${lit(o.expected ?? null)})`;

const open = (o, sub = A, db = DB) => one(db, sqlOpen(o), be(sub));
const add = (o, sub = A, db = DB) => one(db, sqlAdd(o), be(sub));
const hold = (o, sub = A, db = DB) => one(db, sqlHold(o), be(sub));
const review = (o, sub = B, db = DB) => one(db, sqlReview(o), be(sub));
const release = (o, sub = B, db = DB) => one(db, sqlRelease(o), be(sub));
const purge = (o, sub = A, db = DB) => one(db, sqlPurge(o), be(sub));
const manifest = (o, sub = A, db = DB) => one(db, sqlManifest(o), rd(sub));
const sleep = (sec, db = DB) => exec(db, `select pg_sleep(${sec})`, be(A));
const count = (db, table, where = 'true') => Number(one(db, `select count(*)::int as c from c10_gov003_demo.${table} where ${where}`, own).c);

/** A case with `k` evidence items. */
function newCase(db = DB, k = 3, o = {}) {
  const ref = key('INC');
  const c = open({ ref, ...o }, A, db);
  const items = [];
  for (let i = 1; i <= k; i += 1) {
    const ev = `${ref}-ev${i}`; const sha = sha256Hex(`${ref} evidence ${i}`);
    const r = add({ ref, ev, sha, len: 100 + i, src: `src:log-${i}` }, A, db);
    items.push({ ev, sha, len: 100 + i, ...r });
  }
  return { ref, caseId: c.case_id, items };
}
const itemsOf = (db, caseId, sub = A) => rows(db, `select item_seq, evidence_id, evidence_ref, kind, sha256, byte_length, source_ref, ${ISO('retain_until')} as retain_until,
  ${ISO('added_at')} as added_at, added_by, prior_digest, item_digest, purged from c10_gov003_demo.v_incident_evidence where case_id = '${caseId}' order by item_seq`, rd(sub));
const holdsOf = (db, caseId, sub = A) => rows(db, `select hold_id, evidence_id, hold_ref, retention_until, placed_by, review_status, released, in_force
  from c10_gov003_demo.v_incident_holds where case_id = '${caseId}' order by placed_at`, rd(sub));
const auditOf = (db, eventId, sub = A) => one(db, `select * from c10_gov003_demo.v_audit_events where receipt_id = '${eventId}'`, rd(sub));
const auditCount = (db, action) => count(db, 'audit_events', `source_domain = 'gov003.incident' and action = '${action}'`);
/** Node decision for one evidence item from the scoped views (parity with SQL). */
function nodeDecision(db, caseId, evidenceRef) {
  const it = itemsOf(db, caseId).find((x) => x.evidence_ref === evidenceRef);
  const hs = holdsOf(db, caseId);
  return purgeDecision({ item: { evidence_id: it.evidence_id, retain_until: it.retain_until }, holds: hs, tombstoned: it.purged, now: new Date() });
}

before(() => { freshDb(DB, { only: ONLY }); });
after(() => { dropDb(DB); dropDb(DB_TAMPER); });

// ------------------------------------------------------------------------------------------------ open_incident
test('f11 open_incident: server-derived actor, audit receipt, scoped views; replay returns the same case; conflicts are G3C01', () => {
  const ref = key('INC');
  const c = open({ ref, idem: 'open-key-0001' });
  assert.equal(c.outcome, 'created'); assert.equal(c.replayed, false); assert.ok(c.case_id && c.audit_receipt_id);
  const v = one(DB, `select * from c10_gov003_demo.v_incident_cases where case_id = '${c.case_id}'`, rd(A));
  assert.equal(v.case_ref, ref); assert.equal(v.opened_by, A); assert.equal(v.severity, 'high'); assert.equal(v.category, 'security'); assert.equal(v.tenant_id, T1); assert.equal(v.business_id, B1);
  const ev = auditOf(DB, c.audit_receipt_id);
  assert.equal(ev.source_domain, 'gov003.incident'); assert.equal(ev.action, 'incident.open'); assert.equal(ev.reason_category, 'incident'); assert.equal(ev.actor_id, A);
  assert.deepEqual(ev.payload, { case_ref: ref, reason_code: 'security', severity: 'high', status: 'open' });
  const again = open({ ref, idem: 'open-key-0001' });
  assert.equal(again.outcome, 'replayed'); assert.equal(again.case_id, c.case_id); assert.equal(again.audit_receipt_id, c.audit_receipt_id);
  assert.equal(code(() => open({ ref, idem: 'open-key-0001', sev: 'low' })), 'G3C01');
  assert.equal(code(() => open({ ref, idem: key() })), 'G3C01');                       // same case_ref under another key
  assert.equal(code(() => open({ ref: key('INC'), idem: 'open-key-0001' })), 'G3C01'); // same key for a different case
  assert.equal(count(DB, 'incident_cases', `case_ref = '${ref}'`), 1);
});

test('f11 open_incident: site scope is same-business; invalid input is G3A03', () => {
  assert.equal(open({ ref: key('INC'), site: S1 }).outcome, 'created');
  assert.equal(code(() => open({ ref: key('INC'), site: S3 })), 'G3A02');            // site of another business
  for (const bad of [{ sev: 'urgent' }, { cat: 'other_thing' }, { ref: 'has space' }, { ref: 'token-abc' }, { ref: 'a@b.com' }, { ref: '' }, { idem: 'short' }, { ref: 'x'.repeat(129) }]) {
    assert.equal(code(() => open({ ref: key('INC'), ...bad })), 'G3A03', JSON.stringify(bad));
  }
});

// ------------------------------------------------------------------------------------------------ authorization matrix
test('f11 authorization: foreign investigator, other tenant, investor, revoked, site-only staff and support are denied on every operation', () => {
  const c = newCase(DB, 2);
  hold({ ref: c.ref, hold: key('H') });
  const h = holdsOf(DB, c.caseId)[0];
  const baseline = { cases: count(DB, 'incident_cases'), items: count(DB, 'incident_evidence_items'), holds: count(DB, 'incident_holds'), audit: count(DB, 'audit_events') };
  const denied = [U.t2Owner, U.bizOwnerB2, U.staffS1, U.investorB1, U.revokedB1, U.support];
  for (const sub of denied) {
    const w = (sql) => code(() => one(DB, sql, be(sub)));
    assert.equal(w(sqlOpen({ ref: key('INC') })), 'G3A02', `open ${sub}`);
    assert.equal(w(sqlAdd({ ref: c.ref, ev: key('E'), sha: sha256Hex('x') })), 'G3A02', `add ${sub}`);
    assert.equal(w(sqlHold({ ref: c.ref, hold: key('H') })), 'G3A02', `hold ${sub}`);
    assert.equal(w(sqlReview({ ref: c.ref, hold: h.hold_ref })), 'G3A02', `review ${sub}`);
    assert.equal(w(sqlRelease({ ref: c.ref, hold: h.hold_ref })), 'G3A02', `release ${sub}`);
    assert.equal(w(sqlPurge({ ref: c.ref, ev: c.items[0].ev })), 'G3A02', `purge ${sub}`);
    assert.equal(code(() => one(DB, sqlManifest({ ref: c.ref }), rd(sub))), 'G3A02', `manifest ${sub}`);
    assert.equal(code(() => one(DB, `select * from c10_gov003_demo.verify_evidence_item('${T1}', '${B1}', '${c.ref}', '${c.items[0].ev}', '${c.items[0].sha}')`, rd(sub))), 'G3A02', `item ${sub}`);
  }
  // foreign tenant using its own tenant id / the victim's ids in every combination
  assert.equal(code(() => open({ t: T2, b: B1, ref: key('INC') }, U.t2Owner)), 'G3A02');
  assert.equal(code(() => add({ t: T2, b: B3, ref: c.ref, ev: key('E'), sha: sha256Hex('y') }, U.t2Owner)), 'G3A02');   // own business, foreign case ref: not found, no leak
  assert.equal(code(() => add({ t: T1, b: B3, ref: c.ref, ev: key('E'), sha: sha256Hex('y') }, TO)), 'G3A02');
  assert.equal(code(() => open({ ref: key('INC'), b: '00000000-0000-4000-8000-000000000000' }, TO)), 'G3A02');
  // unauthenticated / unknown identity fail closed
  assert.equal(code(() => one(DB, sqlOpen({ ref: key('INC') }), { role: 'c10g3_backend' })), 'G3A05');
  assert.equal(code(() => open({ ref: key('INC') }, U.unknown)), 'G3A05');
  assert.equal(code(() => one(DB, sqlManifest({ ref: c.ref }), { role: 'c10g3_reader' })), 'G3A05');
  // nothing was written by any denied call
  assert.deepEqual({ cases: count(DB, 'incident_cases'), items: count(DB, 'incident_evidence_items'), holds: count(DB, 'incident_holds'), audit: count(DB, 'audit_events') }, baseline);
});

test('f11 authorization: a foreign caller cannot tell "no such case" from "not your case" (identical error text)', () => {
  const c = newCase(DB, 1);
  const real = errOf(() => add({ t: T2, b: B3, ref: c.ref, ev: key('E'), sha: sha256Hex('z') }, U.t2Owner));
  const ghost = errOf(() => add({ t: T2, b: B3, ref: 'no-such-case', ev: key('E'), sha: sha256Hex('z') }, U.t2Owner));
  assert.equal(real.detail, ghost.detail);
  assert.equal(errOf(() => add({ ref: 'no-such-case', ev: key('E'), sha: sha256Hex('z') }, A)).code, 'G3A02');
});

test('f11 forged actor: a caller-supplied actor that differs from the server-derived actor is G3A01 on every writer', () => {
  const c = newCase(DB, 1); const forged = TO;
  hold({ ref: c.ref, hold: 'forge-hold' });
  for (const sql of [sqlOpen({ ref: key('INC'), claimed: forged }), sqlAdd({ ref: c.ref, ev: key('E'), sha: sha256Hex('f'), claimed: forged }),
    sqlHold({ ref: c.ref, hold: key('H'), claimed: forged }), sqlReview({ ref: c.ref, hold: 'forge-hold', claimed: forged }, B),
    sqlRelease({ ref: c.ref, hold: 'forge-hold', claimed: forged }), sqlPurge({ ref: c.ref, ev: c.items[0].ev, claimed: forged })]) {
    assert.equal(code(() => one(DB, sql, be(A))), 'G3A01', sql.slice(0, 60));
  }
  assert.equal(open({ ref: key('INC'), claimed: A }).outcome, 'created'); // matching claim is harmless
});

test('f11 grants: writers only for the backend role; app has no rights; helpers are owner-only; definers pin search_path', () => {
  const c = newCase(DB, 1);
  const app = { role: 'c10g3_app', sub: A };
  assert.equal(code(() => exec(DB, sqlOpen({ ref: key('INC') }), app)), '42501');
  assert.equal(code(() => exec(DB, sqlOpen({ ref: key('INC') }), rd(A))), '42501');
  assert.equal(code(() => exec(DB, sqlPurge({ ref: c.ref, ev: c.items[0].ev }), rd(A))), '42501');
  for (const t of ['incident_cases', 'incident_evidence_items', 'incident_holds', 'incident_hold_reviews', 'incident_hold_releases', 'incident_evidence_tombstones',
    'v_incident_cases', 'v_incident_evidence', 'v_incident_holds']) assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.${t}`, app)), '42501', t);
  for (const f of ['_inc_protection(null, now())', "_inc_gate(null, null, null, null, null)", "_inc_audit(null, null, null, null, null, null, null, null)"]) {
    assert.equal(code(() => exec(DB, `select c10_gov003_demo.${f}`, be(A))), '42501', f);
  }
  assert.equal(code(() => exec(DB, 'alter table c10_gov003_demo.incident_holds disable trigger user', be(A))), '42501');      // only the owner role owns the tables
  assert.equal(code(() => exec(DB, 'alter table c10_gov003_demo.incident_evidence_items disable trigger user', rd(A))), '42501');
  assert.equal(code(() => exec(DB, 'set session_replication_role = replica', own)), '42501');                                  // owner is not a superuser
  const fns = rows(DB, `select p.proname, p.prosecdef, pg_get_userbyid(p.proowner) as owner, p.proconfig::text as cfg, has_function_privilege('public', p.oid, 'execute') as pub
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'c10_gov003_demo' and p.proname in ('open_incident','add_evidence','set_hold','review_hold','release_hold','purge_evidence_attempt','verify_manifest','verify_evidence_item','_inc_protection','_inc_gate')`, own);
  assert.equal(fns.length, 10);
  for (const f of fns) {
    assert.equal(f.prosecdef, true, f.proname); assert.equal(f.owner, 'c10g3_owner', f.proname); assert.equal(f.pub, false, f.proname);
    assert.match(f.cfg, /search_path=pg_catalog, c10_gov003_demo, pg_temp/, f.proname);
  }
});

// ------------------------------------------------------------------------------------------------ evidence manifest
test('f11 add_evidence: immutable manifest entries with sha256, byte length, kind, opaque source ref, chained digests and audit links', () => {
  const ref = key('INC'); const c = open({ ref });
  const sha1 = sha256Hex('first'); const sha2 = sha256Hex('second');
  const a = add({ ref, ev: 'e-1', sha: sha1, len: 5, kind: 'log_extract', src: 'src:app-log-7' });
  const b = add({ ref, ev: 'e-2', sha: sha2, len: 6, kind: 'image', src: 'db/snapshot#12', retain: "now() + interval '10 days'" });
  assert.equal(a.outcome, 'created'); assert.equal(a.item_seq, 1); assert.equal(b.item_seq, 2);
  assert.equal(a.manifest_digest, a.item_digest); assert.equal(b.manifest_digest, b.item_digest); assert.notEqual(a.item_digest, b.item_digest);
  const items = itemsOf(DB, c.case_id);
  assert.equal(items.length, 2);
  assert.deepEqual([items[0].kind, items[0].sha256, items[0].byte_length, items[0].source_ref, items[0].added_by], ['log_extract', sha1, 5, 'src:app-log-7', A]);
  assert.equal(items[0].prior_digest, '0'.repeat(64)); assert.equal(items[1].prior_digest, items[0].item_digest);
  assert.ok(items[1].retain_until && items[0].retain_until === null);
  const ev = auditOf(DB, a.audit_receipt_id);
  assert.equal(ev.action, 'incident.evidence.add'); assert.equal(ev.source_id, ref);
  assert.deepEqual(ev.payload, { artifact_sha256: sha1, case_ref: ref, count: '5', entity_kind: 'log_extract', evidence_ref: 'e-1', source_ref: 'src:app-log-7' });
  const m = manifest({ ref });
  assert.deepEqual([m.ok, m.item_count, m.purged_count, m.manifest_digest], [true, 2, 0, b.item_digest]);
});

test('f11 parity: SQL item digests, chain and manifest digest equal the Node manifest builder/verifier', () => {
  const c = newCase(DB, 4);
  const items = itemsOf(DB, c.caseId);
  const node = buildManifest(c.caseId, items.map((i) => ({ evidence_ref: i.evidence_ref, kind: i.kind, sha256: i.sha256, byte_length: i.byte_length,
    source_ref: i.source_ref, retain_until: i.retain_until, added_at: i.added_at, added_by: i.added_by })));
  assert.deepEqual(node.items.map((i) => i.item_digest), items.map((i) => i.item_digest));
  const sql = manifest({ ref: c.ref });
  assert.equal(node.manifestDigest, sql.manifest_digest);
  assert.equal(verifyManifest(c.caseId, items).manifestDigest, sql.manifest_digest);
  assert.equal(verifyManifest(c.caseId, items, { expectedDigest: sql.manifest_digest }).ok, true);
  // with a retain_until set the digest still matches
  const ref = key('INC'); const cc = open({ ref });
  add({ ref, ev: 'r-1', sha: sha256Hex('r'), len: 1, retain: "'2031-01-01T00:00:00Z'::timestamptz" });
  const it2 = itemsOf(DB, cc.case_id);
  assert.equal(it2[0].retain_until, '2031-01-01T00:00:00.000000Z');
  assert.equal(verifyManifest(cc.case_id, it2).manifestDigest, manifest({ ref }).manifest_digest);
  // empty manifest
  const e = open({ ref: key('INC') });
  assert.equal(manifest({ ref: e.case_ref }).manifest_digest, emptyManifestDigest(e.case_id));
  assert.equal(manifest({ ref: e.case_ref }).item_count, 0);
});

test('f11 verify_manifest: matching expected digest passes; a stale or forged manifest digest is G3A04', () => {
  const c = newCase(DB, 2);
  const m = manifest({ ref: c.ref });
  assert.equal(manifest({ ref: c.ref, expected: m.manifest_digest }).ok, true);
  assert.equal(code(() => manifest({ ref: c.ref, expected: 'e'.repeat(64) })), 'G3A04');
  add({ ref: c.ref, ev: key('late'), sha: sha256Hex('late') });
  assert.equal(code(() => manifest({ ref: c.ref, expected: m.manifest_digest })), 'G3A04');     // digest of the earlier manifest is now stale
  assert.equal(manifest({ ref: c.ref }, TO).item_count, 3);                                          // tenant owner may verify
});

test('f11 verify_evidence_item: content hash/length must match the manifest entry (G3A04), unknown evidence is G3A02', () => {
  const c = newCase(DB, 1); const it = c.items[0];
  const v = (sha, len = null, ref = it.ev) => one(DB, `select * from c10_gov003_demo.verify_evidence_item('${T1}', '${B1}', '${c.ref}', '${ref}', ${lit(sha)}, ${len === null ? 'null::bigint' : len})`, rd(A));
  assert.deepEqual([v(it.sha).ok, v(it.sha, it.len).ok, v(it.sha).purged], [true, true, false]);
  assert.equal(code(() => v(sha256Hex('different'))), 'G3A04');
  assert.equal(code(() => v(it.sha, it.len + 1)), 'G3A04');
  assert.equal(code(() => v(null)), 'G3A04');
  assert.equal(code(() => v(it.sha, null, 'nope')), 'G3A02');
});

test('f11 add_evidence: idempotent replay, conflicts and input validation', () => {
  const ref = key('INC'); open({ ref });
  const sha = sha256Hex('payload'); const k = 'add-key-0001';
  const a = add({ ref, ev: 'x-1', sha, len: 7, idem: k });
  const b = add({ ref, ev: 'x-1', sha, len: 7, idem: k });
  assert.equal(b.outcome, 'replayed'); assert.equal(b.evidence_id, a.evidence_id); assert.equal(b.item_seq, 1); assert.equal(b.audit_receipt_id, a.audit_receipt_id);
  assert.equal(code(() => add({ ref, ev: 'x-1', sha: sha256Hex('changed'), len: 7, idem: k })), 'G3C01');   // same key, changed payload
  assert.equal(code(() => add({ ref, ev: 'x-1', sha, len: 8, idem: k })), 'G3C01');
  assert.equal(code(() => add({ ref, ev: 'x-1', sha, len: 7, idem: key() })), 'G3C01');                   // evidence_ref already bound
  assert.equal(code(() => add({ ref, ev: 'x-2', sha, len: 7, idem: k })), 'G3C01');                        // key reused for a different evidence
  assert.equal(count(DB, 'incident_evidence_items', `evidence_ref = 'x-1' and case_id = (select case_id from c10_gov003_demo.incident_cases where case_ref = '${ref}')`), 1);
  for (const bad of [{ sha: 'ABC' }, { sha: sha.toUpperCase() }, { sha: sha.slice(1) }, { kind: 'video' }, { len: -1 }, { len: 1000000000001 }, { ev: 'has space' },
    { ev: 'someone@example.com' }, { ev: 'token-1' }, { ev: '4111111111111111' }, { src: 'Bearer abc' }, { src: 'x'.repeat(129) }, { idem: 'short' }]) {
    assert.equal(code(() => add({ ref, ev: key('v'), sha, ...bad })), 'G3A03', JSON.stringify(bad));
    if (bad.ev !== undefined || bad.src !== undefined || bad.kind !== undefined || bad.sha !== undefined || bad.len !== undefined) {
      const attempt = { evidence_ref: bad.ev ?? 'ok-ref', kind: bad.kind ?? 'log_extract', sha256: bad.sha ?? sha, byte_length: bad.len ?? 1, source_ref: bad.src ?? 'src:ok' };
      assert.equal(code(() => validateEvidenceInput(attempt)), 'G3A03', `node ${JSON.stringify(bad)}`);   // Node validator rejects the same inputs
    }
  }
});

test('f11 append-only evidence: UPDATE/DELETE/TRUNCATE/INSERT on every incident table are blocked, even for the owner role', () => {
  const c = newCase(DB, 2); hold({ ref: c.ref, hold: key('H') });
  const h = holdsOf(DB, c.caseId)[0]; review({ ref: c.ref, hold: h.hold_ref });
  const free = newCase(DB, 1);                       // no hold: still never deletable
  const rel = newCase(DB, 1); hold({ ref: rel.ref, hold: 'rel-hold' }); release({ ref: rel.ref, hold: 'rel-hold' }, B);   // rows in releases
  const gone = newCase(DB, 1); assert.equal(purge({ ref: gone.ref, ev: gone.items[0].ev }).outcome, 'tombstoned');         // rows in tombstones
  const tbls = { incident_cases: `case_id = '${free.caseId}'`, incident_evidence_items: `case_id = '${free.caseId}'`, incident_holds: `hold_id = '${h.hold_id}'`,
    incident_hold_reviews: `hold_id = '${h.hold_id}'`, incident_hold_releases: 'true', incident_evidence_tombstones: 'true' };
  for (const [t, w] of Object.entries(tbls)) {
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${t} where ${w}`, own)), 'G3H01', `delete ${t}`);
    assert.ok(['G3H01', '0A000'].includes(code(() => exec(DB, `truncate c10_gov003_demo.${t}`, own))), `truncate ${t}`);  // 0A000: FK-referenced tables cannot be truncated at all
    assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.${t} select * from c10_gov003_demo.${t} limit 1`, own)), 'G3H01', `insert ${t}`);
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${t}`, be(A))), '42501', `backend delete ${t}`);
    assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.${t} select * from c10_gov003_demo.${t} limit 1`, be(A))), '42501', `backend insert ${t}`);
  }
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_cases set severity = 'low' where case_id = '${free.caseId}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_evidence_items set sha256 = '${'0'.repeat(64)}' where case_id = '${free.caseId}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_holds set retention_until = now() where hold_id = '${h.hold_id}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_hold_reviews set decision = 'rejected' where hold_id = '${h.hold_id}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_evidence_items set sha256 = '${'0'.repeat(64)}'`, be(A))), '42501');
  assert.equal(itemsOf(DB, free.caseId).length, 1); assert.equal(manifest({ ref: free.ref }).ok, true);
});

// ------------------------------------------------------------------------------------------------ holds + independent review
test('f11 set_hold: placed_by is the server-derived actor, review pending, retention recorded, audited, replay-safe, with the no-legal-promise notice', () => {
  const c = newCase(DB, 2);
  const hr = key('H');
  const h = hold({ ref: c.ref, hold: hr, reason: 'counsel_request', until: "'2032-01-01T00:00:00Z'::timestamptz", idem: 'hold-key-0001' });
  assert.equal(h.outcome, 'created'); assert.equal(h.review_status, 'pending'); assert.equal(h.placed_by, A); assert.equal(h.replayed, false);
  assert.match(h.notice, NOTICE_RE); assert.equal(h.notice, LEGAL_NOTICE); assert.equal(claimsLegalCompliance(h.notice), false);
  const v = holdsOf(DB, c.caseId)[0];
  assert.equal(v.hold_ref, hr); assert.equal(v.placed_by, A); assert.equal(v.review_status, 'pending'); assert.equal(v.released, false); assert.equal(v.in_force, true); assert.equal(v.evidence_id, null);
  const row = one(DB, `select reason_category, ${ISO('retention_until')} as ru from c10_gov003_demo.v_incident_holds where hold_id = '${h.hold_id}'`, rd(A));
  assert.deepEqual([row.reason_category, row.ru], ['counsel_request', '2032-01-01T00:00:00.000000Z']);
  const ev = auditOf(DB, h.audit_receipt_id);
  assert.equal(ev.action, 'incident.hold.set'); assert.equal(ev.actor_id, A);
  assert.deepEqual(ev.payload, { case_ref: c.ref, hold_ref: hr, reason_code: 'counsel_request', status: 'active', window_end: '2032-01-01T00:00:00.000000Z' });
  const again = hold({ ref: c.ref, hold: hr, reason: 'counsel_request', until: "'2032-01-01T00:00:00Z'::timestamptz", idem: 'hold-key-0001' });
  assert.equal(again.outcome, 'replayed'); assert.equal(again.hold_id, h.hold_id);
  assert.equal(code(() => hold({ ref: c.ref, hold: hr, reason: 'counsel_request', until: "'2033-01-01T00:00:00Z'::timestamptz", idem: 'hold-key-0001' })), 'G3C01');
  assert.equal(code(() => hold({ ref: c.ref, hold: hr })), 'G3C01');                                  // hold_ref already used
});

test('f11 set_hold: validation (past retention, bad category/ref, unknown evidence) and item-level holds', () => {
  const c = newCase(DB, 2);
  for (const bad of [{ until: "now() - interval '1 hour'" }, { until: 'null::timestamptz' }, { reason: 'because' }, { hold: 'has space' }, { hold: 'token-9' }, { idem: 'short' }]) {
    assert.equal(code(() => hold({ ref: c.ref, hold: key('H'), ...bad })), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(code(() => hold({ ref: c.ref, hold: key('H'), ev: 'no-such-evidence' })), 'G3A02');
  const h = hold({ ref: c.ref, hold: key('H'), ev: c.items[0].ev });
  assert.equal(holdsOf(DB, c.caseId)[0].evidence_id, c.items[0].evidence_id);
  assert.equal(h.outcome, 'created');
});

test('f11 review: INDEPENDENT owner required; pending -> approved/rejected once; replay-safe; non-owners denied', () => {
  const c = newCase(DB, 1); const hr = key('H'); hold({ ref: c.ref, hold: hr });          // placed by A
  assert.equal(code(() => review({ ref: c.ref, hold: hr }, A)), 'G3A02');                  // self-review
  assert.match(errOf(() => review({ ref: c.ref, hold: hr }, A)).detail, /independent_review_required/);
  for (const sub of [U.staffS1, U.investorB1, U.revokedB1, U.support, U.t2Owner, U.bizOwnerB2]) assert.equal(code(() => review({ ref: c.ref, hold: hr }, sub)), 'G3A02', sub);
  assert.equal(holdsOf(DB, c.caseId)[0].review_status, 'pending');
  assert.equal(code(() => review({ ref: c.ref, hold: hr, decision: 'maybe' }, B)), 'G3A03');
  assert.equal(code(() => review({ ref: c.ref, hold: hr, note: 'Has Caps' }, B)), 'G3A03');
  assert.equal(code(() => review({ ref: c.ref, hold: 'no-such-hold' }, B)), 'G3A02');
  const k = 'rev-key-0001';
  const r = review({ ref: c.ref, hold: hr, decision: 'approved', note: 'confirmed', idem: k }, B);
  assert.equal(r.outcome, 'created'); assert.equal(r.review_status, 'approved'); assert.equal(r.reviewer_id, B); assert.match(r.notice, NOTICE_RE);
  assert.equal(holdsOf(DB, c.caseId)[0].review_status, 'approved');
  const ev = auditOf(DB, r.audit_receipt_id);
  assert.equal(ev.action, 'incident.hold.review'); assert.equal(ev.actor_id, B);
  assert.deepEqual(ev.payload, { case_ref: c.ref, hold_ref: hr, note_code: 'confirmed', review_decision: 'approved', status: 'reviewed' });
  assert.equal(review({ ref: c.ref, hold: hr, decision: 'approved', note: 'confirmed', idem: k }, B).outcome, 'replayed');
  assert.equal(code(() => review({ ref: c.ref, hold: hr, decision: 'rejected', note: 'confirmed', idem: k }, B)), 'G3C01');   // same key, other decision
  assert.equal(code(() => review({ ref: c.ref, hold: hr, decision: 'rejected' }, TO)), 'G3C01');                               // terminal state already set
  assert.equal(count(DB, 'incident_hold_reviews', `hold_id = '${holdsOf(DB, c.caseId)[0].hold_id}'`), 1);
});

test('f11 REAL two-process race: two independent owners review the same hold at once; exactly one terminal review is stored', async () => {
  const c = newCase(DB, 1); const hr = key('H'); hold({ ref: c.ref, hold: hr });
  const [a, b] = await Promise.all([
    execAsync(DB, sqlReview({ ref: c.ref, hold: hr, decision: 'approved' }), be(B)),
    execAsync(DB, sqlReview({ ref: c.ref, hold: hr, decision: 'rejected' }), be(TO)),
  ]);
  assert.equal([a, b].filter((x) => x.ok).length, 1, JSON.stringify([a.error?.message, b.error?.message]));
  assert.equal([a, b].find((x) => !x.ok).error.code, 'G3C01');
  const hid = holdsOf(DB, c.caseId)[0].hold_id;
  assert.equal(count(DB, 'incident_hold_reviews', `hold_id = '${hid}'`), 1);
  assert.ok(['approved', 'rejected'].includes(holdsOf(DB, c.caseId)[0].review_status));
  assert.equal(count(DB, 'audit_events', `action = 'incident.hold.review' and source_id = '${c.ref}'`), 1);   // the loser left no audit row
});

test('f11 REAL two-process race: concurrent add_evidence keeps one gapless digest chain; the same key from two backends yields one item', async () => {
  const ref = key('INC'); const c = open({ ref });
  const sqls = Array.from({ length: 6 }, (_, i) => sqlAdd({ ref, ev: `race-${i}`, sha: sha256Hex(`race ${i}`), len: i }));
  const out = await Promise.all(sqls.map((s) => execAsync(DB, s, be(A))));
  assert.ok(out.every((x) => x.ok), JSON.stringify(out.map((x) => x.error?.message)));
  const items = itemsOf(DB, c.case_id);
  assert.deepEqual(items.map((i) => i.item_seq), [1, 2, 3, 4, 5, 6]);
  const m = manifest({ ref });
  assert.deepEqual([m.ok, m.item_count], [true, 6]);
  assert.equal(verifyManifest(c.case_id, items).ok, true);
  const same = sqlAdd({ ref, ev: 'dup-1', sha: sha256Hex('dup'), len: 3, idem: key('dupkey') });
  const [x, y] = await Promise.all([execAsync(DB, same, be(A)), execAsync(DB, same, be(A))]);
  assert.ok(x.ok && y.ok);
  assert.equal(count(DB, 'incident_evidence_items', `evidence_ref = 'dup-1'`), 1);
  const diff = await Promise.all([execAsync(DB, sqlAdd({ ref, ev: 'dup-2', sha: sha256Hex('d2') }), be(A)), execAsync(DB, sqlAdd({ ref, ev: 'dup-2', sha: sha256Hex('d2') }), be(A))]);
  assert.equal(diff.filter((r) => r.ok).length, 1); assert.equal(diff.find((r) => !r.ok).error.code, 'G3C01');
  assert.equal(manifest({ ref }).ok, true);
});

test('f11 release_hold: independent owner only, adds a row (never deletes), retention_until floor remains, replay-safe', () => {
  const c = newCase(DB, 1); const hr = key('H');
  hold({ ref: c.ref, hold: hr, until: "clock_timestamp() + interval '1500 milliseconds'" });
  assert.equal(code(() => release({ ref: c.ref, hold: hr }, A)), 'G3A02');
  assert.match(errOf(() => release({ ref: c.ref, hold: hr }, A)).detail, /independent_release_required/);
  for (const sub of [U.staffS1, U.investorB1, U.revokedB1, U.support, U.t2Owner]) assert.equal(code(() => release({ ref: c.ref, hold: hr }, sub)), 'G3A02', sub);
  assert.equal(code(() => release({ ref: c.ref, hold: hr, reason: 'Bad Token' }, B)), 'G3A03');
  const k = 'rel-key-0001';
  const r = release({ ref: c.ref, hold: hr, idem: k }, B);
  assert.equal(r.outcome, 'created'); assert.equal(r.released_by, B); assert.equal(r.still_retained, true); assert.match(r.notice, NOTICE_RE);
  assert.equal(release({ ref: c.ref, hold: hr, idem: k }, B).outcome, 'replayed');
  assert.equal(code(() => release({ ref: c.ref, hold: hr }, TO)), 'G3C01');                      // already released
  const v = holdsOf(DB, c.caseId)[0];
  assert.deepEqual([v.released, v.in_force], [true, true]);                                         // retention floor keeps it in force
  assert.equal(count(DB, 'incident_holds', `hold_id = '${v.hold_id}'`), 1);                         // the hold row is still there
  const ev = auditOf(DB, r.audit_receipt_id);
  assert.deepEqual(ev.payload, { case_ref: c.ref, hold_ref: hr, reason_code: 'owner_released', status: 'released' });
  sleep(2);
  assert.equal(holdsOf(DB, c.caseId)[0].in_force, false);
});

// ------------------------------------------------------------------------------------------------ purge service
test('f11 purge with no hold: only a tombstone is appended; history, manifest and hash stay; second purge is a no-op', () => {
  const c = newCase(DB, 3); const it = c.items[1];
  const manifestBefore = manifest({ ref: c.ref });
  const nodeSays = nodeDecision(DB, c.caseId, it.ev);
  const k = key('purge');
  const p = purge({ ref: c.ref, ev: it.ev, idem: k });
  assert.deepEqual([p.outcome, p.error_code, p.protection, p.replayed], ['tombstoned', null, [], false]);
  assert.equal(nodeSays.outcome, 'tombstoned'); assert.match(p.notice, NOTICE_RE);
  const row = itemsOf(DB, c.caseId)[1];
  assert.equal(row.purged, true); assert.equal(row.sha256, it.sha); assert.equal(row.item_digest, it.item_digest);            // item is untouched
  assert.equal(count(DB, 'incident_evidence_items', `case_id = '${c.caseId}'`), 3);
  const t = one(DB, `select * from c10_gov003_demo.incident_evidence_tombstones where evidence_id = '${it.evidence_id}'`, own);
  assert.deepEqual([t.sha256_retained, t.purged_by, t.reason_code], [it.sha, A, 'retention_expiry']);
  const m = manifest({ ref: c.ref });
  assert.deepEqual([m.ok, m.item_count, m.purged_count, m.manifest_digest], [true, 3, 1, manifestBefore.manifest_digest]);   // purge never edits the manifest
  assert.equal(auditOf(DB, p.audit_receipt_id).action, 'incident.purge.tombstone');
  assert.equal(auditOf(DB, p.audit_receipt_id).payload.status, 'tombstoned');
  const again = purge({ ref: c.ref, ev: it.ev, idem: k });
  assert.deepEqual([again.outcome, again.replayed, again.audit_receipt_id], ['tombstoned', true, p.audit_receipt_id]);
  assert.equal(purge({ ref: c.ref, ev: it.ev }).outcome, 'already_purged');
  assert.equal(code(() => purge({ ref: c.ref, ev: c.items[0].ev, idem: k })), 'G3C01');           // key reused for another evidence
  assert.equal(nodeDecision(DB, c.caseId, it.ev).outcome, 'already_purged');
});

test('f11 purge under an ACTIVE HOLD is refused with G3H02 and audited; evidence is retained; replay returns the recorded refusal', () => {
  const c = newCase(DB, 2); const hr = key('H'); hold({ ref: c.ref, hold: hr });
  const it = c.items[0]; const k = key('purge');
  const auditBefore = auditCount(DB, 'incident.purge.blocked');
  const decision = nodeDecision(DB, c.caseId, it.ev);
  const p = purge({ ref: c.ref, ev: it.ev, idem: k });
  assert.deepEqual([p.outcome, p.error_code, p.replayed], ['refused', 'G3H02', false]);
  assert.deepEqual(p.protection, ['hold_active', 'hold_retention']);
  assert.deepEqual([decision.outcome, decision.errorCode, decision.reasons], ['refused', 'G3H02', p.protection]);   // Node mirror
  assert.equal(auditCount(DB, 'incident.purge.blocked'), auditBefore + 1);
  const ev = auditOf(DB, p.audit_receipt_id);
  assert.equal(ev.action, 'incident.purge.blocked'); assert.equal(ev.actor_id, A);
  assert.deepEqual(ev.payload, { case_ref: c.ref, detail_code: 'hold_active.hold_retention', evidence_ref: it.ev, reason_code: 'retention_expiry', status: 'blocked' });
  assert.equal(count(DB, 'incident_evidence_tombstones', `case_id = '${c.caseId}'`), 0);
  assert.equal(itemsOf(DB, c.caseId).length, 2); assert.equal(manifest({ ref: c.ref }).ok, true);
  const again = purge({ ref: c.ref, ev: it.ev, idem: k });
  assert.deepEqual([again.outcome, again.error_code, again.replayed, again.protection], ['refused', 'G3H02', true, p.protection]);
  assert.equal(auditCount(DB, 'incident.purge.blocked'), auditBefore + 1);                                              // replay wrote nothing
  const other = purge({ ref: c.ref, ev: c.items[1].ev });                                                                 // case-wide hold covers every item
  assert.equal(other.outcome, 'refused');
});

test('f11 a REJECTED or still-PENDING review does not release anything: the hold keeps blocking until explicitly released', () => {
  const c = newCase(DB, 1); const hr = key('H'); hold({ ref: c.ref, hold: hr });
  assert.equal(purge({ ref: c.ref, ev: c.items[0].ev }).outcome, 'refused');            // pending
  review({ ref: c.ref, hold: hr, decision: 'rejected', note: 'not_needed' }, B);
  assert.equal(holdsOf(DB, c.caseId)[0].review_status, 'rejected');
  const p = purge({ ref: c.ref, ev: c.items[0].ev });
  assert.equal(p.outcome, 'refused'); assert.ok(p.protection.includes('hold_active'));
  assert.equal(count(DB, 'incident_evidence_tombstones', `case_id = '${c.caseId}'`), 0);
});

test('f11 item-level hold covers only that item; item retain_until and hold retention floor also block purge, and expire', () => {
  const c = newCase(DB, 2); hold({ ref: c.ref, hold: key('H'), ev: c.items[0].ev });
  assert.equal(purge({ ref: c.ref, ev: c.items[0].ev }).outcome, 'refused');
  assert.equal(purge({ ref: c.ref, ev: c.items[1].ev }).outcome, 'tombstoned');           // other item is not covered
  // item retention-until (no hold at all)
  const ref = key('INC'); const cc = open({ ref });
  add({ ref, ev: 'ret-1', sha: sha256Hex('ret'), retain: "clock_timestamp() + interval '1500 milliseconds'" });
  const r1 = purge({ ref, ev: 'ret-1' });
  assert.deepEqual([r1.outcome, r1.error_code, r1.protection], ['refused', 'G3H02', ['item_retention']]);
  assert.equal(nodeDecision(DB, cc.case_id, 'ret-1').reasons[0], 'item_retention');
  // hold released by an independent owner but its retention floor is still in the future
  const ref2 = key('INC'); const c2 = open({ ref: ref2 });
  add({ ref: ref2, ev: 'f-1', sha: sha256Hex('floor') });
  hold({ ref: ref2, hold: 'floor-hold', until: "clock_timestamp() + interval '1500 milliseconds'" });
  release({ ref: ref2, hold: 'floor-hold' }, B);
  const r2 = purge({ ref: ref2, ev: 'f-1' });
  assert.deepEqual([r2.outcome, r2.protection], ['refused', ['hold_retention']]);
  assert.equal(nodeDecision(DB, c2.case_id, 'f-1').reasons.join(), 'hold_retention');
  sleep(2);
  assert.equal(nodeDecision(DB, cc.case_id, 'ret-1').outcome, 'tombstoned');
  assert.equal(purge({ ref, ev: 'ret-1' }).outcome, 'tombstoned');
  assert.equal(nodeDecision(DB, c2.case_id, 'f-1').outcome, 'tombstoned');
  const r3 = purge({ ref: ref2, ev: 'f-1' });
  assert.equal(r3.outcome, 'tombstoned');                                                  // released + retention passed -> allowed, as a tombstone only
  assert.equal(itemsOf(DB, c2.case_id).length, 1);
});

test('f11 purge authorization: non-owners and foreign callers are denied; evidence is not found across cases', () => {
  const c = newCase(DB, 1); const d = newCase(DB, 1);
  for (const sub of [U.staffS1, U.investorB1, U.revokedB1, U.support, U.t2Owner, U.bizOwnerB2]) assert.equal(code(() => purge({ ref: c.ref, ev: c.items[0].ev }, sub)), 'G3A02', sub);
  assert.equal(code(() => purge({ ref: c.ref, ev: d.items[0].ev })), 'G3A02');             // other case's evidence
  assert.equal(code(() => purge({ ref: c.ref, ev: c.items[0].ev, reason: 'Bad Reason' })), 'G3A03');
  assert.equal(count(DB, 'incident_evidence_tombstones', `case_id = '${c.caseId}'`), 0);
});

test('f11 direct deletion path: held evidence cannot be deleted, updated, truncated or tombstoned by ANY role, including the owner role (G3H02/G3H01)', () => {
  const c = newCase(DB, 2); hold({ ref: c.ref, hold: key('H') });
  const it = c.items[0];
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${it.evidence_id}'`, own)), 'G3H02');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_evidence_items set byte_length = 0 where evidence_id = '${it.evidence_id}'`, own)), 'G3H02');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_evidence_items where case_id = '${c.caseId}'`, own)), 'G3H02');
  assert.ok(['G3H01', '0A000'].includes(code(() => exec(DB, `truncate c10_gov003_demo.incident_evidence_items`, own))));
  // the owner role even if it sets the append-path flag itself cannot add a tombstone for protected evidence
  assert.equal(code(() => exec(DB, `select set_config('c10_gov003.writer', 'append_path', false);
    insert into c10_gov003_demo.incident_evidence_tombstones (evidence_id, case_id, tenant_id, business_id, sha256_retained, purged_by, reason_code, purged_at, audit_event_id, audit_receipt_id)
    select i.evidence_id, i.case_id, i.tenant_id, i.business_id, i.sha256, '${A}', 'forced', now(), i.audit_event_id, i.audit_receipt_id from c10_gov003_demo.incident_evidence_items i where i.evidence_id = '${it.evidence_id}'`, own)), 'G3H02');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_holds`, own)), 'G3H01');                // the hold itself cannot be erased either
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.audit_events where source_domain = 'gov003.incident'`, own)), 'G3H01');
  assert.equal(itemsOf(DB, c.caseId).length, 2); assert.equal(manifest({ ref: c.ref }).ok, true);
  assert.equal(count(DB, 'incident_evidence_tombstones', `case_id = '${c.caseId}'`), 0);
});

test('f11 Story C: an incident with an active hold retains ALL bound evidence through every attempted purge; only release + retention expiry allows tombstones', () => {
  const c = newCase(DB, 5); const hr = key('H');
  const before = manifest({ ref: c.ref });
  hold({ ref: c.ref, hold: hr, reason: 'security_incident', until: "clock_timestamp() + interval '2500 milliseconds'" });
  review({ ref: c.ref, hold: hr, decision: 'approved' }, B);
  const shas = itemsOf(DB, c.caseId).map((i) => i.sha256);
  const refusedBefore = auditCount(DB, 'incident.purge.blocked');
  // (1) the retention service, once per item and once more with a fresh key
  for (const it of c.items) for (let round = 0; round < 2; round += 1) {
    const p = purge({ ref: c.ref, ev: it.ev });
    assert.deepEqual([p.outcome, p.error_code], ['refused', 'G3H02']);
  }
  // (2) every direct path by the owner role, by the backend and by reader/app
  for (const it of c.items) {
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${it.evidence_id}'`, own)), 'G3H02');
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.incident_evidence_items set sha256 = '${'f'.repeat(64)}' where evidence_id = '${it.evidence_id}'`, own)), 'G3H02');
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${it.evidence_id}'`, be(A))), '42501');
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${it.evidence_id}'`, { role: 'c10g3_app', sub: A })), '42501');
  }
  // (3) evidence is intact: same rows, same hashes, same manifest digest, no tombstones, refusals audited
  assert.deepEqual(itemsOf(DB, c.caseId).map((i) => i.sha256), shas);
  assert.equal(itemsOf(DB, c.caseId).every((i) => i.purged === false), true);
  const after = manifest({ ref: c.ref });
  assert.deepEqual([after.ok, after.item_count, after.purged_count, after.manifest_digest], [true, 5, 0, before.manifest_digest]);
  assert.equal(count(DB, 'incident_evidence_tombstones', `case_id = '${c.caseId}'`), 0);
  assert.equal(auditCount(DB, 'incident.purge.blocked') - refusedBefore, 10);
  // (4) the control is the hold, not an accident: independent release alone is not enough while the retention floor holds ...
  release({ ref: c.ref, hold: hr, reason: 'owner_released' }, TO);
  assert.deepEqual(purge({ ref: c.ref, ev: c.items[0].ev }).protection, ['hold_retention']);
  assert.equal(nodeDecision(DB, c.caseId, c.items[0].ev).outcome, 'refused');
  // ... and once it passes, purge is allowed but still appends a tombstone only
  sleep(3);
  const p = purge({ ref: c.ref, ev: c.items[0].ev });
  assert.equal(p.outcome, 'tombstoned');
  const m = manifest({ ref: c.ref });
  assert.deepEqual([m.ok, m.item_count, m.purged_count, m.manifest_digest], [true, 5, 1, before.manifest_digest]);
});

test('f11 Node/SQL parity of the purge rule across scenarios (hold, item retention, release floor, other-item hold)', () => {
  const c = newCase(DB, 3);
  const outcomes = () => c.items.map((i) => nodeDecision(DB, c.caseId, i.ev));
  assert.deepEqual(outcomes().map((d) => d.outcome), ['tombstoned', 'tombstoned', 'tombstoned']);
  hold({ ref: c.ref, hold: key('H'), ev: c.items[1].ev });
  assert.deepEqual(outcomes().map((d) => d.outcome), ['tombstoned', 'refused', 'tombstoned']);
  for (const [i, it] of c.items.entries()) {
    const p = purge({ ref: c.ref, ev: it.ev });
    const d = outcomes()[i];
    if (i === 2) assert.equal(p.outcome, 'tombstoned');                                  // purge the unprotected tail item first
    else assert.deepEqual([p.outcome, p.protection ?? []], i === 1 ? ['refused', ['hold_active', 'hold_retention']] : ['tombstoned', []]);
    assert.ok(d);
  }
  assert.deepEqual(protectionReasons({ item: { evidence_id: 'e', retain_until: null }, holds: [{ evidence_id: 'e', retention_until: '2999-01-01T00:00:00Z', released: false }], now: new Date() }),
    ['hold_active', 'hold_retention']);
});

// ------------------------------------------------------------------------------------------------ wording / limitation
test('f11 documentation: tables, functions and results make no legal-compliance promise and state the engineering-control limit', () => {
  const doc = rows(DB, `select obj_description(c.oid, 'pg_class') as d from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'c10_gov003_demo' and c.relname in ('incident_holds', 'incident_evidence_items')`, own).map((r) => r.d);
  assert.equal(doc.length, 2);
  for (const d of doc) assert.equal(claimsLegalCompliance(d), false);
  assert.match(doc[0] + doc[1], /NOT a legal-hold certification/); assert.match(doc[0] + doc[1], /Owner\/counsel gate/);
  const src = rows(DB, `select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'c10_gov003_demo' and p.proname in ('set_hold','review_hold','release_hold','purge_evidence_attempt')`, own);
  assert.equal(src.length, 4);
  for (const s of src) { assert.match(s.prosrc, /not a legal-hold certification/); assert.equal(claimsLegalCompliance(s.prosrc), false); }
});

test('f11 privileged DDL by the owner role is possible but is DETECTED (manifest verify) -- stated limitation, not a legal guarantee', () => {
  freshDb(DB_TAMPER, { only: ONLY });
  const c = newCase(DB_TAMPER, 3);
  hold({ ref: c.ref, hold: key('H') }, A, DB_TAMPER);
  const su = (sql) => adminExec(`set session_replication_role = replica; ${sql}`, DB_TAMPER);
  // 1. superuser edits a stored byte length -> digest mismatch at that item (Node verifier agrees)
  su(`update c10_gov003_demo.incident_evidence_items set byte_length = byte_length + 1 where evidence_id = '${c.items[1].evidence_id}'`);
  let m = manifest({ ref: c.ref }, A, DB_TAMPER);
  assert.deepEqual([m.ok, m.first_bad_seq, m.reason], [false, 2, 'item_digest_mismatch']);
  const nodeView = verifyManifest(c.caseId, itemsOf(DB_TAMPER, c.caseId));
  assert.deepEqual([nodeView.ok, nodeView.firstBadSeq, nodeView.reason], [false, 2, 'item_digest_mismatch']);
  su(`update c10_gov003_demo.incident_evidence_items set byte_length = byte_length - 1 where evidence_id = '${c.items[1].evidence_id}'`);
  assert.equal(manifest({ ref: c.ref }, A, DB_TAMPER).ok, true);
  // 2. superuser removes the middle item -> sequence gap
  su(`delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${c.items[1].evidence_id}'`);
  m = manifest({ ref: c.ref }, A, DB_TAMPER);
  assert.deepEqual([m.ok, m.reason], [false, 'sequence_gap']);
  assert.equal(verifyManifest(c.caseId, itemsOf(DB_TAMPER, c.caseId)).reason, 'sequence_gap');
  // 3. superuser edits the audit event that bound an item -> audit link mismatch
  const c2 = newCase(DB_TAMPER, 2);
  su(`update c10_gov003_demo.audit_events set payload = jsonb_set(payload, '{artifact_sha256}', '"${'a'.repeat(64)}"') where event_id = (select audit_event_id from c10_gov003_demo.incident_evidence_items where evidence_id = '${c2.items[0].evidence_id}')`);
  m = manifest({ ref: c2.ref }, A, DB_TAMPER);
  assert.deepEqual([m.ok, m.first_bad_seq, m.reason], [false, 1, 'audit_link_mismatch']);
  assert.equal(one(DB_TAMPER, `select ok from c10_gov003_demo.verify_chain('${T1}', '${B1}')`, rd(A)).ok, false);
  // 4. a superuser can bypass the hold guard (G3H02 is an engineering control); the audit chain/manifest make that visible
  su(`delete from c10_gov003_demo.incident_evidence_items where evidence_id = '${c2.items[1].evidence_id}'`);
  assert.equal(manifest({ ref: c2.ref }, A, DB_TAMPER).ok, false);
});
