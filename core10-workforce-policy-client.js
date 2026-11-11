/* C10-A053/A054 Workforce Integration & Policy signed-session RPC client. One strict allow-list.
 * - Needs a Supabase client whose auth.getUser() verifies the session with the Auth server (no cached/forged identity).
 * - Calls ONLY schema('c10_demo').rpc(<allow-listed a053_*_v1 / a054_*_v1 / 4 reviewed A051 wf_*_v1>) with exact argument names/types.
 * - No local role authority, no table access, no simulated success. The database stays the only authority.
 * - There is NO payment function here: external payments are RECORDS of money moved outside this system.
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_WORKFORCE_POLICY_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 // type codes: b business id, k request key, i int, I nullable int, s string, S nullable string, d date, D nullable date,
 // t nullable timestamptz, n number, o boolean, j json object, u uuid
 const SPEC={
  my_businesses:{rpc:"wf_my_businesses_v1",a:{},w:0},
  payroll_preview:{rpc:"wf_payroll_preview_v1",a:{p_business:"b",p_period:"d"},w:0},
  list_payroll_runs:{rpc:"wf_list_payroll_runs_v1",a:{p_business:"b"},w:0},
  create_payroll_draft:{rpc:"wf_create_payroll_draft_v1",a:{p_business:"b",p_request:"k",p_period:"d",p_amends_run:"I",p_reason:"S"},w:1},
  payroll_transition:{rpc:"wf_payroll_transition_v1",a:{p_business:"b",p_request:"k",p_run:"i",p_action:"s",p_note:"S"},w:1},
  persona_catalog:{rpc:"a053_persona_catalog_v1",a:{},w:0},
  staff_overview:{rpc:"a053_staff_overview_v1",a:{p_business:"b"},w:0},
  my_assignments:{rpc:"a053_my_assignments_v1",a:{},w:0},
  read_portfolio_workforce:{rpc:"a053_read_portfolio_workforce_v1",a:{p_period:"D"},w:0},
  link_staff_identity:{rpc:"a053_link_staff_identity_v1",a:{p_business:"b",p_request:"k",p_employee:"i",p_alias:"s",p_reason:"s"},w:1},
  unlink_staff_identity:{rpc:"a053_unlink_staff_identity_v1",a:{p_business:"b",p_request:"k",p_employee:"i",p_reason:"s"},w:1},
  grant_delegation:{rpc:"a054_grant_delegation_v1",a:{p_business:"b",p_request:"k",p_delegate:"u",p_role:"s",p_effect:"s",p_site:"I",p_period_from:"D",p_period_to:"D",p_expires_at:"t",p_reason:"s"},w:1},
  revoke_delegation:{rpc:"a054_revoke_delegation_v1",a:{p_business:"b",p_request:"k",p_delegation:"i",p_expected_version:"i",p_note:"s"},w:1},
  list_delegations:{rpc:"a054_list_delegations_v1",a:{p_business:"b"},w:0},
  eligible_delegates:{rpc:"a054_eligible_delegates_v1",a:{p_business:"b"},w:0},
  my_access:{rpc:"a054_my_access_v1",a:{p_business:"b"},w:0},
  save_policy:{rpc:"a054_save_policy_v1",a:{p_business:"b",p_request:"k",p_kind:"s",p_subject:"s",p_effective_from:"d",p_params:"j",p_reason:"s",p_legal_ref:"S"},w:1},
  list_policies:{rpc:"a054_list_policies_v1",a:{p_business:"b",p_kind:"s"},w:0},
  leave_balance:{rpc:"a054_leave_balance_v1",a:{p_business:"b",p_employee:"I",p_year:"I"},w:0},
  place_legal_hold:{rpc:"a054_place_legal_hold_v1",a:{p_business:"b",p_request:"k",p_employee:"I",p_from:"d",p_to:"d",p_reason:"s"},w:1},
  release_legal_hold:{rpc:"a054_release_legal_hold_v1",a:{p_business:"b",p_request:"k",p_hold:"i",p_note:"s"},w:1},
  retention_report:{rpc:"a054_retention_report_v1",a:{p_business:"b"},w:0},
  record_external_payment:{rpc:"a054_record_external_payment_v1",a:{p_business:"b",p_request:"k",p_period:"d",p_employee:"i",p_amount:"n",p_method:"s",p_reference:"s",p_paid_on:"d",p_note:"S"},w:1},
  reverse_payment_record:{rpc:"a054_reverse_payment_record_v1",a:{p_business:"b",p_request:"k",p_record:"i",p_note:"s"},w:1},
  liability_report:{rpc:"a054_liability_report_v1",a:{p_business:"b",p_period:"D"},w:0},
  export_liability_csv:{rpc:"a054_export_liability_csv_v1",a:{p_business:"b",p_request:"k",p_period:"d"},w:1}
 };
 const NAMES=Object.freeze(Object.keys(SPEC));
 const DATE=/^\d{4}-\d{2}-\d{2}$/,KEY=/^[A-Za-z0-9_-]{8,100}$/,TS=/(Z|[+-]\d{2}:?\d{2})$/,UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function fail(code,detail){const e=new Error(code);e.code=code;if(detail)e.detail=detail;throw e}
 function check(type,v,name){
  const nullable=type==="t"||"ISDNJ".includes(type);
  if(v===null||v===undefined){if(nullable)return null;fail("INVALID_ARGUMENT",name)}
  switch(type.toLowerCase()){
   case"b":case"i":if(!Number.isSafeInteger(v)||(type==="b"&&v<1))fail("INVALID_ARGUMENT",name);return v;
   case"k":if(typeof v!=="string"||!KEY.test(v))fail("INVALID_REQUEST_KEY",name);return v;
   case"u":if(typeof v!=="string"||!UUID.test(v))fail("INVALID_ARGUMENT",name);return v;
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
  return (String(prefix||"wfp").replace(/[^A-Za-z0-9_-]/g,"").slice(0,20)||"wfp")+"-"+hex;
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
   const res=await s.rpc(spec.rpc,args);
   if(!res||res.error){
    const msg=res&&res.error&&res.error.message||"WORKFORCE_RPC_UNAVAILABLE";
    const e=new Error(msg);e.code=msg;e.status=res&&res.error&&res.error.code;throw e;
   }
   const d=res.data;
   if(d===null||d===undefined||typeof d!=="object")fail("WORKFORCE_RESPONSE_REJECTED",name);
   if(!spec.w&&d.server_authorized!==true)fail("WORKFORCE_RESPONSE_UNAUTHORIZED",name);
   return d;
  }
  return Object.freeze({call,requestKey,names:NAMES});
 }
 return Object.freeze({create,requestKey,NAMES,SPEC});
});
