/* Central-host mount boundary: reuse its signed client and existing shell. */
(function(root){'use strict';
 function attach(host,options){
  if(!root.CORE10_SALES_ORDER_CLIENT||!root.CORE10_SALES_ORDER_UI)throw Error('SALES_MODULES_REQUIRED');
  let master,api,ui,sub,ended=false;
  function dispose(){if(ended)return;ended=true;sub?.unsubscribe();ui?.destroy();api?.destroy();master?.destroy();}
  try{
   master=!options.catalogProvider&&root.CORE10_SALES_MASTER_CATALOG?root.CORE10_SALES_MASTER_CATALOG.create({client:options.client,lang:options.lang}):null;
   api=root.CORE10_SALES_ORDER_CLIENT.create({client:options.client,backendMode:options.backendMode});
   ui=root.CORE10_SALES_ORDER_UI.mount(host,{api,backendMode:options.backendMode,lang:options.lang,catalogProvider:options.catalogProvider||master?.load,initialScope:options.initialScope});
   sub=options.client.auth.onAuthStateChange(event=>{if(event==='INITIAL_SESSION'||ended)return;ui.reset();api.destroy();master?.destroy();})?.data?.subscription;
   if(!sub?.unsubscribe)throw Error('SALES_SESSION_SUBSCRIPTION_REQUIRED');
   return Object.freeze({ready:ui.ready,refresh:ui.refresh,getState:ui.getState,destroy:dispose});
  }catch(e){dispose();throw e;}
 }
 root.CORE10_SALES_ORDER_ENTRY=Object.freeze({attach});
})(typeof window!=='undefined'?window:globalThis);
