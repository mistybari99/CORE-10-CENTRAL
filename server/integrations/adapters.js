'use strict';
// Adapter contract (see design/integrations/CONTRACT.md). An adapter NEVER decides policy (consent, caps, quiet hours,
// state transitions): the database does. An adapter only turns a prepared job into a provider request.
//
//   adapter.send(job, ctx) -> { ok, providerRef?, transient?, errorCode? }
//   ctx = { secret, http, dryRun }     // http is undefined when dryRun is true: a dry-run adapter cannot reach a network
//
// Real provider wire formats are intentionally NOT implemented (they must be verified at integration time).
// Adding a provider = implementing `build(job, secret)` -> { url, method, headers, body } and `parse(response)`.

function dryRunAdapter(family) {
  return {
    family, kind: 'dry_run',
    async send(job, ctx) {
      // builds nothing external; records what WOULD have been sent (no secret, no network)
      return { ok: true, providerRef: 'dryrun-' + job.id, dryRunNote: family + ':' + job.template_code };
    },
  };
}

function httpAdapter(family, { build, parse }) {
  return {
    family, kind: 'http',
    async send(job, ctx) {
      if (ctx.dryRun || !ctx.http) return { ok: false, transient: false, errorCode: 'network_forbidden_in_dry_run' };
      let req;
      try { req = build(job, ctx.secret); } catch (e) { return { ok: false, transient: false, errorCode: 'build_failed' }; }
      let res;
      try { res = await ctx.http(req); } catch (e) { return { ok: false, transient: true, errorCode: 'network_error' }; }
      if (res.status >= 500 || res.status === 429) return { ok: false, transient: true, errorCode: 'http_' + res.status };
      if (res.status >= 400) return { ok: false, transient: false, errorCode: 'http_' + res.status };
      const p = parse(res);
      return p && p.ok ? { ok: true, providerRef: p.providerRef } : { ok: false, transient: false, errorCode: 'bad_response' };
    },
  };
}

// registry: provider code -> adapter. Unknown / unimplemented providers ALWAYS resolve to the dry-run adapter.
function createRegistry(real) {
  const table = Object.assign({}, real || {});
  return {
    get(providerCode, family) {
      return table[providerCode] || dryRunAdapter(family || 'unknown');
    },
    has(providerCode) { return Object.prototype.hasOwnProperty.call(table, providerCode); },
  };
}
module.exports = { dryRunAdapter, httpAdapter, createRegistry };
