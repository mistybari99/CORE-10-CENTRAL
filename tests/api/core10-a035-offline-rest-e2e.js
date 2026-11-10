"use strict";
// Synthetic JWTs signed and verified by disposable PostgREST, not Supabase Auth.
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("Missing disposable JWT secret");
const root=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const ids={owner:"11111111-1111-4111-8111-111111111111",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777"};
function jwt(sub,claims={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({typ:"JWT",alg:"HS256"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({sub,role:"authenticated",aud:"authenticated",
  iat:now,exp:now+300,...claims})).toString("base64url");
 const message=h+"."+p;
 return message+"."+crypto.createHmac("sha256",secret).update(message).digest("base64url");
}
const t=Object.fromEntries(Object.entries(ids).map(([k,u])=>[k,jwt(u)]));
async function req(path,token,method="GET",body){
 const r=await fetch(root+path,{method,headers:{"content-type":"application/json",
  ...(token?{authorization:"Bearer "+token}:{})},
  body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
 return{status:r.status,data};
}
function ok(r,label){assert.equal(r.status,200,label+" "+JSON.stringify(r));console.log("PASS "+label);return r.data}
function deny(r,label,err){
 if(err){assert.equal(r.status,400,label+" "+JSON.stringify(r));assert.equal(r.data?.message,err)}
 else assert.ok([401,403,404].includes(r.status),label+" allowed: "+JSON.stringify(r));
 console.log("DENIED "+label);
}
const replay=(body,token)=>req("/rpc/replay_offline_stock_v1",token,"POST",body);
(async()=>{
 let reports=ok(await req("/offline_stock_inbox_v1?select=location_id,applied,conflicts",t.owner),
 "Owner sees offline exception inbox");
 assert.equal(reports.length,1);
 assert.equal(Number(reports[0].applied),3);
 assert.equal(Number(reports[0].conflicts),2);
 const silent=ok(await req("/offline_stock_receipts_v1?select=id",t.staff),"Revoked staff sees no offline records");
 assert.equal(silent.length,0);
 deny(await replay({p_location:5001,p_item:8001,p_delta:1,p_expected_version:4,p_request:"revoked-http"},t.staff),
  "Revoked staff cannot replay","offline_stock_not_authorized");
 deny(await replay({p_location:5001,p_item:8001,p_delta:1,p_expected_version:4,p_request:"investor-http"},t.investor),
  "Investor cannot replay stock","offline_stock_not_authorized");
 deny(await replay({p_location:5001,p_item:8001,p_delta:1,p_expected_version:4,p_request:"cross-tenant-http"},t.customer),
  "Independent customer tenant denied","offline_stock_not_authorized");
 const input={p_location:5001,p_item:8001,p_delta:3,p_expected_version:4,p_request:"offline-http-concurrent"};
 const results=await Promise.all(Array.from({length:12},()=>replay(input,t.owner)));
 const receipt=Number(ok(results[0],"One accepted signed HTTP offline replay"));
 assert.ok(Number.isSafeInteger(receipt)&&receipt>0);
 for(const r of results)assert.equal(Number(ok(r,"Parallel signed replay idempotency")),receipt);
 const detail=ok(await req("/offline_stock_receipts_v1?id=eq."+receipt+
 "&select=status,balance_after,observed_ledger_version,stock_movement_id",t.owner),
 "Read server-issued offline receipt");
 assert.equal(detail.length,1);
 assert.equal(detail[0].status,"applied");
 assert.equal(Number(detail[0].balance_after),10);
 assert.equal(Number(detail[0].observed_ledger_version),4);
 const snapshot=ok(await req("/offline_stock_snapshot_v1?location_id=eq.5001&select=on_hand,ledger_version",t.owner),
 "Read server scoped balance/version after twelve concurrent requests");
 assert.equal(snapshot.length,1);
 assert.equal(Number(snapshot[0].on_hand),10);
 assert.equal(Number(snapshot[0].ledger_version),5);
 const stale=Number(ok(await replay({...input,p_delta:-3,p_expected_version:4,p_request:"offline-http-stale"},t.owner),
 "Concurrent human backlog rejected as stale"));
 const conflict=ok(await req("/offline_stock_receipts_v1?id=eq."+stale+
 "&select=status,conflict_reason,balance_before,balance_after",t.owner),
 "Conflict receipt stored and quarantined");
 assert.equal(conflict[0].status,"conflict");
 assert.equal(conflict[0].conflict_reason,"stale_ledger_version");
 assert.equal(conflict[0].balance_before,conflict[0].balance_after);
 deny(await replay({...input,p_delta:4},t.owner),"Same replay key mutated","offline_replay_payload_conflict");
 deny(await replay(input,t.manager),"Different manager cannot claim owner receipt","offline_replay_payload_conflict");
 const foreign=Number(ok(await replay({p_location:6001,p_item:9001,p_delta:4,
  p_expected_version:0,p_request:"offline-http-customer"},t.customer),"Customer writes own tenant only"));
 assert.ok(foreign>0);
 const owner=ok(await req("/offline_stock_receipts_v1?select=id&business_id=eq.201",t.owner),
 "Portfolio owner cannot view customer receipts");
 assert.equal(owner.length,0);
 deny(await req("/offline_stock_receipts_v1",t.owner,"POST",{
  tenant_id:1,business_id:101,site_id:1001,location_id:5001,item_id:8001,
  request_key:"direct",actor_uid:ids.owner,submitted_delta:9,
  expected_ledger_version:5,observed_ledger_version:5,
  balance_before:10,balance_after:19,status:"applied"}),"Direct receipt forgery denied");
 deny(await req("/offline_stock_snapshot_v1",null),"Anonymous cannot view stock snapshots");
 deny(await replay(input,jwt(ids.investor,{app_metadata:{role:"tenant_owner",tenant_id:1}})),
  "JWT role metadata cannot turn investor into stock poster","offline_stock_not_authorized");
 console.log("SUCCESS: 12 JWT HTTP concurrent replays exactly once; stale conflict quarantined; revoked user, spoofed owner, cross tenant and direct INSERT all denied.");
})().catch(e=>{console.error(e);process.exitCode=1});
