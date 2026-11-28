'use strict';
// Resolves a secret REFERENCE (a name) to a value inside the server function only.
// The default resolver reads process.env[ref upper-cased]; production swaps in a Vault/Edge-secret resolver.
// A resolved value must never be logged, returned, or stored: callers get it only for the duration of one call.
function envResolver(env) {
  const e = env || process.env;
  return async function resolve(ref) {
    if (typeof ref !== 'string' || !/^[a-z0-9_]{3,80}$/.test(ref)) throw new Error('secret_ref_invalid');
    const v = e[ref.toUpperCase()];
    if (!v) throw new Error('secret_not_found');   // note: the message never includes the value
    return v;
  };
}
module.exports = { envResolver };
