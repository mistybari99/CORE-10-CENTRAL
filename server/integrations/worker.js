'use strict';
// Outbox worker. `db` is the thin client around the integration RPCs (claim/report); `resolveSecret` maps secret_ref -> value.
// Policy (consent, quiet hours, caps) was already decided in the database when the row was queued.
async function runOnce({ db, registry, resolveSecret, http, account, now, limit }) {
  const out = { claimed: 0, sent: 0, dry_run_logged: 0, requeued: 0, failed: 0 };
  if (!account || account.mode === 'off') return out;                       // an OFF port is never touched
  const dryRun = account.mode === 'dry_run';
  const rows = await db.claim(account.id, limit || 10, now);
  out.claimed = rows.length;
  if (!rows.length) return out;
  const adapter = registry.get(account.provider_code, account.family);
  let secret;
  if (!dryRun && adapter.kind === 'http') {
    try { secret = await resolveSecret(account.secret_ref); }
    catch (e) {
      for (const r of rows) { await db.report(r.id, false, true, null, 'secret_unavailable', now); out.requeued++; }
      return out;
    }
  }
  for (const r of rows) {
    let res;
    try { res = await adapter.send(r, { secret, http: dryRun ? undefined : http, dryRun }); }
    catch (e) { res = { ok: false, transient: true, errorCode: 'adapter_exception' }; }   // never include e.message (could echo a secret)
    const state = await db.report(r.id, !!res.ok, !!res.transient, res.providerRef || null, res.errorCode || null, now);
    if (state === 'sent') out.sent++; else if (state === 'dry_run_logged') out.dry_run_logged++;
    else if (state === 'queued') out.requeued++; else out.failed++;
  }
  return out;
}
module.exports = { runOnce };
