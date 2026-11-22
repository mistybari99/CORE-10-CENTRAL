#!/usr/bin/env node
/**
 * CORE10 STAGING ONLY. Create a new clean demo business via the real signed setup RPC.
 * Deliberately does not DELETE old drafts or immutable canonical audit evidence.
 * Credentials are supplied at runtime, never written to disk or printed.
 */
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export const STAGING = 'https://rhrqhbyzrhaafynfhdaf.supabase.co';
// Public, browser-safe key already present in preview/core10-central-owner-app/build.mjs.
export const PUBLISHABLE_KEY = 'sb_publishable_HeeiXCowelMel7kc171mvg_4xwkh7wf';
export const OWNER_TENANT_ID = 1;
export const OWNER_LEGAL_ID = 1;

const SITES = Object.freeze([
  { kind: 'showroom', label: 'Demo Showroom' },
  { kind: 'factory', label: 'Demo Factory' },
  { kind: 'warehouse', label: 'Demo Warehouse' },
]);

function guard(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw Error(`${name}_REQUIRED`);
  return value;
}
function scopedRequest(fetcher) {
  return async function request(path, { method = 'GET', body, token } = {}) {
    if (!/^\/(auth\/v1\/(token\?grant_type=password|user)|rest\/v1\/rpc\/build01_(context|setup|workspace)_v1)$/.test(path)) {
      throw Error('STAGING_ENDPOINT_NOT_ALLOWED');
    }
    const headers = { apikey: PUBLISHABLE_KEY };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (path.startsWith('/rest/')) {
      headers['Content-Profile'] = 'core10';
      headers['Accept-Profile'] = 'core10';
    }
    const result = await fetcher(STAGING + path, {
      method, headers, redirect: 'error',
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!result.ok) throw Error('STAGING_REQUEST_FAILED_' + result.status);
    return result.json();
  };
}
export function proposedFreshDemo(nonce = randomBytes(4).toString('hex'), now = new Date()) {
  if (!/^[0-9a-f]{8}$/.test(nonce)) throw Error('INVALID_DEMO_NONCE');
  const day = now.toISOString().slice(0, 10).replaceAll('-', '');
  const slug = `core10-demo-sweets-${day}-${nonce}`;
  return Object.freeze({
    p_legal: OWNER_LEGAL_ID,
    p_slug: slug,
    p_template: 'sweets_bakery',
    p_display_name: 'CORE10 DEMO Sweets (TEST ONLY)',
    p_mode: 'advanced',
    p_sites: SITES.map(s => ({ ...s })),
    p_request: `owner-demo-sweets-${day}-${nonce}`,
    p_brand_hex: '#D38A2D',
  });
}

/** The only write is the canonical setup RPC. The server enforces tenant scope. */
export async function createFreshOwnerDemo({ email, password, fetcher = fetch, nonce, now } = {}) {
  guard(email, 'DEMO_EMAIL');
  guard(password, 'DEMO_PASSWORD');
  const request = scopedRequest(fetcher);
  const auth = await request('/auth/v1/token?grant_type=password', {
    method: 'POST', body: { email: email.trim(), password },
  });
  const token = guard(auth.access_token, 'SIGNED_ACCESS_TOKEN');
  const user = await request('/auth/v1/user', { token });
  if (user.email?.toLowerCase() !== email.trim().toLowerCase()) throw Error('SIGNED_USER_MISMATCH');
  const context = await request('/rest/v1/rpc/build01_context_v1', { method: 'POST', token, body: {} });
  if (!context.tenants?.some(t => Number(t.id) === OWNER_TENANT_ID) ||
      !context.legal_entities?.some(l => Number(l.id) === OWNER_LEGAL_ID && Number(l.tenant_id) === OWNER_TENANT_ID)) {
    throw Error('OWNER_STAGING_SCOPE_REQUIRED');
  }
  const args = proposedFreshDemo(nonce, now);
  const receipt = await request('/rest/v1/rpc/build01_setup_v1', { method: 'POST', token, body: args });
  const id = Number(receipt.business_id);
  if (!Number.isSafeInteger(id) || id < 1) throw Error('SETUP_RECEIPT_MISSING_ID');
  if (receipt.status !== 'draft' || receipt.production_certified !== false) throw Error(`SETUP_RECEIPT_INVALID_FOR_${id}`);
  const freshContext = await request('/rest/v1/rpc/build01_context_v1', { method: 'POST', token, body: {} });
  if (!freshContext.businesses?.some(b => Number(b.id) === id && Number(b.tenant_id) === OWNER_TENANT_ID && b.slug === args.p_slug && b.can_manage === true)) {
    throw Error(`CREATED_BUT_CONTEXT_VERIFY_FAILED_${id}`);
  }
  const workspace = await request('/rest/v1/rpc/build01_workspace_v1', {
    method: 'POST', token, body: { p_business: id },
  });
  const actual = workspace.sites || [];
  if (Number(workspace.business_id) !== id || workspace.can_manage !== true || actual.length !== SITES.length ||
      !SITES.every(s => actual.some(x => x.kind === s.kind && x.label === s.label && Number(x.business_id) === id))) {
    throw Error(`CREATED_BUT_WORKSPACE_VERIFY_FAILED_${id}`);
  }
  return Object.freeze({ business_id: id, slug: args.p_slug, status: 'draft', sites: actual.length,
    setup_url: 'https://core10-central.mistybari99.workers.dev/#/setup',
    reset_policy: 'fresh instance; immutable audit and old drafts are retained' });
}

async function main() {
  if (process.argv.includes('--help') || !process.argv.includes('--fresh')) {
    console.log('Fresh staging demo (no deletion): node scripts/staging/create-fresh-owner-demo.mjs --fresh');
    console.log('Requires CORE10_DEMO_EMAIL and CORE10_DEMO_PASSWORD environment variables.');
    console.log('Old demo businesses and canonical audit events remain intact.');
    return;
  }
  const result = await createFreshOwnerDemo({
    email: process.env.CORE10_DEMO_EMAIL,
    password: process.env.CORE10_DEMO_PASSWORD,
  });
  console.log(JSON.stringify(result, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(err => { console.error('Fresh demo failed:', err.message); process.exitCode = 1; });
}
