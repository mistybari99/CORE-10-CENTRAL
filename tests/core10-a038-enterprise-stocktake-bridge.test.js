"use strict";
// C10-A038 safe enterprise read API bridge contract; NO live Supabase or stock writes.
const assert=require("node:assert/strict");
const {create}=require("../core10-enterprise-client.js");
const events=[],uid="11111111-1111-4111-8111-111111111111";
let validUser=true,errorCode=null;
const rowsByTable={
 stocktakes_v1:[{id:17,business_id:101}],
 stocktake_lines_v1:[{item_id:8001,stocktake_id:17,business_id:101}],
 stocktake_discrepancy_v1:[{item_id:8001,difference:-3,business_id:101}],
 stocktake_audit_v1:[{id:2,stocktake_id:17,event:"submitted"}]
};
function query(table){
 const filters=[];
 const q={
  select(columns){events.push(["select",table,columns]);return this;},
  eq(key,val){filters.push([key,val]);events.push(["eq",table,key,val]);return this;},
  order(key,options){events.push(["order",table,key,options]);return this;},
  limit(count){events.push(["limit",table,count]);let data=rowsByTable[table]||[];
   // Simulate RLS and typed equality filtering exactly at response boundary.
   for(const [k,v] of filters)data=data.filter(x=>x[k]===v);
   return Promise.resolve({data,error:errorCode?{code:errorCode,message:"permission denied"}:null});
  }
 };return q;
}
const db={from(table){events.push(["from",table]);return query(table);},
 rpc(name,args){events.push(["rpc",name,args]);return Promise.resolve({data:55,error:null});}};
const client={auth:{async getUser(){events.push(["getUser"]);return validUser?
 {data:{user:{id:uid}},error:null}:{data:{user:null},error:null};}},
 schema(name){events.push(["schema",name]);return db}};
async function denies(p,code){await assert.rejects(p,e=>e&&e.code===code);}
(async()=>{
 const disabled=create({client});
 await denies(disabled.listStocktakes(101),"ENTERPRISE_BACKEND_NOT_RELEASED");
 await denies(disabled.listStocktakeLines(101,17),"ENTERPRISE_BACKEND_NOT_RELEASED");
 assert.equal(events.length,0,"disabled bridge must have zero network calls");
 for(const method of ["createStocktake","approveStocktake","postStocktake","voidStocktake"]){
  await denies(disabled[method]({businessId:101}),"C10_A038_REAL_AUTH_AND_OWNER_RELEASE_REQUIRED");
 }
 assert.equal(events.length,0,"disabled stocktake write functions must never access Supabase");
 const api=create({client,experimentalRead:true,experimentalWrite:true});
 assert.deepEqual(await api.listStocktakes(101),rowsByTable.stocktakes_v1);
 assert.deepEqual(await api.listStocktakes("101",{status:"submitted",locationId:5001}),[]);
 assert.deepEqual(await api.listStocktakeLines(101,17),rowsByTable.stocktake_lines_v1);
 assert.deepEqual(await api.listStocktakeDiscrepancy(101,17),rowsByTable.stocktake_discrepancy_v1);
 assert.deepEqual(await api.listStocktakeAudit(101,17),rowsByTable.stocktake_audit_v1);
 assert.deepEqual(await api.listStocktakeAudit(999,17),[],"audit must never fetch if document is outside business");
 const auditEvents=events.filter(x=>x[0]==="from"&&x[1]==="stocktake_audit_v1");
 assert.equal(auditEvents.length,1,"cross-business audit request must stop after header scope check");
 assert.ok(events.some(x=>x[0]==="eq"&&x[1]==="stocktakes_v1"&&x[2]==="business_id"&&x[3]===101));
 assert.ok(events.some(x=>x[0]==="eq"&&x[1]==="stocktake_lines_v1"&&x[2]==="business_id"&&x[3]===101));
 assert.ok(events.some(x=>x[0]==="eq"&&x[1]==="stocktake_discrepancy_v1"&&x[2]==="business_id"&&x[3]===101));
 assert.ok(events.some(x=>x[0]==="schema"&&x[1]==="c10_demo"),"must use enterprise schema only");
 assert.ok(events.some(x=>x[0]==="getUser"),"session must be verified for each read");
 for(const bad of [0,-1,1.5,"00","101;DROP TABLE",null,{},Infinity]){
  await denies(api.listStocktakes(bad),"INVALID_BUSINESS_ID");
 }
 await denies(api.listStocktakes(101,{status:"published"}),"INVALID_STOCKTAKE_STATUS");
 await denies(api.listStocktakes(101,{tenantId:2}),"INVALID_STOCKTAKE_FILTER");
 await denies(api.listStocktakes(101,{locationId:-1}),"INVALID_LOCATION_ID");
 await denies(api.listStocktakeLines(101,"1 OR 1=1"),"INVALID_STOCKTAKE_ID");
 await denies(api.listStocktakeDiscrepancy(101,0),"INVALID_STOCKTAKE_ID");
 await denies(api.listStocktakeAudit(101,"7;DELETE"),"INVALID_STOCKTAKE_ID");
 for(const method of ["createStocktake","approveStocktake","postStocktake","voidStocktake"]){
  await denies(api[method]({businessId:101}),"C10_A038_REAL_AUTH_AND_OWNER_RELEASE_REQUIRED");
 }
 assert.equal(events.filter(x=>x[0]==="rpc").length,0,
  "A038 live stocktake RPC calls must NEVER be wired while staging is deferred");
 assert.ok(!events.some(x=>["insert","update","upsert","delete"].includes(x[0])),
  "no direct database mutation");
 validUser=false;
 await denies(api.listStocktakes(101),"AUTHENTICATED_USER_REQUIRED");
 validUser=true;
 errorCode="42501";
 await denies(api.listStocktakes(101),"42501");
 console.log("PASS C10-A038 enterprise bridge: scoped signed READ, ID and filter whitelist, RLS errors, no wrong-business audit, all stocktake writes hard-locked");
})().catch(e=>{console.error(e);process.exitCode=1});
