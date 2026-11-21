"use strict";
// SDK boundary mocks; hosted GoTrue and PostgreSQL invariants have separate tests.
const test=require("node:test"),assert=require("node:assert/strict"),{create}=require("../../core10-sales-order-client.js");
const actor="11111111-1111-4111-8111-111111111111",other="22222222-2222-4222-8222-222222222222",hash="a".repeat(64);
const scope={businessId:101,siteId:1001};
const clone=x=>structuredClone(x);
const line=()=>({item_id:81,variant_id:null,uom_id:72,quantity:2,unit_price:300,discount_percent:0,tax_percent:0});
const doc=()=>({customer_id:70,price_list_id:71,currency:"BDT",lines:[line()]});
const selection=()=>[{order_line_no:1,quantity:2}];
const boundary=()=>({issued:false,stock_posted:false,financial_posted:false,connections:{issuance:"NOT_CONNECTED",stock:"NOT_CONNECTED",money:"NOT_CONNECTED",tax:"ZERO_ONLY"}});
const receipt=(version=1,validated=false)=>({...boundary(),invoice_id:91,business_id:101,site_id:1001,source_order_id:11,source_order_version:2,version,status:"draft",validated,total:600,currency:"BDT",source_sha256:hash});
function approval(version=1){return {invoice_id:91,site_id:1001,version,source_order_id:11,source_order_version:2,source_sha256:hash,document:doc(),memo:"",total:600,money_scale:2,required_stages:1,action:"invoice_validate"};}
function row(){return {...receipt(),customer_id:70,price_list_id:71,document:doc(),selection:selection(),memo:"",money_scale:2,
 source_snapshot:{order_id:11,order_version:2,business_id:101,site_id:1001,document:doc(),total:600,money_scale:2,confirmation_audit_event_id:80,line_totals:[600]},
 changed_by:actor,validated_by:null,validated_at:null,approval_payload:approval(),
 lines:[{...line(),invoice_id:91,tenant_id:1,business_id:101,site_id:1001,source_order_id:11,line_no:1,source_line_no:1,line_total:600}],
 audit:[{id:82,action:"sales.invoice_draft_saved",actor_id:actor,event_at:"2026-11-18T12:00:00Z",stream_seq:4,payload:{receipt:receipt(),document:doc(),memo:"",selection:selection()}}]};}
const read=()=>({...boundary(),invoices:[row()],validation_control:{feature_key:"sales.invoice_validate",enabled:true,required:true,stages:1,approval_domain:"sales",approval_action:"invoice_validate",version:1}});
const saveInput=()=>({...scope,invoiceId:null,expectedVersion:0,orderId:11,orderVersion:2,lines:null,memo:"",requestKey:"invoice_save_01"});
const validateInput=()=>({...scope,invoiceId:91,expectedVersion:1,approvalId:33,requestKey:"invoice_validate_01"});
function fixture(responder){let user=actor,listener,checks=0,subscriptions=0,unsubscribed=0;const calls=[],schemas=[];
 const client={auth:{async getUser(){checks++;return {data:{user:user?{id:user}:null}};},onAuthStateChange(fn){subscriptions++;listener=fn;return {data:{subscription:{unsubscribe(){unsubscribed++;}}}};}},schema(s){schemas.push(s);return {async rpc(name,args){calls.push({name,args});if(responder)return responder(name,args);return {data:name==="read_sales_invoice_drafts_v1"?read():receipt(args.p_expected+1,name==="validate_sales_invoice_draft_v1")};}};}};
 return {api:create({client,backendMode:"signed"}),calls,schemas,setUser(u){user=u;},emit(e){listener(e);},get checks(){return checks;},get subscriptions(){return subscriptions;},get unsubscribed(){return unsubscribed;}};
}
test("three invoice methods reuse the single session-bound core10 client and exact RPC signatures",async()=>{
 const f=fixture();assert.equal((await f.api.readInvoices({...scope,invoiceId:91})).invoices[0].invoice_id,91);
 assert.equal((await f.api.saveInvoice(saveInput())).validated,false);assert.equal((await f.api.validateInvoice(validateInput())).validated,true);
 assert.equal(f.checks,6);assert.equal(f.subscriptions,1);assert.deepEqual(f.schemas,["core10","core10","core10"]);
 assert.deepEqual(f.calls,[{name:"read_sales_invoice_drafts_v1",args:{p_business:101,p_site:1001,p_invoice:91}},
 {name:"save_sales_invoice_draft_v1",args:{p_business:101,p_site:1001,p_invoice:null,p_expected:0,p_order:11,p_order_version:2,p_lines:null,p_memo:"",p_key:"invoice_save_01"}},
 {name:"validate_sales_invoice_draft_v1",args:{p_business:101,p_site:1001,p_invoice:91,p_expected:1,p_approval:33,p_key:"invoice_validate_01"}}]);f.api.destroy();assert.equal(f.unsubscribed,1);
});
test("save snapshots quantities, source and key before await; exact retries retain the receipt",async()=>{
 let release;const f=fixture((name,args)=>new Promise(resolve=>{release=()=>resolve({data:receipt(args.p_expected+1)});}));
 const input={...saveInput(),lines:selection()},pending=f.api.saveInvoice(input);input.lines[0].quantity=999;input.orderId=99;input.requestKey="different_key_01";input.memo="edited";
 while(!release)await new Promise(setImmediate);const args=clone(f.calls[0].args);assert.equal(args.p_lines[0].quantity,2);assert.equal(args.p_key,"invoice_save_01");release();const result=await pending;
 const retry=f.api.saveInvoice({...saveInput(),lines:selection()});while(f.calls.length<2)await new Promise(setImmediate);assert.deepEqual(f.calls[1].args,args);release();assert.deepEqual(await retry,result);f.api.destroy();
});
test("null create selection, explicit update quantities, and null approval are preserved",async()=>{
 const f=fixture();await f.api.saveInvoice({...saveInput(),invoiceId:91,expectedVersion:1,lines:selection()});await f.api.validateInvoice({...validateInput(),approvalId:null});assert.deepEqual(f.calls[0].args.p_lines,selection());assert.equal(f.calls[1].args.p_approval,null);f.api.destroy();
});
test("all invoice operations deny unsigned identity before the RPC",async()=>{
 for(const [method,input] of [["readInvoices",scope],["saveInvoice",saveInput()],["validateInvoice",validateInput()]]){const f=fixture();f.setUser(null);await assert.rejects(f.api[method](input),/SIGNED_SESSION_REQUIRED/);assert.equal(f.calls.length,0);f.api.destroy();}
});
test("session events, actor changes and destroy discard in-flight invoice responses",async()=>{
 for(const change of [f=>f.emit("SIGNED_OUT"),f=>f.emit("SIGNED_IN"),f=>f.emit("TOKEN_REFRESHED"),f=>f.setUser(other),f=>f.api.destroy()]){
  let release;const f=fixture(()=>new Promise(resolve=>{release=resolve;}));const pending=f.api.readInvoices(scope);while(!release)await new Promise(setImmediate);change(f);release({data:read()});await assert.rejects(pending,/SESSION_INVALIDATED/);f.api.destroy();
 }
});
test("write transport uncertainty preserves a reusable client and original retry key",async()=>{
 let n=0;const f=fixture(()=>++n===1?{error:new Error("Failed to fetch")}:{data:receipt()});await assert.rejects(f.api.saveInvoice(saveInput()),/RPC_UNAVAILABLE/);assert.equal(f.api.getState().connected,true);await f.api.saveInvoice(saveInput());assert.deepEqual(f.calls[0].args,f.calls[1].args);f.api.destroy();
});
test("invalid invoice commands fail locally without network",async()=>{
 for(const patch of [{expectedVersion:1},{orderId:0},{orderVersion:0},{memo:null},{requestKey:"bad key"},{lines:[]},{lines:[{order_line_no:1,quantity:0}]},{lines:[{order_line_no:1,quantity:1,unit_price:0}]},{lines:[{order_line_no:1,quantity:1},{order_line_no:1,quantity:1}]},{invoiceId:91,expectedVersion:1,lines:null}]){
  const f=fixture();await assert.rejects(f.api.saveInvoice({...saveInput(),...patch}),/SALES_CLIENT_/);assert.equal(f.calls.length,0);f.api.destroy();
 }
});
test("write receipts reject foreign source/scope, wrong version, issued or invented postings",async()=>{
 for(const patch of [{business_id:102},{site_id:1002},{source_order_id:12},{source_order_version:3},{version:2},{status:"issued"},{validated:true},{source_sha256:"xyz"},{invoice_id:0},{issued:true},{stock_posted:true},{financial_posted:true},{connections:{issuance:"CONNECTED",stock:"NOT_CONNECTED",money:"NOT_CONNECTED",tax:"ZERO_ONLY"}}]){
  const f=fixture(()=>({data:{...receipt(),...patch}}));await assert.rejects(f.api.saveInvoice(saveInput()),/SALES_CLIENT_/);f.api.destroy();
 }
 const f=fixture(()=>({data:receipt(2,false)}));await assert.rejects(f.api.validateInvoice(validateInput()),/INVALID_INVOICE_RECEIPT/);f.api.destroy();
});
test("read guards snapshot, line, approval, audit and control graph against foreign or malformed data",async()=>{
 const changes=[x=>x.invoices[0].source_snapshot.business_id=102,x=>x.invoices[0].source_snapshot.order_id=12,x=>x.invoices[0].source_snapshot.order_version=3,
 x=>x.invoices[0].lines[0].site_id=1002,x=>x.invoices[0].lines[0].invoice_id=92,x=>x.invoices[0].lines[0].source_order_id=12,x=>x.invoices[0].lines[0].source_line_no=2,
 x=>x.invoices[0].lines[0].unit_price=301,x=>x.invoices[0].lines[0].line_total=601,x=>x.invoices[0].source_snapshot.line_totals=[601],
 x=>x.invoices[0].approval_payload.invoice_id=92,x=>x.invoices[0].approval_payload.source_sha256="b".repeat(64),x=>x.invoices[0].approval_payload.document.lines[0].quantity=1,
 x=>x.invoices[0].audit[0].payload.receipt.site_id=1002,x=>x.invoices[0].audit[0].payload.receipt.source_sha256="b".repeat(64),x=>x.invoices[0].audit[0].payload.document.lines[0].item_id=99,
 x=>x.invoices[0].audit[0].action="sales.invoice_issued",x=>x.invoices[0].validated_by=actor,x=>x.invoices.push(clone(x.invoices[0])),x=>x.validation_control.stages=6,x=>x.connections.money="CONNECTED"];
 for(const change of changes){const result=read();change(result);const f=fixture(()=>({data:result}));await assert.rejects(f.api.readInvoices(scope),/SALES_CLIENT_/);f.api.destroy();}
});
test("read supports edited quantities and validated draft history without re-pricing",async()=>{
 const x=read(),r=x.invoices[0];r.version=3;r.total=300;r.document.lines[0].quantity=1;r.selection[0].quantity=1;r.lines[0].quantity=1;r.lines[0].line_total=300;r.validated=true;r.validated_by=other;r.validated_at="2026-11-18T14:00:00Z";r.approval_payload={...approval(3),document:clone(r.document),total:300};
 r.audit.push({id:83,action:"sales.invoice_draft_saved",actor_id:actor,event_at:"2026-11-18T13:00:00Z",stream_seq:5,payload:{receipt:{...receipt(2),total:300},document:clone(r.document),selection:clone(r.selection),memo:""}});
 r.audit.push({id:84,action:"sales.invoice_draft_validated",actor_id:other,event_at:"2026-11-18T14:00:00Z",stream_seq:6,payload:{receipt:{...receipt(3,true),total:300},approval_id:33,approval_payload:{...approval(2),document:clone(r.document),total:300}}});
 const f=fixture(()=>({data:x}));assert.equal((await f.api.readInvoices(scope)).invoices[0].validated,true);f.api.destroy();
 const empty=fixture(()=>({data:{...read(),invoices:[]}}));assert.deepEqual((await empty.api.readInvoices(scope)).invoices,[]);empty.api.destroy();
});

test("authoritative PG half rounding is accepted without re-rounding original unit prices",async()=>{
 const x=read(),r=x.invoices[0];
 for(const d of [r.document,r.source_snapshot.document,r.approval_payload.document,r.audit[0].payload.document]){d.lines[0].quantity=1;d.lines[0].unit_price=1.005;}
 r.total=1.01;r.source_snapshot.total=1.01;r.source_snapshot.line_totals=[1.01];r.approval_payload.total=1.01;
 r.selection[0].quantity=1;r.audit[0].payload.selection[0].quantity=1;r.audit[0].payload.receipt.total=1.01;
 Object.assign(r.lines[0],{quantity:1,unit_price:1.005,line_total:1.01});
 const f=fixture(()=>({data:x}));assert.equal((await f.api.readInvoices(scope)).invoices[0].document.lines[0].unit_price,1.005);f.api.destroy();
});
test("unsorted source selection follows ordered materialized line mappings",async()=>{
 const x=read(),r=x.invoices[0];
 for(const d of [r.document,r.source_snapshot.document,r.approval_payload.document,r.audit[0].payload.document])d.lines.push({...line(),item_id:82});
 r.total=1200;r.source_snapshot.total=1200;r.source_snapshot.line_totals.push(600);r.approval_payload.total=1200;r.audit[0].payload.receipt.total=1200;
 r.selection=[{order_line_no:2,quantity:2},{order_line_no:1,quantity:2}];r.audit[0].payload.selection=clone(r.selection);
 r.lines.push({...r.lines[0],line_no:2,source_line_no:2,item_id:82});
 const f=fixture(()=>({data:x}));assert.equal((await f.api.readInvoices(scope)).invoices[0].lines[1].source_line_no,2);f.api.destroy();
});

test("untrusted mutation receipts mark write outcome uncertain without changing error codes",async()=>{
 for(const [method,input,output,code] of [
  ["saveInvoice",saveInput(),{...receipt(),financial_posted:true},"SALES_CLIENT_UNEXPECTED_POSTING"],
  ["saveInvoice",saveInput(),{...receipt(),source_order_id:99},"SALES_CLIENT_INVALID_INVOICE_RECEIPT"],
  ["validateInvoice",validateInput(),{...receipt(2,true),site_id:1002},"SALES_CLIENT_SCOPE_MISMATCH"]]){
  const f=fixture(()=>({data:output}));await assert.rejects(f.api[method](input),e=>e.code===code&&e.writeOutcomeUncertain===true&&!e.responseUntrusted);f.api.destroy();
 }
});
test("invalid JSON returned after successful RPC data is untrusted for reads and writes",async()=>{
 for(const [method,input] of [["readInvoices",scope],["saveInvoice",saveInput()],["validateInvoice",validateInput()]]){
  const output={...receipt(),unexpected:undefined};const f=fixture(()=>({data:output}));
  await assert.rejects(f.api[method](input),e=>e.code==="SALES_CLIENT_INVALID_JSON"&&e.responseUntrusted===true&&!e.writeOutcomeUncertain);f.api.destroy();
 }
});
test("explicit SQL denials and local validation are never marked as uncertain mutation results",async()=>{
 for(const code of ["CONTROL_DISABLED","MASTER_ITEM_INACTIVE","SALES_SCOPE_DENIED"]){
  for(const [method,input] of [["saveInvoice",saveInput()],["validateInvoice",validateInput()]]){
   const f=fixture(()=>({error:{message:code}}));await assert.rejects(f.api[method](input),e=>e.code===code&&!e.writeOutcomeUncertain&&!e.responseUntrusted);f.api.destroy();
  }
 }
 const f=fixture();await assert.rejects(f.api.saveInvoice({...saveInput(),memo:null}),e=>e.code==="SALES_CLIENT_INVALID_MEMO"&&!e.writeOutcomeUncertain&&!e.responseUntrusted);assert.equal(f.calls.length,0);f.api.destroy();
 const g=fixture();g.setUser(null);await assert.rejects(g.api.validateInvoice(validateInput()),e=>e.code==="SALES_CLIENT_SIGNED_SESSION_REQUIRED"&&!e.writeOutcomeUncertain&&!e.responseUntrusted);g.api.destroy();
});
