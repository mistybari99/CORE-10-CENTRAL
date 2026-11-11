"use strict";
const assert=require("node:assert/strict");
const E=require("../core10-owner-intent-engine.js");
const {create}=require("../core10-owner-intent-client.js");
let signed=true,calls=[],reply={};
const client={auth:{getUser:async()=>signed?{data:{user:{id:"u"}},error:null}:{data:{user:null},error:{code:"401"}}},
 schema:k=>{assert.equal(k,"c10_demo");return{rpc:async(n,a)=>{calls.push([n,a]);const r=reply[n];return typeof r==="function"?r(a):(r||{data:null,error:{code:"X",message:"no reply"}})}}}};
const api=create({client,engine:E});
(async()=>{
 // interpret is local and deterministic; unknown locale is never submitted
 const it=api.interpret("৩ শতাংশের বেশি নষ্ট হলে সতর্ক করো");assert.equal(it.submittable,true);assert.equal(it.result.capability_key,"wastage_threshold");
 const bad=api.interpret("你好世界");assert.equal(bad.submittable,false);
 await assert.rejects(()=>api.submit(101,null,"你好世界",E.toInterpretation(bad.result),"a052sub_valid01"),/UNSUPPORTED_LOCALE/);
 assert.equal(calls.length,0,"nothing sent for an unusable locale");
 reply.submit_owner_intent_v1={data:{status:"submitted",intent_id:7,applied:false,intent_status:"INTERPRETED",version:1},error:null};
 const s=await api.submit(101,1001,"text here",E.toInterpretation(it.result),"a052sub_valid01");assert.equal(s.intent_id,7);
 const args=calls.at(-1)[1];assert.equal(args.p_business,101);assert.equal(args.p_site,1001);assert.equal(args.p_request,"a052sub_valid01");
 // server claiming "applied" on submit is rejected as an invalid receipt
 reply.submit_owner_intent_v1={data:{status:"submitted",intent_id:7,applied:true},error:null};
 await assert.rejects(()=>api.submit(101,null,"text here",E.toInterpretation(it.result)),/INVALID_SUBMIT_RECEIPT/);
 // input validation before network
 const n=calls.length;
 await assert.rejects(()=>api.submit("x",null,"text here",E.toInterpretation(it.result)),/INVALID_BUSINESS_ID/);
 await assert.rejects(()=>api.preview(7,0,null),/INVALID_VERSION/);
 await assert.rejects(()=>api.preview(7,1,null,"short"),/INVALID_REQUEST_KEY/);
 await assert.rejects(()=>api.approve(7,1,"no",undefined),/REASON_REQUIRED/);
 await assert.rejects(()=>api.rollback(101,"low_stock_alert",1,2,"  ",undefined),/REASON_REQUIRED/);
 assert.equal(calls.length,n);
 // preview receipt must prove nothing was written
 reply.preview_owner_intent_v1={data:{status:"previewed",writes_now:false,applied:false,preview_hash:"h",preview:{effect:{writes_now:false},impact:{}}},error:null};
 assert.equal((await api.preview(7,1,null)).preview_hash,"h");
 reply.preview_owner_intent_v1={data:{status:"previewed",writes_now:true,applied:false,preview_hash:"h",preview:{effect:{writes_now:true},impact:{}}},error:null};
 await assert.rejects(()=>api.preview(7,1,null),/INVALID_PREVIEW_RECEIPT/);
 // publish must be advisory-only and non-operational
 reply.publish_owner_intent_v1={data:{status:"published",applied:true,advisory_only:true,operational_enforcement:true,setting_version:1},error:null};
 await assert.rejects(()=>api.publish(7,1),/INVALID_PUBLISH_RECEIPT/);
 reply.publish_owner_intent_v1={data:{status:"published",applied:true,advisory_only:true,operational_enforcement:false,setting_version:1},error:null};
 assert.equal((await api.publish(7,1)).setting_version,1);
 // unverified server data
 reply.read_intent_context_v1={data:{server_authorized:false,actor:{},capabilities:[],business:{}},error:null};
 await assert.rejects(()=>api.context(101),/UNVERIFIED_CONTEXT/);
 reply.read_guidance_v1={data:{server_authorized:true,content:{what:{en:"x"}},effective_permission:{}},error:null};
 await assert.rejects(()=>api.guidance(101,"k"),/INVALID_GUIDANCE/);
 // server denial surfaces its code
 reply.read_owner_intents_v1={data:null,error:{code:"P0001",message:"intent_denied"}};
 await assert.rejects(()=>api.intents(101),/intent_denied/);
 signed=false;await assert.rejects(()=>api.businesses(),/SIGN_IN_REQUIRED/);
 assert.deepEqual(api.release(),{live:false,production:false,source:"c10_demo",advisory_only:true});
 await assert.rejects(()=>create({}).businesses(),/SIGNED_CLIENT_REQUIRED/);
 console.log("PASS A052 signed client: receipts, validation-before-network, denial, invalid response checks");
})().catch(e=>{console.error(e);process.exitCode=1});
