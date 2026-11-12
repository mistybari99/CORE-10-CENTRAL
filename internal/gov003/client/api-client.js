// GOV-003 scoped browser adapter. DEMO / NOT LIVE.
//
// Deliberately tiny and deliberately weak:
//  * fetches ONLY same-origin paths that start with /api/ (no absolute URL, no production URL, ever);
//  * has no credential of any kind: no service role key (never), no token, no cookie handling. The only identity hint it
//    can send is the inert fixture label in X-Demo-Identity, which the local server accepts in demo mode only and the
//    server (not this file) turns into an actor. This file can neither choose nor assert an actor, role or tenant;
//  * cannot touch a table: every action is one of the documented endpoints below, and the database decides each time;
//  * never throws on HTTP errors: callers get { status, ok, data } and render denied / conflict / error states.

const ALLOWED_PREFIX = '/api/';

export function createApiClient({ getIdentity = () => null } = {}) {
  async function call(method, path, { query, body } = {}) {
    if (typeof path !== 'string' || !path.startsWith(ALLOWED_PREFIX) || path.includes('//') || path.includes('..')) {
      throw new Error('api-client only calls same-origin /api/ endpoints');
    }
    let url = path;
    if (query) {
      const sp = new URLSearchParams();
      for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== '') sp.set(k, String(v));
      const qs = sp.toString();
      if (qs) url += `?${qs}`;
    }
    const headers = { accept: 'application/json' };
    const identity = getIdentity();
    if (identity) headers['x-demo-identity'] = identity;
    if (body !== undefined) headers['content-type'] = 'application/json';
    try {
      const res = await fetch(url, { method, headers, credentials: 'omit', cache: 'no-store', redirect: 'error',
        body: body === undefined ? undefined : JSON.stringify(body) });
      let data = null;
      try { data = await res.json(); } catch { data = { ok: false, error: 'bad_response', message: 'The server returned a non-JSON response.' }; }
      return { status: res.status, ok: res.ok, data };
    } catch {
      return { status: 0, ok: false, data: { ok: false, error: 'network', message: 'The local demo server is not reachable.' } };
    }
  }
  const scope = (s) => ({ tenant_id: s.tenant_id, business_id: s.business_id });
  const get = (path, s, extra) => call('GET', path, { query: { ...scope(s), ...(extra || {}) } });
  const post = (path, s, extra) => call('POST', path, { body: { ...scope(s), ...(extra || {}) } });

  return Object.freeze({
    me: () => call('GET', '/api/me'),
    audit: (s, filters) => get('/api/audit', s, filters),
    verifyChain: (s) => get('/api/audit/verify', s),
    appendEvent: (s, event) => post('/api/audit/append', s, event),
    signals: (s) => get('/api/signals', s),
    detect: (s, asOf) => post('/api/signals/detect', s, asOf ? { as_of: asOf } : {}),
    review: (signalId, decision) => call('POST', `/api/signals/${encodeURIComponent(signalId)}/review`, { body: decision }),
    readiness: (s) => get('/api/readiness', s),
    trace: (s) => get('/api/trace', s),
    incidents: (s) => get('/api/incidents', s),
    purgeAttempt: (s, caseRef, req) => call('POST', `/api/incidents/${encodeURIComponent(caseRef)}/purge-attempt`, { body: { ...scope(s), ...req } }),
    exportList: (s) => get('/api/export', s),
    exportCreate: (s, req) => post('/api/export', s, req),
    exportVerify: (receiptId, csv) => call('POST', '/api/export/verify', { body: { export_receipt_id: receiptId, csv } }),
    errorsDemo: (s, siteId) => post('/api/errors/demo', s, siteId ? { site_id: siteId } : {}),
    errors: (s) => get('/api/errors', s),
    grants: (s) => get('/api/grants/diff', s),
    grantsDiff: (s, idem) => post('/api/grants/diff', s, { idempotency_key: idem }),
    grantsBaseline: (s, idem) => post('/api/grants/baseline', s, { idempotency_key: idem }),
  });
}

/** Fresh idempotency key for a UI action (the server validates the format again). */
export function newKey(prefix = 'ui') {
  const rnd = (globalThis.crypto && crypto.randomUUID) ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return `${prefix}-${rnd}`.replace(/[^A-Za-z0-9_.:-]/g, '').slice(0, 100);
}

/** SHA-256 hex of the exact UTF-8 bytes of a string (browser SubtleCrypto; null if unavailable). */
export async function sha256Hex(text) {
  if (!globalThis.crypto || !crypto.subtle) return null;
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
