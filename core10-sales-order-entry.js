/* Central-host mount: one signed Sales client, task tabs, no new app/login. */
(function(root){'use strict';
 function attach(host,options){
  if(!root.CORE10_SALES_ORDER_CLIENT||!root.CORE10_SALES_ORDER_UI)throw Error('SALES_MODULES_REQUIRED');
  let master,api,ui,sub,ended=false,sessionEnded=false,view=options.initialView==='invoices'?'invoices':'orders',nav,content=host;
  const invoiceReady=!!root.CORE10_SALES_INVOICE_UI;
  function dispose(){if(ended)return;ended=true;sub?.unsubscribe();ui?.destroy();api?.destroy();master?.destroy();if(nav)host.replaceChildren();}
  function stateChanged(s){if(!nav)return;for(const b of nav.querySelectorAll('button')){const name=b.dataset.salesView;b.textContent=s.lang==='en'?(name==='orders'?'Sales orders':'Draft invoices'):(name==='orders'?'বিক্রয় অর্ডার':'ইনভয়েসের খসড়া');b.disabled=sessionEnded||s.busy||s.uncertain;b.setAttribute('aria-pressed',String(name===view));}}
  function mountView(next,source){
   // A retained view callback must not resurrect a route after unmount/sign-out.
   if(ended||sessionEnded)return Promise.resolve();
   const previous=ui?.getState?.(),scope=source?{businessId:source.businessId,siteId:source.siteId}:previous?.businessId?{businessId:previous.businessId,siteId:previous.siteId}:options.initialScope;
   ui?.destroy();content.classList?.remove('so-workspace','si-workspace');view=next;
   const module=next==='invoices'?root.CORE10_SALES_INVOICE_UI:root.CORE10_SALES_ORDER_UI;
   ui=module.mount(content,{api,backendMode:options.backendMode,lang:source?.lang||previous?.lang||options.lang,catalogProvider:options.catalogProvider||master?.load,initialScope:scope,initialOrderId:source?.orderId||(!previous?options.initialOrderId:undefined),
    onStateChange:stateChanged,onCreateInvoice:invoiceReady?source=>mountView('invoices',source):undefined});
   return ui.ready;
  }
  try{
   master=!options.catalogProvider&&root.CORE10_SALES_MASTER_CATALOG?root.CORE10_SALES_MASTER_CATALOG.create({client:options.client,lang:options.lang}):null;
   api=root.CORE10_SALES_ORDER_CLIENT.create({client:options.client,backendMode:options.backendMode});
   if(invoiceReady){const d=host.ownerDocument;nav=d.createElement('nav');nav.className='so-sales-nav';nav.setAttribute('aria-label',options.lang==='en'?'Sales tasks':'বিক্রয় কাজ');content=d.createElement('div');
    for(const next of ['orders','invoices']){const b=d.createElement('button');b.type='button';b.className='outline';b.dataset.salesView=next;b.addEventListener('click',()=>{if(ended||sessionEnded||view===next)return;const open=()=>mountView(next);if(ui.requestLeave)ui.requestLeave(open);else open();});nav.append(b);}host.replaceChildren(nav,content);
   }else view='orders';
   const ready=mountView(view);
   sub=options.client.auth.onAuthStateChange(event=>{if(event==='INITIAL_SESSION'||ended)return;sessionEnded=true;ui.reset();api.destroy();master?.destroy();stateChanged({lang:ui.getState?.()?.lang||options.lang,busy:false,uncertain:false});})?.data?.subscription;
   if(!sub?.unsubscribe)throw Error('SALES_SESSION_SUBSCRIPTION_REQUIRED');
   return Object.freeze({ready,refresh:()=>ended||sessionEnded?undefined:ui.refresh?.(),getState:()=>({...ui.getState?.(),view}),destroy:dispose});
  }catch(e){dispose();throw e;}
 }
 root.CORE10_SALES_ORDER_ENTRY=Object.freeze({attach});
})(typeof window!=='undefined'?window:globalThis);
