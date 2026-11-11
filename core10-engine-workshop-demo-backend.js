/* C10-A045 DEMO BACKEND — in-memory, runs only in this browser tab.
 * NOT Supabase, NOT a login, NOTHING is saved (reload = reset). Exists so the real Workshop UI can be
 * tried from a GitHub preview page with demo data. It never contacts any server.
 */
(function(){
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
const st={engines:[],audit:[],pending:[],nid:1,aid:1,rid:1,calls:[]};
const handlers=[{handler_id:"threshold_rule_v1",kind:"rule",certified:true,can_execute:true},
 {handler_id:"workflow_v1",kind:"workflow",certified:false,can_execute:false}];
const hash=(o)=>"h"+Array.from(JSON.stringify(o)).reduce((a,c)=>(a*31+c.charCodeAt(0))>>>0,7).toString(16).padStart(8,"0")+"0000";
const err=(code)=>({data:null,error:{code,message:code}});
const ok=(d)=>({data:d,error:null});
function ev(e,b,ev_,before,after){st.audit.push({audit_id:st.aid++,engine_id:e.engine_id,event:ev_,business_id:b,before,after,created_at:new Date().toISOString()})}
function evalRule(d,p,inp){const v=inp[d.field];if(typeof v!=="number")return null;
 const th=p&&p.threshold!==undefined?p.threshold:d.threshold,oc=(p&&p.outcome)||d.outcome;
 const hit={lt:v<th,lte:v<=th,gt:v>th,gte:v>=th,eq:v===th}[d.op];
 return{advisory:true,matched:hit,outcome:hit?oc:"allow",wouldBlock:hit&&oc==="block",requiresApproval:hit&&oc==="approval_required",
  effective:{field:d.field,op:d.op,threshold:th,outcome:oc},canAuthorizeOperation:false,mutates:false}}
function rpc(name,a){
 st.calls.push({name,args:a});
 if(name==="read_engines_v1")return ok({tenant_id:a.p_tenant,server_authorized:true,operationally_certified:false,handlers,engines:JSON.parse(JSON.stringify(st.engines))});
 if(name==="read_engine_pending_v1")return ok({tenant_id:a.p_tenant,items:st.pending.filter(r=>r.status==="pending")});
 if(name==="read_engine_audit_v1")return ok({engine_id:a.p_engine,items:st.audit.filter(x=>x.engine_id===a.p_engine).slice().reverse()});
 if(name==="preview_engine_draft_v1"){const r=evalRule(a.p_descriptor,a.p_params,a.p_inputs);return r?ok(r):err("invalid_input")}
 if(name==="save_engine_draft_v1"){let e=st.engines.find(x=>x.engine_key===a.p_key);
  if(!e){if(a.p_expected_version!==0)return err("engine_stale_version");
   e={engine_id:st.nid++,engine_key:a.p_key,display_name:a.p_name,handler_id:a.p_handler,current_version:0,versions:[],assignments:[]};st.engines.push(e);ev(e,null,"engine_created",null,{engine_key:a.p_key})}
  else if(e.current_version!==a.p_expected_version)return err("engine_stale_version");
  e.current_version++;e.versions.push({version:e.current_version,state:"DRAFT",descriptor:a.p_descriptor,hash:hash(a.p_descriptor),created_at:new Date().toISOString()});
  ev(e,null,"version_saved",null,{version:e.current_version});
  return ok({status:"saved",engine_id:e.engine_id,version:e.current_version,state:"DRAFT",can_execute:a.p_handler==="threshold_rule_v1"})}
 const e=st.engines.find(x=>x.engine_id===(a.p_engine));
 if(name==="validate_engine_version_v1"){const v=e.versions.find(x=>x.version===a.p_version);v.state="VALIDATED";ev(e,null,"version_validated",{state:"DRAFT"},{version:v.version});return ok({status:"validated",engine_id:e.engine_id,version:v.version,state:"VALIDATED"})}
 if(name==="assign_engine_v1"){let x=e.assignments.find(r=>r.business_id===a.p_business);const cur=x?x.version:0;
  if(cur!==a.p_expected)return err("engine_stale_version");
  const before=x?JSON.parse(JSON.stringify(x)):null;
  const nx={business_id:a.p_business,state:a.p_state,pinned_version:a.p_version,params:a.p_params,placement:a.p_placement,local_edit_mode:a.p_local_edit,version:cur+1};
  if(x)Object.assign(x,nx);else e.assignments.push(nx);
  ev(e,a.p_business,"assignment_changed",before,nx);return ok({status:"applied",engine_id:e.engine_id,business_id:a.p_business,state:a.p_state,version:cur+1})}
 if(name==="preview_business_engine_v1"){const x=e.assignments.find(r=>r.business_id===a.p_business);if(!x||x.state!=="PUBLISHED")return err("engine_not_published");
  const r=evalRule(e.versions.find(v=>v.version===x.pinned_version).descriptor,x.params,a.p_inputs);return ok(Object.assign(r,{engine_id:e.engine_id,business_id:a.p_business,version:x.pinned_version}))}
 if(name==="read_business_engines_v1"){const items=[];for(const g of st.engines){const x=g.assignments.find(r=>r.business_id===a.p_business);
   if(!x||x.state==="REVOKED"||!["both","business_only"].includes(x.placement))continue;
   const d=g.versions.find(v=>v.version===x.pinned_version).descriptor;
   items.push({control_id:"engine."+g.engine_key,engine_id:g.engine_id,display_name:g.display_name,handler_id:g.handler_id,group:"micro_engine",state:x.state,pinned_version:x.pinned_version,
    descriptor:d,params:x.params,effective:{field:d.field,op:d.op,threshold:x.params.threshold!==undefined?x.params.threshold:d.threshold,outcome:d.outcome},placement:x.placement,
    local_edit_mode:x.local_edit_mode,preferred_enabled:x.state==="PUBLISHED",version:x.version,can_execute:true,advisory_only:true,site_overrides:(g.sites||[]).filter(z=>z.business_id===a.p_business).map(z=>({site_id:z.site_id,params:z.params,version:z.version}))})}
  return ok({tenant_id:1,business_id:a.p_business,server_authorized:true,operationally_certified:false,items})}
 if(name==="edit_engine_params_v1"){const x=e.assignments.find(r=>r.business_id===a.p_business);
  if(!x||x.version!==a.p_expected)return err("engine_stale_version");
  if(x.local_edit_mode==="central_only")return err("engine_local_edit_denied");
  if(x.local_edit_mode==="request_approval"){st.pending.push({request_id:st.rid++,engine_id:e.engine_id,business_id:a.p_business,target_params:a.p_params,expected_version:x.version,reason:a.p_reason,status:"pending"});return ok({status:"pending",version:x.version})}
  x.params=a.p_params;x.version++;return ok({status:"applied",version:x.version})}
 if(name==="rollback_engine_assignment_v1"){const au=st.audit.find(z=>z.audit_id===a.p_audit_id),x=e.assignments.find(r=>r.business_id===a.p_business);
  if(!au||!x||x.version!==a.p_expected)return err("engine_stale_version");
  const b=au.before||x;Object.assign(x,{state:b.state,pinned_version:b.pinned_version,params:b.params,placement:b.placement,local_edit_mode:b.local_edit_mode,version:x.version+1});
  ev(e,a.p_business,"assignment_rolled_back",null,{version:x.version});return ok({status:"rolled_back",version:x.version,state:x.state,config_only:true})}
 if(name==="set_engine_site_override_v1"){e.sites=e.sites||[];let o=e.sites.find(z=>z.business_id===a.p_business&&z.site_id===a.p_site);const cur=o?o.version:0;
  if(cur!==a.p_expected)return err("engine_stale_version");
  if(o){o.params=a.p_params;o.version++}else{o={business_id:a.p_business,site_id:a.p_site,params:a.p_params,version:1};e.sites.push(o)}
  return ok({status:"applied",site_id:a.p_site,version:o.version})}
 if(name==="preview_site_engine_v1"){const x=e.assignments.find(r=>r.business_id===a.p_business);if(!x||x.state!=="PUBLISHED")return err("engine_not_published");
  const o=(e.sites||[]).find(z=>z.business_id===a.p_business&&z.site_id===a.p_site);
  const r=evalRule(e.versions.find(v=>v.version===x.pinned_version).descriptor,Object.assign({},x.params,o?o.params:{}),a.p_inputs);
  return ok(Object.assign(r,{engine_id:e.engine_id,business_id:a.p_business,site_id:a.p_site,version:x.pinned_version,site_override:!!o}))}
 return err("UNKNOWN_RPC");
}
window.CORE10_E2E=st;
window.supabase={createClient:function(){return{auth:{getUser:async()=>({data:{user:{id:"signed-test-fixture-uuid"}},error:null})},
 schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");
  return{rpc:async(n,a)=>rpc(n,a),from:function(t){if(t!=="businesses")throw Error("TABLE_SHADOW_ACCESS");
   return{select(){return this},order(){return this},limit:async()=>({data:[{id:101,tenant_id:1,slug:"business-a"},{id:102,tenant_id:1,slug:"business-b"}],error:null})}}}}}}};
})();
document.addEventListener("DOMContentLoaded",function(){
 var b=document.createElement("div");b.setAttribute("role","note");
 b.style.cssText="background:#3a2230;border-bottom:2px solid #f5a6a2;color:#ffe4e1;padding:10px 16px;font:13px system-ui;text-align:center";
 b.innerHTML="DEMO PREVIEW · in-memory demo accounts · nothing is saved or sent anywhere · reload resets. View as: "+
  '<a style="color:#ffd9a0" href="./core10-engine-workshop-demo.html">Owner</a> · <a style="color:#ffd9a0" href="./core10-engine-workshop-demo.html?biz=101">Business A owner</a>';
 document.body.insertBefore(b,document.body.firstChild);
});
