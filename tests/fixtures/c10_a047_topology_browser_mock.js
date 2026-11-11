(function(){
"use strict";
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-test-only"};
let next=60;
const businesses=[{id:101,tenant_id:1,slug:"synthetic-sweets",status:"draft"},
 {id:102,tenant_id:1,slug:"synthetic-second",status:"draft"}];
const site={site_id:1001,label:"Original Showroom",kind:"showroom",version:1,
 locations:[{id:5001,code:"MAIN"}]};
const groups={
 101:[
  {group_id:11,group_key:"showroom",label:"Showrooms",kind:"showroom",default:true,sites:[site]},
  {group_id:12,group_key:"factory",label:"Factories",kind:"factory",default:true,sites:[{site_id:1002,label:"Main Factory",kind:"factory",version:1,locations:[{id:5002,code:"MAIN"}]}]},
  {group_id:13,group_key:"godown",label:"Godowns",kind:"godown",default:true,sites:[]}
 ],
 102:[{group_id:21,group_key:"showroom",label:"Second Business Showrooms",kind:"showroom",default:true,sites:[{site_id:1003,label:"B Main",kind:"showroom",version:1,locations:[{id:5003,code:"MAIN"}]}]}]
};
const audit={101:[],102:[]};
window.CORE10_A047_E2E={calls:[],groups};
function clone(v){return JSON.parse(JSON.stringify(v))}
function respond(name,args){
 window.CORE10_A047_E2E.calls.push({name,args});
 if(name==="read_site_topology_v1")return{data:{
  server_authorized:true,tenant_id:1,business_id:args.p_business,can_manage:true,
  groups:clone(groups[args.p_business]||[]),ungrouped:[],operationally_certified:false},error:null};
 if(name==="read_site_topology_audit_v1")return{data:{business_id:args.p_business,items:clone(audit[args.p_business]||[])},error:null};
 if(name==="bootstrap_site_groups_v1")return{data:{business_id:args.p_business,initialized:true,new_members:0},error:null};
 if(name==="create_site_group_v1"){
  const id=next++;const g={group_id:id,group_key:args.p_key,label:args.p_label,kind:args.p_kind,default:false,sites:[]};
  groups[args.p_business].push(g);
  audit[args.p_business].unshift({event_kind:"group_created",reason:"Create an operating group"});
  return{data:{business_id:args.p_business,group_id:id,kind:args.p_kind},error:null};
 }
 if(name==="create_site_in_group_v1"){
  const g=groups[args.p_business].find(x=>x.group_id===args.p_group);
  if(!g)return{data:null,error:{code:"FORBIDDEN",message:"Wrong group"}};
  const sid=next++;
  g.sites.push({site_id:sid,label:args.p_label,kind:g.kind,version:1,locations:[{id:7000+sid,code:"MAIN"}]});
  return{data:{business_id:args.p_business,group_id:args.p_group,site_id:sid},error:null};
 }
 if(name==="move_site_group_v1"){
  const groupList=groups[101];
  const source=groupList.find(x=>x.sites.some(y=>y.site_id===args.p_site));
  const target=groupList.find(x=>x.group_id===args.p_group);
  if(!source||!target)return{data:null,error:{code:"MISSING",message:"Wrong target"}};
  const site=source.sites.find(x=>x.site_id===args.p_site);
  if(site.version!==args.p_expected_version)return{data:null,error:{code:"STALE",message:"Stale version"}};
  source.sites=source.sites.filter(x=>x!==site);site.version++;target.sites.push(site);
  audit[101].unshift({event_kind:"site_moved",site_id:site.site_id,reason:args.p_reason,before_version:site.version-1,after_version:site.version});
  return{data:{business_id:101,site_id:site.site_id,group_id:target.group_id,version:site.version},error:null};
 }
 return{data:null,error:{code:"UNKNOWN_RPC",message:"Unsupported test fixture method"}};
}
window.supabase={createClient:()=>({
 auth:{getUser:async()=>({data:{user:{id:"synthetic-auth-session"}},error:null})},
 schema:(name)=>{
  if(name!=="c10_demo")throw Error("INVALID_SCHEMA");
  return{rpc:async(n,a)=>respond(n,a),
   from:(table)=>{
    if(table!=="businesses")throw Error("DIRECT_PRIVATE_TABLE_ACCESS");
    return{select(){return this},order(){return this},limit:async()=>({data:businesses,error:null})};
   }
  };
 }
})};
})();