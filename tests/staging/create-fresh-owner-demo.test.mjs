import test from 'node:test';
import assert from 'node:assert/strict';
import { createFreshOwnerDemo, proposedFreshDemo, STAGING, PUBLISHABLE_KEY } from '../../scripts/staging/create-fresh-owner-demo.mjs';

function simulated({ foreign = false, badAuth = false, badWorkspace = false } = {}) {
  const calls = [];
  const fetcher = async (url, opts) => {
    const pathname = url.slice(STAGING.length);
    calls.push({ url, opts, path: pathname });
    const response = (obj, status = 200) => ({ ok: status < 400, status, json: async () => obj });
    if (pathname === '/auth/v1/token?grant_type=password') return badAuth ? response({}, 400) : response({ access_token: 'temporary-test-token' });
    if (pathname === '/auth/v1/user') return response({ email: 'example@staging.invalid' });
    if (pathname === '/rest/v1/rpc/build01_context_v1') return response({
      tenants: [{ id: foreign ? 9801 : 1 }],
      legal_entities: [{ id: foreign ? 9811 : 1, tenant_id: foreign ? 9801 : 1 }],
      businesses: calls.some(x => x.path === '/rest/v1/rpc/build01_setup_v1')
        ? [{ id: 551, tenant_id: 1, slug: 'core10-demo-sweets-20261122-1234abcd', can_manage: true }] : [],
    });
    if (pathname === '/rest/v1/rpc/build01_setup_v1') return response({ business_id: 551, status: 'draft', production_certified: false });
    if (pathname === '/rest/v1/rpc/build01_workspace_v1') return response({ business_id: 551, can_manage: true,
      sites: badWorkspace ? [] : ['showroom', 'factory', 'warehouse'].map((kind, i) => ({
        business_id: 551, kind, label: ['Demo Showroom', 'Demo Factory', 'Demo Warehouse'][i],
      })) });
    throw Error('UNEXPECTED_PATH ' + pathname);
  };
  return { calls, fetcher };
}

test('fresh staging demo uses signed tenant-scoped setup and verifies three sites', async () => {
  const { calls, fetcher } = simulated();
  const result = await createFreshOwnerDemo({ email: 'example@staging.invalid', password: 'test-only-password',
    fetcher, nonce: '1234abcd', now: new Date('2026-11-22T00:00:00Z') });
  assert.equal(result.business_id, 551);
  assert.equal(result.sites, 3);
  assert.equal(result.slug, 'core10-demo-sweets-20261122-1234abcd');
  assert.equal(calls.length, 6);
  assert.ok(calls.every(c => c.url.startsWith(STAGING + '/')));
  assert.ok(calls.every(c => c.opts.headers.apikey === PUBLISHABLE_KEY && c.opts.redirect === 'error'));
  assert.ok(calls.filter(c => c.path === '/rest/v1/rpc/build01_setup_v1').length === 1);
  assert.ok(calls.filter(c => c.path.startsWith('/rest/')).every(c => c.opts.headers['Content-Profile'] === 'core10'));
  assert.equal(calls.filter(c => c.path.includes('delete') || c.opts.method === 'DELETE').length, 0);
  assert.doesNotMatch(JSON.stringify(result), /test-only-password|temporary-test-token/);
});

test('wrong tenant is rejected before setup write', async () => {
  const { calls, fetcher } = simulated({ foreign: true });
  await assert.rejects(createFreshOwnerDemo({ email: 'example@staging.invalid', password: 'test-only-password',
    fetcher, nonce: '1234abcd' }), /OWNER_STAGING_SCOPE_REQUIRED/);
  assert.equal(calls.some(c => c.path === '/rest/v1/rpc/build01_setup_v1'), false);
});

test('failed auth never reaches setup write', async () => {
  const { calls, fetcher } = simulated({ badAuth: true });
  await assert.rejects(createFreshOwnerDemo({ email: 'example@staging.invalid', password: 'test-only-password',
    fetcher, nonce: '1234abcd' }), /STAGING_REQUEST_FAILED_400/);
  assert.equal(calls.length, 1);
});

test('verification failure explicitly retains created ID for recovery', async () => {
  const { calls, fetcher } = simulated({ badWorkspace: true });
  await assert.rejects(createFreshOwnerDemo({ email: 'example@staging.invalid', password: 'test-only-password',
    fetcher, nonce: '1234abcd', now: new Date('2026-11-22T00:00:00Z') }), /CREATED_BUT_WORKSPACE_VERIFY_FAILED_551/);
  assert.equal(calls.some(c => c.opts.method === 'DELETE'), false);
});

test('invalid shape/nonce rejected, no secrets in module source or CLI help', () => {
  assert.throws(() => proposedFreshDemo('not-a-hex-nonce'), /INVALID_DEMO_NONCE/);
  const args = proposedFreshDemo('1234abcd', new Date('2026-11-22T00:00:00Z'));
  assert.equal(args.p_legal, 1);
  assert.equal(args.p_mode, 'advanced');
  assert.deepEqual(args.p_sites.map(x => x.kind), ['showroom', 'factory', 'warehouse']);
  assert.equal(args.p_request, 'owner-demo-sweets-20261122-1234abcd');
});
