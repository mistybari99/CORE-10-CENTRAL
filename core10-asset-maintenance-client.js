/* C10-A055 Assets & Maintenance signed-session RPC client. One strict allow-list adapter for every A055 page.
 * - Auth pattern identical to A044/A051: needs a Supabase client whose auth.getUser() verifies the session with the Auth server,
 *   then calls ONLY client.schema('c10_demo').rpc(<allow-listed am_*_v1>, exactly the declared argument names/types).
 * - The client NEVER holds service keys, never reads tables, never persists tokens, never fakes success.
 * - Capability hints from am_whoami_v1 are advisory only: the database is the sole authority.
 * - Allow-list == the public RPC names of docs/architecture/C10_A055_RPC_CONTRACT.md (a test keeps them equal, argument by argument).
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_AM_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 /* argument type codes (lower-case = required, UPPER-case = nullable):
  * b business id (int>=1)  i int  n finite number  s string  d date YYYY-MM-DD  t timestamptz string with zone  o boolean
  * k request key  j json object/array  u uuid  a int array  x text array */
 const W=1,R=0;
 const SPEC={
  /* policy */
  am_whoami_v1:{a:{p_business:"b"},w:R},
  am_policy_catalog_v1:{a:{p_business:"b"},w:R},
  am_get_policy_v1:{a:{p_business:"b",p_site:"I",p_category:"I"},w:R},
  am_save_policy_v1:{a:{p_business:"b",p_request:"k",p_expected_rev:"i",p_scope_type:"s",p_scope_id:"i",p_changes:"j",p_reason:"s"},w:W},
  am_reset_policy_v1:{a:{p_business:"b",p_request:"k",p_expected_rev:"i",p_scope_type:"s",p_scope_id:"i",p_keys:"x",p_reason:"s"},w:W},
  am_apply_preset_v1:{a:{p_business:"b",p_request:"k",p_expected_rev:"i",p_preset:"s",p_scope_type:"s",p_scope_id:"i",p_reason:"s"},w:W},
  am_preview_policy_v1:{a:{p_business:"b",p_scope_type:"s",p_scope_id:"i",p_changes:"j"},w:R},
  am_simulate_schedule_v1:{a:{p_business:"b",p_params:"j"},w:R},
  am_policy_history_v1:{a:{p_business:"b",p_limit:"i"},w:R},
  am_bootstrap_v1:{a:{p_business:"b",p_request:"k"},w:W},
  /* registry */
  am_grant_role_v1:{a:{p_business:"b",p_request:"k",p_user:"u",p_role:"s",p_site:"I",p_note:"S",p_reason:"s"},w:W},
  am_revoke_role_v1:{a:{p_business:"b",p_request:"k",p_grant:"i",p_reason:"s"},w:W},
  am_save_category_v1:{a:{p_business:"b",p_request:"k",p_id:"I",p_expected_version:"I",p_data:"j",p_reason:"s"},w:W},
  am_save_code_v1:{a:{p_business:"b",p_request:"k",p_kind:"s",p_code:"s",p_label:"s",p_label_bn:"S",p_active:"o",p_reason:"s"},w:W},
  am_create_asset_v1:{a:{p_business:"b",p_request:"k",p_data:"j",p_reason:"s"},w:W},
  am_update_asset_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_expected_version:"i",p_changes:"j",p_reason:"s"},w:W},
  am_set_asset_status_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_expected_version:"i",p_status:"s",p_reason:"s"},w:W},
  am_request_transfer_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_to_site:"i",p_include_children:"o",p_reason:"s"},w:W},
  am_decide_transfer_v1:{a:{p_business:"b",p_request:"k",p_transfer:"i",p_expected_version:"i",p_decision:"s",p_note:"S"},w:W},
  am_add_meter_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_code:"s",p_unit:"s",p_initial_reading:"N"},w:W},
  am_record_meter_reading_v1:{a:{p_business:"b",p_request:"k",p_meter:"i",p_reading:"n",p_read_at:"T",p_kind:"s",p_note:"S"},w:W},
  am_save_warranty_v1:{a:{p_business:"b",p_request:"k",p_id:"I",p_expected_version:"I",p_data:"j",p_reason:"s"},w:W},
  am_save_claim_v1:{a:{p_business:"b",p_request:"k",p_id:"I",p_expected_version:"I",p_data:"j"},w:W},
  am_claim_transition_v1:{a:{p_business:"b",p_request:"k",p_claim:"i",p_expected_version:"i",p_action:"s",p_data:"J"},w:W},
  am_list_grants_v1:{a:{p_business:"b"},w:R},
  am_list_catalog_v1:{a:{p_business:"b"},w:R},
  am_list_assets_v1:{a:{p_business:"b",p_filters:"J",p_limit:"i",p_offset:"i"},w:R},
  am_get_asset_v1:{a:{p_business:"b",p_asset:"i"},w:R},
  am_list_transfers_v1:{a:{p_business:"b",p_status:"S"},w:R},
  am_list_claims_v1:{a:{p_business:"b",p_status:"S",p_limit:"i",p_offset:"i"},w:R},
  am_list_warranties_v1:{a:{p_business:"b",p_asset:"I"},w:R},
  /* planning */
  am_save_checklist_template_v1:{a:{p_business:"b",p_request:"k",p_code:"s",p_name:"s",p_category_id:"I",p_items:"j",p_reason:"s"},w:W},
  am_save_plan_v1:{a:{p_business:"b",p_request:"k",p_id:"I",p_expected_version:"I",p_data:"j",p_reason:"s"},w:W},
  am_generate_work_orders_v1:{a:{p_business:"b",p_request:"k",p_target_ids:"a",p_site:"I",p_horizon_days:"I"},w:W},
  am_defer_target_v1:{a:{p_business:"b",p_request:"k",p_target:"i",p_until:"d",p_reason:"s"},w:W},
  am_list_checklists_v1:{a:{p_business:"b",p_include_inactive:"o"},w:R},
  am_list_plans_v1:{a:{p_business:"b",p_filters:"J"},w:R},
  am_due_suggestions_v1:{a:{p_business:"b",p_site:"I",p_horizon_days:"I"},w:R},
  am_calendar_v1:{a:{p_business:"b",p_from:"d",p_to:"d",p_site:"I"},w:R},
  /* work orders */
  am_create_work_order_v1:{a:{p_business:"b",p_request:"k",p_data:"j"},w:W},
  am_update_work_order_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_expected_version:"i",p_changes:"j",p_reason:"s"},w:W},
  am_assign_work_order_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_expected_version:"i",p_assigned_to:"U",p_assignee_ref:"S",p_team_ref:"S",p_reason:"s"},w:W},
  am_wo_transition_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_expected_version:"i",p_action:"s",p_reason:"S",p_data:"J"},w:W},
  am_wo_checklist_result_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_seq:"i",p_result:"s",p_value:"N",p_note:"S"},w:W},
  am_wo_add_labor_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_data:"j"},w:W},
  am_wo_add_spares_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_data:"j"},w:W},
  am_wo_add_attachment_v1:{a:{p_business:"b",p_request:"k",p_wo:"i",p_data:"j"},w:W},
  am_acknowledge_safety_v1:{a:{p_business:"b",p_request:"k",p_wo:"i"},w:W},
  am_merge_work_orders_v1:{a:{p_business:"b",p_request:"k",p_keep:"i",p_merge:"i",p_reason:"s"},w:W},
  am_report_breakdown_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_data:"j"},w:W},
  am_start_downtime_v1:{a:{p_business:"b",p_request:"k",p_asset:"i",p_data:"j"},w:W},
  am_end_downtime_v1:{a:{p_business:"b",p_request:"k",p_downtime:"i",p_ended_at:"T",p_note:"S"},w:W},
  am_list_work_orders_v1:{a:{p_business:"b",p_filters:"J",p_limit:"i",p_offset:"i"},w:R},
  am_get_work_order_v1:{a:{p_business:"b",p_wo:"i"},w:R},
  am_my_work_v1:{a:{p_business:"b"},w:R},
  am_list_downtime_v1:{a:{p_business:"b",p_filters:"J",p_limit:"i",p_offset:"i"},w:R},
  /* reports */
  am_overview_v1:{a:{p_business:"b",p_site:"I"},w:R},
  am_downtime_report_v1:{a:{p_business:"b",p_from:"d",p_to:"d",p_site:"I"},w:R},
  am_kpi_report_v1:{a:{p_business:"b",p_from:"d",p_to:"d",p_site:"I"},w:R},
  am_asset_health_report_v1:{a:{p_business:"b",p_site:"I"},w:R},
  am_warranty_report_v1:{a:{p_business:"b",p_horizon_days:"I"},w:R},
  am_reconciliation_v1:{a:{p_business:"b",p_from:"d",p_to:"d"},w:R},
  am_export_csv_v1:{a:{p_business:"b",p_request:"k",p_kind:"s",p_params:"J"},w:W},
  am_integrity_report_v1:{a:{p_business:"b"},w:R},
  am_audit_log_v1:{a:{p_business:"b",p_entity:"S",p_entity_id:"S",p_limit:"i",p_offset:"i"},w:R},
  read_asset_maintenance_business_summary_v1:{a:{p_business:"b",p_period:"D"},w:R}
 };
 const NAMES=Object.freeze(Object.keys(SPEC));
 const DATE=/^\d{4}-\d{2}-\d{2}$/,KEY=/^[A-Za-z0-9_-]{8,100}$/,TS=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/;
 const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
 const ERR_RX=/\b(am_[a-z0-9_]+)\b/;

 function fail(code,detail){const e=new Error(code);e.code=code;if(detail)e.detail=detail;throw e}
 /* A business id from untrusted text (URL ?biz=). Returns an integer or null. */
 function parseBusinessId(v){
  if(typeof v!=="string"&&typeof v!=="number")return null;
  const s=String(v).trim();
  if(!/^[1-9][0-9]{0,14}$/.test(s))return null;
  const n=Number(s);return Number.isSafeInteger(n)?n:null;
 }
 function check(type,v,name){
  const nullable=type!==type.toLowerCase(),base=type.toLowerCase();
  if(v===null||v===undefined){if(nullable)return null;fail("INVALID_ARGUMENT",name)}
  switch(base){
   case"b":if(!Number.isSafeInteger(v)||v<1)fail("INVALID_ARGUMENT",name);return v;
   case"i":if(!Number.isSafeInteger(v))fail("INVALID_ARGUMENT",name);return v;
   case"k":if(typeof v!=="string"||!KEY.test(v))fail("INVALID_REQUEST_KEY",name);return v;
   case"s":if(typeof v!=="string"||v.length>4000)fail("INVALID_ARGUMENT",name);return v;
   case"d":if(typeof v!=="string"||!DATE.test(v))fail("INVALID_ARGUMENT",name);return v;
   case"t":if(typeof v!=="string"||!TS.test(v))fail("INVALID_ARGUMENT",name);return v;
   case"n":if(typeof v!=="number"||!Number.isFinite(v))fail("INVALID_ARGUMENT",name);return v;
   case"o":if(typeof v!=="boolean")fail("INVALID_ARGUMENT",name);return v;
   case"j":if(typeof v!=="object")fail("INVALID_ARGUMENT",name);return v;
   case"u":if(typeof v!=="string"||!UUID.test(v))fail("INVALID_ARGUMENT",name);return v;
   case"a":if(!Array.isArray(v)||v.length>500||!v.every(x=>Number.isSafeInteger(x)&&x>0))fail("INVALID_ARGUMENT",name);return v;
   case"x":if(!Array.isArray(v)||v.length>200||!v.every(x=>typeof x==="string"&&x.length<=80))fail("INVALID_ARGUMENT",name);return v;
  }
  return fail("INVALID_ARGUMENT",name);
 }
 /* Request key: crypto.randomUUID based, regex-safe (^[A-Za-z0-9_-]{8,100}$). */
 function requestKey(prefix){
  const c=(typeof globalThis!=="undefined"&&globalThis.crypto)||null;
  if(!c)fail("SECURE_RANDOM_REQUIRED");
  let id;
  if(typeof c.randomUUID==="function")id=c.randomUUID();
  else if(typeof c.getRandomValues==="function"){const b=new Uint8Array(16);c.getRandomValues(b);id=Array.from(b,x=>x.toString(16).padStart(2,"0")).join("")}
  else fail("SECURE_RANDOM_REQUIRED");
  const p=String(prefix||"am").replace(/[^A-Za-z0-9_-]/g,"").slice(0,20)||"am";
  return p+"-"+id;
 }
 function stable(v){
  if(v===null||typeof v!=="object")return JSON.stringify(v===undefined?null:v);
  if(Array.isArray(v))return"["+v.map(stable).join(",")+"]";
  return"{"+Object.keys(v).sort().map(k=>JSON.stringify(k)+":"+stable(v[k])).join(",")+"}";
 }
 function errorFrom(res){
  const raw=res&&res.error||{};
  const msg=String(raw.message||raw.details||raw.hint||"");
  const m=ERR_RX.exec(msg);
  const e=new Error(m?m[1]:(msg||"AM_RPC_UNAVAILABLE"));
  e.code=m?m[1]:(/fetch|network|timeout|load failed/i.test(msg)?"AM_NETWORK":"AM_RPC_UNAVAILABLE");
  e.status=raw.code;e.raw=msg.slice(0,300);
  return e;
 }
 function create({client}={}){
  /* retry-safe request keys: the same action (op + identical arguments) re-uses its key until it succeeds */
  const pending=new Map();
  function keyFor(name,args){
   const sig=name+"|"+stable(args);
   let k=pending.get(sig);
   if(!k){k=requestKey("am");pending.set(sig,k);if(pending.size>300)pending.delete(pending.keys().next().value)}
   return{key:k,sig};
  }
  async function schema(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   const r=await client.auth.getUser();
   if(!r||r.error||!r.data||!r.data.user||typeof r.data.user.id!=="string"||!r.data.user.id)fail("AUTHENTICATED_USER_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function")fail("AM_SCHEMA_NOT_AVAILABLE");
   return s;
  }
  async function call(name,params){
   const spec=Object.prototype.hasOwnProperty.call(SPEC,name)?SPEC[name]:null;
   if(!spec)fail("RPC_NOT_ALLOWED",name);
   const given=Object.assign({},params||{});
   for(const k of Object.keys(given))if(!(k in spec.a))fail("UNKNOWN_ARGUMENT",k);
   let sig=null;
   if(spec.w&&(given.p_request===undefined||given.p_request===null)){
    const rest=Object.assign({},given);const kk=keyFor(name,rest);given.p_request=kk.key;sig=kk.sig;
   }
   const args={};
   for(const [k,t] of Object.entries(spec.a))args[k]=check(t,given[k],k);
   const s=await schema();
   let res;
   try{res=await s.rpc(name,args)}catch(x){const e=new Error("AM_NETWORK");e.code="AM_NETWORK";e.raw=String(x&&x.message||x).slice(0,200);throw e}
   if(!res||res.error)throw errorFrom(res);
   const d=res.data;
   if(d===null||d===undefined||typeof d!=="object")fail("AM_RESPONSE_REJECTED",name);
   if(sig)pending.delete(sig);
   return d;
  }
  return Object.freeze({call,requestKey,names:NAMES,isWrite:(n)=>!!(SPEC[n]&&SPEC[n].w)});
 }
 return Object.freeze({create,requestKey,parseBusinessId,NAMES,SPEC,stable});
});
