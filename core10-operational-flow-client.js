/* C10-A049 genuine signed RPC adapter; finance estimates are NEVER ledger postings. */
(function(root,factory){const a=factory();if(typeof module==="object"&&module.exports)module.exports=a;
 if(root)root.CORE10_OPERATIONS_API=a;
})(typeof window!=="undefined"?window:globalThis,function(){"use strict";
 const kinds=["purchase_receive","sale_issue","production_plan"];
 function bad(x){const e=new Error(x);e.code=x;throw e}
 const id=v=>{if(!/^[1-9]\d*$/.test(String(v))||!Number.isSafeInteger(Number(v)))bad("INVALID_ID");return Number(v)};
 const request=v=>{if(typeof v!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(v))bad("INVALID_REQUEST");return v};
 const number=(v,min,max,scale)=>{if(!/^\d{1,9}(?:\.\d{1,3})?$/.test(String(v))||Number(v)<min||Number(v)>max||Number(v)!==Math.round(Number(v)*Math.pow(10,scale))/Math.pow(10,scale))bad("INVALID_AMOUNT");return Number(v)};
 function create({client}={}){
  async function db(){
   if(!client?.auth?.getUser||typeof client.schema!=="function")bad("SIGNED_CLIENT_REQUIRED");
   const r=await client.auth.getUser();if(!r||r.error||!r.data?.user?.id)bad("AUTH_REQUIRED");
   const s=client.schema("c10_demo");if(!s?.rpc||!s?.from)bad("SCHEMA_UNAVAILABLE");return s;
  }
  function unpack(r){if(!r||r.error){const e=new Error(r?.error?.message||"SERVER_ERROR");e.code=r?.error?.code||"SERVER_ERROR";throw e}return r.data}
  async function businesses(){return unpack(await (await db()).from("businesses").select("id,tenant_id,slug").order("id",{ascending:true}).limit(150))}
  async function catalog(biz){
   biz=id(biz);const s=await db();
   const locations=unpack(await s.from("stock_locations").select("id,business_id,site_id,code").eq("business_id",biz).order("id",{ascending:true}));
   const items=unpack(await s.from("items").select("id,business_id,sku").eq("business_id",biz).order("id",{ascending:true}));
   if(!Array.isArray(locations)||!Array.isArray(items)||locations.some(l=>l.business_id!==biz)||items.some(l=>l.business_id!==biz))bad("WRONG_SCOPE_CATALOG");
   return{locations,items};
  }
  async function read(biz){
   biz=id(biz);const x=unpack(await(await db()).rpc("read_operation_overview_v1",{p_business:biz}));
   if(!x||x.business_id!==biz||x.server_authorized!==true||x.financial_posted!==false||
     x.certified_cogs!==false||x.production_posting_built!==false||x.operationally_certified!==false||
     !Array.isArray(x.items))bad("INVALID_OPERATION_RESPONSE");return x;
  }
  async function draft(biz,location,item,kind,quantity,unit,external,req){
   biz=id(biz);if(!kinds.includes(kind))bad("UNKNOWN_OPERATION");
   const u=number(unit,0,100000000,2);
   if(external!=null&&(typeof external!=="string"||external.length>120))bad("INVALID_REFERENCE");
   const r=unpack(await(await db()).rpc("create_operation_order_v1",{
    p_business:biz,p_location:id(location),p_item:id(item),p_kind:kind,p_quantity:number(quantity,.001,1000000,3),
    p_unit_value:u,p_external:external||null,p_request:request(req)}));
   if(!r||r.business_id!==biz||!Number.isSafeInteger(r.order_id)||r.status!=="draft")bad("INVALID_DRAFT_RECEIPT");
   return r;
  }
  async function advance(order,action,version,req){
   order=id(order);if(!["confirm","post"].includes(action)||!Number.isSafeInteger(version)||version<1)bad("INVALID_TRANSITION");
   const r=unpack(await(await db()).rpc("advance_operation_order_v1",{
    p_order:order,p_action:action,p_expected:version,p_request:request(req)}));
   if(!r||r.order_id!==order||r.status!==(action==="confirm"?"confirmed":"posted")||!Number.isSafeInteger(r.version)||r.version<=version)bad("INVALID_ACTION_RECEIPT");
   return r;
  }
  return Object.freeze({businesses,catalog,read,draft,advance,kinds});
 }
 return Object.freeze({create,kinds});
});
