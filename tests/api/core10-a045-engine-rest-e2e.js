// C10-A045: Signed HMAC JWT HTTP E2E through PostgREST, disposable PostgreSQL17 ONLY.
// Uses the repository's demo tenants/staff identities (tests/c10_a018_demo_seed.sql). Real HTTP, real DB roles
// and real function grants. NOT a Supabase-issued GoTrue token; NEVER a production or SG test.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("DISPOSABLE_JWT_SECRET_REQUIRED");
const actors={
 owner:"11111111-1111-4111-8111-111111111111",businessOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",revoked:"66666666-6666-4666-8666-666666666666",
 customer:"77777777-7777-4777-8777-777777777777",operator:"99999999-9999-4999-8999-999999999999"};
function jwt(sub,claims={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({role:"authenticated",sub,aud:"authenticated",iat:now,exp:now+300,...claims})).toString("base64url");
 const body=h+"."+p;return body+"."+crypto.createHmac("sha256",secret).update(body).digest("base64url");
}
const T=Object.fromEntries(Object.entries(actors).map(([k,v])=>[k,jwt(v)]));
// Forged/expired/wrong-secret tokens must never work.
const forged=(()=>{const b=T.owner.split(".");return b[0]+"."+b[1]+"."+Buffer.from("x".repeat(32)).toString("base64url")})();
const expired=jwt(actors.owner,{exp:Math.floor(Date.now()/1000)-60});
const spoofedRole=jwt(actors.staff,{app_metadata:{role:"tenant_owner",tenant_id:1},user_role:"tenant_owner"});
async function request(path,token,method="GET",payload){
 const headers={accept:"application/json"};
 if(token)headers.authorization="Bearer "+token;
 if(payload!==undefined)headers["content-type"]="application/json";
 const res=await fetch(base+path,{method,headers,body:payload===undefined?undefined:JSON.stringify(payload),redirect:"error",signal:AbortSignal.timeout(15000)});
 const raw=await res.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
 return{status:res.status,data};
}
const rpc=(n,t,a)=>request("/rpc/"+n,t,"POST",a);
function ok(r,m){assert.ok(r.status>=200&&r.status<300,m+": HTTP "+r.status+" "+JSON.stringify(r.data));return r.data}
function denied(r,m,reason){
 if(reason){assert.equal(r.status,400,m+": "+JSON.stringify(r.data));assert.equal(r.data&&r.data.message,reason,m+": reason mismatch "+JSON.stringify(r.data))}
 else assert.ok([401,403,404].includes(r.status),m+": unexpected access "+JSON.stringify(r));
}
let n=0;const key=(p)=>"a045http_"+p+"_"+(++n);
const D={field:"on_hand",op:"lt",threshold:12,outcome:"warn",message:"Stock below advisory level"};
(async()=>{
 // ---- ERP side: real stock postings by demo identities (site staff + owner) ----
 ok(await rpc("post_stock_event",T.owner,{p_location:5001,p_item:8001,p_delta:6,p_request:"a045-seed-owner"}),"owner stock");
 ok(await rpc("post_stock_event",T.staff,{p_location:5001,p_item:8001,p_delta:2,p_request:"a045-seed-staff"}),"site staff stock");
 denied(await rpc("post_stock_event",T.investor,{p_location:5001,p_item:8001,p_delta:1,p_request:"a045-no-grant"}),"investor has no stock.post","stock_post_not_authorized");
 const onHandA=ok(await request("/stock_summary?select=net_movement&business_id=eq.101",T.owner),"read stock").reduce((s,r)=>s+Number(r.net_movement),0);
 assert.equal(onHandA,8,"Business A real on-hand = 8");
 const movements=async()=>ok(await request("/stock_movements?select=id",T.owner),"movements").length;
 const baseline=await movements();
 // ---- Owner: create/validate/preview/publish A and B over HTTP ----
 denied(await rpc("save_engine_draft_v1",null,{p_tenant:1,p_key:"anon_engine",p_name:"Anonymous Engine",p_handler:"threshold_rule_v1",p_descriptor:D,p_expected_version:0,p_request:key("anon"),p_reason:"anonymous must fail"}),"anonymous create");
 for(const [label,tok] of [["forged",forged],["expired",expired]])
  denied(await rpc("read_engines_v1",tok,{p_tenant:1}),label+" token");
 const save={p_tenant:1,p_key:"stock_low_threshold_advisory",p_name:"Stock Low Threshold Advisory",p_handler:"threshold_rule_v1",p_descriptor:D,p_expected_version:0,p_request:"a045http_save_main",p_reason:"Create advisory stock threshold"};
 const eng=ok(await rpc("save_engine_draft_v1",T.owner,save),"owner save");
 assert.equal(eng.status,"saved");assert.equal(eng.version,1);
 assert.deepEqual(ok(await rpc("save_engine_draft_v1",T.owner,save),"idempotent replay"),eng);
 denied(await rpc("save_engine_draft_v1",T.owner,{...save,p_descriptor:{...D,threshold:99}}),"tampered replay","engine_idempotency_conflict");
 denied(await rpc("save_engine_draft_v1",T.owner,{...save,p_key:"bad_dsl",p_request:key("dsl"),p_descriptor:{...D,formula:"1+1"}}),"unknown DSL key","invalid_descriptor");
 const id=eng.engine_id;
 const pv=ok(await rpc("preview_engine_draft_v1",T.owner,{p_tenant:1,p_handler:"threshold_rule_v1",p_descriptor:D,p_params:{},p_inputs:{on_hand:8}}),"preview draft");
 assert.equal(pv.outcome,"warn");assert.equal(pv.canAuthorizeOperation,false);assert.equal(pv.mutates,false);
 denied(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:101,p_version:1,p_state:"PUBLISHED",p_params:{},p_placement:"both",p_local_edit:"business_owner",p_expected:0,p_request:key("early"),p_reason:"not validated yet"}),"publish before validate","engine_version_not_validated");
 ok(await rpc("validate_engine_version_v1",T.owner,{p_engine:id,p_version:1,p_request:key("val"),p_reason:"Validated for publishing"}),"validate");
 ok(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:101,p_version:1,p_state:"PUBLISHED",p_params:{threshold:12},p_placement:"both",p_local_edit:"business_owner",p_expected:0,p_request:key("pubA"),p_reason:"Publish to Business A"}),"publish A");
 ok(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:102,p_version:1,p_state:"PUBLISHED",p_params:{threshold:30},p_placement:"business_only",p_local_edit:"central_only",p_expected:0,p_request:key("pubB"),p_reason:"Publish to Business B"}),"publish B");
 denied(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:201,p_version:1,p_state:"PUBLISHED",p_params:{},p_placement:"both",p_local_edit:"central_only",p_expected:0,p_request:key("xt"),p_reason:"cross tenant business"}),"cross-tenant publish","engine_denied");
 // ---- Same canonical service, independent values; advisory outcome uses the REAL on-hand ----
 const a=ok(await rpc("read_business_engines_v1",T.owner,{p_business:101}),"read A").items[0];
 const b=ok(await rpc("read_business_engines_v1",T.owner,{p_business:102}),"read B").items[0];
 assert.equal(a.effective.threshold,12);assert.equal(b.effective.threshold,30);
 assert.equal(a.placement,"both");assert.equal(b.placement,"business_only");
 assert.equal(ok(await rpc("preview_business_engine_v1",T.owner,{p_engine:id,p_business:101,p_inputs:{on_hand:onHandA}}),"A eval").outcome,"warn");
 assert.equal(ok(await rpc("preview_business_engine_v1",T.owner,{p_engine:id,p_business:102,p_inputs:{on_hand:20}}),"B eval").outcome,"warn");
 // ---- Negative matrix: every non-Owner identity, direct tables, spoofed claims ----
 for(const who of ["manager","staff","investor","revoked","customer","operator"]){
  denied(await rpc("read_engines_v1",T[who],{p_tenant:1}),who+" registry read","engine_denied");
  denied(await rpc("save_engine_draft_v1",T[who],{...save,p_key:"x_"+who,p_request:key(who+"s")}),who+" create","engine_denied");
  denied(await rpc("assign_engine_v1",T[who],{p_engine:id,p_business:101,p_version:1,p_state:"REVOKED",p_params:{},p_placement:"both",p_local_edit:"business_owner",p_expected:1,p_request:key(who+"a"),p_reason:"unauthorized revoke"}),who+" assign","engine_denied");
  denied(await rpc("read_business_engines_v1",T[who],{p_business:101}),who+" business read","engine_denied");
 }
 denied(await rpc("read_engines_v1",spoofedRole,{p_tenant:1}),"role spoof via JWT metadata","engine_denied");
 denied(await rpc("preview_engine_draft_v1",T.customer,{p_tenant:1,p_handler:"threshold_rule_v1",p_descriptor:D,p_params:{},p_inputs:{on_hand:1}}),"other tenant preview","engine_denied");
 for(const t of ["micro_engines_v1","micro_engine_versions_v1","micro_engine_assignments_v1","micro_engine_audit_v1","micro_engine_receipts_v1","micro_engine_requests_v1"]){
  for(const who of ["owner","businessOwner"])denied(await request("/"+t+"?select=*",T[who]),who+" direct table read "+t);
 }
 denied(await request("/micro_engine_assignments_v1",T.businessOwner,"POST",{engine_id:id,tenant_id:1,business_id:101,state:"PUBLISHED",pinned_version:1,placement:"both",local_edit_mode:"business_owner",changed_by:actors.businessOwner}),"direct INSERT");
 denied(await request("/micro_engine_audit_v1",T.owner,"DELETE"),"direct audit DELETE");
 // ---- Business Owner (Business A only) ----
 const edit=ok(await rpc("edit_engine_params_v1",T.businessOwner,{p_engine:id,p_business:101,p_params:{threshold:15},p_expected:1,p_request:key("boedit"),p_reason:"Raise Business A level"}),"business owner edit");
 assert.equal(edit.status,"applied");
 denied(await rpc("edit_engine_params_v1",T.businessOwner,{p_engine:id,p_business:102,p_params:{threshold:1},p_expected:1,p_request:key("bob"),p_reason:"cross business edit"}),"cross-business edit","engine_denied");
 denied(await rpc("edit_engine_params_v1",T.businessOwner,{p_engine:id,p_business:101,p_params:{threshold:16},p_expected:1,p_request:key("stale"),p_reason:"stale version edit"}),"stale edit","engine_stale_version");
 assert.equal(ok(await rpc("read_business_engines_v1",T.owner,{p_business:102}),"B untouched").items[0].effective.threshold,30);
 // ---- Advisory 'block' must not gate real operations (hidden/advisory never authorizes or denies) ----
 ok(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:101,p_version:1,p_state:"PUBLISHED",p_params:{threshold:100,outcome:"block"},p_placement:"hidden_from_menus",p_local_edit:"central_only",p_expected:2,p_request:key("blk"),p_reason:"Advisory block, hidden"}),"set advisory block");
 const blk=ok(await rpc("preview_business_engine_v1",T.owner,{p_engine:id,p_business:101,p_inputs:{on_hand:onHandA}}),"block eval");
 assert.equal(blk.wouldBlock,true);assert.equal(blk.canAuthorizeOperation,false);
 ok(await rpc("post_stock_event",T.staff,{p_location:5001,p_item:8001,p_delta:1,p_request:"a045-after-block-staff"}),"stock still posts despite advisory block");
 denied(await rpc("post_stock_event",T.investor,{p_location:5001,p_item:8001,p_delta:1,p_request:"a045-hidden-grant"}),"engine visibility grants no stock right","stock_post_not_authorized");
 // ---- Pause/revoke A: B intact; config rollback never undoes posted stock ----
 const afterPost=await movements();assert.equal(afterPost,baseline+1);
 ok(await rpc("assign_engine_v1",T.owner,{p_engine:id,p_business:101,p_version:1,p_state:"REVOKED",p_params:{threshold:100,outcome:"block"},p_placement:"hidden_from_menus",p_local_edit:"central_only",p_expected:3,p_request:key("revA"),p_reason:"Revoke Business A"}),"revoke A");
 assert.equal(ok(await rpc("preview_business_engine_v1",T.owner,{p_engine:id,p_business:102,p_inputs:{on_hand:20}}),"B after A revoked").outcome,"warn");
 denied(await rpc("preview_business_engine_v1",T.owner,{p_engine:id,p_business:101,p_inputs:{on_hand:1}}),"A revoked","engine_not_published");
 const audit=ok(await rpc("read_engine_audit_v1",T.owner,{p_engine:id}),"audit").items;
 const target=audit.find(x=>x.event==="assignment_changed"&&x.business_id===101&&x.after.state==="REVOKED");
 const rb=ok(await rpc("rollback_engine_assignment_v1",T.owner,{p_engine:id,p_business:101,p_audit_id:target.audit_id,p_expected:4,p_request:key("rb"),p_reason:"Undo revoke (config only)"}),"rollback");
 assert.equal(rb.config_only,true);assert.equal(rb.state,"PUBLISHED");
 assert.equal(await movements(),afterPost,"config rollback must not touch posted stock");
 assert.ok(audit.length>=8,"immutable audit history present");
 console.log("PASS C10-A045 signed-JWT PostgREST E2E: demo owner/business-owner/manager/staff/investor/revoked/other-tenant/operator/anonymous/forged/expired/spoofed; real stock postings unaffected by engine config; NOT GoTrue");
})().catch(e=>{console.error(e);process.exitCode=1});
