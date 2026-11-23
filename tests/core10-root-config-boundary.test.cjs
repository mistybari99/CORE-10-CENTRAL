'use strict';
/* Root-page safety regression, independent of and IN ADDITION TO the immutable
 * canonical guard. Root CORE10 historical pages must not load retired IMG-ERP.
 * Central configuration is an explicit dependency; no old-config compatibility
 * global and no invented credential/key are supplied by this test.
 */
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const root=path.resolve(__dirname,'..');
const read=name=>fs.readFileSync(path.join(root,name),'utf8');
const pages=[
 'core10-asset-maintenance-assets.html',
 'core10-asset-maintenance-breakdown.html',
 'core10-asset-maintenance-reports.html',
 'core10-asset-maintenance-schedule.html',
 'core10-asset-maintenance-settings.html',
 'core10-asset-maintenance-workorders.html',
 'core10-business-builder.html',
 'core10-business-controls.html',
 'core10-control-studio.html',
 'core10-engine-workshop.html',
 'core10-inventory-operations.html',
 'core10-operational-flow.html',
 'core10-owner-intent.html',
 'core10-owner-portfolio.html',
 'core10-site-topology.html',
 'core10-workforce-attendance.html',
 'core10-workforce-delegation.html',
 'core10-workforce-directory.html',
 'core10-workforce-integration.html',
 'core10-workforce-leave.html',
 'core10-workforce-liability.html',
 'core10-workforce-payroll.html',
 'core10-workforce-policy.html',
 'core10-workforce-reports.html',
 'core10-workforce-self.html'
];
const runtime=[
 'core10-asset-maintenance-app.js','core10-business-builder-staging.js',
 'core10-control-studio.js','core10-engine-workshop.js',
 'core10-inventory-operations.js','core10-operational-flow.js',
 'core10-owner-intent.js','core10-owner-portfolio.js',
 'core10-site-topology.js','core10-workforce-app.js',
 'core10-workforce-policy-app.js'
];
test('every root CORE10 HTML, not only A055, has zero retired config loader imports',()=>{
 const all=fs.readdirSync(root).filter(f=>/^core10-.*\.html$/.test(f));
 assert.ok(all.length>=pages.length,'original root page inventory must be present');
 for(const file of all){
  const html=read(file);
  assert.doesNotMatch(html,/<script\b[^>]*\bsrc\s*=\s*["'](?:\.\/)?config\.js["'][^>]*>/i,
   'ROOT_CORE10_LEGACY_LOADER:'+file);
 }
});
test('all 25 previously affected pages keep Supabase, config, adapter and UI load ordering',()=>{
 for(const file of pages){
  const html=read(file);
  const scripts=[...html.matchAll(/<script\b[^>]*\bsrc\s*=\s*"([^"]+)"[^>]*><\/script>/gi)]
   .map(x=>x[1]);
  const vendor=scripts.indexOf('./vendor/supabase.js');
  const conf=scripts.indexOf('./core10-control-centre-config.js');
  assert.ok(vendor>=0&&conf>vendor&&conf===vendor+1,file+': canonical config after vendor');
  assert.equal(scripts.filter(x=>x==='./core10-control-centre-config.js').length,1,
   file+': exactly one Central config');
  assert.ok(scripts.length>=4&&conf<scripts.length-1,file+': preserve downstream app dependencies');
  assert.match(html,/script-src 'self'/,file+': leave CSP script source restricted');
 }
});
test('shared app bootstraps read Central config and deny absent URL/key, never alias legacy globals',()=>{
 for(const file of runtime){
  const js=read(file);
  assert.match(js,/window\.CORE10_CONTROL_CENTRE_CONFIG/,file+': canonical config reference required');
  assert.doesNotMatch(js,/\bBOS_CONFIG\b/,file+': no retired project config binding');
  assert.match(js,/!cfg(?:\?\.|\.)key/,file+': reject missing publishable key');
  assert.match(js,/createClient\(/,file+': preserve signed client initialization');
 }
});
test('canonical root Central config has its own endpoint and does not silently invent credentials',()=>{
 const sandbox={window:{}};
 vm.runInNewContext(read('core10-control-centre-config.js'),sandbox,{timeout:1000});
 const cfg=sandbox.window.CORE10_CONTROL_CENTRE_CONFIG;
 assert.equal(typeof cfg,'object');
 assert.match(cfg.url,/^https:\/\/[a-z0-9]+\.supabase\.co$/);
 assert.doesNotMatch(cfg.url,/kbuhnpqooycqbzrfejcs/);
 assert.equal(cfg.key,'','no key without Owner authorized preview setup');
});
test('A055 client still authenticates through getUser and calls only core10 signed RPC',async()=>{
 const API=require('../core10-asset-maintenance-client.js');
 let authChecks=0;
 const calls=[];
 const client={auth:{getUser:async()=>{authChecks++;return {data:{user:{id:'DEMO-SIGNED-USER'}}};}},
  schema:ns=>{assert.equal(ns,'core10');return {rpc:async(name,args)=>{
   calls.push({name,args});return {data:{items:[],total:0}};}};}};
 const a=API.create({client});
 const result=await a.call('am_whoami_v1',{p_business:101});
 assert.equal(authChecks,1);
 assert.deepEqual(calls,[{name:'am_whoami_v1',args:{p_business:101}}]);
 assert.equal(result.total,0);
 await assert.rejects(()=>a.call('not_an_allowed_rpc',{}),{code:'RPC_NOT_ALLOWED'});
 const denied=API.create({client:{auth:{getUser:async()=>({data:{user:null}})},
  schema:()=>({rpc:async()=>({data:{}})})}});
 await assert.rejects(()=>denied.call('am_whoami_v1',{p_business:101}),
  {code:'AUTHENTICATED_USER_REQUIRED'});
});
