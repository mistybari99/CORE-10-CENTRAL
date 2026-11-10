/* CORE 10 CENTRAL · C10-A011 real business-place creation, using existing place135 RPC.
 * Class M/H integration candidate: no direct table writes, no new server grants.
 * Must not be released until real owner/staff Auth regression and safety review.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root&&root.document)api.install(root);
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
 "use strict";
 var TYPES={showroom:1,factory:1,godown:1};
 var state={busy:false,key:null,signature:null};
 function string(v){return String(v==null?"":v).trim()}
 function number(v){var n=Number(v);return Number.isSafeInteger(n)&&n>0?n:null}
 function escape(v){return string(v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]})}
 function context(w){
  var A=w.BOS_APP,B=w.BOS;
  if(!A||!A.S||!A.S.ctx||!A.S.ctx.is_owner||!B||!B.biz||!w.location||!w.document)return null;
  if(w.document.body&&w.document.body.dataset.core10Owner==="1")return null;
  var url;try{url=new URL(w.location.href)}catch(_){return null}
  if(!["islamia","business"].includes(url.searchParams.get("workspace")))return null;
  var id=number(url.searchParams.get("biz"));
  if(!id||number(B.biz.cur&&B.biz.cur())!==id)return null;
  var list=B.biz.list&&B.biz.list();
  if(!Array.isArray(list))return null;
  var business=list.find(function(x){return number(x&&x.id)===id&&x.status!=="inactive"});
  if(!business)return null;
  var profile=A.S.ctx.profile||{};
  return{business_id:id,identity:string(profile.id||A.S.ctx.user_id||""),business:business};
 }
 function validate(fields){
  if(!fields||!TYPES[fields.kind])return{ok:false,error:"Select showroom, factory or godown."};
  var bn=string(fields.name_bn),en=string(fields.name_en),code=string(fields.code).toLowerCase();
  if(!bn&&!en)return{ok:false,error:"Enter a Bengali or English site name."};
  if(bn.length>120||en.length>120)return{ok:false,error:"Site names must be at most 120 characters."};
  if(code&&!/^[a-z][a-z0-9_]{1,29}$/.test(code))return{ok:false,error:"Code: 2–30 lowercase letters, digits or underscore; start with a letter."};
  return{ok:true,fields:{kind:fields.kind,name_bn:bn,name_en:en,code:code}};
 }
 function requestSignature(ctx,fields){return JSON.stringify([ctx.business_id,ctx.identity,fields.kind,fields.name_bn,fields.name_en,fields.code])}
 function errorMessage(err){
  var m=string(err&&err.message||err);
  if(/not allowed|permission denied|unauthorized/i.test(m))return"Permission denied. Verify the signed-in Owner account.";
  if(/code_in_use|duplicate key/i.test(m))return"Site code already exists. Choose another code.";
  if(/bad_code|name_required|too_long/i.test(m))return"Invalid site details. Check the names and code.";
  if(/business_inactive|unknown_business|bad_branch/i.test(m))return"Business is unavailable or its scope could not be verified.";
  return"Site was not confirmed. Check your connection and retry with the same details.";
 }
 function titleText(w,bn,en){var B=w.BOS;return B&&B.L&&B.lab?B.lab(B.L(bn,en)):bn}
 function html(w,ctx){
  var biz=ctx.business,name=string(biz.name_bn||biz.name_en||biz.code);
  return '<h2>'+escape(titleText(w,"নতুন শোরুম / কারখানা / গোডাউন","Add Showroom / Factory / Godown"))+'</h2>'+
   '<p class="muted">'+escape(titleText(w,"নির্বাচিত ব্যবসা","Selected business"))+': <b>'+escape(name)+'</b> (#'+ctx.business_id+')</p>'+
   '<div class="notice warn">'+escape(titleText(w,"এটি বাস্তব লোকেশন তৈরি করবে। অনুমোদন ছাড়া পরীক্ষামূলক ডাটা তৈরি করবেন না।","This creates a real business location. Do not use for test records without approval."))+'</div>'+
   '<div class="stack" id="c10_place_form">'+
   '<label for="c10_place_kind">Site type</label><select id="c10_place_kind"><option value="showroom">Showroom / Branch</option><option value="factory">Factory</option><option value="godown">Godown / Warehouse</option></select>'+
   '<label for="c10_place_bn">বাংলা নাম</label><input id="c10_place_bn" maxlength="120" autocomplete="off" placeholder="নাম">'+
   '<label for="c10_place_en">English name (optional)</label><input id="c10_place_en" maxlength="120" autocomplete="off" placeholder="Name">'+
   '<label for="c10_place_code">Code (optional)</label><input id="c10_place_code" maxlength="30" autocomplete="off" placeholder="main_showroom">'+
   '<p class="muted">Code omitted → existing ERP service generates a unique code. Created site starts in Setup status.</p>'+
   '<div id="c10_place_error" role="alert" class="notice warn" hidden></div>'+
   '<div class="row"><button type="button" data-act="closesheet">Cancel</button>'+
   '<button type="button" class="primary" id="c10_place_submit" data-act="c10_place_create">Create site</button></div></div>';
 }
 function notify(w,message){
  var element=w.document.getElementById("c10_place_error");
  if(element){element.hidden=false;element.textContent=message}
  else if(w.BOS_APP&&w.BOS_APP.toast)w.BOS_APP.toast(message);
 }
 function collect(w){
  var d=w.document,f=function(id){var el=d.getElementById(id);return el?el.value:null};
  if(!d.getElementById("c10_place_form"))return null;
  return{kind:f("c10_place_kind"),name_bn:f("c10_place_bn"),name_en:f("c10_place_en"),code:f("c10_place_code")};
 }
 function install(w){
  var A=w.BOS_APP;
  if(!A||!A.H||!A.sb||!w.BOS||!w.BOS.biz)return false;
  A.H.c10_place_open=function(){
   if(state.busy)return;
   var ctx=context(w);
   if(!ctx||typeof A.openSheet!=="function")return;
   state.key=null;state.signature=null;
   A.openSheet(html(w,ctx));
  };
  A.H.c10_place_create=async function(){
   if(state.busy)return;
   var ctx=context(w),fields=collect(w),check=validate(fields);
   if(!ctx){notify(w,"Owner/business identity could not be verified.");return}
   if(!check.ok){notify(w,check.error);return}
   if(!w.crypto||typeof w.crypto.randomUUID!=="function"){notify(w,"Secure request ID unavailable.");return}
   var signature=requestSignature(ctx,check.fields);
   if(state.signature!==signature){state.signature=signature;state.key=w.crypto.randomUUID()}
   var button=w.document.getElementById("c10_place_submit"),session=ctx.identity;
   state.busy=true;if(button)button.disabled=true;
   try{
    var p=check.fields,response=await A.sb.rpc("business_place_create135",{
      p_business:ctx.business_id,p_kind:p.kind,p_code:p.code||null,
      p_name_bn:p.name_bn||null,p_name_en:p.name_en||null,
      p_org_branch:null,p_client:state.key
    });
    if(response.error)throw response.error;
    var created=response.data;
    if(!created||number(created.id)===null||number(created.business_id)!==ctx.business_id)throw Error("response_scope_unverified");
    var latest=context(w);
    if(!latest||latest.business_id!==ctx.business_id||latest.identity!==session)return;
    state.key=null;state.signature=null;
    if(typeof A.closeSheet==="function")A.closeSheet();
    if(typeof A.toast==="function")A.toast("Site "+created.code+" (#"+created.id+") created; setup required.");
    // Existing Location screen performs its own fresh database load.
    w.location.hash="#/locations";
   }catch(e){if(context(w))notify(w,errorMessage(e))}
   finally{state.busy=false;if(button)button.disabled=false}
  };
  return true;
 }
 return{context:context,validate:validate,requestSignature:requestSignature,errorMessage:errorMessage,install:install};
});
