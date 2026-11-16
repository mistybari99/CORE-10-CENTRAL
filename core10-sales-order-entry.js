/* Central-host mount boundary: reuse its signed client; never create another
 * login/configuration shell or inherit BOS_CONFIG from the protected legacy app. */
(function(root){'use strict';
 function attach(host,options){
  if(!root.CORE10_SALES_ORDER_CLIENT||!root.CORE10_SALES_ORDER_UI)throw Error('SALES_MODULES_REQUIRED');
  const api=root.CORE10_SALES_ORDER_CLIENT.create({client:options.client,backendMode:options.backendMode});
  const ui=root.CORE10_SALES_ORDER_UI.mount(host,{api,backendMode:options.backendMode,lang:options.lang,catalogProvider:options.catalogProvider,initialScope:options.initialScope});
  let ended=false;
  const sub=options.client.auth.onAuthStateChange(event=>{if(event==='INITIAL_SESSION'||ended)return;ui.reset();api.destroy();})?.data?.subscription;
  if(!sub?.unsubscribe){ui.destroy();api.destroy();throw Error('SALES_SESSION_SUBSCRIPTION_REQUIRED');}
  return Object.freeze({ready:ui.ready,refresh:ui.refresh,getState:ui.getState,destroy(){if(ended)return;ended=true;sub.unsubscribe();ui.destroy();api.destroy();}});
 }
 root.CORE10_SALES_ORDER_ENTRY=Object.freeze({attach});
})(typeof window!=='undefined'?window:globalThis);
