/* C10-A051 Workforce signed-session RPC client. One strict allow-list adapter for every Workforce page.
 * - Requires a Supabase client whose auth.getUser() verifies the session with the Auth server (no cached/forged identity).
 * - Calls ONLY schema('c10_demo').rpc(<allow-listed wf_*_v1>) with exactly the declared argument names/types.
 * - No local role/permission authority, no direct table access, no simulated success, no token persistence here.
 * - UI hints come from server `capabilities`; the database remains the only authority.
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_WORKFORCE_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 // type codes: b business id, k request key, i int, I nullable int, s string, S nullable string, d date, D nullable date,
 // t nullable timestamptz, n number, N nullable number, o boolean, j json object/array, J nullable json
 const SPEC={
  my_businesses:{a:{},w:0},
  read_overview:{a:{p_business:"b"},w:0},
  list_employees:{a:{p_business:"b",p_search:"S",p_status:"S",p_site:"I",p_limit:"i",p_offset:"i"},w:0},
  get_employee:{a:{p_business:"b",p_employee:"i"},w:0},
  read_catalog:{a:{p_business:"b",p_year:"I"},w:0},
  list_attendance:{a:{p_business:"b",p_from:"d",p_to:"d",p_employee:"I",p_site:"I"},w:0},
  list_punches:{a:{p_business:"b",p_employee:"i",p_from:"d",p_to:"d"},w:0},
  list_corrections:{a:{p_business:"b",p_status:"S"},w:0},
  list_leave:{a:{p_business:"b",p_status:"S",p_employee:"I"},w:0},
  leave_balance:{a:{p_business:"b",p_employee:"I",p_year:"I"},w:0},
  list_advances:{a:{p_business:"b"},w:0},
  list_payroll_runs:{a:{p_business:"b"},w:0},
  get_payroll_run:{a:{p_business:"b",p_run:"i"},w:0},
  payroll_preview:{a:{p_business:"b",p_period:"d"},w:0},
  my_payslips:{a:{p_business:"b"},w:0},
  get_my_payslip:{a:{p_business:"b",p_payslip:"i"},w:0},
  report_attendance:{a:{p_business:"b",p_from:"d",p_to:"d"},w:0},
  report_headcount:{a:{p_business:"b"},w:0},
  report_payroll:{a:{p_business:"b",p_period:"d"},w:0},
  payslip_register:{a:{p_business:"b",p_period:"D"},w:0},
  audit_list:{a:{p_business:"b",p_limit:"i"},w:0},
  integrity_report:{a:{p_business:"b"},w:0},
  save_settings:{a:{p_business:"b",p_request:"k",p_expected_version:"i",p_changes:"j",p_reason:"s"},w:1},
  save_department:{a:{p_business:"b",p_request:"k",p_code:"s",p_name:"s",p_active:"o",p_reason:"s"},w:1},
  save_employee:{a:{p_business:"b",p_request:"k",p_employee_id:"I",p_expected_version:"I",p_data:"j",p_reason:"s"},w:1},
  set_employment:{a:{p_business:"b",p_request:"k",p_employee:"i",p_effective_from:"d",p_status:"s",p_contract_type:"s",p_reason:"s"},w:1},
  assign_employee:{a:{p_business:"b",p_request:"k",p_employee:"i",p_effective_from:"d",p_site:"i",p_department_code:"S",p_designation:"S",p_is_supervisor:"o",p_reason:"s"},w:1},
  save_shift:{a:{p_business:"b",p_request:"k",p_expected_version:"i",p_shift:"j",p_reason:"s"},w:1},
  assign_shift:{a:{p_business:"b",p_request:"k",p_employee:"i",p_shift_code:"s",p_effective_from:"d",p_reason:"s"},w:1},
  save_holiday:{a:{p_business:"b",p_request:"k",p_date:"d",p_name:"s",p_kind:"s",p_paid:"o",p_site:"I",p_active:"o",p_reason:"s"},w:1},
  import_punches:{a:{p_business:"b",p_request:"k",p_site:"i",p_source:"s",p_punches:"j"},w:1},
  request_correction:{a:{p_business:"b",p_request:"k",p_employee:"i",p_work_date:"d",p_new_in:"t",p_new_out:"t",p_new_status:"S",p_reason:"s"},w:1},
  decide_correction:{a:{p_business:"b",p_request:"k",p_correction:"i",p_decision:"s",p_note:"s"},w:1},
  decide_overtime:{a:{p_business:"b",p_request:"k",p_employee:"i",p_work_date:"d",p_minutes:"i",p_note:"s"},w:1},
  save_leave_type:{a:{p_business:"b",p_request:"k",p_expected_version:"i",p_type:"j",p_reason:"s"},w:1},
  request_leave:{a:{p_business:"b",p_request:"k",p_employee:"I",p_type_code:"s",p_from:"d",p_to:"d",p_reason:"s"},w:1},
  decide_leave:{a:{p_business:"b",p_request:"k",p_leave:"i",p_decision:"s",p_note:"s"},w:1},
  cancel_leave:{a:{p_business:"b",p_request:"k",p_leave:"i",p_note:"s"},w:1},
  save_pay_policy:{a:{p_business:"b",p_request:"k",p_expected_version:"i",p_policy:"j",p_reason:"s"},w:1},
  set_salary_structure:{a:{p_business:"b",p_request:"k",p_employee:"i",p_policy_code:"s",p_base:"n",p_effective_from:"d",p_reason:"s"},w:1},
  save_component:{a:{p_business:"b",p_request:"k",p_expected_version:"i",p_component:"j",p_reason:"s"},w:1},
  assign_component:{a:{p_business:"b",p_request:"k",p_employee:"i",p_component_code:"s",p_enabled:"o",p_override:"N",p_effective_from:"d",p_reason:"s"},w:1},
  request_advance:{a:{p_business:"b",p_request:"k",p_employee:"I",p_amount:"n",p_installment:"n",p_start_period:"d",p_reason:"s"},w:1},
  decide_advance:{a:{p_business:"b",p_request:"k",p_advance:"i",p_decision:"s",p_note:"s"},w:1},
  create_payroll_draft:{a:{p_business:"b",p_request:"k",p_period:"d",p_amends_run:"I",p_reason:"S"},w:1},
  recalculate_payroll_draft:{a:{p_business:"b",p_request:"k",p_run:"i"},w:1},
  payroll_transition:{a:{p_business:"b",p_request:"k",p_run:"i",p_action:"s",p_note:"S"},w:1},
  purge_expired_punches:{a:{p_business:"b",p_request:"k",p_dry_run:"o"},w:1},
  export_csv:{a:{p_business:"b",p_request:"k",p_kind:"s",p_params:"J"},w:1}
 };
 const NAMES=Object.freeze(Object.keys(SPEC));
 const DATE=/^\d{4}-\d{2}-\d{2}$/,KEY=/^[A-Za-z0-9_-]{8,100}$/,TS=/(Z|[+-]\d{2}:?\d{2})$/;
 function fail(code,detail){const e=new Error(code);e.code=code;if(detail)e.detail=detail;throw e}
 function check(type,v,name){
  const nullable=type==="t"||"ISDNJ".includes(type);
  if(v===null||v===undefined){if(nullable)return null;fail("INVALID_ARGUMENT",name)}
  switch(type.toLowerCase()){
   case"b":case"i":if(!Number.isSafeInteger(v)||(type==="b"&&v<1))fail("INVALID_ARGUMENT",name);return v;
   case"k":if(typeof v!=="string"||!KEY.test(v))fail("INVALID_REQUEST_KEY",name);return v;
   case"s":if(typeof v!=="string"||v.length>2000)fail("INVALID_ARGUMENT",name);return v;
   case"d":if(typeof v!=="string"||!DATE.test(v))fail("INVALID_ARGUMENT",name);return v;
   case"t":if(typeof v!=="string"||!TS.test(v))fail("INVALID_ARGUMENT",name);return v;
   case"n":if(typeof v!=="number"||!Number.isFinite(v))fail("INVALID_ARGUMENT",name);return v;
   case"o":if(typeof v!=="boolean")fail("INVALID_ARGUMENT",name);return v;
   case"j":if(v===null||typeof v!=="object")fail("INVALID_ARGUMENT",name);return v;
  }
  fail("INVALID_ARGUMENT",name);
 }
 function requestKey(prefix){
  const c=(typeof globalThis!=="undefined"&&globalThis.crypto)||null;
  if(!c||typeof c.getRandomValues!=="function")fail("SECURE_RANDOM_REQUIRED");
  const b=new Uint8Array(12);c.getRandomValues(b);
  const hex=Array.from(b,x=>x.toString(16).padStart(2,"0")).join("");
  const p=String(prefix||"wf").replace(/[^A-Za-z0-9_-]/g,"").slice(0,20)||"wf";
  return p+"-"+hex;
 }
 function create({client}={}){
  async function schema(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   const r=await client.auth.getUser();
   if(!r||r.error||!r.data||!r.data.user||typeof r.data.user.id!=="string"||!r.data.user.id)fail("AUTHENTICATED_USER_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function")fail("WORKFORCE_SCHEMA_NOT_AVAILABLE");
   return s;
  }
  async function call(name,params){
   const spec=Object.prototype.hasOwnProperty.call(SPEC,name)?SPEC[name]:null;
   if(!spec)fail("RPC_NOT_ALLOWED",name);
   const given=params||{},args={};
   for(const k of Object.keys(given))if(!(k in spec.a))fail("UNKNOWN_ARGUMENT",k);
   for(const [k,t] of Object.entries(spec.a))args[k]=check(t,given[k],k);
   const s=await schema();
   const res=await s.rpc("wf_"+name+"_v1",args);
   if(!res||res.error){
    const msg=res&&res.error&&res.error.message||"WORKFORCE_RPC_UNAVAILABLE";
    const e=new Error(msg);e.code=msg;e.status=res&&res.error&&res.error.code;throw e;
   }
   const d=res.data;
   if(d===null||d===undefined||typeof d!=="object")fail("WORKFORCE_RESPONSE_REJECTED",name);
   if(!spec.w&&d.server_authorized!==true)fail("WORKFORCE_RESPONSE_UNAUTHORIZED",name);
   return d;
  }
  async function integrationSummary(businessId,period){
   const s=await schema();
   const b=check("b",businessId,"p_business"),p=check("D",period===undefined?null:period,"p_period");
   const res=await s.rpc("read_workforce_business_summary_v1",{p_business:b,p_period:p});
   if(!res||res.error)fail(res&&res.error&&res.error.message||"WORKFORCE_RPC_UNAVAILABLE");
   return res.data;
  }
  return Object.freeze({call,integrationSummary,requestKey,names:NAMES});
 }
 return Object.freeze({create,requestKey,NAMES,SPEC});
});
