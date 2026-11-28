'use strict';
// Outbox worker. `db` is the thin client around the integration RPCs (claim/report); `resolveSecret` maps secret_ref -> value.
// Policy (consent, quiet hours, caps) was already decided in the database when the row was queued.
async function runOnce({ db, registry, resolveSecret, http, account, now, limit }) {
  const out = { claimed: 0, sent: 0, dry_run_logged: 0, requeued: 0, failed: 0 };
  if (!account || account.mode === 'off') return out;                       // an OFF port is never touched
  if (account.mode !== 'dry_run' && account.mode !== 'live') throw new Error('integration_mode_invalid');
  const dryRun = account.mode === 'dry_run';
  const rows = await db.claim(account.id, limit || 10, now);
  out.claimed = rows.length;
  if (!rows.length) return out;
  const adapter = registry.get(account.provider_code, account.family);
  const report = async (r, ok, transient, ref, error) => {
    const state = await db.report(r.id, ok, transient, ref, error, now);
    if (state === 'sent') out.sent++; else if (state === 'dry_run_logged') out.dry_run_logged++;
    else if (state === 'queued') out.requeued++; else out.failed++;
  };
  let secret, secretUnavailable = false, secretAttempted = false;
  for (const r of rows) {
    // The database normally filters this flag. Recheck before any provider call or secret lookup.
    if (r.is_dry_run !== dryRun) { await report(r, false, false, null, 'job_mode_mismatch'); continue; }
    if (!dryRun && adapter.kind === 'dry_run') { await report(r, false, false, null, 'live_adapter_unavailable'); continue; }
    if (!dryRun && adapter.kind === 'http' && !secretAttempted) {
      secretAttempted = true;
      try { secret = await resolveSecret(account.secret_ref); }
      catch (e) { secretUnavailable = true; }
    }
    if (secretUnavailable) { await report(r, false, true, null, 'secret_unavailable'); continue; }
    let res;
    try { res = await adapter.send(r, { secret, http: dryRun ? undefined : http, dryRun }); }
    catch (e) { res = { ok: false, transient: true, errorCode: 'adapter_exception' }; }   // never include e.message (could echo a secret)
    await report(r, !!res.ok, !!res.transient, res.providerRef || null, res.errorCode || null);
  }
  return out;
}
module.exports = { runOnce };
