import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AdapterError, SessionAdapter, NoSignedSessionAdapter, FixtureSessionAdapter, createSessionAdapter, CanonicalAuditAdapter,
  GitHubVerifierAdapter, DeployProbeAdapter, DEMO_IDENTITIES, isDemoModeEnabled, ADAPTER_STATUS, DEMO_BANNER,
} from '../../../internal/gov003/server/adapters.mjs';
import { U } from '../lib/ids.mjs';

const rejects = (p, code) => assert.rejects(p, (e) => e instanceof AdapterError && e.code === code);

test('NoSignedSessionAdapter fails closed for every request shape', async () => {
  const a = new NoSignedSessionAdapter();
  for (const req of [undefined, {}, { headers: {} }, { headers: { authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.e30.x' } },
    { headers: { 'x-demo-identity': 'business_owner_b1' } }, { demoIdentity: 'business_owner_b1' }]) {
    await rejects(a.authenticate(req), 'SIGNED_SESSION_UNAVAILABLE');
  }
});

test('SessionAdapter base is abstract', async () => { await rejects(new SessionAdapter().authenticate({}), 'NOT_IMPLEMENTED'); });

test('FixtureSessionAdapter refuses to exist unless demo mode is explicitly on', () => {
  for (const o of [{}, { demo: false, env: {} }, { demo: 'true', env: {} }, { demo: 1, env: {} }, { env: { GOV003_DEMO_MODE: '0' } },
    { env: { GOV003_DEMO_MODE: 'true' } }, { env: { GOV003_DEMO_MODE: '' } }]) {
    assert.throws(() => new FixtureSessionAdapter(o), (e) => e.code === 'DEMO_MODE_REQUIRED', JSON.stringify(o));
  }
  assert.equal(isDemoModeEnabled({ env: {} }), false);
  assert.equal(isDemoModeEnabled({ demo: true, env: {} }), true);
  assert.equal(isDemoModeEnabled({ env: { GOV003_DEMO_MODE: '1' } }), true);
});

test('FixtureSessionAdapter maps labels to inert ids, labelled DEMO / NOT LIVE, never signed', async () => {
  const a = new FixtureSessionAdapter({ demo: true, env: {} });
  const s = await a.authenticate({ headers: { 'x-demo-identity': 'business_owner_b1' } });
  assert.equal(s.actor_id, U.bizOwnerB1);
  assert.equal(s.signed, false); assert.equal(s.demo, true); assert.equal(s.proof, null); assert.equal(s.source, 'fixture');
  assert.equal(s.banner, DEMO_BANNER); assert.equal(s.banner, 'DEMO / NOT LIVE');
  assert.ok(Object.isFrozen(s));
  assert.equal((await a.authenticate({ demoIdentity: 'tenant_owner_t2' })).actor_id, U.t2Owner);
  assert.equal(Object.keys(DEMO_IDENTITIES).length, 9);
  // a caller-supplied UUID, role, or bearer token is not an identity
  for (const req of [{ headers: { 'x-demo-identity': U.bizOwnerB1 } }, { headers: { 'x-demo-identity': '__proto__' } },
    { headers: { 'x-demo-identity': 'constructor' } }, { headers: { authorization: 'Bearer x' } }, {}, undefined, { headers: { 'x-demo-identity': 5 } }]) {
    await rejects(a.authenticate(req), 'FIXTURE_IDENTITY_UNKNOWN');
  }
});

test('FixtureSessionAdapter re-checks demo mode on every call (env flag switched off mid-run)', async () => {
  const env = { GOV003_DEMO_MODE: '1' };
  const a = new FixtureSessionAdapter({ env });
  assert.equal((await a.authenticate({ demoIdentity: 'staff_s1' })).actor_id, U.staffS1);
  env.GOV003_DEMO_MODE = '0';
  await rejects(a.authenticate({ demoIdentity: 'staff_s1' }), 'DEMO_MODE_REQUIRED');
});

test('createSessionAdapter: outside demo mode only the failing adapter is ever produced', async () => {
  const off = createSessionAdapter({ env: {} });
  assert.ok(off instanceof NoSignedSessionAdapter);
  await rejects(off.authenticate({ headers: { 'x-demo-identity': 'business_owner_b1' } }), 'SIGNED_SESSION_UNAVAILABLE');
  assert.ok(createSessionAdapter({ demo: true, env: {} }) instanceof FixtureSessionAdapter);
  assert.ok(createSessionAdapter({ env: { GOV003_DEMO_MODE: '1' } }) instanceof FixtureSessionAdapter);
});

test('integration stubs throw INTEGRATION_PENDING and are never "integrated"', async () => {
  const a = new CanonicalAuditAdapter(); const g = new GitHubVerifierAdapter(); const d = new DeployProbeAdapter();
  for (const x of [a, g, d]) assert.equal(x.integrated, false);
  await rejects(a.appendEvent({}), 'INTEGRATION_PENDING'); await rejects(a.getReceipt('x'), 'INTEGRATION_PENDING'); await rejects(a.verifyChain(), 'INTEGRATION_PENDING');
  await rejects(g.verifyCommit({ sha: 'abc' }), 'INTEGRATION_PENDING'); await rejects(g.verifyCheckRun({}), 'INTEGRATION_PENDING');
  await rejects(d.probe({}), 'INTEGRATION_PENDING');
  assert.equal(ADAPTER_STATUS.signed_gotrue_session, 'FUTURE_BLOCKER');
  assert.ok(Object.isFrozen(ADAPTER_STATUS));
});
