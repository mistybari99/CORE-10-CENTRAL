'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../../core10-sales-order-entry.js'),'utf8');
function fixture(failure){
 const cleaned=[],callbacks=[];let mounted;
 const master={load(){},destroy(){cleaned.push('master');}};
 const api={destroy(){cleaned.push('api');}};
 const ui={ready:Promise.resolve(),reset(){cleaned.push('reset');},destroy(){cleaned.push('ui');}};
 const root={CORE10_SALES_MASTER_CATALOG:{create:()=>master},CORE10_SALES_ORDER_CLIENT:{create(){if(failure==='client')throw Error('CLIENT');return api;}},CORE10_SALES_ORDER_UI:{mount(host,opts){mounted=opts;if(failure==='ui')throw Error('UI');return ui;}}};
 vm.runInNewContext(source,{window:root});
 const client={auth:{onAuthStateChange(fn){callbacks.push(fn);return failure==='subscription'?{}:{data:{subscription:{unsubscribe(){cleaned.push('subscription');}}}};}}};
 return {attach:()=>root.CORE10_SALES_ORDER_ENTRY.attach({}, {client,backendMode:'signed'}),cleaned,callbacks,master,get mounted(){return mounted;}};
}
test('partial attachment never leaves a Master session subscription alive',()=>{for(const failure of ['client','ui','subscription']){const f=fixture(failure);assert.throws(f.attach);assert.ok(f.cleaned.includes('master'));if(failure!=='client')assert.ok(f.cleaned.includes('api'));if(failure==='subscription')assert.ok(f.cleaned.includes('ui'));}});
test('default canonical provider and session invalidation share the host lifecycle',()=>{const f=fixture();const c=f.attach();assert.equal(f.mounted.catalogProvider,f.master.load);f.callbacks[0]('INITIAL_SESSION');assert.deepEqual(f.cleaned,[]);f.callbacks[0]('SIGNED_OUT');assert.deepEqual(f.cleaned,['reset','api','master']);c.destroy();const count=f.cleaned.length;c.destroy();assert.equal(f.cleaned.length,count);assert.ok(f.cleaned.includes('subscription'));});

// Module contract only: this does not claim the shared Central route loads Sales.
function taskFixture(){
 const mounts=[],cleaned=[],events=[],buttons=[];
 function element(){return {dataset:{},classList:{remove(){}},setAttribute(){},append(x){if(x.dataset?.salesView)buttons.push(x);},addEventListener(name,fn){this.click=fn;},querySelectorAll(){return buttons;},replaceChildren(){}};}
 const host=element();host.ownerDocument={createElement:element};
 const module=name=>({mount(host,options){const ui={ready:Promise.resolve(),getState:()=>({businessId:101,siteId:1001,lang:'bn'}),requestLeave:fn=>fn(),refresh(){cleaned.push('refresh');},reset(){cleaned.push('reset');},destroy(){cleaned.push(name);}};mounts.push({name,options});return ui;}});
 const root={CORE10_SALES_ORDER_CLIENT:{create:()=>({destroy(){cleaned.push('api');}})},CORE10_SALES_ORDER_UI:module('orders'),CORE10_SALES_INVOICE_UI:module('invoices')};
 vm.runInNewContext(source,{window:root});
 const client={auth:{onAuthStateChange(fn){events.push(fn);return {data:{subscription:{unsubscribe(){cleaned.push('subscription');}}}};}}};
 const controller=root.CORE10_SALES_ORDER_ENTRY.attach(host,{client,backendMode:'signed',lang:'bn',initialScope:{businessId:101,siteId:1001}});
 return {mounts,cleaned,events,buttons,controller};
}
test('same-client task navigation destroys the old view and preserves canonical scope/locale',()=>{
 const f=taskFixture(),first=f.mounts[0];f.buttons[1].click();
 assert.equal(f.mounts[1].name,'invoices');assert.equal(first.options.api,f.mounts[1].options.api);
 assert.equal(f.mounts[1].options.lang,'bn');assert.deepEqual(JSON.parse(JSON.stringify(f.mounts[1].options.initialScope)),{businessId:101,siteId:1001});
 assert.ok(f.cleaned.includes('orders'));f.controller.destroy();
});
test('retained order handoff and refresh cannot resurrect destroyed or invalidated routes',()=>{
 for(const end of ['destroy','SIGNED_OUT','TOKEN_REFRESHED','USER_UPDATED']){
  const f=taskFixture(),handoff=f.mounts[0].options.onCreateInvoice;
  if(end==='destroy')f.controller.destroy();else f.events[0](end);
  const count=f.mounts.length;handoff({businessId:101,siteId:1001,orderId:1});f.controller.refresh();f.buttons[1].click();
  assert.equal(f.mounts.length,count,end);assert.ok(!f.cleaned.includes('refresh'),end);
  f.controller.destroy();
 }
});
