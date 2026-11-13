"use strict";
const assert=require("node:assert/strict");
const {create}=require("../core10-inventory-commands-client.js");
let signed=true,called=[];
const mock={auth:{getUser:async()=>signed?{data:{user:{id:"uuid"}},error:null}:{data:{user:null},error:{message:"no"}}},
 schema:()=>{
 const from=t=>({select(){return this},eq(){return this},order(){return this},
  limit:async()=>({data:[{id:101,tenant_id:1,slug:"a"}],error:null}),
  then:fn=>fn({data:t==="stock_locations"?[{id:5001,site_id:1001,business_id:101,code:"MAIN"}]:
                   [{id:8001,business_id:101,sku:"A"}],error:null})});
 return{from,rpc:async(n,p)=>{called.push([n,p]);return{data:n==="read_inventory_commands_v1"?
 {business_id:101,server_authorized:true,operationally_certified:false,items:[]}:
 n==="create_inventory_command_v1"?{business_id:101,command_id:1,status:"draft",version:1}:
 {command_id:1,status:"confirmed",version:2},error:null}}};
 }};
(async()=>{
 const api=create({client:mock});
 assert.equal((await api.businesses())[0].id,101);
 assert.equal((await api.read(101)).items.length,0);
 assert.equal((await api.draft(101,"receive",null,5001,8001,"3.5","receive-test-01")).command_id,1);
 assert.equal((await api.advance(1,"confirm",1,"confirm-test-01")).version,2);
 await assert.rejects(()=>api.draft(101,"issue",null,null,8001,1,"reject-test-01"),/INVALID_LOCATION_SHAPE/);
 await assert.rejects(()=>api.draft(101,"receive",null,5001,8001,-1,"reject-test-02"),/INVALID_QTY/);
 signed=false;await assert.rejects(()=>api.read(101),/SIGNED_USER_REQUIRED/);
 assert.equal(called.length,3);
 console.log("PASS A048 JS signed RPC contract, command validation, no auth bypass");
})().catch(e=>{console.error(e);process.exitCode=1});
