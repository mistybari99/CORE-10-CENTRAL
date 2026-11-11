'use strict';
// Generic webhook signature helpers. Provider-specific header names / algorithms are NOT asserted here:
// each adapter passes its own header value, secret and (optional) timestamp. Verify at integration time.
const crypto = require('crypto');

function hmacHex(secret, payload, algo) {
  return crypto.createHmac(algo || 'sha256', secret).update(payload).digest('hex');
}
function safeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const A = Buffer.from(a.toLowerCase(), 'utf8'), B = Buffer.from(b.toLowerCase(), 'utf8');
  if (A.length !== B.length) return false;
  return crypto.timingSafeEqual(A, B);
}
// returns 'ok' | 'bad' | 'missing'  (the exact vocabulary the database expects)
function verifyHmac({ secret, rawBody, signature, timestamp, toleranceSec, nowSec, algo }) {
  if (!secret) return 'missing';
  if (signature == null || signature === '') return 'missing';
  if (toleranceSec != null) {
    const now = nowSec != null ? nowSec : Math.floor(Date.now() / 1000);
    const ts = Number(timestamp);
    if (!Number.isFinite(ts) || Math.abs(now - ts) > toleranceSec) return 'bad';   // replay protection
  }
  const signed = timestamp != null ? String(timestamp) + '.' + rawBody : rawBody;
  const expected = hmacHex(secret, signed, algo);
  const given = String(signature).replace(/^sha256=/i, '');
  return safeEqualHex(expected, given) ? 'ok' : 'bad';
}
module.exports = { hmacHex, verifyHmac, safeEqualHex };
