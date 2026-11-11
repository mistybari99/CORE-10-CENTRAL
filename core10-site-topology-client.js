/* CORE10 A047 signed-context RPC adapter. No mock success or direct topology table DML. */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_SITE_TOPOLOGY_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e}
 function integer(v,name){
  if((typeof v!=="string"&&typeof v!=="number")||!/^[1-9]\d*$/.test(String(v))||
    !Number.isSafeInteger(Number(v)))fail("INVALID_"+name);
  return Number(v);
 }
 function request(v){
  if(typeof v!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(v))fail("INVALID_REQUEST_KEY");
  return v;
 }
 function name(v,min,max,label){
  if(typeof v!=="string"||v.trim().length<min||v.trim().length>max)fail("INVALID_"+label);
  return v.trim();
 }
 const TYPES=Object.freeze(["showroom","factory","godown","warehouse","project"]);
 function create({client}={}){
  async function db(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")
     fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   const a=await client.auth.getUser();
   if(!a||a.error||!a.data||!a.data.user||typeof a.data.user.id!=="string"||!a.data.user.id)
     fail("AUTHENTICATED_USER_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function"||typeof s.from!=="function")fail("TOPOLOGY_SCHEMA_NOT_AVAILABLE");
   return s;
  }
  function unwrap(r){
   if(!r||r.error){const e=new Error(r&&r.error&&r.error.message||"TOPOLOGY_RPC_FAILED");
    e.code=r&&r.error&&r.error.code||"TOPOLOGY_RPC_FAILED";throw e}
   return r.data;
  }
  async function call(action,params){
   return unwrap(await (await db()).rpc(action,params));
  }
  async function businesses(){
   const rows=unwrap(await (await db()).from("businesses").select("id,tenant_id,slug,status")
    .order("id",{ascending:true}).limit(200));
   if(!Array.isArray(rows)||rows.some(x=>!x||!Number.isSafeInteger(x.id)||!Number.isSafeInteger(x.tenant_id)))
     fail("INVALID_BUSINESS_LIST");
   return rows;
  }
  function response(r,biz){
   if(!r||r.server_authorized!==true||r.business_id!==biz||
      !Number.isSafeInteger(r.tenant_id)||typeof r.can_manage!=="boolean"||
      !Array.isArray(r.groups)||!Array.isArray(r.ungrouped)||r.operationally_certified!==false)
    fail("INVALID_AUTHORIZED_TOPOLOGY_RESPONSE");
   const ids=new Set(),groups=new Set();
   for(const g of r.groups){
    if(!g||!Number.isSafeInteger(g.group_id)||g.group_id<=0||
      !TYPES.includes(g.kind)||typeof g.label!=="string"||
      typeof g.group_key!=="string"||typeof g.default!=="boolean"||
      !Array.isArray(g.sites)||groups.has(g.group_id))fail("INVALID_TOPOLOGY_GROUP");
    groups.add(g.group_id);
    for(const s of g.sites){
     if(!s||!Number.isSafeInteger(s.site_id)||s.site_id<=0||
       !Number.isSafeInteger(s.version)||s.version<1||
       s.kind!==g.kind||typeof s.label!=="string"||
       !Array.isArray(s.locations)||ids.has(s.site_id))fail("INVALID_TOPOLOGY_SITE");
     ids.add(s.site_id);
     if(s.locations.some(loc=>!loc||!Number.isSafeInteger(loc.id)||typeof loc.code!=="string"))
       fail("INVALID_TOPOLOGY_LOCATION");
    }
   }
   for(const s of r.ungrouped){
    if(!s||!Number.isSafeInteger(s.site_id)||ids.has(s.site_id))fail("INVALID_UNGROUPED_SITE");
    ids.add(s.site_id);
   }
   return r;
  }
  async function read(biz){
   biz=integer(biz,"BUSINESS_ID");
   return response(await call("read_site_topology_v1",{p_business:biz}),biz);
  }
  async function bootstrap(biz,key){
   biz=integer(biz,"BUSINESS_ID");request(key);
   const r=await call("bootstrap_site_groups_v1",{p_business:biz,p_request:key});
   if(!r||r.business_id!==biz||r.initialized!==true||!Number.isSafeInteger(r.new_members))
    fail("INVALID_BOOTSTRAP_RECEIPT");
   return r;
  }
  async function addGroup(biz,kind,key,label,requestKey){
   biz=integer(biz,"BUSINESS_ID");
   if(!TYPES.includes(kind)||typeof key!=="string"||!/^[a-z][a-z0-9_]{1,39}$/.test(key))
     fail("INVALID_GROUP");
   name(label,2,90,"LABEL");request(requestKey);
   const r=await call("create_site_group_v1",{p_business:biz,p_kind:kind,
    p_key:key,p_label:label.trim(),p_request:requestKey});
   if(!r||r.business_id!==biz||!Number.isSafeInteger(r.group_id)||r.group_id<=0)
     fail("INVALID_GROUP_RECEIPT");
   return r;
  }
  async function addSite(biz,group,label,requestKey){
   biz=integer(biz,"BUSINESS_ID");group=integer(group,"GROUP_ID");
   name(label,2,120,"SITE_LABEL");request(requestKey);
   const r=await call("create_site_in_group_v1",{p_business:biz,p_group:group,
    p_label:label.trim(),p_request:requestKey});
   if(!r||r.business_id!==biz||r.group_id!==group||!Number.isSafeInteger(r.site_id))
     fail("INVALID_SITE_RECEIPT");
   return r;
  }
  async function move(site,group,version,requestKey,reason){
   site=integer(site,"SITE_ID");group=integer(group,"GROUP_ID");
   if(!Number.isSafeInteger(version)||version<1)fail("INVALID_EXPECTED_VERSION");
   request(requestKey);name(reason,5,300,"REASON");
   const r=await call("move_site_group_v1",{p_site:site,p_group:group,
    p_expected_version:version,p_request:requestKey,p_reason:reason.trim()});
   if(!r||r.site_id!==site||r.group_id!==group||!Number.isSafeInteger(r.version)||r.version<=version)
     fail("INVALID_MOVE_RECEIPT");
   return r;
  }
  async function audit(biz){
   biz=integer(biz,"BUSINESS_ID");
   const r=await call("read_site_topology_audit_v1",{p_business:biz,p_limit:50});
   if(!r||r.business_id!==biz||!Array.isArray(r.items))fail("INVALID_AUDIT_RECEIPT");
   return r.items;
  }
  return Object.freeze({businesses,read,bootstrap,addGroup,addSite,move,audit,
   releaseStatus:()=>Object.freeze({signedUserRequired:true,storage:"server",productionCertified:false,stockWrites:false})});
 }
 return Object.freeze({create,TYPES});
});
