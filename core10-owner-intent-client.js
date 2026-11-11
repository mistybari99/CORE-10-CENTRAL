/* C10-A052 signed RPC adapter for the Owner Intent engine. Server is the authority: no local permissions,
 * no persisted tokens, no direct table access, no simulated success. Every response shape is verified. */
(function(root,factory){"use strict";
 const api=factory(root&&root.CORE10_INTENT_ENGINE);
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_INTENT_API=api;
})(typeof window!=="undefined"?window:globalThis,function(engineGlobal){
 "use strict";
 const REQ=/^[A-Za-z0-9_-]{8,90}$/;
 function fail(code){const e=new Error(code);e.code=code;throw e}
 const id=(v,c)=>{if(!/^[1-9]\d*$/.test(String(v))||!Number.isSafeInteger(Number(v)))fail(c||"INVALID_ID");return Number(v)};
 const ver=(v)=>{if(!Number.isSafeInteger(v)||v<1)fail("INVALID_VERSION");return v};
 const req=(v)=>{if(typeof v!=="string"||!REQ.test(v))fail("INVALID_REQUEST_KEY");return v};
 const reason=(v)=>{if(typeof v!=="string"||v.trim().length<5||v.trim().length>500)fail("REASON_REQUIRED");return v.trim()};
 function newKey(prefix){
  const c=(typeof crypto!=="undefined"&&crypto.getRandomValues)?crypto:require("node:crypto").webcrypto;
  const a=new Uint8Array(12);c.getRandomValues(a);return (prefix||"a052")+"_"+Array.from(a,x=>x.toString(16).padStart(2,"0")).join("");
 }
 function create({client,engine}={}){
  const E=engine||engineGlobal;
  async function schema(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("SIGNED_CLIENT_REQUIRED");
   const u=await client.auth.getUser();
   if(!u||u.error||!u.data||!u.data.user||!u.data.user.id)fail("SIGN_IN_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function")fail("SCHEMA_MISSING");
   return s;
  }
  async function rpc(name,params){
   const r=await (await schema()).rpc(name,params);
   if(!r||r.error){const m=(r&&r.error&&r.error.message)||"RPC_FAILED";const e=new Error(m);e.code=(r&&r.error&&r.error.code)||"RPC_FAILED";throw e}
   return r.data;
  }
  const must=(r,k,code)=>{if(!r||r.server_authorized!==true||!Array.isArray(r[k]))fail(code)};
  async function businesses(){const r=await rpc("read_intent_businesses_v1",{});must(r,"items","UNVERIFIED_BUSINESSES");
   for(const b of r.items)if(!Number.isSafeInteger(b.business_id)||typeof b.can_submit!=="boolean"||typeof b.can_publish!=="boolean")fail("INVALID_BUSINESS_RESPONSE");return r}
  async function context(business){
   const r=await rpc("read_intent_context_v1",{p_business:id(business,"INVALID_BUSINESS_ID")});
   if(!r||r.server_authorized!==true||r.operationally_certified!==false||!r.actor||!Array.isArray(r.capabilities)||!r.business)fail("UNVERIFIED_CONTEXT");
   return r;
  }
  /* parse locally (deterministic), refuse to submit an unusable locale, then let the server re-validate */
  function interpret(text){
   if(!E)fail("ENGINE_MISSING");
   const r=E.parse(text);
   return{result:r,submittable:r.locale!=="unknown"};
  }
  async function submit(business,site,text,interpretation,request){
   if(!interpretation||interpretation.locale==="unknown")fail("UNSUPPORTED_LOCALE");
   if(typeof text!=="string"||text.trim().length<3||text.length>1000)fail("INVALID_TEXT");
   const r=await rpc("submit_owner_intent_v1",{p_business:id(business,"INVALID_BUSINESS_ID"),p_site:site==null?null:id(site,"INVALID_SITE_ID"),
    p_text:text,p_interpretation:interpretation,p_request:req(request||newKey("a052sub"))});
   if(!r||r.status!=="submitted"||!Number.isSafeInteger(r.intent_id)||r.applied!==false)fail("INVALID_SUBMIT_RECEIPT");
   return r;
  }
  async function revise(intent,expected,interpretation,request){
   const r=await rpc("revise_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_interpretation:interpretation,p_request:req(request||newKey("a052rev"))});
   if(!r||r.status!=="revised"||r.applied!==false)fail("INVALID_REVISE_RECEIPT");return r;
  }
  async function preview(intent,expected,sample,request){
   const r=await rpc("preview_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_sample:sample||null,p_request:req(request||newKey("a052prv"))});
   if(!r||r.status!=="previewed"||r.writes_now!==false||r.applied!==false||typeof r.preview_hash!=="string"||!r.preview||
     !r.preview.effect||r.preview.effect.writes_now!==false||!r.preview.impact)fail("INVALID_PREVIEW_RECEIPT");
   return r;
  }
  async function validate(intent,expected,hash,request){
   const r=await rpc("validate_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_preview_hash:hash,p_request:req(request||newKey("a052val"))});
   if(!r||r.status!=="validated"||r.applied!==false)fail("INVALID_VALIDATE_RECEIPT");return r;
  }
  async function approve(intent,expected,why,request){
   const r=await rpc("approve_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_reason:reason(why),p_request:req(request||newKey("a052apr"))});
   if(!r||r.status!=="approved"||r.applied!==false)fail("INVALID_APPROVE_RECEIPT");return r;
  }
  async function reject(intent,expected,why,request){
   const r=await rpc("reject_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_reason:reason(why),p_request:req(request||newKey("a052rej"))});
   if(!r||r.status!=="rejected")fail("INVALID_REJECT_RECEIPT");return r;
  }
  async function publish(intent,expected,request){
   const r=await rpc("publish_owner_intent_v1",{p_intent:id(intent),p_expected:ver(expected),p_request:req(request||newKey("a052pub"))});
   if(!r||r.status!=="published"||r.applied!==true||r.advisory_only!==true||r.operational_enforcement!==false||!Number.isSafeInteger(r.setting_version))fail("INVALID_PUBLISH_RECEIPT");
   return r;
  }
  async function rollback(business,key,toVersion,activeVersion,why,request){
   const r=await rpc("rollback_intent_setting_v1",{p_business:id(business,"INVALID_BUSINESS_ID"),p_key:String(key),p_to_version:ver(toVersion),p_expected_active:ver(activeVersion),
    p_reason:reason(why),p_request:req(request||newKey("a052rbk"))});
   if(!r||r.status!=="rolled_back"||!Number.isSafeInteger(r.setting_version))fail("INVALID_ROLLBACK_RECEIPT");return r;
  }
  async function intents(business){const r=await rpc("read_owner_intents_v1",{p_business:id(business,"INVALID_BUSINESS_ID")});must(r,"items","UNVERIFIED_INTENTS");return r}
  async function history(business){const r=await rpc("read_intent_history_v1",{p_business:id(business,"INVALID_BUSINESS_ID")});
   if(!r||r.server_authorized!==true||!Array.isArray(r.settings)||!Array.isArray(r.audit))fail("UNVERIFIED_HISTORY");return r}
  async function requirements(business){const r=await rpc("read_engineering_requirements_v1",{p_business:id(business,"INVALID_BUSINESS_ID")});must(r,"items","UNVERIFIED_REQUIREMENTS");return r}
  async function guidance(business,key){
   const r=await rpc("read_guidance_v1",{p_business:id(business,"INVALID_BUSINESS_ID"),p_control_key:String(key)});
   const c=r&&r.content;
   if(!r||r.server_authorized!==true||!c||!r.effective_permission)fail("UNVERIFIED_GUIDANCE");
   for(const k of["what","why","when","default","exception","consequence","data_formula_units","linked_report"])if(!c[k]||typeof c[k].en!=="string"||typeof c[k].bn!=="string")fail("INVALID_GUIDANCE");
   return r;
  }
  async function guidanceIndex(business){const r=await rpc("read_guidance_index_v1",{p_business:id(business,"INVALID_BUSINESS_ID")});must(r,"items","UNVERIFIED_GUIDANCE_INDEX");return r}
  return Object.freeze({businesses,context,interpret,submit,revise,preview,validate,approve,reject,publish,rollback,intents,history,requirements,guidance,guidanceIndex,
   newKey,release:()=>({live:false,production:false,source:"c10_demo",advisory_only:true})});
 }
 return Object.freeze({create,newKey});
});
