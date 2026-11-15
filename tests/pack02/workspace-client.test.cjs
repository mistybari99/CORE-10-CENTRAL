"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const api=require("../../core10-pack02-workspace.js");
// Fixtures are verbatim pack02_workspace_v1 output from the disposable SQL stack.
const fx=n=>JSON.parse(JSON.stringify(require(`./fixtures/${n}.json`)));
const code=(fn,c)=>assert.throws(fn,e=>e&&e.code===c,c);

test("real server projections render for all three workspaces",()=>{
 const u=api.view(fx("universal-owner"));
 assert.equal(u.umbrella,true);assert.equal(u.title,"CORE 10");
 assert.ok(u.businesses.every(b=>b.tenantId===1));
 assert.equal(u.nav[0].bn,"সব ব্যবসার সারাংশ");
 const bo=api.view(fx("business-owner"));
 assert.equal(bo.umbrella,false);assert.equal(bo.sites.length,2);
 const br=api.view(fx("business-owner-branded"));
 assert.equal(br.title,"রঙ ঘর ডেমো");assert.equal(br.theme.brand,"#0055AA");assert.equal(br.theme.onBrand,"#FFFFFF");
 assert.equal(br.sites[0].kindLabel,"শোরুম");
 const st=api.view(fx("staff"));
 assert.equal(st.umbrella,false);assert.equal(st.modeLabel,"");
 assert.deepEqual(st.sites.map(s=>s.id),[1001]);
 assert.deepEqual(st.nav.map(n=>n.key),["staff.home","stock.view","staff.reports","stock.post"]);
});

test("staff projection fails closed on any umbrella, tenant, actor or sister leak",()=>{
 const base=fx("staff");
 code(()=>api.view({...base,umbrella:{visible:true}}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,tenants:[{id:1}]}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,actor_uid:"x"}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,business:{...base.business,tenant_id:1}}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,business:{...base.business,brand:{...base.business.brand,brand_source:"x"}}}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,sites:[{...base.sites[0],label:"CORE 10 HQ"}]}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,nav:["staff.home","owner.portfolio"]}),"PACK02_PROJECTION_UNSAFE");
 code(()=>api.view({...base,sites:[{...base.sites[0],tenant_id:1}]}),"PACK02_PROJECTION_UNSAFE");
});

test("staff nav may not exceed projected site actions",()=>{
 const base=fx("staff");
 const readOnly={...base,sites:[{...base.sites[0],allowed_actions:["stock.read"]}]};
 code(()=>api.view(readOnly),"PACK02_PROJECTION_UNSAFE");
 assert.deepEqual(api.view({...readOnly,nav:["staff.home","stock.view","staff.reports"]}).nav.map(n=>n.key),["staff.home","stock.view","staff.reports"]);
 code(()=>api.view({...base,sites:[]}),"PACK02_PROJECTION_INVALID");
});

test("malformed projections, duplicates, bad brand and certification claims are refused",()=>{
 code(()=>api.view(null),"PACK02_PROJECTION_INVALID");
 code(()=>api.view({...fx("staff"),production_certified:true}),"PACK02_PROJECTION_INVALID");
 code(()=>api.view({...fx("staff"),contract:"OTHER"}),"PACK02_PROJECTION_INVALID");
 const bo=fx("business-owner");
 code(()=>api.view({...bo,sites:[bo.sites[0],bo.sites[0]]}),"PACK02_PROJECTION_DUPLICATE_SITE");
 code(()=>api.view({...bo,business:{...bo.business,brand:{...bo.business.brand,brand_hex:"red;background:url(x)"}}}),"PACK02_PROJECTION_INVALID");
 code(()=>api.view({...bo,sites:[{...bo.sites[0],kind:"vault"}]}),"PACK02_PROJECTION_INVALID");
 code(()=>api.view({...bo,sites:[{...bo.sites[0],allowed_actions:["finance.post"]}]}),"PACK02_PROJECTION_INVALID");
 code(()=>api.view({...bo,nav:["biz.dashboard","owner.setup"]}),"PACK02_PROJECTION_UNSAFE");
 const u=fx("universal-owner");
 code(()=>api.view({...u,umbrella:{visible:false}}),"PACK02_PROJECTION_INVALID");
});

test("adapter requires signed rpc, validates mode/business and rejects stale or mismatched responses",async()=>{
 code(()=>api.create({}),"PACK02_SIGNED_RPC_REQUIRED");
 const calls=[];
 const w=api.create({rpc:async(n,a)=>{calls.push([n,a]);return a.p_mode==="staff"?fx("staff"):fx("universal-owner");}});
 await assert.rejects(w.load("root"),e=>e.code==="PACK02_MODE_INVALID");
 await assert.rejects(w.load("universal_owner",101),e=>e.code==="PACK02_MODE_INVALID");
 await assert.rejects(w.load("staff","1;drop"),e=>e.code==="PACK02_PROJECTION_INVALID");
 assert.equal((await w.load("staff",101)).sites.length,1);
 await assert.rejects(w.load("staff",102),e=>e.code==="PACK02_PROJECTION_UNSAFE");
 assert.deepEqual(calls[0],["pack02_workspace_v1",{p_mode:"staff",p_business:101}]);
 let release;const slow=new Promise(r=>release=r);
 const w2=api.create({rpc:async(n,a)=>a.p_mode==="staff"?(await slow,fx("staff")):fx("business-owner")});
 const first=w2.load("staff",101);
 const second=w2.load("business_owner",101);release();
 await assert.rejects(first,e=>e.code==="PACK02_STALE_RESPONSE");
 assert.equal((await second).mode,"business_owner");
});

test("brand foreground keeps readable contrast",()=>{
 assert.equal(api.onBrand("#FFFFFF"),"#111111");
 assert.equal(api.onBrand("#000000"),"#FFFFFF");
 assert.equal(api.onBrand("#FFDD00"),"#111111");
});
