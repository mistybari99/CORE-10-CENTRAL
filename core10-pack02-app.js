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
    const wired=o.mode==="universal_owner"?["owner.reports"]:o.mode==="business_owner"?["biz.controls","biz.reports"]:["staff.reports"];
    WS.render(shell,v,async key=>{
     const mine2=++epoch;panel.replaceChildren();
     try{
      if(key==="biz.controls"){const p=await rpc("pack02_controls_v1",{p_surface:"business",p_business:o.business});if(mine2!==epoch)return;CT.render(panel,CT.view(p));}
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
