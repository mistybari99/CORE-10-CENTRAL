/* A050: canonical signed RPC adapter. Never fake business access. */
(function(root,factory){
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_PORTFOLIO_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const choices=["sites","operations","modules","governance"];
 function fail(k){const e=new Error(k);e.code=k;throw e}
 function id(v){if(!/^[1-9]\d*$/.test(String(v))||!Number.isSafeInteger(Number(v)))fail("INVALID_BUSINESS_ID");return Number(v)}
 function create({client}={}){
  async function schema(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")
    fail("SIGNED_CLIENT_REQUIRED");
   const u=await client.auth.getUser();
   if(!u||u.error||!u.data?.user?.id)fail("SIGN_IN_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function")fail("SCHEMA_MISSING");
   return s;
  }
  async function rpc(name,params){
   const r=await (await schema()).rpc(name,params);
   if(!r||r.error){const err=new Error(r?.error?.message||"RPC_FAILED");err.code=r?.error?.code||"RPC_FAILED";throw err}
   return r.data;
  }
  async function read(){
   const r=await rpc("read_portfolio_workspace_v1",{});
   if(!r||r.server_authorized!==true||r.production_ready!==false||r.operationally_certified!==false||
    !Array.isArray(r.businesses))fail("UNVERIFIED_PORTFOLIO");
   const ids=new Set();
   for(const b of r.businesses){
    if(!Number.isSafeInteger(b.business_id)||ids.has(b.business_id)||typeof b.can_manage!=="boolean"||
       !Number.isSafeInteger(b.tenant_id)||!Array.isArray(b.sites)||!Array.isArray(b.modules)||
       !b.layout||!["compact","detailed"].includes(b.layout.mode)||!Number.isSafeInteger(b.layout.version)||
       !Array.isArray(b.layout.sections)||b.layout.sections.some(x=>!choices.includes(x)))
      fail("INVALID_BUSINESS_RESPONSE");
    ids.add(b.business_id);
   }
   return r;
  }
  async function layout(business,mode,sections,version,request){
   const biz=id(business);
   if(!["compact","detailed"].includes(mode)||!Array.isArray(sections)||
     sections.length<1||sections.length>4||new Set(sections).size!==sections.length||
     sections.some(x=>!choices.includes(x))||!Number.isSafeInteger(version)||version<1||
     typeof request!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(request))
    fail("INVALID_LAYOUT");
   const r=await rpc("set_portfolio_layout_v1",{p_business:biz,p_mode:mode,
    p_sections:sections,p_version:version,p_request:request});
   if(!r||r.business_id!==biz||!Number.isSafeInteger(r.version)||r.version<=version)
    fail("INVALID_LAYOUT_RECEIPT");
   return r;
  }
  return Object.freeze({read,layout,release:()=>({live:false,production:false,source:"c10_demo"})});
 }
 return Object.freeze({create,choices});
});
