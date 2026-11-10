"use strict";
// Disposable signed-HS256 JWT/PostgREST proof, NOT actual Supabase Auth users.
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("CI signing secret missing");
const root=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const ids={
 tenantOwner:"11111111-1111-4111-8111-111111111111",
 bizOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777",
 revokedStaff:"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
 newStaff:"ffffffff-ffff-4fff-8fff-ffffffffffff"
};
function jwt(sub,overrides={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({typ:"JWT",alg:"HS256"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({sub,role:"authenticated",aud:"authenticated",iat:now,exp:now+300,...overrides})).toString("base64url");
 const signed=h+"."+p;
 return signed+"."+crypto.createHmac("sha256",secret).update(signed).digest("base64url");
}
const tok=Object.fromEntries(Object.entries(ids).map(([k,u])=>[k,jwt(u)]));
async function req(path,token,method="GET",body){
 const r=await fetch(root+path,{method,headers:{
   "content-type":"application/json",...(token?{authorization:"Bearer "+token}:{})
 },body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let data;
 try{data=JSON.parse(raw)}catch{data=raw}
 return{code:r.status,data};
}
function success(r,label){
 assert.equal(r.code,200,label+" HTTP "+r.code+" "+JSON.stringify(r.data));
 console.log("PASS "+label);return r.data;
}
function refusal(r,label,message){
 if(message){
  assert.equal(r.code,400,label+" HTTP "+r.code+" "+JSON.stringify(r.data));
  assert.equal(r.data?.message,message,label);
 }else assert.ok([401,403,404].includes(r.code),label+" returned "+JSON.stringify(r));
 console.log("PASS DENIED "+label);
}
const change=(p,token)=>req("/rpc/change_access_v1",token,"POST",p);
(async()=>{
 const owner=success(await req("/access_governance_overview_v1?select=business_id,audited_access_changes&order=business_id.asc",tok.tenantOwner),"owner access board");
 assert.deepEqual(owner.map(x=>x.business_id),[101,102]);
 assert.equal(owner[0].audited_access_changes,7);
 success(await req("/access_governance_overview_v1?select=business_id",tok.bizOwner),"business owner scoped board");
 const revoked=success(await req("/stock_locations?select=id",tok.revokedStaff),"previously revoked site staff sees no locations");
 assert.equal(revoked.length,0);
 const manager=success(await req("/access_change_events_v1?select=id",tok.manager),"manager cannot read owner security audit");
 assert.equal(manager.length,0);
 const investor=success(await req("/access_change_events_v1?select=id",tok.investor),"investor cannot read security audit");
 assert.equal(investor.length,0);
 refusal(await change({p_business:101,p_subject:ids.newStaff,
  p_command:"business_member.grant",p_role:"manager",p_site:null,p_actions:null,p_request:"investor-forge"},tok.investor),
 "investor cannot add staff","access_change_not_authorized");
 refusal(await change({p_business:101,p_subject:ids.newStaff,
  p_command:"business_member.grant",p_role:"manager",p_site:null,p_actions:null,p_request:"customer-forge"},tok.customer),
 "other tenant cannot add staff","access_change_not_authorized");
 const q={p_business:101,p_subject:ids.newStaff,p_command:"site_grant.grant",p_role:null,
  p_site:1001,p_actions:["stock.read","stock.post"],p_request:"http-site-grant-concurrent"};
 const answers=await Promise.all(Array.from({length:10},()=>change(q,tok.bizOwner)));
 const eventId=Number(success(answers[0],"signed HTTP grant"));
 assert.ok(Number.isSafeInteger(eventId)&&eventId>0);
 for(const a of answers)assert.equal(Number(success(a,"parallel signed grant idempotency")),eventId);
 let sites=success(await req("/stock_locations?select=id",tok.newStaff),"new staff scope after authenticated grant");
 assert.deepEqual(sites.map(x=>x.id),[5001]);
 let audits=success(await req("/access_change_events_v1?request_key=eq.http-site-grant-concurrent&select=id",tok.tenantOwner),
  "only one audit event from ten concurrent JWT calls");
 assert.equal(audits.length,1);
 refusal(await change({...q,p_actions:["stock.read"]},tok.bizOwner),
 "same idempotency key with changed permission","access_request_idempotency_conflict");
 const revokedId=Number(success(await change({...q,p_command:"site_grant.revoke",p_actions:null,
  p_request:"http-site-grant-revoke"},tok.bizOwner),"signed owner revocation"));
 assert.ok(revokedId>eventId);
 sites=success(await req("/stock_locations?select=id",tok.newStaff),"same JWT after revocation");
 assert.equal(sites.length,0);
 refusal(await req("/stock_movements",tok.newStaff,"POST",{
  tenant_id:1,business_id:101,site_id:1001,location_id:5001,item_id:8001,
  delta:2,request_key:"forged-ledger",created_by:ids.newStaff
 }),"revoked cannot insert stock record directly");
 refusal(await req("/access_change_events_v1",tok.tenantOwner,"DELETE"),
 "audit history is append-only");
 refusal(await req("/access_governance_overview_v1",null),"anonymous security board");
 const forged=jwt(ids.manager,{app_metadata:{role:"tenant_owner",tenant_id:1},
  user_metadata:{role:"owner"}});
 refusal(await change(q,forged),"forged JWT role cannot grant","access_change_not_authorized");
 console.log("PASS: 10 concurrent signed-JWT grants -> 1 audited action; revoked same JWT loses access immediately; forged role/investor/customer/anon denied.");
})().catch(e=>{console.error(e);process.exitCode=1});
