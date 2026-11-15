/* PACK-01-owned S2 bridge. PACK-02 owns SQL, projection and renderer.
 * Available only when the isolated Build01 gateway has packaged both S2 assets.
 * No direct fetch to a third-party service, no role claims, no cached authority.
 */
(function(root){
 "use strict";
 const doc=root.document,el=id=>doc.getElementById(id);
 const panel=el("b01-pack02"),mode=el("b01-pack02-mode"),result=el("b01-pack02-view"),status=el("b01-pack02-status");
 let generation=0,context=null,api=null,business=null,promise=null;
 function empty(){result.replaceChildren();result.removeAttribute("data-mode");status.textContent="";panel.hidden=true;}
 function clear(){generation++;api=null;context=null;business=null;empty();}
 function available(){return root.CORE10_BUILD01_CONFIG?.enabled===true&&
  root.CORE10_BUILD01_CONFIG?.mode==="isolated-development"&&root.CORE10_BUILD01_CONFIG?.pack02Enabled===true;}
 function asset(tag,url){
  return new Promise((resolve,reject)=>{
   const node=doc.createElement(tag);if(tag==="script"){node.src=url;node.async=false;}
   else{node.rel="stylesheet";node.href=url;}
   node.onload=resolve;node.onerror=()=>reject(Error("PACK02_ASSET_UNAVAILABLE"));
   doc.head.append(node);
  });
 }
 async function assets(){
  if(root.CORE10_PACK02_WORKSPACE)return;
  if(!promise)promise=(async()=>{
   await asset("link","./core10-pack02-workspace.css");
   await asset("script","./core10-pack02-workspace.js");
   if(!root.CORE10_PACK02_WORKSPACE?.create||!root.CORE10_PACK02_WORKSPACE?.render)throw Error("PACK02_RENDERER_UNAVAILABLE");
  })().catch(error=>{promise=null;throw error;});
  await promise;
 }
 function modes(ctx,id){
  const rows=[];
  if(Array.isArray(ctx.legal_entities)&&ctx.legal_entities.length)rows.push(["universal_owner","Universal Owner"]);
  const member=(ctx.businesses||[]).find(b=>Number(b.id)===id);
  if(member?.can_manage)rows.push(["business_owner","Business Owner"]);
  if(member)rows.push(["staff","Staff"]);
  return rows;
 }
 async function draw(request=++generation){
  if(!available()||!api||!context){empty();return;}
  const selected=mode.value;
  const scoped=selected==="universal_owner"?null:business;
  empty();
  try{
   await assets();if(request!==generation)return;
   const renderer=root.CORE10_PACK02_WORKSPACE;
   const bridge=renderer.create({rpc:(name,args)=>{
    if(name!=="pack02_workspace_v1")throw Error("PACK02_RPC_UNAVAILABLE");
    return api.pack02Workspace(args.p_mode,args.p_business);
   }});
   const view=await bridge.load(selected,scoped);
   if(request!==generation)return;
   renderer.render(result,view); // Unwired PR105 navigation stays disabled.
   panel.hidden=false;
   status.textContent="Signed server scope verified · demo only";
  }catch(error){
   if(request===generation){empty();status.textContent="Workspace denied or unavailable";}
  }
 }
 async function refresh(next){
  clear();
  if(!available()||!next||!next.api||!next.context||typeof next.api.pack02Workspace!=="function")return;
  api=next.api;context=next.context;business=next.businessId;
  const rows=modes(context,business);
  if(!rows.length)return;
  mode.replaceChildren();
  for(const [value,label] of rows){const option=doc.createElement("option");option.value=value;option.textContent=label;mode.append(option);}
  await draw(++generation);
 }
 mode.addEventListener("change",()=>void draw());
 el("b01-pack02-reload").addEventListener("click",()=>void draw());
 root.CORE10_BUILD01_PACK02=Object.freeze({clear,refresh});
})(window);
