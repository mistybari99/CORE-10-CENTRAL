"use strict";
// C10-A035: signed synthetic JWT HTTP test. Offline data is DRAFT ONLY.
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("Missing disposable JWT secret");
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const ids={owner:"11111111-1111-4111-8111-111111111111",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777"};
function token(subject,claims={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({typ:"JWT",alg:"HS256"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({sub:subject,role:"authenticated",aud:"authenticated",
  iat:now,exp:now+300,...claims})).toString("base64url");
 const part=h+"."+p;
 return part+"."+crypto.createHmac("sha256",secret).update(part).digest("base64url");
}
const jwt=Object.fromEntries(Object.entries(ids).map(([k,u])=>[k,token(u)]));
async function http(path,t,method="GET",body){
 const r=await fetch(base+path,{method,headers:{"content-type":"application/json",
   ...(t?{authorization:"Bearer "+t}:{})},
   body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
 return{status:r.status,data};
}
function ok(r,label){
 assert.equal(r.status,200,label+" "+JSON.stringify(r));
 console.log("PASS "+label);return r.data;
}
function blocked(r,label,why){
 if(why){assert.equal(r.status,400,label+" "+JSON.stringify(r));assert.equal(r.data?.message,why)}
 else assert.ok([401,403,404].includes(r.status),label+" unexpectedly allowed "+JSON.stringify(r));
 console.log("PASS DENIED "+label);
}
const propose=(body,who)=>http("/rpc/replay_offline_stock_v1",who,"POST",body);
(async()=>{
 const report=ok(await http("/offline_stock_inbox_v1?select=location_id,staged,conflicts,owner_reviewed",jwt.owner),
  "Owner-only offline draft inbox");
 assert.equal(report.length,1);
 assert.equal(Number(report[0].staged),2);
 assert.equal(Number(report[0].conflicts),2);
 assert.equal(Number(report[0].owner_reviewed),1);
 const revoked=ok(await http("/offline_stock_receipts_v1?select=id",jwt.staff),
  "Revoked device user sees no old proposals");
 assert.equal(revoked.length,0);
 const attempt={p_location:5001,p_item:8001,p_delta:3,
  p_expected_version:1,p_request:"http-staged-concurrent"};
 blocked(await propose(attempt,jwt.staff),"revoked staff proposal","offline_stock_not_authorized");
 blocked(await propose(attempt,jwt.investor),"investor proposal","offline_stock_not_authorized");
 blocked(await propose(attempt,jwt.customer),"different tenant proposal","offline_stock_not_authorized");
 const replies=await Promise.all(Array.from({length:12},()=>propose(attempt,jwt.owner)));
 const receiptId=Number(ok(replies[0],"create one online DRAFT from 12 signed HTTP requests"));
 assert.ok(Number.isSafeInteger(receiptId)&&receiptId>0);
 for(const p of replies)assert.equal(Number(ok(p,"idempotent concurrent DRAFT submission")),receiptId);
 const detail=ok(await http("/offline_stock_receipts_v1?id=eq."+receiptId+
   "&select=status,balance_before,balance_after,observed_ledger_version,review_status",jwt.owner),
  "Server draft receipt no inventory posting");
 assert.equal(detail.length,1);
 assert.equal(detail[0].status,"staged");
 assert.equal(detail[0].review_status,"pending");
 assert.equal(Number(detail[0].balance_before),20);
 assert.equal(Number(detail[0].balance_after),20);
 assert.equal(Number(detail[0].observed_ledger_version),1);
 let snapshot=ok(await http("/offline_stock_snapshot_v1?location_id=eq.5001&select=on_hand,ledger_version",jwt.owner),
  "Physical inventory unchanged after 12 draft-only submits");
 assert.equal(Number(snapshot[0].on_hand),20);
 assert.equal(Number(snapshot[0].ledger_version),1);
 const stale=Number(ok(await propose({...attempt,p_delta:-3,p_expected_version:0,
  p_request:"http-stale"},jwt.owner),"Stale device proposal quarantined"));
 const conflict=ok(await http("/offline_stock_receipts_v1?id=eq."+stale+
  "&select=status,conflict_reason,balance_before,balance_after",jwt.owner),
  "Conflict audit is immutable and does not post stock");
 assert.equal(conflict[0].status,"conflict");
 assert.equal(conflict[0].conflict_reason,"stale_ledger_version");
 assert.equal(conflict[0].balance_before,conflict[0].balance_after);
 blocked(await propose({...attempt,p_delta:4},jwt.owner),
  "changed idempotency key payload","offline_replay_payload_conflict");
 blocked(await propose(attempt,jwt.manager),
  "manager cannot claim owner draft receipt","offline_replay_payload_conflict");
 blocked(await http("/rpc/review_offline_stock_draft_v1",jwt.manager,"POST",
  {p_receipt:receiptId,p_decision:"review"}),
  "manager cannot owner-review draft","offline_review_not_authorized");
 assert.equal(ok(await http("/rpc/review_offline_stock_draft_v1",jwt.owner,"POST",
  {p_receipt:receiptId,p_decision:"review"}),"owner signs draft-only review"),"reviewed");
 blocked(await http("/rpc/review_offline_stock_draft_v1",jwt.owner,"POST",
  {p_receipt:stale,p_decision:"review"}),
  "conflict cannot be owner-reviewed as valid","conflicted_offline_draft_cannot_be_approved");
 snapshot=ok(await http("/offline_stock_snapshot_v1?location_id=eq.5001&select=on_hand,ledger_version",jwt.owner),
  "Review is not stock posting");
 assert.equal(Number(snapshot[0].on_hand),20);
 assert.equal(Number(snapshot[0].ledger_version),1);
 const independent=Number(ok(await propose({p_location:6001,p_item:9001,
  p_delta:4,p_expected_version:0,p_request:"customer-draft"},jwt.customer),
  "Independent customer tenant stages own stock draft"));
 assert.ok(independent>0);
 const unseen=ok(await http("/offline_stock_receipts_v1?business_id=eq.201&select=id",jwt.owner),
  "Owner portfolio cannot see customer proposal");
 assert.equal(unseen.length,0);
 blocked(await http("/offline_stock_receipts_v1",jwt.owner,"POST",{
  tenant_id:1,business_id:101,site_id:1001,location_id:5001,item_id:8001,
  request_key:"forged",actor_uid:ids.owner,submitted_delta:9,
  expected_ledger_version:1,observed_ledger_version:1,
  balance_before:20,balance_after:20,status:"staged"}),
  "Client forbidden direct receipt insert");
 blocked(await http("/offline_stock_snapshot_v1",null),
  "Anonymous cannot see server stock snapshot");
 blocked(await propose(attempt,token(ids.investor,{app_metadata:{role:"tenant_owner"}})),
  "JWT role spoofing cannot create stock proposal","offline_stock_not_authorized");
 console.log("SUCCESS: offline DRAFT only, 12 concurrent signed HTTP submits one proposal, no stock changes, conflicted snapshots quarantined, owner reviewed not posted, cross tenant and forged identities denied.");
})().catch(e=>{console.error(e);process.exitCode=1});
