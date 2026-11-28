'use strict';
// Candidate private DB port: no live adapter, credentials, HTTP or old unfenced report path.
async function runLeasedDryRunOnce({db,account,limit=10}) {
  const out={claimed:0,dry_run_logged:0,requeued:0,failed:0};
  if (!account || account.mode==='off') return out;
  if (account.mode!=='dry_run') throw Error('integration_dry_run_only');
  if (!Number.isInteger(limit)||limit<1||limit>100) throw Error('integration_limit_invalid');
  const rows=await db.claimDryRun(account.id,limit);
  if (!Array.isArray(rows)||rows.length>limit) throw Error('integration_claim_invalid');
  const seen=new Set();
  for(const r of rows) {
    if (!r || String(r.account_id)!==String(account.id)||r.is_dry_run!==true||r.state!=='claimed'
        ||r.id==null||typeof r.lease_token!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(r.lease_token)
        ||seen.has(String(r.id))) throw Error('integration_claim_invalid');
    seen.add(String(r.id));
  }
  out.claimed=rows.length;
  for(const r of rows) {
    const state=await db.reportDryRun(account.id,r.id,r.lease_token,true,false,null);
    if(state==='dry_run_logged')out.dry_run_logged++;
    else if(state==='queued')out.requeued++;
    else if(state==='failed')out.failed++;
    else throw Error('integration_report_invalid');
  }
  return out;
}
module.exports={runLeasedDryRunOnce};
