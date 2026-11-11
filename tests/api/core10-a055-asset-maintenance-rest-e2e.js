// C10-A055: signed HMAC JWT HTTP E2E against disposable PostgreSQL17 + PostgREST ONLY.
// NOT a Supabase-issued GoTrue token and NEVER a production release test. Claims never grant authority: the database decides.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("DISPOSABLE_JWT_SECRET_REQUIRED");
const A={owner:"11111111-1111-4111-8111-111111111111",bo101:"22222222-2222-4222-8222-222222222222",stock:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",revoked:"66666666-6666-4666-8666-666666666666",owner2:"77777777-7777-4777-8777-777777777777",
 operator:"99999999-9999-4999-8999-999999999999",sup:"d1111111-1111-4111-8111-111111111111",tech:"d3333333-3333-4333-8333-333333333333",
 reporter:"d5555555-5555-4555-8555-555555555555",auditor:"d6666666-6666-4666-8666-666666666666",revtech:"d7777777-7777-4777-8777-777777777777"};
function jwt(sub,claims={},key=secret){
 const now=Math.floor(Date.now()/1000),b64=(o)=>Buffer.from(JSON.stringify(o)).toString("base64url");
 const body=b64({alg:"HS256",typ:"JWT"})+"."+b64({role:"authenticated",sub,aud:"authenticated",iat:now,exp:now+300,...claims});
 return body+"."+crypto.createHmac("sha256",key).update(body).digest("base64url");
}
const T=Object.fromEntries(Object.entries(A).map(([k,v])=>[k,jwt(v)]));
async function request(path,token,method="GET",payload){
 const headers={accept:"application/json"};
 if(token)headers.authorization="Bearer "+token;
 if(payload!==undefined)headers["content-type"]="application/json";
 const res=await fetch(base+path,{method,headers,body:payload===undefined?undefined:JSON.stringify(payload),redirect:"error",signal:AbortSignal.timeout(20000)});
 const raw=await res.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
 return{status:res.status,data};
}
const rpc=(n,t,a)=>request("/rpc/"+n,t,"POST",a);
let seq=0;const K=(p)=>"rest-"+p+"-"+String(++seq).padStart(5,"0")+"-"+crypto.randomBytes(3).toString("hex");
function ok(r,m){assert.ok(r.status>=200&&r.status<300,m+": HTTP "+r.status+" "+JSON.stringify(r.data));return r.data}
function bad(r,m,code){assert.equal(r.status,400,m+": expected a stable am_* error, got "+r.status+" "+JSON.stringify(r.data));
 assert.ok(String(r.data&&r.data.message).startsWith(code),m+": wanted "+code+" got "+(r.data&&r.data.message))}
function blocked(r,m){assert.ok([400,401,403,404].includes(r.status),m+": unexpectedly allowed "+JSON.stringify(r));
 if(r.status===400)assert.match(String(r.data&&r.data.message),/^am_(denied|not_permitted|owner_required)/,m)}
const ids={};
(async()=>{
 // ---- identity & claims never elevate ----
 const who=ok(await rpc("am_whoami_v1",T.bo101,{p_business:101}),"business owner whoami");assert.equal(who.level,"business_owner");
 assert.equal(ok(await rpc("am_whoami_v1",T.owner,{p_business:101}),"tenant owner").level,"tenant_owner");
 bad(await rpc("am_whoami_v1",T.stock,{p_business:101}),"stock staff has no maintenance authority","am_denied");
 bad(await rpc("am_whoami_v1",T.investor,{p_business:101}),"investor","am_denied");
 bad(await rpc("am_whoami_v1",T.revoked,{p_business:101}),"revoked manager","am_denied");
 bad(await rpc("am_whoami_v1",T.operator,{p_business:101}),"platform operator without membership","am_denied");
 bad(await rpc("am_whoami_v1",T.owner2,{p_business:101}),"other tenant owner","am_denied");
 bad(await rpc("am_whoami_v1",T.revtech,{p_business:101}),"revoked grant","am_denied");
 const forged=jwt(A.stock,{role:"authenticated",app_metadata:{role:"owner",roles:["business_owner","supervisor"]},user_role:"admin",business_id:101,is_owner:true});
 bad(await rpc("am_whoami_v1",forged,{p_business:101}),"forged role/owner claims","am_denied");
 const svc=await rpc("am_whoami_v1",jwt(A.stock,{role:"service_role"}),{p_business:101});
 assert.ok(svc.status>=400,"service_role claim without a matching DB role must not work: "+svc.status);
 // ---- transport-level negatives ----
 blocked(await rpc("am_whoami_v1",null,{p_business:101}),"no token");
 assert.ok((await rpc("am_whoami_v1",jwt(A.bo101,{},"wrong_secret_wrong_secret_wrong_secret_1"),{p_business:101})).status===401,"bad signature");
 assert.ok((await rpc("am_whoami_v1",jwt(A.bo101,{exp:Math.floor(Date.now()/1000)-60}),{p_business:101})).status===401,"expired token");
 blocked(await request("/am_assets?select=*",T.bo101),"direct table read (owner)");
 blocked(await request("/am_assets?select=*",null),"direct table read (anon)");
 blocked(await request("/am_assets",T.bo101,"POST",{name:"x"}),"direct table insert");
 blocked(await rpc("ami_ctx",T.bo101,{p_business:101}),"internal helper not exposed");
 // ---- asset registry via HTTP ----
 ok(await rpc("am_bootstrap_v1",T.bo101,{p_business:101,p_request:K("boot")}),"bootstrap defaults (idempotent)");
 const cats=ok(await rpc("am_list_catalog_v1",T.bo101,{p_business:101}),"catalog").categories;
 const cat=cats.find(c=>c.code==="PROD-EQ").id;
 const mk=ok(await rpc("am_create_asset_v1",T.bo101,{p_business:101,p_request:K("ast"),p_data:{name:"HTTP oven",category_id:cat,site_id:1001,ownership:"owned",
  meters:[{code:"HRS",unit:"hours",reading:10}]},p_reason:"register via http"}),"create asset");
 ids.a=mk.asset_id;assert.equal(mk.status,"applied");
 const key=K("dup"),dupArgs={p_business:101,p_request:key,p_data:{name:"HTTP dup",category_id:cat,site_id:1001},p_reason:"dup test"};
 const burst=await Promise.all(Array.from({length:6},()=>rpc("am_create_asset_v1",T.bo101,dupArgs)));
 const first=ok(burst[0],"idempotent burst");for(const r of burst)assert.deepEqual(ok(r,"burst replay"),first);
 bad(await rpc("am_create_asset_v1",T.bo101,{...dupArgs,p_data:{name:"HTTP changed",category_id:cat,site_id:1001}}),"changed payload same key","am_idempotency_conflict");
 bad(await rpc("am_create_asset_v1",T.bo101,{...dupArgs,p_request:"short"}),"bad request key","am_invalid_request_key");
 bad(await rpc("am_create_asset_v1",T.reporter,{p_business:101,p_request:K("rep"),p_data:{name:"Rogue",category_id:cat,site_id:1001},p_reason:"nope nope"}),"reporter cannot register","am_not_permitted");
 bad(await rpc("am_get_asset_v1",T.owner2,{p_business:101,p_asset:ids.a}),"cross-tenant asset read","am_denied");
 bad(await rpc("am_update_asset_v1",T.owner2,{p_business:101,p_request:K("x"),p_asset:ids.a,p_expected_version:1,p_changes:{location_note:"hax"},p_reason:"cross tenant"}),"cross-tenant update","am_denied");
 const list=ok(await rpc("am_list_assets_v1",T.sup,{p_business:101,p_filters:{search:"HTTP oven"},p_limit:10,p_offset:0}),"supervisor list");assert.equal(list.total,1);
 const v=ok(await rpc("am_get_asset_v1",T.bo101,{p_business:101,p_asset:ids.a}),"get").asset.version;
 bad(await rpc("am_update_asset_v1",T.bo101,{p_business:101,p_request:K("st"),p_asset:ids.a,p_expected_version:v+5,p_changes:{location_note:"Bay 9"},p_reason:"stale test"}),"stale version","am_stale_version");
 ok(await rpc("am_update_asset_v1",T.bo101,{p_business:101,p_request:K("up"),p_asset:ids.a,p_expected_version:v,p_changes:{location_note:"Bay 9",custodian_ref:"EMP-7"},p_reason:"assign custody"}),"update");
 // ---- breakdown -> work order lifecycle -> downtime/cost -> reports ----
 const bd=ok(await rpc("am_report_breakdown_v1",T.reporter,{p_business:101,p_request:K("bd"),p_asset:ids.a,p_data:{description:"Motor tripped",priority:"critical"}}),"report breakdown");
 ids.w=bd.id;assert.equal(bd.wo_status,"APPROVED");
 const get=async()=>ok(await rpc("am_get_work_order_v1",T.bo101,{p_business:101,p_wo:ids.w}),"get WO");
 const tr=async(t,a,p,d)=>rpc("am_wo_transition_v1",t,{p_business:101,p_request:K("tr"),p_wo:ids.w,p_expected_version:(await get()).version,p_action:a,p_reason:p||null,p_data:d||null});
 bad(await tr(T.reporter,"start"),"reporter cannot start","am_not_permitted");
 ok(await rpc("am_assign_work_order_v1",T.bo101,{p_business:101,p_request:K("as"),p_wo:ids.w,p_expected_version:(await get()).version,p_assigned_to:A.tech,p_assignee_ref:null,p_team_ref:null,p_reason:"urgent repair"}),"assign");
 ok(await tr(T.tech,"start"),"start");
 const race=await Promise.all([1,2,3,4].map(()=>rpc("am_wo_transition_v1",T.tech,{p_business:101,p_request:K("cm"),p_wo:ids.w,p_expected_version:(1e9),p_action:"complete",p_reason:null,p_data:{cause_code:"AGE"}})));
 for(const r of race)bad(r,"stale parallel complete","am_stale_version");
 ok(await rpc("am_wo_add_labor_v1",T.tech,{p_business:101,p_request:K("lb"),p_wo:ids.w,p_data:{hours:2,rate:25,phase:"actual",worker_ref:"EMP-T1"}}),"labour");
 ok(await rpc("am_wo_add_spares_v1",T.tech,{p_business:101,p_request:K("sp"),p_wo:ids.w,p_data:{description:"Contactor",qty:1,unit_cost:60,item_ref:"CT-1",phase:"actual"}}),"spares");
 ok(await rpc("am_wo_add_attachment_v1",T.tech,{p_business:101,p_request:K("at"),p_wo:ids.w,p_data:{file_name:"p.jpg",mime:"image/jpeg",size_bytes:100,sha256:"c".repeat(64),storage_ref:"synthetic/http/p.jpg"}}),"evidence record");
 ok(await tr(T.tech,"complete",null,{cause_code:"AGE"}),"complete");
 bad(await tr(T.tech,"verify"),"technician cannot verify","am_not_permitted");
 ok(await tr(T.bo101,"verify"),"verify");ok(await tr(T.bo101,"close"),"close");
 const w=await get();assert.equal(w.status,"CLOSED");assert.ok(Number(w.actual_labor_cost)===50&&Number(w.actual_spares_cost)===60,"advisory cost totals "+w.actual_labor_cost+"/"+w.actual_spares_cost);
 assert.equal(ok(await rpc("am_list_downtime_v1",T.bo101,{p_business:101,p_filters:{open:true},p_limit:50,p_offset:0}),"open downtime").total,0);
 const today=new Date().toISOString().slice(0,10),past=new Date(Date.now()-30*864e5).toISOString().slice(0,10);
 ok(await rpc("am_overview_v1",T.bo101,{p_business:101,p_site:null}),"overview");
 const kpi=ok(await rpc("am_kpi_report_v1",T.bo101,{p_business:101,p_from:past,p_to:today,p_site:null}),"kpi");assert.match(JSON.stringify(kpi.cost_rollup),/ADVISORY/);
 ok(await rpc("am_downtime_report_v1",T.auditor,{p_business:101,p_from:past,p_to:today,p_site:null}),"auditor reads downtime report");
 bad(await rpc("am_kpi_report_v1",T.reporter,{p_business:101,p_from:past,p_to:today,p_site:null}),"reporter has no reports","am_not_permitted");
 const csv=ok(await rpc("am_export_csv_v1",T.bo101,{p_business:101,p_request:K("csv"),p_kind:"work_orders",p_params:null}),"csv");assert.match(JSON.stringify(csv),/WO-/);
 assert.equal(ok(await rpc("am_integrity_report_v1",T.bo101,{p_business:101}),"integrity").ok,true);
 bad(await rpc("am_integrity_report_v1",T.sup,{p_business:101}),"supervisor cannot read integrity","am_not_permitted");
 const audit=ok(await rpc("am_audit_log_v1",T.auditor,{p_business:101,p_entity:"asset",p_entity_id:String(ids.a),p_limit:20,p_offset:0}),"audit trail");assert.ok(audit.items.length>=2);
 ok(await rpc("read_asset_maintenance_business_summary_v1",T.bo101,{p_business:101,p_period:null}),"A050 adapter owner");
 bad(await rpc("read_asset_maintenance_business_summary_v1",T.sup,{p_business:101,p_period:null}),"A050 adapter owner-only","am_");
 // ---- policy: only owners write; reads are scoped ----
 bad(await rpc("am_save_policy_v1",T.sup,{p_business:101,p_request:K("pol"),p_expected_rev:0,p_scope_type:"business",p_scope_id:0,p_changes:{"wo.reopen_window_days":10},p_reason:"supervisor try"}),"supervisor cannot change policy","am_");
 ok(await rpc("am_policy_catalog_v1",T.sup,{p_business:101}),"policy catalog readable");
 console.log("A055_REST_E2E_PASS (signed HMAC JWT -> PostgREST; synthetic disposable data only)");
})().catch(e=>{console.error(e);process.exit(1)});
