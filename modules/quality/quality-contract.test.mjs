import test from "node:test";
import assert from "node:assert/strict";
import {createQualityClient,QUALITY_RPC,QUALITY_VIEWS,QualityTransportError} from "./quality-client.mjs";

const fake=()=>{
 const calls=[];
 const api=createQualityClient({
   enabled:true,
   environment:"disposable-only",
   rpc:async x=>{calls.push(x);return {data:1001,error:null};},
   read:async x=>{calls.push(x);return {data:[{id:1}],error:null};}
 });
 return {api,calls};
};
const lot={businessId:101,itemId:8010,siteId:1001,code:"LOT-ALPHA",source:"purchase",
 reference:"TEST-PO-1",manufacturedOn:"2026-11-11",expiresOn:"2026-11-18",key:"req-lot-01"};
test("A058 disabled in production/default and never authorizes by UI",()=>{
 assert.throws(()=>createQualityClient({rpc:()=>{},read:()=>{}}),/demo_only/);
 assert.throws(()=>createQualityClient({enabled:true,environment:"production",rpc:()=>{},read:()=>{}}),/demo_only/);
 assert.throws(()=>createQualityClient({enabled:true}),/transports_required/);
});
test("typed lot registration emits complete scoped RPC and does not forward role or tenant",async()=>{
 const {api,calls}=fake();
 const got=await api.registerLot({...lot,tenantId:999,role:"superadmin"});
 assert.equal(got,1001);
 assert.equal(calls.length,1);
 assert.deepEqual(calls[0],{schema:"c10_demo",method:QUALITY_RPC.registerLot,params:{
   p_business:101,p_item:8010,p_origin_site:1001,p_code:"LOT-ALPHA",
   p_source:"purchase",p_reference:"TEST-PO-1",p_made:"2026-11-11",
   p_expiry:"2026-11-18",p_key:"req-lot-01"}});
});
test("invalid lot date, id, source and request rejected before transport",async()=>{
 const {api,calls}=fake();
 for(const arg of [
  {...lot,expiresOn:"2026-11-10"},
  {...lot,expiresOn:"2026-02-30"},
  {...lot,siteId:0},
  {...lot,source:"injected"},
  {...lot,key:""},
  {...lot,code:" "},
  {...lot,itemId:NaN},
 ])assert.throws(()=>api.registerLot(arg),TypeError);
 assert.equal(calls.length,0);
});
test("inspection fail-closed on checkbox, duplicates, fake passes",async()=>{
 const {api,calls}=fake();
 assert.throws(()=>api.inspect({lotId:1,result:"pass",checks:[{code:"temp",ok:false}],key:"i-1"}),/false_pass/);
 assert.throws(()=>api.inspect({lotId:1,result:"fail",checks:[],key:"i-2"}),/checks/);
 assert.throws(()=>api.inspect({lotId:1,result:"fail",checks:[{code:"dup",ok:false},{code:"dup",ok:true}],key:"i-3"}),/duplicate/);
 await api.inspect({lotId:8,result:"pass",checks:[{code:"temp",ok:true}],notes:"pass",key:"i-4"});
 assert.deepEqual(calls[0].params.p_checks,[{code:"temp",ok:true}]);
});
test("all operational paths use bounded quantities and exact method names",async()=>{
 const {api,calls}=fake();
 await api.enableTracking({businessId:101,itemId:8010});
 await api.receipt({lotId:7,locationId:5001,quantity:"10.125",reason:"Goods in",key:"stk-rec-001"});
 await api.issue({lotId:7,locationId:5001,quantity:"1.125",reason:"Delivery",key:"stk-out-001"});
 await api.dispose({lotId:7,locationId:5001,quantity:"2",reason:"QC reject",key:"stk-dsp-001"});
 await api.transfer({lotId:7,fromLocationId:5001,toLocationId:5002,quantity:"4",key:"stk-trf-001"});
 await api.decide({lotId:7,action:"release",reason:"QC approved",key:"status-001"});
 await api.link({parentLotId:7,childLotId:8,key:"link-001"});
 await api.recall({rootLotId:7,severity:"critical",reason:"Potential contamination",key:"recall-001"});
 await api.closeRecall({recallId:2,key:"closed-001"});
 await api.fefo({businessId:101,itemId:8010,siteId:1001,quantity:"11"});
 assert.deepEqual(calls.map(c=>c.method),[
 QUALITY_RPC.enableTracking,QUALITY_RPC.postStock,QUALITY_RPC.postStock,QUALITY_RPC.postStock,
 QUALITY_RPC.transfer,QUALITY_RPC.decide,QUALITY_RPC.linkGenealogy,QUALITY_RPC.startRecall,
 QUALITY_RPC.closeRecall,QUALITY_RPC.fefo]);
 assert.equal(calls[1].params.p_quantity,"10.125");
 assert.equal(calls[1].params.p_kind,"receipt");
 assert.equal(calls[3].params.p_kind,"disposal");
});
test("reject floating numeric, unsupported movement, self transfer and malformed IDs",async()=>{
 const {api,calls}=fake();
 const stock={lotId:7,locationId:5001,reason:"Valid reason",key:"stock-req-001"};
 for(const q of [1.1,"1.2345","0","-3","NaN","Infinity","1000001","1e4","00.1"])
 assert.throws(()=>api.issue({...stock,quantity:q}),TypeError);
 assert.throws(()=>api.transfer({lotId:7,fromLocationId:5001,toLocationId:5001,quantity:"1",key:"t-001"}),/same_location/);
 assert.throws(()=>api.link({parentLotId:1,childLotId:1,key:"link"}),/self_genealogy/);
 assert.throws(()=>api.recall({rootLotId:1,severity:"extreme",reason:"valid reason",key:"r-key"}),TypeError);
 assert.equal(calls.length,0);
});
test("read-only views are scoped to selected business filter, never trust client to return rows",async()=>{
 const {api,calls}=fake();
 const data=await api.getReconciliation({businessId:101});
 assert.deepEqual(data,[{id:1}]);
 assert.deepEqual(calls[0],{schema:"c10_demo",view:QUALITY_VIEWS.reconciliation,filters:{business_id:101}});
});
test("error object and thrown transport failures preserve boundary and do not produce success",async()=>{
 const a=createQualityClient({
 enabled:true, rpc:async()=>({data:null,error:{message:"tracked_item_requires_quality_command"}}),
 read:async()=>({data:null,error:{message:"quality_read_denied"}})});
 await assert.rejects(a.enableTracking({businessId:101,itemId:8010}),QualityTransportError);
 await assert.rejects(a.listLots({businessId:101}),QualityTransportError);
 const b=createQualityClient({enabled:true,rpc:async()=>{throw Error("offline");},read:async()=>[]});
 await assert.rejects(b.enableTracking({businessId:101,itemId:8010}),/quality_transport_failed/);
});
