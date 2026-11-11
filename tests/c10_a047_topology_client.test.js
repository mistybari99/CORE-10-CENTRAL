"use strict";
const assert=require("node:assert/strict");
const api=require("../core10-site-topology-client.js");
const calls=[];
const groups=[
 {group_id:11,group_key:"showroom",label:"Showrooms",kind:"showroom",default:true,
  sites:[{site_id:1001,label:"Main",kind:"showroom",version:1,locations:[{id:5001,code:"MAIN"}]}]},
 {group_id:12,group_key:"factory",label:"Factories",kind:"factory",default:true,sites:[]}
];
const result={server_authorized:true,business_id:101,tenant_id:1,
 can_manage:true,operationally_certified:false,groups,ungrouped:[]};
let denied=false,wrong=false;
const client={
 auth:{getUser:async()=>denied?{data:{user:null},error:{message:"DENIED"}}:{data:{user:{id:"synthetic-session-sub"}},error:null}},
 schema:(name)=>{
  assert.equal(name,"c10_demo");
  return {
   from:(table)=>{
    assert.equal(table,"businesses");
    return{select(){return this},order(){return this},limit:async()=>({data:[{id:101,tenant_id:1,slug:"test-business",status:"draft"}],error:null})};
   },
   rpc:async(name,args)=>{
    calls.push([name,args]);
    if(name==="read_site_topology_v1")return{data:wrong?{...result,business_id:201}:result,error:null};
    if(name==="bootstrap_site_groups_v1")return{data:{business_id:101,initialized:true,new_members:1},error:null};
    if(name==="create_site_group_v1")return{data:{business_id:101,group_id:55,kind:args.p_kind},error:null};
    if(name==="create_site_in_group_v1")return{data:{business_id:101,group_id:55,site_id:3001},error:null};
    if(name==="move_site_group_v1")return{data:{business_id:101,site_id:1001,group_id:55,version:2},error:null};
    if(name==="read_site_topology_audit_v1")return{data:{business_id:101,items:[{id:1,event_kind:"bootstrap"}]},error:null};
    return{error:{code:"RPC_NOT_REGISTERED",message:"Unregistered"},data:null}
   }
  };
 }
};
(async()=>{
 const sdk=api.create({client});
 assert.equal((await sdk.businesses())[0].id,101);
 assert.equal((await sdk.read(101)).groups[0].sites[0].locations[0].id,5001);
 assert.equal((await sdk.bootstrap(101,"boot-101-001")).new_members,1);
 assert.equal((await sdk.addGroup(101,"showroom","north_showrooms","North Showrooms","group-north-001")).group_id,55);
 assert.equal((await sdk.addSite(101,55,"North Test Shop","site-north-001")).site_id,3001);
 assert.equal((await sdk.move(1001,55,1,"move-shop-001","Group reorganization")).version,2);
 assert.equal((await sdk.audit(101)).length,1);
 assert.equal(sdk.releaseStatus().productionCertified,false);
 assert.equal(sdk.releaseStatus().stockWrites,false);
 assert.equal(calls.some(([fn])=>fn==="read_site_topology_v1"),true);
 assert.equal(calls.some(([fn])=>fn==="move_site_group_v1"),true);
 await assert.rejects(()=>sdk.read("101?role=owner"),/INVALID_BUSINESS_ID/);
 await assert.rejects(()=>sdk.addGroup(101,"showroom","Bad Key","North","group-north-001"),/INVALID_GROUP/);
 await assert.rejects(()=>sdk.addSite(101,55,"","site-north-001"),/INVALID_SITE_LABEL/);
 await assert.rejects(()=>sdk.move(1001,55,0,"move-shop-001","no"),/INVALID_EXPECTED_VERSION/);
 wrong=true;
 await assert.rejects(()=>sdk.read(101),/INVALID_AUTHORIZED_TOPOLOGY_RESPONSE/);
 wrong=false;
 denied=true;
 await assert.rejects(()=>sdk.read(101),/AUTHENTICATED_USER_REQUIRED/);
 assert.equal(calls.filter(([name])=>name==="read_site_topology_v1").length,2,"denied before any network RPC");
 console.log("PASS A047 signed-session client RPC contracts, scope rejection, create/move/read and credential gate");
})().catch(e=>{console.error(e);process.exitCode=1});
