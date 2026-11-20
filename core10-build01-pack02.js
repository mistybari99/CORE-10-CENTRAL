/* PACK-01 Build01 host for PR #105. PACK-02 owns its own views, reports and controls.
 * Only the isolated gateway can advertise five packaged S2 static files.
 */
(function(root){"use strict";
 const doc=root.document,host=doc.getElementById("b01-pack02"),panel=doc.getElementById("b01-pack02-panel");
 const files=["core10-pack02-workspace.css","core10-pack02-workspace.js","core10-pack02-controls.js","core10-pack02-signed.js","core10-pack02-app.js"];
 let seq=0,controller=null,loading=null;
 function available(){const c=root.CORE10_BUILD01_CONFIG;return c?.enabled===true&&c.mode==="isolated-development"&&c.pack02Enabled===true;}
 function clear(){seq++;if(controller){try{controller.reset();}catch{}}controller=null;host.replaceChildren();panel.hidden=true;}
 function asset(file){return new Promise((resolve,reject)=>{const style=file.endsWith(".css"),tag=doc.createElement(style?"link":"script");
  if(style){tag.rel="stylesheet";tag.href="./"+file;}else{tag.src="./"+file;tag.async=false;}
  tag.onload=resolve;tag.onerror=()=>reject(Error("PACK02_ASSET_UNAVAILABLE"));doc.head.append(tag);});}
 async function ensure(){
  if(root.CORE10_PACK02_APP?.mount&&root.CORE10_PACK02_SIGNED?.fromRpc)return;
  if(!loading)loading=(async()=>{for(const file of files)await asset(file);
    if(!root.CORE10_PACK02_APP?.mount||!root.CORE10_PACK02_SIGNED?.fromRpc)throw Error("PACK02_MODULE_MISSING");
  })().catch(e=>{loading=null;throw e;});
  await loading;
 }
 async function refresh(x){
  clear();const my=seq;
  if(!available()||!x?.api||!x?.context||typeof x.api.pack02!=="function")return;
  try{
   await ensure();if(my!==seq)return;
   const rpc=root.CORE10_PACK02_SIGNED.fromRpc(x.api.pack02).rpc;
   const mount=root.CORE10_PACK02_APP.mount(host,{rpc,context:x.context});
   controller=mount;await mount.ready;
   if(my!==seq){mount.reset();return;}
   panel.hidden=false;
  }catch{if(my===seq)clear();}
 }
 root.CORE10_BUILD01_PACK02=Object.freeze({clear,refresh});
})(window);
