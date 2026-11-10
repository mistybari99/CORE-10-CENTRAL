/* CORE 10 | Scoped owner inbox (read-only until database contract certified).
 * Only calls the single server-authenticated business-scoped RPC.
 * No client filtering of legacy approvals, no cross-business counts and no
 * approve/reject endpoint exposed in this compatibility phase.
 */
(function(){
"use strict";
var A=window.BOS_APP,B=window.BOS;
if(!A||!A.S||!A.H||!A.sb||!B||!B.biz)return;
var requestSeq=0,currentNode=null,currentKey="";
function esc(x){return String(x==null?"":x).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]})}
function tr(b,e){return A.S.lang==="en"?e:b}
function scope(){
 var ctx=A.S.ctx;if(!ctx||ctx.is_owner!==true||!document.body||!ctx.profile||ctx.profile.id==null)return null;
 var principal=String(ctx.profile.id);if(!principal||principal==="undefined"||principal==="null")return null;
 if(document.body.dataset.core10Owner==="1"){
  if(String(location.hash||"")!=="#/organization")return null;
  return {kind:"master",id:null,key:"master:"+principal}
 }
 var search=window.location.search||"";
 if(!/(?:^|[?&])workspace=(?:islamia|business)(?:&|$)/.test(search))return null;
 if(!/^#\/?(?:home|owner-inbox)$/.test(location.hash||""))return null;
 var raw=(search.match(/(?:^|[?&])biz=([1-9][0-9]*)(?:&|$)/)||[])[1];
 var id=raw?Number(raw):null;
 if(!Number.isSafeInteger(id))return null;
 if(String(B.biz.cur())!==String(id))return null;
 if(!(B.biz.list()||[]).some(function(x){return Number(x.id)===id}))return null;
 return {kind:"business",id:id,key:"business:"+id+":"+principal}
}
function nodeFor(s){
 if(s.kind==="master"){
  var host=document.querySelector("#ph_overview");if(!host)return null;
  var existing=host.querySelector(".c10-inbox");
  if(existing)return existing;
  var el=document.createElement("section");el.className="c10-inbox";
  var actions=host.querySelector(".ph-master-actions");
  if(actions)host.insertBefore(el,actions);else host.appendChild(el);
  return el
 }
 var wrap=document.querySelector(".bo-attention");if(!wrap)return null;
 var existing=wrap.querySelector(".c10-inbox");if(existing)return existing;
 var el=document.createElement("section");el.className="c10-inbox";
 var head=wrap.querySelector(".bo-attention-head");
 if(head)head.insertAdjacentElement("afterend",el);else wrap.appendChild(el);
 return el
}
function header(s){return '<div class="c10-inbox-bar"><b>'+esc(s.kind==="master"?tr("সব ব্যবসার অপেক্ষমাণ সিদ্ধান্ত","Decisions across businesses"):tr("এই ব্যবসার অপেক্ষমাণ সিদ্ধান্ত","This business decisions"))+'</b>'+
 '<button type="button" class="c10-inbox-reload" data-act="c10in_refresh">'+esc(tr("রিফ্রেশ","Refresh"))+'</button></div>'}
function message(s,info,tone){
 return header(s)+'<p class="c10-inbox-note c10-inbox-'+esc(tone||"info")+'">'+esc(info)+'</p>'
}
function safeRows(data,s){
 if(!data||data.certified!==true||data.scope!=="owner"||!Array.isArray(data.items)||data.items.length>40)return null;
 if(s.kind==="business"&&(typeof data.business_id!=="number"||!Number.isSafeInteger(data.business_id)||data.business_id!==s.id))return null;
 if(s.kind==="master"&&data.business_id!==null)return null;
 var allowed=new Set((B.biz.list()||[]).map(function(x){return Number(x.id)})),seen=new Set;
 var list=[];
 for(var i=0;i<data.items.length;i++){
  var row=data.items[i],id=row&&row.id;
  // The server must return canonical stable IDs and numeric positive business IDs.
  var biz=row&&row.business_id;
  if(typeof id!=="string"||!/^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$/.test(id)||
     seen.has(id)||typeof biz!=="number"||!Number.isSafeInteger(biz)||biz<=0||
     !allowed.has(biz)||(s.kind==="business"&&biz!==s.id))return null;
  if(row.status!=="pending")return null;
  if(typeof row.title!=="string"||row.title.length===0||row.title.length>300)return null;
  if(typeof row.request_type!=="string"||row.request_type.length===0||row.request_type.length>100)return null;
  if(row.created_at!=null&&(typeof row.created_at!=="string"||!/^\d{4}-\d\d-\d\dT/.test(row.created_at)))return null;
  seen.add(String(id));list.push(row);
 }
 return list
}
function displayRows(rows,s){
 var businessNames=new Map((B.biz.list()||[]).map(function(x){return [Number(x.id),x.name_bn||x.name_en||x.code||"Business"]}));
 if(!rows.length)return message(s,tr("এই মুহূর্তে Server-Verified Pending Request নেই।","No server-verified pending requests at the moment."),"ok");
 return header(s)+'<div class="c10-inbox-caption">'+esc(tr("নিরাপদ API থেকে পাওয়া সর্বোচ্চ ৪০টি অপেক্ষমাণ অনুরোধ (শুধু দেখার জন্য)।","Up to 40 pending requests returned by the secured API (read-only)."))+'</div>'+
 '<div class="c10-inbox-rows">'+rows.map(function(r){
  var date=typeof r.created_at==="string"?r.created_at.slice(0,10):"";
  return '<div class="c10-inbox-row"><div class="c10-inbox-title">'+esc(r.title)+'</div>'+
   '<div class="c10-inbox-meta">'+esc(s.kind==="master"?(businessNames.get(Number(r.business_id))||"")+ " · ":"")+
    esc(r.request_type)+(date?' · '+esc(date):"")+'</div></div>'
 }).join("")+'</div>'+
 '<p class="c10-inbox-foot">'+esc(tr("Approve / Reject চালু হবে সংশ্লিষ্ট ব্যবসার অনুমতি ও ডেটাবেস অডিট পাস করার পরে।","Approve / Reject actions require verified business permissions and database audit."))+'</p>'
}
async function refresh(){
 var s=scope();if(!s)return;
 var node=nodeFor(s);if(!node)return;
 var id=++requestSeq;currentNode=node;currentKey=s.key;
 node.innerHTML=message(s,tr("নিরাপদ Approval API যাচাই হচ্ছে…","Checking secured approval API…"));
 try{
  var result=await A.sb.rpc("core10_owner_inbox_v1",{p_business_id:s.id,p_limit:40});
  if(id!==requestSeq||currentNode!==node||currentKey!==s.key||!node.isConnected)return;
  if(!scope()||scope().key!==s.key)return;
  if(!result||result.error){
   node.innerHTML=message(s,tr("এই ব্যবসার নিরাপদ Approval API এখনো প্রস্তুত নয়। পুরোনো Approval ডেটা মিশিয়ে দেখানো হচ্ছে না।","The secured approval API is not ready. Legacy requests are deliberately not mixed into this view."),"warn");
   return
  }
  var rows=safeRows(result.data,s);
  node.innerHTML=rows===null?message(s,tr("Approval API-এর Scope যাচাই ব্যর্থ। অন্য ব্যবসার তথ্য দেখানো হয়নি।","Approval scope validation failed. No other-business data has been shown."),"warn"):displayRows(rows,s)
 }catch(_){
  if(id===requestSeq&&node.isConnected&&currentNode===node&&currentKey===s.key&&scope()&&scope().key===s.key)
   node.innerHTML=message(s,tr("নিরাপদ Approval API পাওয়া যাচ্ছে না।","The secured approval API is unavailable."),"warn")
 }
}
function scan(){
 var s=scope();
 if(!s){if(currentNode&&currentNode.isConnected)currentNode.innerHTML="";currentNode=null;currentKey="";requestSeq++;return}
 var node=nodeFor(s);if(!node)return;
 if(node!==currentNode||s.key!==currentKey)refresh()
}
A.H.c10in_refresh=function(){if(scope())refresh()};
var queued=false;function schedule(){if(queued)return;queued=true;Promise.resolve().then(function(){queued=false;scan()})}
document.addEventListener("DOMContentLoaded",schedule);
window.addEventListener("hashchange",schedule);
window.addEventListener("bos:biz",schedule);
if(document.body&&typeof MutationObserver==="function"){
 var observer=new MutationObserver(schedule);
 observer.observe(document.body,{childList:true,subtree:true})
}
var style=document.createElement("style");style.id="c10-inbox-css";
style.textContent=[
'.c10-inbox{margin:14px 0;padding:14px;border:1px solid var(--line);border-radius:14px;background:var(--card);color:var(--ink)}',
'.c10-inbox-bar{display:flex;align-items:center;justify-content:space-between;gap:10px}',
'.c10-inbox-bar b{font-size:.94rem}',
'.c10-inbox-reload{min-height:36px;border:1px solid var(--line);border-radius:9px;padding:5px 11px;background:var(--s1);color:var(--ruby);font-size:.77rem}',
'.c10-inbox-note{font-size:.82rem;line-height:1.6;color:var(--muted);margin:10px 0 0}',
'.c10-inbox-warn{border-inline-start:3px solid var(--gold);padding:8px 10px;background:var(--s1)}',
'.c10-inbox-ok{color:var(--muted)}',
'.c10-inbox-caption,.c10-inbox-foot{font-size:.76rem;color:var(--muted);line-height:1.5;margin:9px 0}',
'.c10-inbox-rows{display:grid;gap:8px;margin-top:12px}',
'.c10-inbox-row{padding:10px;border:1px solid var(--line);border-radius:9px;background:var(--s1)}',
'.c10-inbox-title{font-size:.86rem;font-weight:750;overflow-wrap:anywhere}',
'.c10-inbox-meta{font-size:.75rem;margin-top:5px;color:var(--muted)}'
].join("");
document.head.appendChild(style);
window.CORE10_OWNER_INBOX={scope:scope,validate:safeRows,scan:scan,refresh:refresh};
schedule();
})();