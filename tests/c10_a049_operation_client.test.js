"use strict";
const assert=require("node:assert/strict");
const {create}=require("../core10-operational-flow-client.js");
let loggedIn=true,calls=[];
const client={auth:{getUser:async()=>loggedIn?{data:{user:{id:"test"}},error:null}:{data:{user:null},error:null}},
 schema:()=>({from:table=>({select(){return this},eq(){return this},order(){return this},
  limit:async()=>({data:[{id:101,tenant_id:1,slug:"test"}],error:null}),
  then:fn=>fn({data:table==="items"?[{id:8001,business_id:101,sku:"SWEET"}]:
    [{id:5001,business_id:101,site_id:1001,code:"MAIN"}],error:null})}),
 rpc:async(name,args)=>{calls.push(name);return{data:name==="read_operation_overview_v1"?{
  business_id:101,server_authorized:true,financial_posted:false,certified_cogs:false,
  production_posting_built:false,operationally_certified:false,items:[]}:
  name==="create_operation_order_v1"?{order_id:42,business_id:101,status:"draft",version:1}:
  {order_id:42,status:"confirmed",version:2},error:null}}})};
(async()=>{
 const api=create({client});assert.equal((await api.businesses())[0].id,101);
 assert.equal((await api.read(101)).items.length,0);
 assert.equal((await api.draft(101,5001,8001,"purchase_receive",10,45,"PO-A","create-purchase-01")).order_id,42);
 assert.equal((await api.advance(42,"confirm",1,"confirm-purchase-01")).version,2);
 await assert.rejects(()=>api.draft(101,5001,8001,"unknown",1,20,null,"test-key-001"),/UNKNOWN_OPERATION/);
 loggedIn=false;await assert.rejects(()=>api.read(101),/AUTH_REQUIRED/);
 assert.equal(calls.length,3);
 console.log("PASS A049 signed operations client and restricted workflow contract");
})().catch(e=>{console.error(e);process.exitCode=1});
