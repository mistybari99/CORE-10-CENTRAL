/* PACK-02 S2 — workspace host. Mounted by a signed page (Build01) with its
 * signed rpc and its server context. Chooses which workspaces to OFFER from
 * that context, but every workspace is still decided by pack02_workspace_v1.
 */
(function(root,factory){
 "use strict";
 const api=factory(root);
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_PACK02_APP=api;
})(typeof window!=="undefined"?window:globalThis,function(root){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 const obj=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const DENIED="এই অংশ দেখার অনুমতি নেই অথবা সেশন শেষ হয়েছে। আবার সাইন ইন করুন।";
 // Offer list from Build01 context. An offer is only a menu entry, not authority.
 function offers(context){
  if(!obj(context)||!Array.isArray(context.businesses)||!Array.isArray(context.legal_entities))fail("PACK02_CONTEXT_INVALID");
  const out=[];
  if(context.legal_entities.length)out.push({mode:"universal_owner",business:null,label:"CORE 10 — সব ব্যবসা"});
  for(const b of context.businesses){
   if(!obj(b)||!Number.isSafeInteger(b.id)||b.id<1||typeof b.label!=="string")fail("PACK02_CONTEXT_INVALID");
   out.push(b.can_manage===true?{mode:"business_owner",business:b.id,label:b.label+" — মালিক"}:{mode:"staff",business:b.id,label:b.label});
  }
  return out;
 }
 function el(doc,tag,cls,text){const e=doc.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=String(text);return e;}
 function reportList(doc,box,rows,line){
  box.replaceChildren();
  if(!rows.length){box.append(el(doc,"p","p2-empty","দেখানোর মতো কোনো তথ্য নেই।"));return;}
  const ul=el(doc,"ul","p2-cards");
  for(const r of rows){const li=el(doc,"li","p2-card");const t=line(r);li.append(el(doc,"strong",null,t[0]),el(doc,"span",null,t[1]));ul.append(li);}
  box.append(el(doc,"p","p2-note","শুধু সংখ্যা — মূল্যায়ন (valuation) এখানে নেই।"),ul);
 }
 // Setup readback (A020/D032): persisted sites, locations and integrity checks.
 const CHECKS=Object.freeze({
  legal_entity_same_tenant:"আইনি প্রতিষ্ঠান একই মালিকানার অধীনে",configuration_present:"ব্যবসার নাম ও রং সংরক্ষিত",
  setup_receipt_single:"সেটআপের একটিই রসিদ আছে",has_site:"অন্তত একটি শাখা আছে",every_site_has_main_location:"প্রতিটি শাখায় মূল স্টক লোকেশন আছে",
  no_orphan_locations:"শাখা ছাড়া কোনো লোকেশন নেই",no_duplicate_sites:"একই শাখা দুবার নেই",modules_locked:"মডিউল এখনো চালু করা হয়নি",not_activated:"ব্যবসা এখনো খসড়া অবস্থায়"});
 const KIND=Object.freeze({showroom:"শোরুম",factory:"ফ্যাক্টরি",godown:"গোডাউন",warehouse:"ওয়্যারহাউস",project:"প্রজেক্ট"});
 function readback(doc,box,p,business){
  if(!obj(p)||p.contract!=="C10_PACK02_SETUP_READBACK_V1"||!obj(p.business)||p.business.id!==business||!Array.isArray(p.sites)||!obj(p.checks)||
     typeof p.integrity_ok!=="boolean"||p.production_certified!==false)fail("PACK02_READBACK_INVALID");
  const keys=Object.keys(p.checks);
  if(keys.some(k=>!(k in CHECKS)||typeof p.checks[k]!=="boolean"))fail("PACK02_READBACK_INVALID");
  // The summary must agree with its own checks; never show "ঠিক আছে" over a failed check.
  if(p.integrity_ok!==keys.every(k=>p.checks[k]))fail("PACK02_READBACK_INVALID");
  box.replaceChildren();
  box.append(el(doc,"p",p.integrity_ok?"p2-note":"p2-status",p.integrity_ok?"সেটআপ সম্পূর্ণ ও সঠিকভাবে সংরক্ষিত আছে।":"সেটআপে সমস্যা আছে — নিচের চিহ্নিত বিষয়গুলো দেখুন।"));
  const cl=el(doc,"ul","p2-cards");
  for(const k of keys){const li=el(doc,"li","p2-card");li.dataset.check=k;li.dataset.ok=String(p.checks[k]);
   li.append(el(doc,"strong",null,(p.checks[k]?"✓ ":"✗ ")+CHECKS[k]),el(doc,"span",null,p.checks[k]?"ঠিক আছে":"পর্যালোচনা দরকার"));cl.append(li);}
  const sl=el(doc,"ul","p2-cards");
  for(const s of p.sites){
   if(!obj(s)||typeof s.label!=="string"||!(s.kind in KIND)||!Array.isArray(s.location_codes))fail("PACK02_READBACK_INVALID");
   const li=el(doc,"li","p2-card");li.dataset.site=String(s.id);
   li.append(el(doc,"strong",null,s.label),el(doc,"span",null,`${KIND[s.kind]} · লোকেশন: ${s.location_codes.join(", ")||"নেই"}`));sl.append(li);}
  box.append(cl,el(doc,"p","p2-note",`শাখা ${p.sites.length}টি`),sl);
 }
 function mount(rootEl,options){
  const WS=root.CORE10_PACK02_WORKSPACE,CT=root.CORE10_PACK02_CONTROLS;
  if(!WS||!CT)fail("PACK02_MODULES_MISSING");
  if(!obj(options)||typeof options.rpc!=="function")fail("PACK02_SIGNED_RPC_REQUIRED");
  const doc=rootEl.ownerDocument,rpc=options.rpc,loader=WS.create({rpc});
  let list=offers(options.context),epoch=0;
  rootEl.classList.add("p2-host");rootEl.replaceChildren();
  const pick=el(doc,"select","p2-pick");pick.setAttribute("aria-label","ওয়ার্কস্পেস বাছাই করুন");
  const status=el(doc,"p","p2-status");status.setAttribute("role","status");
  const shell=el(doc,"div","p2-root"),panel=el(doc,"section","p2-panel");
  rootEl.append(pick,status,shell,panel);
  function fill(){
   pick.replaceChildren();
   list.forEach((o,i)=>{const op=el(doc,"option",null,o.label);op.value=String(i);pick.append(op);});
   // A single-business staff member gets no chooser at all.
   pick.hidden=list.length<2;
  }
  function closed(){shell.replaceChildren();panel.replaceChildren();status.textContent=DENIED;}
  async function open(i){
   const mine=++epoch,o=list[i];
   panel.replaceChildren();status.textContent="";
   if(!o)return closed();
   try{
    const v=await loader.load(o.mode,o.business);
    if(mine!==epoch)return;
    const wired=o.mode==="universal_owner"?["owner.reports"]:o.mode==="business_owner"?["biz.sites","biz.controls","biz.reports"]:["staff.reports"];
    WS.render(shell,v,async key=>{
     const mine2=++epoch;panel.replaceChildren();
     try{
      if(key==="biz.controls"){const p=await rpc("pack02_controls_v1",{p_surface:"business",p_business:o.business});if(mine2!==epoch)return;CT.render(panel,CT.view(p));}
      else if(key==="biz.sites"){const p=await rpc("pack02_setup_readback_v1",{p_business:o.business});if(mine2!==epoch)return;readback(doc,panel,p,o.business);}
      else if(key==="owner.reports"){const p=await rpc("pack02_owner_report_v1",{});if(mine2!==epoch)return;
       if(p.contract!=="C10_PACK02_OWNER_REPORT_V1"||!Array.isArray(p.businesses))fail("PACK02_REPORT_INVALID");
       reportList(doc,panel,p.businesses,r=>[String(r.display_name),`শাখা ${r.sites} · লোকেশন ${r.locations} · স্টক এন্ট্রি ${r.movements}`]);}
      else{const p=await rpc("pack02_business_report_v1",{p_business:o.business});if(mine2!==epoch)return;
       if(p.contract!=="C10_PACK02_BUSINESS_REPORT_V1"||p.business_id!==o.business||!Array.isArray(p.sites))fail("PACK02_REPORT_INVALID");
       reportList(doc,panel,p.sites,r=>[String(r.label),r.stock_read===true?`স্টক এন্ট্রি ${r.movement_count}`:"স্টক দেখার অনুমতি নেই"]);}
     }catch{if(mine2===epoch)closed();}
    },wired);
   }catch{if(mine===epoch)closed();}
  }
  pick.addEventListener("change",()=>open(Number(pick.value)));
  fill();
  const ready=list.length?open(0):Promise.resolve(closed());
  return Object.freeze({ready,
   // Host calls reset() on sign-out and refresh(context) after a new sign-in.
   reset(){epoch++;list=[];fill();shell.replaceChildren();panel.replaceChildren();status.textContent="";},
   refresh(context){list=offers(context);fill();return list.length?open(0):Promise.resolve(closed());}});
 }
 return Object.freeze({offers,mount});
});
