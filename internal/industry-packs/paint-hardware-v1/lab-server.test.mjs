
import test from 'node:test';
import assert from 'node:assert/strict';
import {createDemoServer} from './lab-server.mjs';

test('loopback synthetic UI loads with CSP, no production connections, and guards internal source',async t=>{
  const demo=createDemoServer({port:0}),port=await demo.listen();
  t.after(()=>demo.close());
  const origin='http://127.0.0.1:'+port;
  const page=await fetch(origin+'/');
  assert.equal(page.status,200);
  assert.match(page.headers.get('content-security-policy'),/default-src 'none'/);
  const html=await page.text();
  assert.match(html,/SYNTHETIC DATA/);
  assert.match(html,/lang="bn"/);
  assert.match(html,/@?Paint Operations/);
  assert.match(html,/<meta name="viewport"/);
  assert.match(html,/<nav aria-label/);
  assert.match(html,/<meta name="demo-token" content="[a-f0-9]{48}"/);
  assert.equal((await fetch(origin+'/core.mjs')).status,404);
  assert.equal((await fetch(origin+'/api/state')).status,200);
  const css=await (await fetch(origin+'/lab.css')).text();
  assert.match(css,/@media\(max-width:720px\)/);
  const js=await (await fetch(origin+'/lab.js')).text();
  assert.match(js,/textContent/);
});
test('demo state, complete QC failure/rework and preview never posts',async t=>{
  const demo=createDemoServer({port:0}),port=await demo.listen();
  t.after(()=>demo.close());
  const origin='http://127.0.0.1:'+port;
  const html=await (await fetch(origin+'/')).text();
  const token=html.match(/name="demo-token" content="([a-f0-9]+)"/)[1];
  const action=async(a,tokenValue=token)=>{
    const r=await fetch(origin+'/api/step',{method:'POST',headers:{
      'Content-Type':'application/json','X-Demo-Token':tokenValue},body:JSON.stringify({action:a})});
    return {code:r.status,body:await r.json()};
  };
  let s=(await (await fetch(origin+'/api/state')).json());
  assert.equal(s.mode,'SYNTHETIC_ONLY');
  assert.equal(s.ticket,null);
  assert.equal(s.credit.withinLimit,false);
  assert.equal(s.profitability.grossMarginMinor,null);
  assert.equal(s.profitability.pendingRebatesExcludedFromProfitMinor,10000);
  assert.equal(s.scheme.estimatedRebateMinor,8000);
  assert.equal(s.sds.canShip,false);
  assert.equal((await action('mix')).code,422);
  assert.equal((await action('start','invalid')).code,403);
  assert.equal((await action('unapproved-action')).code,400);
  assert.equal((await action('start')).body.ticket.status,'DRAFT');
  assert.equal((await action('mix')).body.ticket.status,'MIXED');
  assert.equal((await action('qc-fail')).body.ticket.status,'QC_FAILED');
  assert.equal((await action('rework')).body.ticket.status,'MIXED');
  s=(await action('qc-pass')).body;
  assert.equal(s.ticket.status,'QC_PASSED');
  assert.equal(s.quote.payableMinor,null);
  assert.equal(s.quote.canPost,false);
  assert.equal(s.summary.qcRuns,2);
  assert.equal(s.postingAllowed,false);
  assert.ok(s.trail.length>=6);
  assert.equal((await action('reset')).body.ticket,null);
});
