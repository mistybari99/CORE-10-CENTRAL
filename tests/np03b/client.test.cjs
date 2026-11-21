"use strict";
// Mock SDK contracts only; not a real Supabase GoTrue/session certification.
const test=require("node:test"),assert=require("node:assert/strict");
const {create}=require("../../core10-sales-order-client.js");
const owner="11111111-1111-4111-8111-111111111111",other="77777777-7777-4777-8777-777777777777";
const scope={businessId:101,siteId:1001};
const doc=()=>({customer_id:7001,price_list_id:7101,currency:"BDT",lines:[{item_id:8101,variant_id:7301,uom_id:7201,quantity:2,unit_price:300,discount_percent:0,tax_percent:0}]});
const context=()=>({actor_uid:owner,businesses:[{id:101,tenant_id:1,label:"Synthetic sweets",can_manage:true}],sites:[{id:1001,tenant_id:1,business_id:101,label:"Synthetic showroom",allowed_actions:["stock.read"]}],legal_entities:[{id:11,tenant_id:1,label:"Synthetic legal entity"}]});
const receipt=(status="draft",version=1)=>({business_id:101,site_id:1001,order_id:1,status,version,total:600,stock_posted:false,financial_posted:false});
const read=()=>({business_id:101,site_id:1001,items:[{id:1,site_id:1001,status:"draft",version:1,total:600,document:doc()}],stock_posted:false,financial_posted:false});
const audit=()=>({business_id:101,site_id:1001,order_id:1,items:[{id:80,business_id:101,site_id:1001,order_id:1,stream_seq:3,actor_id:owner,action:"sales.draft_saved",event_at:"2026-11-16T12:00:00Z",payload:{document:doc(),receipt:receipt()}}]});
const controls=()=>[{feature_key:"sales.order_draft",business_id:101,site_id:1001,enabled:true,stages:0,params:{max_discount_percent:0}}];
function response(name,args){
 if(name==="build01_context_v1")return {data:context()};
 if(name==="read_sales_orders_v1")return {data:read()};
 if(name==="control_read_v1")return {data:controls()};
 if(name==="save_sales_order_v1")return {data:receipt("draft",args.p_expected+1)};
 if(name==="transition_sales_order_v1")return {data:receipt(args.p_action==="confirm"?"confirmed":"cancelled",args.p_expected+1)};
 if(name==="read_sales_order_audit_v1")return {data:audit()};
 throw Error("Unexpected mock RPC "+name);
}
function fixture({who=owner,responder=response}={}){
 let user=who,listener=null,checks=0,unsubscribed=0;
 const calls=[],schemas=[];
 const client={auth:{
  async getUser(){checks++;return {data:{user:user?{id:user}:null},error:null};},
  onAuthStateChange(fn){listener=fn;return {data:{subscription:{unsubscribe(){unsubscribed++;listener=null;}}}};}
 },schema(name){schemas.push(name);return {async rpc(name,args){calls.push({name,args});return responder(name,args);}};}};
 return {client,calls,schemas,setUser(v){user=v;},emit(event){listener?.(event,{user:user?{id:user}:null});},get checks(){return checks;},get unsubscribed(){return unsubscribed;}};
}
const make=f=>create({client:f.client,backendMode:"synthetic"});
const saveInput=()=>({...scope,orderId:null,expectedVersion:0,document:doc(),requestKey:"sales_request_01"});
const transitionInput=()=>({...scope,orderId:1,expectedVersion:1,approvalId:30,action:"confirm",requestKey:"confirm_request_01"});
test("canonical Sales calls use only core10 RPCs and verify signed identity before AND after every call",async()=>{
 const f=fixture(),c=make(f);
 assert.equal((await c.context()).actor_uid,owner);
 assert.equal((await c.read(scope)).items[0].id,1);
 assert.equal((await c.controls(scope))[0].feature_key,"sales.order_draft");
 assert.equal((await c.save(saveInput())).status,"draft");
 assert.equal((await c.transition(transitionInput())).status,"confirmed");
 assert.equal((await c.audit({...scope,orderId:1})).items[0].id,80);
 assert.equal(f.checks,12);
 assert.deepEqual(f.schemas,Array(6).fill("core10"));
 assert.deepEqual(f.calls.map(x=>x.name),["build01_context_v1","read_sales_orders_v1","control_read_v1","save_sales_order_v1","transition_sales_order_v1","read_sales_order_audit_v1"]);
 assert.deepEqual(f.calls[3].args,{p_business:101,p_site:1001,p_order:null,p_expected:0,p_document:doc(),p_key:"sales_request_01"});
 assert.deepEqual(f.calls[4].args,{p_business:101,p_site:1001,p_order:1,p_action:"confirm",p_expected:1,p_approval:30,p_key:"confirm_request_01"});
 assert.equal(c.getState().backendMode,"synthetic");
 c.destroy();assert.equal(f.unsubscribed,1);assert.equal(c.getState().connected,false);
});
test("input snapshots and request keys survive an in-flight edit and exact retry",async()=>{
 let release;
 const f=fixture({responder:(name,args)=>new Promise(resolve=>{release=()=>resolve(response(name,args));})}),c=make(f);
 const input=saveInput(),pending=c.save(input);
 input.document.lines[0].quantity=999;input.requestKey="changed_key_01";
 while(!release)await new Promise(setImmediate);
 assert.equal(f.calls[0].args.p_document.lines[0].quantity,2);
 assert.equal(f.calls[0].args.p_key,"sales_request_01");
 release();const result=await pending;
 const retry=c.save(saveInput());
 while(f.calls.length<2)await new Promise(setImmediate);
 assert.deepEqual(f.calls[1].args,f.calls[0].args);
 release();assert.deepEqual(await retry,result);c.destroy();
});
test("missing auth, malformed UUID or getUser failure refuses commands before any RPC",async()=>{
 for(const who of [null,"not-a-user"]){
  const f=fixture({who}),c=make(f);
  await assert.rejects(c.save(saveInput()),/SALES_CLIENT_SIGNED_SESSION_REQUIRED/);
  assert.equal(f.calls.length,0);assert.equal(c.getState().connected,false);c.destroy();
 }
 const f=fixture();f.client.auth.getUser=async()=>{throw Error("SDK unavailable");};const c=make(f);
 await assert.rejects(c.read(scope),/SALES_CLIENT_SIGNED_SESSION_REQUIRED/);assert.equal(f.calls.length,0);c.destroy();
});
test("identity changes after pinning and during an in-flight RPC invalidate the adapter",async()=>{
 const f=fixture(),c=make(f);await c.context();f.setUser(other);
 await assert.rejects(c.read(scope),/SALES_CLIENT_SESSION_INVALIDATED/);assert.equal(f.calls.length,1);c.destroy();
 let release;const g=fixture({responder:()=>new Promise(resolve=>{release=resolve;})}),d=make(g);
 const pending=d.read(scope);while(!release)await new Promise(setImmediate);
 g.setUser(other);release({data:read()});
 await assert.rejects(pending,/SALES_CLIENT_SESSION_INVALIDATED/);d.destroy();
});
test("same-user sign-out/sign-in, refresh and destroy cannot release stale private data",async()=>{
 for(const event of ["SIGNED_OUT","SIGNED_IN","TOKEN_REFRESHED","USER_UPDATED"]){
  let release;const f=fixture({responder:()=>new Promise(resolve=>{release=resolve;})}),c=make(f);
  const pending=c.read(scope);while(!release)await new Promise(setImmediate);
  f.emit(event);release({data:read()});
  await assert.rejects(pending,/SALES_CLIENT_SESSION_INVALIDATED/);
  await assert.rejects(c.read(scope),/SALES_CLIENT_SESSION_INVALIDATED/);c.destroy();
 }
 let release;const f=fixture({responder:()=>new Promise(resolve=>{release=resolve;})}),c=make(f);
 const pending=c.read(scope);while(!release)await new Promise(setImmediate);
 c.destroy();c.destroy();release({data:read()});
 await assert.rejects(pending,/SALES_CLIENT_SESSION_INVALIDATED/);assert.equal(f.unsubscribed,1);
});
test("an auth event while preflight getUser is pending prevents dispatch",async()=>{
 let release;const f=fixture();f.client.auth.getUser=()=>new Promise(resolve=>{release=resolve;});const c=make(f);
 const pending=c.read(scope);f.emit("SIGNED_OUT");release({data:{user:{id:owner}}});
 await assert.rejects(pending,/SALES_CLIENT_SESSION_INVALIDATED/);assert.equal(f.calls.length,0);c.destroy();
});
test("server denials propagate safe codes, and failed RPCs still recheck identity",async()=>{
 const f=fixture({responder:()=>({data:null,error:{message:"NOT_CONNECTED:MASTER_SALES_VALIDATION",code:"P0001"}})}),c=make(f);
 await assert.rejects(c.save(saveInput()),/NOT_CONNECTED:MASTER_SALES_VALIDATION/);assert.equal(f.checks,2);c.destroy();
 for(const reply of [null,undefined,{data:null},{error:null}]){
  const f=fixture({responder:()=>reply}),c=make(f);
  await assert.rejects(c.read(scope),/SALES_CLIENT_RPC_NO_RECEIPT/);assert.equal(f.checks,2);c.destroy();
 }
 const g=fixture({responder:()=>{throw Error("network endpoint secret detail");}}),d=make(g);
 await assert.rejects(d.read(scope),/SALES_CLIENT_RPC_UNAVAILABLE/);assert.equal(g.checks,2);d.destroy();
});
test("commands reject mismatched scope, order, version, status and invented posting success",async()=>{
 for(const change of [{business_id:201},{site_id:1002},{order_id:2},{version:7},{status:"posted"},{stock_posted:true},{financial_posted:true},{stock_posted:undefined}]){
  const f=fixture({responder:()=>({data:{...receipt("confirmed",2),...change}})}),c=make(f);
  await assert.rejects(c.transition(transitionInput()),/SALES_CLIENT_/);c.destroy();
 }
});
test("transport response loss stays uncertain and preserves retry identity; missing RPC codes stay distinguishable",async()=>{
 for(const error of [Error("Failed to fetch"),{message:"TypeError: fetch failed"},{message:"Network request failed"},{message:"The connection timed out"},{name:"AbortError",message:"The operation was aborted"},{code:"ETIMEDOUT",message:"transport did not complete"}]){
  let lost=true;
  const f=fixture({responder:(name,args)=>lost?{data:null,error}:response(name,args)}),c=make(f);
  await assert.rejects(c.save(saveInput()),/SALES_CLIENT_RPC_UNAVAILABLE/);
  assert.equal(c.getState().connected,true,"uncertain transport must not poison the signed actor");
  lost=false;assert.equal((await c.save(saveInput())).status,"draft");
  assert.deepEqual(f.calls[0].args,f.calls[1].args,"unchanged retry retains exact key and payload");
  assert.equal(f.checks,4);c.destroy();
 }
 for(const code of ["PGRST202","42883"]){
  const f=fixture({responder:()=>({data:null,error:{code,message:"Could not find the function core10.read_sales_order_audit_v1 in the schema cache"}})}),c=make(f);
  await assert.rejects(c.audit({...scope,orderId:1}),e=>e.code===code&&e.message===code);
  assert.equal(c.getState().connected,true);c.destroy();
 }
 const f=fixture({responder:()=>({data:null,error:{code:"42501",message:"permission denied for function save_sales_order_v1"}})}),c=make(f);
 await assert.rejects(c.save(saveInput()),/SALES_CLIENT_RPC_DENIED/);c.destroy();
});
test("read rejects foreign site/order rows, duplicates and malformed documents",async()=>{
 for(const change of [{site_id:1002},{business_id:201},{id:2},{status:"posted"},{document:{...doc(),customer_id:9007199254740992}}]){
  const x=read();Object.assign(x.items[0],change);
  const f=fixture({responder:()=>({data:x})}),c=make(f);
  await assert.rejects(c.read({...scope,orderId:1}),/SALES_CLIENT_/);c.destroy();
 }
 const x=read();x.items.push({...x.items[0]});const f=fixture({responder:()=>({data:x})}),c=make(f);
 await assert.rejects(c.read(scope),/SALES_CLIENT_SCOPE_MISMATCH/);c.destroy();
});
test("audit rejects mismatched event scope, missing provenance and duplicate event IDs",async()=>{
 for(const patch of [{business_id:201},{site_id:1002},{order_id:2},{actor_id:"spoofed"},{event_at:"not-a-date"},{action:"money.posted"},{stream_seq:0},{payload:null}]){
  const x=audit();Object.assign(x.items[0],patch);
  const f=fixture({responder:()=>({data:x})}),c=make(f);
  await assert.rejects(c.audit({...scope,orderId:1}),/SALES_CLIENT_/);c.destroy();
 }
 const x=audit();x.items.push({...x.items[0]});const f=fixture({responder:()=>({data:x})}),c=make(f);
 await assert.rejects(c.audit({...scope,orderId:1}),/SALES_CLIENT_SCOPE_MISMATCH/);c.destroy();
});
test("context and controls cannot invent actor or cross-scope selections",async()=>{
 for(const data of [{...context(),actor_uid:other},{...context(),sites:[{...context().sites[0],business_id:201}]},{...context(),sites:[{...context().sites[0],tenant_id:2}]}]){
  const f=fixture({responder:()=>({data})}),c=make(f);
  await assert.rejects(c.context(),/SALES_CLIENT_INVALID_CONTEXT/);c.destroy();
 }
 for(const rows of [[{...controls()[0],enabled:"true"}],[{...controls()[0],stages:6}],[{...controls()[0],site_id:2001}],[...controls(),...controls()]]){
  const f=fixture({responder:()=>({data:rows})}),c=make(f);
  await assert.rejects(c.controls(scope),/SALES_CLIENT_/);c.destroy();
 }
});
test("malformed input and unimplemented actions fail before dispatch",async()=>{
 const f=fixture(),c=make(f);
 for(const patch of [{businessId:"101"},{siteId:0},{orderId:0},{expectedVersion:1},{requestKey:"short"},{requestKey:"request with spaces"},{requestKey:"a".repeat(101)},{unknown:true}])await assert.rejects(c.save({...saveInput(),...patch}),/SALES_CLIENT_/);
 for(const amount of [-1,0,NaN,Infinity]){const d=doc();d.lines[0].quantity=amount;await assert.rejects(c.save({...saveInput(),document:d}),/SALES_CLIENT_/);}
 const circular=doc();circular.lines[0].quantity=circular;await assert.rejects(c.save({...saveInput(),document:circular}),/SALES_CLIENT_INVALID_JSON/);
 for(const action of [null,"post","refund","approve"])await assert.rejects(c.transition({...transitionInput(),action}),/SALES_CLIENT_INVALID_ACTION/);
 assert.equal(f.calls.length,0);c.destroy();
 assert.throws(()=>create({client:f.client}),/SALES_CLIENT_BACKEND_MODE_REQUIRED/);
 assert.throws(()=>create({client:{auth:{}},backendMode:"signed"}),/SALES_CLIENT_SIGNED_CLIENT_REQUIRED/);
});
