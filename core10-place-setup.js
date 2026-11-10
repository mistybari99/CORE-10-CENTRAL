/* CORE 10 CENTRAL · C10-A011 owner business-location creation.
 * Reuse existing server-authorized business_place_create135 RPC. No direct table writes.
 * The form creates an ERP Location (not a future c10_operating_sites record).
 * Draft integration: real signed-in tests and review required before release.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root&&root.document)api.install(root);
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
 "use strict";
 var TYPES={showroom:1,factory:1,godown:1};
 var state={busy:false,key:null,signature:null,formSerial:0};
 function string(v){return String(v==null?"":v).trim()}
 function number(v){var n=Number(v);return Number.isSafeInteger(n)&&n>0?n:null}
 function escape(v){return string(v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]})}
 function tr(w,bn,en){var B=w.BOS;return B&&B.L&&B.lab?B.lab(B.L(bn,en)):bn}
 function context(w){
  var A=w.BOS_APP,B=w.BOS;
  if(!A||!A.S||!A.S.ctx||!A.S.ctx.is_owner||!B||!B.biz||!w.location||!w.document)return null;
  if(w.document.body&&w.document.body.dataset.core10Owner==="1")return null;
  var url;try{url=new URL(w.location.href)}catch(_){return null}
  if(["islamia","business"].indexOf(url.searchParams.get("workspace"))===-1)return null;
  var id=number(url.searchParams.get("biz"));
  if(!id||number(B.biz.cur&&B.biz.cur())!==id)return null;
  var list=B.biz.list&&B.biz.list();
  if(!Array.isArray(list))return null;
  var business=list.find(function(x){return number(x&&x.id)===id&&x.kind==="business"&&x.status!=="inactive"});
  if(!business)return null;
  var profile=A.S.ctx.profile||{},identity=string(profile.id||A.S.ctx.user_id||"");
  if(!identity)return null;
  return{business_id:id,identity:identity,business:business};
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
  if(/unverified_replay/i.test(m))return"Request already processed. Check Locations before creating or retrying; the server did not confirm the replay details.";
  if(/not allowed|permission denied|unauthorized/i.test(m))return"Permission denied. Verify the signed-in Owner account.";
  if(/code_in_use|duplicate key/i.test(m))return"Site code already exists. Choose another code.";
  if(/bad_code|name_required|too_long/i.test(m))return"Invalid site details. Check the names and code.";
  if(/business_inactive|unknown_business|bad_branch/i.test(m))return"Business is unavailable or its scope could not be verified.";
  return"Site was not confirmed. Check your connection and retry with the same details.";
 }
 function typeOption(w,value,bn,en,detailBn,detailEn,icon,checked){
  return '<label class="c10-site-type"><input type="radio" name="c10_place_kind" value="'+value+'"'+(checked?' checked':'')+'>'+
   '<span class="c10-site-type-inner"><span class="c10-site-type-icon" aria-hidden="true">'+icon+'</span>'+
   '<span><strong>'+escape(tr(w,bn,en))+'</strong><small>'+escape(tr(w,detailBn,detailEn))+'</small></span></span></label>';
 }
 function html(w,ctx){
  var b=ctx.business,name=string(b.name_bn||b.name_en||b.code),t=function(bn,en){return escape(tr(w,bn,en))};
  return '<div class="c10-site-panel">'+
   '<header class="c10-site-head"><span class="c10-site-kicker">CORE 10 · '+t("নতুন লোকেশন","NEW LOCATION")+'</span>'+
   '<h2 id="c10-site-title">'+t("শোরুম, কারখানা বা গোডাউন যোগ করুন","Add a business location")+'</h2>'+
   '<p>'+t("যেকোনো জায়গা থেকে সেটআপ করুন। নির্দিষ্ট GPS লোকেশনে যাওয়ার প্রয়োজন নেই।","Set up from anywhere. No GPS or on-site check-in required.")+'</p></header>'+
   '<section class="c10-site-context" aria-label="'+t("নির্বাচিত ব্যবসা","Selected business")+'">'+
   '<div><small>'+t("এই ব্যবসার অধীনে তৈরি হবে","CREATING UNDER THIS BUSINESS")+'</small><strong>'+escape(name)+'</strong></div>'+
   '<span class="c10-site-context-id">ID '+ctx.business_id+'</span></section>'+
   '<div class="c10-site-form" id="c10_place_form" data-c10-form="'+state.formSerial+'">'+
   '<fieldset class="c10-site-fieldset"><legend><span class="c10-site-step">01</span>'+t("লোকেশনের ধরন","Location type")+'</legend>'+
   '<div class="c10-site-types">'+
   typeOption(w,"showroom","শোরুম / ব্রাঞ্চ","Showroom / Branch","বিক্রয় ও কাস্টমার সার্ভিস","Sales and customers","▣",true)+
   typeOption(w,"factory","কারখানা","Factory","উৎপাদন ও প্রসেসিং","Production and processing","⚙",false)+
   typeOption(w,"godown","গোডাউন / ওয়্যারহাউস","Godown / Warehouse","স্টোরেজ ও স্টক","Storage and stock","▤",false)+
   '</div></fieldset>'+
   '<div class="c10-site-divider"></div>'+
   '<div class="c10-site-fieldset"><h3><span class="c10-site-step">02</span>'+t("নাম ও পরিচিতি","Name and identity")+'</h3>'+
   '<div class="c10-site-fields"><div class="c10-site-field"><label for="c10_place_bn">'+t("বাংলা নাম","Bengali name")+'</label>'+
   '<input id="c10_place_bn" maxlength="120" autocomplete="off" placeholder="'+t("যেমন: ইসলামিয়া — নতুন বাজার","e.g. Main Market Showroom")+'"></div>'+
   '<div class="c10-site-field"><label for="c10_place_en">'+t("ইংরেজি নাম (ঐচ্ছিক)","English name (optional)")+'</label>'+
   '<input id="c10_place_en" maxlength="120" autocomplete="off" placeholder="Main Market"></div></div>'+
   '<p class="c10-site-hint">'+t("কমপক্ষে একটি ভাষায় নাম দিন। পরে Locations থেকে নাম ও অন্যান্য সেটিংস পরিবর্তন করা যাবে।","Provide a name in at least one language. Edit the name and settings later in Locations.")+'</p>'+
   '<div class="c10-site-code-row"><div class="c10-site-field"><label for="c10_place_code">'+t("লোকেশন কোড (ঐচ্ছিক)","Location code (optional)")+'</label>'+
   '<input id="c10_place_code" maxlength="30" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="main_showroom" inputmode="text">'+
   '<p class="c10-site-hint">'+t("ফাঁকা রাখলে স্বয়ংক্রিয় কোড তৈরি হবে। নিজে দিলে a–z, 0–9 ও _ ব্যবহার করুন।","Leave blank for automatic code. Manual codes use a–z, 0–9 and _.")+'</p></div>'+
   '<span class="c10-site-code-tag">'+t("ইউনিক কোড","UNIQUE CODE")+'</span></div></div>'+
   '<section class="c10-site-preview" aria-label="'+t("তৈরির আগে সারাংশ","Creation preview")+'" aria-live="polite">'+
   '<span class="c10-site-preview-kicker">'+t("তৈরির আগে দেখুন","BEFORE YOU CREATE")+'</span>'+
   '<div class="c10-site-preview-content"><span class="c10-site-preview-icon" aria-hidden="true">▣</span><div>'+
   '<strong id="c10_place_preview_name">'+t("নতুন শোরুম","New showroom")+'</strong>'+
   '<small id="c10_place_preview_detail">'+t("শোরুম · স্বয়ংক্রিয় কোড","Showroom · Auto code")+'</small></div>'+
   '<span class="c10-site-preview-status">'+t("সেটআপ বাকি","SETUP PENDING")+'</span></div></section>'+
   '<p class="c10-site-note">'+t("তৈরি করার পর লোকেশনটি প্রথমে Setup অবস্থায় থাকবে—সঙ্গে সঙ্গে Active হবে না। পরে স্টাফ, স্টক ও অন্যান্য কনফিগারেশন করবেন।","The new location starts in Setup status, not Active. Configure staff, stock and other settings afterward.")+'</p>'+
   '<p id="c10_place_error" class="c10-site-error" role="alert" hidden></p>'+
   '<div class="c10-site-actions"><button type="button" class="c10-site-cancel" data-act="closesheet">'+t("বাতিল","Cancel")+'</button>'+
   '<button type="button" class="c10-site-submit primary" id="c10_place_submit" data-act="c10_place_create">'+t("লোকেশন তৈরি করুন","Create location")+'</button></div></div></div>';
 }
 function collect(w){
  var d=w.document;
  if(!d.getElementById("c10_place_form"))return null;
  var radio=typeof d.querySelector==="function"?d.querySelector('input[name="c10_place_kind"]:checked'):null;
  var f=function(id){var el=d.getElementById(id);return el?el.value:null};
  return{kind:radio?radio.value:null,name_bn:f("c10_place_bn"),name_en:f("c10_place_en"),code:f("c10_place_code")};
 }
 function updatePreview(w){
  var fields=collect(w);if(!fields)return;
  var d=w.document,n=d.getElementById("c10_place_preview_name"),meta=d.getElementById("c10_place_preview_detail");
  var icon=d.querySelector&&d.querySelector(".c10-site-preview-icon");
  var kinds={showroom:["শোরুম","Showroom","▣"],factory:["কারখানা","Factory","⚙"],godown:["গোডাউন","Warehouse","▤"]};
  var row=kinds[fields.kind]||kinds.showroom;
  if(n)n.textContent=string(fields.name_bn)||string(fields.name_en)||tr(w,"নতুন "+row[0],"New "+row[1]);
  if(meta)meta.textContent=tr(w,row[0],row[1])+" · "+(string(fields.code)?string(fields.code).toLowerCase():tr(w,"স্বয়ংক্রিয় কোড","Auto code"));
  if(icon)icon.textContent=row[2];
 }
 function notify(w,message){
  var el=w.document.getElementById("c10_place_error");
  if(el){el.hidden=false;el.textContent=message;return}
  if(w.BOS_APP&&w.BOS_APP.toast)w.BOS_APP.toast(message);
 }
 function clearError(w){var el=w.document.getElementById("c10_place_error");if(el){el.hidden=true;el.textContent=""}}
 function install(w){
  var A=w.BOS_APP;
  if(!A||!A.H||!A.sb||!w.BOS||!w.BOS.biz)return false;
  A.H.c10_place_open=function(){
   if(state.busy)return;
   var ctx=context(w);
   if(!ctx||typeof A.openSheet!=="function")return;
   state.key=null;state.signature=null;state.formSerial++;
   A.openSheet(html(w,ctx));
   var form=w.document.getElementById("c10_place_form");
   if(form&&typeof form.addEventListener==="function"){
    form.addEventListener("input",function(){updatePreview(w);clearError(w)});
    form.addEventListener("change",function(){updatePreview(w);clearError(w)});
   }
  };
  A.H.c10_place_create=async function(){
   if(state.busy)return;
   var ctx=context(w),fields=collect(w),check=validate(fields);
   if(!ctx){notify(w,"Owner/business identity could not be verified.");return}
   if(!fields){notify(w,"Location form is no longer open.");return}
   if(!check.ok){notify(w,check.error);return}
   if(!w.crypto||typeof w.crypto.randomUUID!=="function"){notify(w,"Secure request ID unavailable.");return}
   var signature=requestSignature(ctx,check.fields);
   if(state.signature!==signature){state.signature=signature;state.key=w.crypto.randomUUID()}
   var form=w.document.getElementById("c10_place_form"),button=w.document.getElementById("c10_place_submit"),serial=state.formSerial,session=ctx.identity,route=string(w.location.hash);
   state.busy=true;if(button){button.disabled=true;button.setAttribute&&button.setAttribute("aria-busy","true");button.textContent=tr(w,"তৈরি হচ্ছে…","Creating…")}
   clearError(w);
   try{
    var p=check.fields,response=await A.sb.rpc("business_place_create135",{
      p_business:ctx.business_id,p_kind:p.kind,p_code:p.code||null,
      p_name_bn:p.name_bn||null,p_name_en:p.name_en||null,
      p_org_branch:null,p_client:state.key
    });
    if(response.error)throw response.error;
    var created=response.data;
    // The old production RPC returns an unsigned duplicate. Reject it.
    // The reviewed A011 backend upgrade can certify a replay only with
    // request_matched=true, original kind and the current location status.
    var verifiedReplay=!!(created&&created.dup===true&&created.request_matched===true);
    if(created&&created.dup===true&&!verifiedReplay)throw Error("unverified_replay");
    if(!created||number(created.id)===null||number(created.business_id)!==ctx.business_id||
       (created.kind!=null&&string(created.kind)!==p.kind)||
       (!verifiedReplay&&created.status!=null&&string(created.status)!=="setting_up")||
       (verifiedReplay&&(!created.kind||!created.status||
         ["planned","setting_up","live","paused","closed"].indexOf(string(created.status))===-1))
      )throw Error("response_scope_unverified");
    var latest=context(w);
    if(!latest||latest.business_id!==ctx.business_id||latest.identity!==session)return;
    state.key=null;state.signature=null;
    // Do not display a success message from an old/closed form or changed route.
    var liveForm=w.document.getElementById("c10_place_form");
    if(!liveForm||liveForm!==form||state.formSerial!==serial||string(w.location.hash)!==route)return;
    if(typeof A.toast==="function")A.toast(verifiedReplay?
     tr(w,"লোকেশনটি আগেই তৈরি হয়েছে। Locations থেকে দেখুন।","Location was already created. Open it in Locations."):
     tr(w,"লোকেশন তৈরি হয়েছে; এখন সেটআপ সম্পূর্ণ করুন।","Location created; finish setup next."));
    if(typeof A.closeSheet==="function")A.closeSheet();
    w.location.hash="#/locations";
   }catch(e){
    var current=context(w);
    if(current&&current.identity===session&&current.business_id===ctx.business_id&&state.formSerial===serial&&string(w.location.hash)===route&&w.document.getElementById("c10_place_form")===form)notify(w,errorMessage(e));
   }
   finally{
    state.busy=false;
    // Reset the original button even when closeSheet has removed it from the DOM.
    // Never touch a replacement sheet's submit control.
    var live=w.document.getElementById("c10_place_submit");
    if(button&&state.formSerial===serial&&(!w.document.getElementById("c10_place_form")||w.document.getElementById("c10_place_form")===form)&&(!live||live===button)){
     button.disabled=false;
     button.removeAttribute&&button.removeAttribute("aria-busy");
     button.textContent=tr(w,"লোকেশন তৈরি করুন","Create location");
    }
   }
  };
  return true;
 }
 return{context:context,validate:validate,requestSignature:requestSignature,errorMessage:errorMessage,updatePreview:updatePreview,install:install,html:html};
});
