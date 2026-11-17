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
