// GOV-003 strict Content-Security-Policy and security headers for the LOCAL demo server. Zero dependencies.
// No inline script, no eval, no inline style, no third-party origins, no framing, no referrer, no sniffing.
// The demo UI must therefore ship its JS/CSS as same-origin files (script-src 'self', style-src 'self').

export class CspError extends Error {
  constructor(message) { super(message); this.name = 'CspError'; this.code = 'CSP_UNSAFE'; }
}

const BASE = Object.freeze({
  'default-src': ["'none'"],
  'script-src': ["'self'"],
  'style-src': ["'self'"],
  'img-src': ["'self'"],
  'font-src': ["'self'"],
  'connect-src': ["'self'"],
  'manifest-src': ["'none'"],
  'media-src': ["'none'"],
  'worker-src': ["'none'"],
  'frame-src': ["'none'"],
  'object-src': ["'none'"],
  'base-uri': ["'none'"],
  'form-action': ["'self'"],
  'frame-ancestors': ["'none'"],
});

const FORBIDDEN_TOKENS = ["'unsafe-inline'", "'unsafe-eval'", "'unsafe-hashes'", "'wasm-unsafe-eval'", "'strict-dynamic'", 'data:', 'blob:', 'filesystem:', '*', 'http:', 'https:'];

/**
 * Parse a CSP string and throw CspError if it is weaker than the GOV-003 baseline. Used by buildCsp and by tests.
 */
export function assertStrictCsp(policy) {
  if (typeof policy !== 'string') throw new CspError('policy must be a string');
  const dirs = new Map();
  for (const part of policy.split(';').map((s) => s.trim()).filter(Boolean)) {
    const [name, ...vals] = part.split(/\s+/);
    if (dirs.has(name.toLowerCase())) throw new CspError(`duplicate directive ${name}`);
    dirs.set(name.toLowerCase(), vals);
  }
  const need = (n, pred, msg) => { if (!dirs.has(n) || !pred(dirs.get(n))) throw new CspError(msg); };
  need('default-src', (v) => v.length === 1 && v[0] === "'none'", "default-src must be 'none'");
  need('frame-ancestors', (v) => v.length === 1 && v[0] === "'none'", "frame-ancestors must be 'none'");
  need('object-src', (v) => v.length === 1 && v[0] === "'none'", "object-src must be 'none'");
  need('base-uri', (v) => v.length === 1 && v[0] === "'none'", "base-uri must be 'none'");
  need('script-src', (v) => v.every((t) => t === "'self'" || /^'nonce-[A-Za-z0-9+/=_-]{16,}'$/.test(t)), 'script-src may only contain self/nonce');
  for (const [name, vals] of dirs) {
    for (const t of vals) {
      if (FORBIDDEN_TOKENS.includes(t.toLowerCase())) throw new CspError(`${name} contains forbidden token ${t}`);
    }
  }
  return true;
}

/** Build the CSP string. `extra` may only ADD same-origin sources to a known directive; unsafe tokens are refused. */
export function buildCsp({ extra = {}, reportUri } = {}) {
  const d = Object.fromEntries(Object.entries(BASE).map(([k, v]) => [k, [...v]]));
  for (const [k, vals] of Object.entries(extra)) {
    if (!Object.hasOwn(d, k)) throw new CspError(`unknown directive ${k}`);
    for (const t of vals) {
      if (t !== "'self'" && !/^'nonce-[A-Za-z0-9+/=_-]{16,}'$/.test(t)) throw new CspError(`refused source ${t} for ${k}`);
      if (!d[k].includes(t)) d[k] = d[k].filter((x) => x !== "'none'").concat(t);
    }
  }
  let out = Object.entries(d).map(([k, v]) => `${k} ${v.join(' ')}`).join('; ');
  if (reportUri) {
    if (!/^\/[A-Za-z0-9_./-]{0,100}$/.test(reportUri)) throw new CspError('report-uri must be a same-origin path');
    out += `; report-uri ${reportUri}`;
  }
  assertStrictCsp(out);
  return out;
}

/** Full response header set (lower-case names -> value). `https` adds HSTS; the local demo is plain http by default. */
export function securityHeaders({ https = false, cache = 'no-store', extra, reportUri } = {}) {
  const h = {
    'content-security-policy': buildCsp({ extra, reportUri }),
    'referrer-policy': 'no-referrer',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'cross-origin-opener-policy': 'same-origin',
    'cross-origin-resource-policy': 'same-origin',
    'permissions-policy': 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()',
    'cache-control': cache,
    'x-gov003-mode': 'DEMO / NOT LIVE',
  };
  if (https) h['strict-transport-security'] = 'max-age=31536000; includeSubDomains';
  return h;
}

/** Apply headers to a node:http ServerResponse (or anything with setHeader). */
export function applySecurityHeaders(res, opts) {
  for (const [k, v] of Object.entries(securityHeaders(opts))) res.setHeader(k, v);
  return res;
}
