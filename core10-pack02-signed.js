/* PACK-02 S2 — signed RPC adapter. PACK-02 never talks to Auth itself: it is
 * handed either Build01's signed rpc (preferred) or the SAME Supabase client
 * Build01 signed in with. Only the six PACK-02 RPCs are reachable, the actor
 * is re-verified before every call, and a changed actor poisons the adapter.
 */
(function(root,factory){
 "use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_PACK02_SIGNED=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 const obj=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const RPC=Object.freeze({
  pack02_workspace_v1:["p_mode","p_business"],
  pack02_controls_v1:["p_surface","p_business"],
  pack02_business_report_v1:["p_business"],
  pack02_owner_report_v1:[],
  pack02_setup_readback_v1:["p_business"],
  pack02_setup_business_v1:["p_legal","p_slug","p_template","p_display_name","p_mode","p_sites","p_request","p_brand_hex"]
 });
 const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function check(name,args){
  if(!Object.prototype.hasOwnProperty.call(RPC,name))fail("PACK02_RPC_NOT_ALLOWED");
  const a=args===undefined?{}:args;
  if(!obj(a)||Object.keys(a).some(k=>!RPC[name].includes(k)))fail("PACK02_RPC_ARGS_INVALID");
  return a;
 }
 function clean(e){
  const raw=e&&(e.code||e.message);
  return typeof raw==="string"&&/^[a-zA-Z0-9_.:-]{1,120}$/.test(raw)?raw:"PACK02_RPC_DENIED_OR_UNAVAILABLE";
 }
 // Preferred: wrap the host's already-signed rpc (Build01 `pack02` export).
 function fromRpc(signedRpc){
  if(typeof signedRpc!=="function")fail("PACK02_SIGNED_RPC_REQUIRED");
  return Object.freeze({rpc:async(name,args)=>{
   const a=check(name,args);let d;
   try{d=await signedRpc(name,a);}catch(e){fail(clean(e));}
   if(!obj(d))fail("PACK02_INVALID_RESPONSE");
   return d;
  }});
 }
 // Alternative: the host hands over its signed Supabase client.
 function fromClient(client){
  if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("PACK02_SIGNED_CLIENT_REQUIRED");
  let pinned=null,poisoned=false;
  async function actor(){
   let r;try{r=await client.auth.getUser();}catch{fail("PACK02_SESSION_UNAVAILABLE");}
   const id=r&&!r.error&&r.data&&r.data.user&&r.data.user.id;
   if(typeof id!=="string"||!UUID.test(id))fail("PACK02_SIGN_IN_REQUIRED");
   return id.toLowerCase();
  }
  return Object.freeze({rpc:async(name,args)=>{
   const a=check(name,args);
   if(poisoned)fail("PACK02_SESSION_CHANGED");
   const who=await actor();
   if(pinned===null)pinned=who;else if(pinned!==who){poisoned=true;fail("PACK02_SESSION_CHANGED");}
   const db=client.schema("core10");
   if(!db||typeof db.rpc!=="function")fail("PACK02_API_UNAVAILABLE");
   let r;try{r=await db.rpc(name,a);}catch{fail("PACK02_RPC_DENIED_OR_UNAVAILABLE");}
   if(!r||r.error)fail(clean(r&&r.error));
   if(!obj(r.data))fail("PACK02_INVALID_RESPONSE");
   if(typeof r.data.actor_uid==="string"&&r.data.actor_uid.toLowerCase()!==who)fail("PACK02_ACTOR_MISMATCH");
   return r.data;
  }});
 }
 return Object.freeze({RPC_NAMES:Object.freeze(Object.keys(RPC)),fromRpc,fromClient});
});
