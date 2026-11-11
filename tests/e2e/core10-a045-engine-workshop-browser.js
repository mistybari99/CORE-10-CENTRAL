"use strict";
/* A045 actual browser UI test at 390px and 1440px.
 * SYNTHETIC in-page RPC fixture that mimics the server contract (receipts, versions, lifecycle).
 * It is NOT Supabase, NOT GoTrue and NOT RLS evidence; server security is proven by tests/c10_a045_micro_engine_e2e.sql.
 */
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const fixture=String.raw`(function(){
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
const st={engines:[],audit:[],pending:[],nid:1,aid:1,rid:1,calls:[]};
const handlers=[{handler_id:"threshold_rule_v1",kind:"rule",certified:true,can_execute:true},
 {handler_id:"workflow_v1",kind:"workflow",certified:false,can_execute:false}];
const hash=(o)=>"h"+Array.from(JSON.stringify(o)).reduce((a,c)=>(a*31+c.charCodeAt(0))>>>0,7).toString(16).padStart(8,"0")+"0000";
const err=(code)=>({data:null,error:{code,message:code}});
const ok=(d)=>({data:d,error:null});
function ev(e,b,ev_,before,after){st.audit.push({audit_id:st.aid++,engine_id:e.engine_id,event:ev_,business_id:b,before,after,created_at:new Date().toISOString()})}
function evalRule(d,p,inp){const v=inp[d.field];if(typeof v!=="number")return null;
 const th=p&&p.threshold!==undefined?p.threshold:d.threshold,oc=(p&&p.outcome)||d.outcome;
 const hit={lt:v<th,lte:v<=th,gt:v>th,gte:v>=th,eq:v===th}[d.op];
 return{advisory:true,matched:hit,outcome:hit?oc:"allow",wouldBlock:hit&&oc==="block",requiresApproval:hit&&oc==="approval_required",
  effective:{field:d.field,op:d.op,threshold:th,outcome:oc},canAuthorizeOperation:false,mutates:false}}
function rpc(name,a){
 st.calls.push({name,args:a});
 if(name==="read_engines_v1")return ok({tenant_id:a.p_tenant,server_authorized:true,operationally_certified:false,handlers,engines:JSON.parse(JSON.stringify(st.engines))});
 if(name==="read_engine_pending_v1")return ok({tenant_id:a.p_tenant,items:st.pending.filter(r=>r.status==="pending")});
 if(name==="read_engine_audit_v1")return ok({engine_id:a.p_engine,items:st.audit.filter(x=>x.engine_id===a.p_engine).slice().reverse()});
 if(name==="preview_engine_draft_v1"){const r=evalRule(a.p_descriptor,a.p_params,a.p_inputs);return r?ok(r):err("invalid_input")}
 if(name==="save_engine_draft_v1"){let e=st.engines.find(x=>x.engine_key===a.p_key);
  if(!e){if(a.p_expected_version!==0)return err("engine_stale_version");
   e={engine_id:st.nid++,engine_key:a.p_key,display_name:a.p_name,handler_id:a.p_handler,current_version:0,versions:[],assignments:[]};st.engines.push(e);ev(e,null,"engine_created",null,{engine_key:a.p_key})}
  else if(e.current_version!==a.p_expected_version)return err("engine_stale_version");
  e.current_version++;e.versions.push({version:e.current_version,state:"DRAFT",descriptor:a.p_descriptor,hash:hash(a.p_descriptor),created_at:new Date().toISOString()});
  ev(e,null,"version_saved",null,{version:e.current_version});
  return ok({status:"saved",engine_id:e.engine_id,version:e.current_version,state:"DRAFT",can_execute:a.p_handler==="threshold_rule_v1"})}
 const e=st.engines.find(x=>x.engine_id===(a.p_engine));
 if(name==="validate_engine_version_v1"){const v=e.versions.find(x=>x.version===a.p_version);v.state="VALIDATED";ev(e,null,"version_validated",{state:"DRAFT"},{version:v.version});return ok({status:"validated",engine_id:e.engine_id,version:v.version,state:"VALIDATED"})}
 if(name==="assign_engine_v1"){let x=e.assignments.find(r=>r.business_id===a.p_business);const cur=x?x.version:0;
  if(cur!==a.p_expected)return err("engine_stale_version");
  const before=x?JSON.parse(JSON.stringify(x)):null;
  const nx={business_id:a.p_business,state:a.p_state,pinned_version:a.p_version,params:a.p_params,placement:a.p_placement,local_edit_mode:a.p_local_edit,version:cur+1};
  if(x)Object.assign(x,nx);else e.assignments.push(nx);
  ev(e,a.p_business,"assignment_changed",before,nx);return ok({status:"applied",engine_id:e.engine_id,business_id:a.p_business,state:a.p_state,version:cur+1})}
 if(name==="preview_business_engine_v1"){const x=e.assignments.find(r=>r.business_id===a.p_business);if(!x||x.state!=="PUBLISHED")return err("engine_not_published");
  const r=evalRule(e.versions.find(v=>v.version===x.pinned_version).descriptor,x.params,a.p_inputs);return ok(Object.assign(r,{engine_id:e.engine_id,business_id:a.p_business,version:x.pinned_version}))}
 if(name==="read_business_engines_v1"){const items=[];for(const g of st.engines){const x=g.assignments.find(r=>r.business_id===a.p_business);
   if(!x||x.state==="REVOKED"||!["both","business_only"].includes(x.placement))continue;
   const d=g.versions.find(v=>v.version===x.pinned_version).descriptor;
   items.push({control_id:"engine."+g.engine_key,engine_id:g.engine_id,display_name:g.display_name,handler_id:g.handler_id,group:"micro_engine",state:x.state,pinned_version:x.pinned_version,
    descriptor:d,params:x.params,effective:{field:d.field,op:d.op,threshold:x.params.threshold!==undefined?x.params.threshold:d.threshold,outcome:d.outcome},placement:x.placement,
    local_edit_mode:x.local_edit_mode,preferred_enabled:x.state==="PUBLISHED",version:x.version,can_execute:true,advisory_only:true})}
  return ok({tenant_id:1,business_id:a.p_business,server_authorized:true,operationally_certified:false,items})}
 if(name==="edit_engine_params_v1"){const x=e.assignments.find(r=>r.business_id===a.p_business);
  if(!x||x.version!==a.p_expected)return err("engine_stale_version");
  if(x.local_edit_mode==="central_only")return err("engine_local_edit_denied");
  if(x.local_edit_mode==="request_approval"){st.pending.push({request_id:st.rid++,engine_id:e.engine_id,business_id:a.p_business,target_params:a.p_params,expected_version:x.version,reason:a.p_reason,status:"pending"});return ok({status:"pending",version:x.version})}
  x.params=a.p_params;x.version++;return ok({status:"applied",version:x.version})}
 if(name==="rollback_engine_assignment_v1"){const au=st.audit.find(z=>z.audit_id===a.p_audit_id),x=e.assignments.find(r=>r.business_id===a.p_business);
  if(!au||!x||x.version!==a.p_expected)return err("engine_stale_version");
  const b=au.before||x;Object.assign(x,{state:b.state,pinned_version:b.pinned_version,params:b.params,placement:b.placement,local_edit_mode:b.local_edit_mode,version:x.version+1});
  ev(e,a.p_business,"assignment_rolled_back",null,{version:x.version});return ok({status:"rolled_back",version:x.version,state:x.state,config_only:true})}
 return err("UNKNOWN_RPC");
}
window.CORE10_E2E=st;
window.supabase={createClient:function(){return{auth:{getUser:async()=>({data:{user:{id:"signed-test-fixture-uuid"}},error:null})},
 schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");
  return{rpc:async(n,a)=>rpc(n,a),from:function(t){if(t!=="businesses")throw Error("TABLE_SHADOW_ACCESS");
   return{select(){return this},order(){return this},limit:async()=>({data:[{id:101,tenant_id:1,slug:"business-a"},{id:102,tenant_id:1,slug:"business-b"}],error:null})}}}}}}};
})();`;
async function noOverflow(page,label){
 const o=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
 assert.ok(o<=2,label+" horizontal overflow "+o);
}
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}});
   const errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
   await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
   await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:fixture}));
   await page.goto(base+"/core10-engine-workshop.html",{waitUntil:"load"});
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("registry loaded"),{timeout:20000});
   // required-input validation blocks the server call
   await page.locator("#ew-save").click();
   assert.match(await page.locator("#ew-err-key").innerText(),/Required/);
   assert.match(await page.locator("#ew-err-reason").innerText(),/Required/);
   assert.equal(await page.evaluate(()=>window.CORE10_E2E.calls.some(c=>c.name==="save_engine_draft_v1")),false,"invalid form must not call server");
   // create descriptor without code
   await page.locator("#ew-key").fill("stock_low_threshold_advisory");
   await page.locator("#ew-name").fill("Stock Low Threshold Advisory");
   await page.locator("#ew-field").selectOption("on_hand");await page.locator("#ew-op").selectOption("lt");
   await page.locator("#ew-threshold").fill("12");await page.locator("#ew-outcome").selectOption("warn");
   await page.locator("#ew-reason").fill("Create the advisory stock threshold");
   await page.locator("#ew-preview-input").fill("8");await page.locator("#ew-preview").click();
   await page.waitForFunction(()=>document.querySelector("#ew-preview-result")?.textContent.includes("outcome warn"));
   assert.match(await page.locator("#ew-preview-result").innerText(),/canAuthorizeOperation = false/);
   await page.locator("#ew-save").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Saved immutable version 1"));
   assert.equal(await page.locator('[data-engine]').count(),1);
   assert.match(await page.locator("#ew-versions").innerText(),/DRAFT[\s\S]*Needs validation/);
   assert.equal(await page.locator("#ew-pub-save").isDisabled(),true,"cannot publish unvalidated version");
   await page.locator("#ew-validate").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("VALIDATED"));
   assert.match(await page.locator("#ew-versions").innerText(),/Ready to publish/);
   // Business A: both + request approval; Business B: business-only, 30
   await page.locator("#ew-pub-business").selectOption("101");
   await page.locator("#ew-pub-placement").selectOption("both");await page.locator("#ew-pub-edit").selectOption("request_approval");
   assert.match(await page.locator("#ew-diff").innerText(),/Other businesses are not changed/);
   await page.locator("#ew-pub-save").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Business #101 → PUBLISHED"));
   await page.locator("#ew-pub-business").selectOption("102");
   await page.locator("#ew-pub-threshold").fill("30");
   await page.locator("#ew-pub-placement").selectOption("business_only");await page.locator("#ew-pub-edit").selectOption("central_only");
   await page.locator("#ew-pub-save").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Business #102 → PUBLISHED"));
   assert.equal(await page.locator("[data-assigned]").count(),2);
   const txt=await page.locator("#ew-assignments").innerText();
   assert.match(txt,/descriptor default/);assert.match(txt,/30/);
   // independent calls, each scoped to exactly one business
   const pubs=await page.evaluate(()=>window.CORE10_E2E.calls.filter(c=>c.name==="assign_engine_v1").map(c=>[c.args.p_business,c.args.p_params.threshold,c.args.p_placement]));
   assert.deepEqual(pubs,[[101,undefined,"both"],[102,30,"business_only"]]);
   // pause only A; B untouched
   await page.locator('[data-act="pause"][data-biz="101"]').click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Business #101 is now PAUSED"));
   assert.match(await page.locator('[data-assigned="101"]').innerText(),/PAUSED/);
   assert.match(await page.locator('[data-assigned="102"]').innerText(),/PUBLISHED/);
   await page.locator('[data-act="prev"][data-biz="102"]').click();
   await page.waitForFunction(()=>document.querySelector("#ew-preview-result")?.textContent.includes("Business #102"));
   assert.match(await page.locator("#ew-preview-result").innerText(),/warn/);
   // rollback config of A to before the pause
   await page.locator('[data-rollback]').first().click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("rolled back"));
   assert.match(await page.locator('[data-assigned="101"]').innerText(),/PUBLISHED/);
   assert.ok(await page.locator("[data-audit]").count()>=6,"audit history rendered");
   await noOverflow(page,"owner "+width);
   assert.deepEqual(errors,[],"owner "+width+" JS errors");
   assert.deepEqual(external,[],"owner "+width+" external requests");
   await page.close();
   console.log("PASS A045 owner workshop "+width+"px: create/validate/preview/publish A+B/pause/rollback/audit; synthetic RPC fixture only");
  }
  // Business surface in a fresh page with seeded state through the owner flow is covered via the stateful fixture:
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}});
   const errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
   const seeded=fixture.replace("const st={engines:[]",`const st={engines:[{engine_id:1,engine_key:"stock_low_threshold_advisory",display_name:"Stock Low Threshold Advisory",handler_id:"threshold_rule_v1",current_version:1,
     versions:[{version:1,state:"VALIDATED",descriptor:{field:"on_hand",op:"lt",threshold:12,outcome:"warn"},hash:"h000000000000",created_at:"2026-11-11T00:00:00Z"}],
     assignments:[{business_id:101,state:"PUBLISHED",pinned_version:1,params:{},placement:"both",local_edit_mode:"request_approval",version:1},
                  {business_id:102,state:"PUBLISHED",pinned_version:1,params:{threshold:30},placement:"hidden_from_menus",local_edit_mode:"central_only",version:1}]}]`).replace("nid:1,","nid:2,");
   await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
   await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:seeded}));
   await page.goto(base+"/core10-engine-workshop.html?biz=101",{waitUntil:"load"});
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Server-authorized engines loaded"),{timeout:20000});
   assert.equal(await page.locator("[data-engine-row]").count(),1);
   await page.locator("[data-th]").fill("15");
   await page.locator("[data-save]").click();
   assert.match(await page.locator("#ew-status").innerText(),/Enter a threshold and a reason/);
   await page.locator("[data-why]").fill("Raise level for the festival week");
   await page.locator("[data-save]").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Approval request submitted"));
   assert.match(await page.locator("#ew-biz-list").innerText(),/→ warn/);
   assert.equal(await page.evaluate(()=>window.CORE10_E2E.engines[0].assignments[0].params.threshold),undefined,"request must not silently write");
   await page.locator("[data-prev]").click();
   await page.waitForFunction(()=>document.querySelector("#ew-preview-result")?.textContent.includes("advisory"));
   // Business B (hidden) is not exposed on Business A's surface
   assert.equal((await page.locator("body").innerText()).includes("#102"),false);
   await noOverflow(page,"business "+width);
   assert.deepEqual(errors,[],"business "+width+" JS errors");assert.deepEqual(external,[],"business "+width+" external");
   await page.close();
   console.log("PASS A045 business engines "+width+"px: server-scoped list, request-approval does not silently write; synthetic fixture only");
  }
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(e=>{console.error(e);process.exitCode=1});
