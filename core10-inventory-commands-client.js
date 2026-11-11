/* A048: real signed server RPC; not a synthetic user selector. */
(function(root,factory){"use strict";
 const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_INVENTORY_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 function bad(code){let e=new Error(code);e.code=code;throw e}
 function id(v){if(!/^[1-9]\d*$/.test(String(v))||!Number.isSafeInteger(Number(v)))bad("INVALID_INTEGER_ID");return Number(v)}
 function qty(v){if(!/^\d{1,7}(?:\.\d{1,3})?$/.test(String(v))||Number(v)<=0||Number(v)>1000000)bad("INVALID_QTY");return Number(v)}
 function key(v){if(typeof v!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(v))bad("INVALID_REQUEST");return v}
 const actions=["receive","issue","transfer","adjust_in","adjust_out"];
 function create({client}={}){
  async function db(){
   if(!client?.auth?.getUser||typeof client.schema!=="function")bad("SIGNED_CLIENT_REQUIRED");
   const user=await client.auth.getUser();
   if(!user||user.error||!user.data?.user?.id)bad("SIGNED_USER_REQUIRED");
   const s=client.schema("c10_demo");if(!s?.rpc||!s?.from)bad("SCHEMA_UNAVAILABLE");
   return s;
  }
  function unwrap(r){if(!r||r.error){const e=new Error(r?.error?.message||"REQUEST_FAILED");e.code=r?.error?.code||"REQUEST_FAILED";throw e}return r.data}
  async function businesses(){return unwrap(await (await db()).from("businesses").select("id,tenant_id,slug,status").order("id",{ascending:true}).limit(150))}
  async function catalog(biz){
   biz=id(biz);const s=await db();
   const locations=unwrap(await s.from("stock_locations").select("id,site_id,business_id,code").eq("business_id",biz).order("id",{ascending:true}));
   const items=unwrap(await s.from("items").select("id,business_id,sku").eq("business_id",biz).order("id",{ascending:true}));
   if(!Array.isArray(locations)||!Array.isArray(items)||
     locations.some(x=>x.business_id!==biz)||items.some(x=>x.business_id!==biz))bad("INVALID_CATALOG_SCOPE");
   return{locations,items};
  }
  async function read(biz){
   biz=id(biz);const r=unwrap(await (await db()).rpc("read_inventory_commands_v1",{p_business:biz}));
   if(!r||r.business_id!==biz||r.server_authorized!==true||r.operationally_certified!==false||!Array.isArray(r.items))
    bad("INVALID_SCOPE_RECEIPT");
   return r;
  }
  async function draft(biz,kind,source,destination,item,quantity,request){
   biz=id(biz);
   if(!actions.includes(kind))bad("INVALID_KIND");
   const src=source==null?null:id(source),dst=destination==null?null:id(destination);
   if((kind==="transfer"&&(!src||!dst||src===dst))||
      (["receive","adjust_in"].includes(kind)&&(src||!dst))||
      (["issue","adjust_out"].includes(kind)&&(!src||dst)))bad("INVALID_LOCATION_SHAPE");
   const r=unwrap(await (await db()).rpc("create_inventory_command_v1",{
    p_business:biz,p_kind:kind,p_source:src,p_destination:dst,p_item:id(item),
    p_quantity:qty(quantity),p_request:key(request)}));
   if(!r||r.business_id!==biz||!Number.isSafeInteger(r.command_id)||r.status!=="draft")bad("INVALID_DRAFT_RECEIPT");
   return r;
  }
  async function advance(command,action,version,request){
   if(!["confirm","post"].includes(action)||!Number.isSafeInteger(version)||version<1)bad("INVALID_ACTION");
   const cmd=id(command);
   const r=unwrap(await (await db()).rpc("advance_inventory_command_v1",{
    p_command:cmd,p_action:action,p_version:version,p_request:key(request)}));
   if(!r||r.command_id!==cmd||r.status!==(action==="confirm"?"confirmed":"posted")||
     !Number.isSafeInteger(r.version)||r.version<=version)bad("INVALID_ACTION_RECEIPT");
   return r;
  }
  return Object.freeze({businesses,catalog,read,draft,advance,actions});
 }
 return Object.freeze({create,actions});
});
