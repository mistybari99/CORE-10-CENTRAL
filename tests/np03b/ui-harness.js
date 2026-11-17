/* TEST ONLY: browser -> real disposable SQL, synthetic Auth, canonical Master. */
(async function(){'use strict';
 const q=new URLSearchParams(location.search),persona=q.get('persona')||'11111111-1111-4111-8111-111111111111',events=new Set();
 const client={auth:{async getUser(){return {data:{user:{id:persona}},error:null};},onAuthStateChange(fn){events.add(fn);return {data:{subscription:{unsubscribe(){events.delete(fn);}}}};}},schema(name){if(name!=='core10')throw Error('WRONG_SCHEMA');return {async rpc(name,args){try{const r=await fetch('/rpc/'+name,{method:'POST',headers:{'content-type':'application/json','x-test-persona':persona},body:JSON.stringify(args||{})});const value=await r.json();return r.ok?{data:value,error:null}:{data:null,error:value};}catch(e){return {data:null,error:{message:'NETWORK_UNCERTAIN'}};}}};}};
 const lang=q.get('lang')==='en'?'en':'bn';
 const provider=q.has('missing')?async()=>null:undefined;
 const initialScope=q.has('scope')?{businessId:Number(q.get('scope')),siteId:Number(q.get('site'))}:undefined;
 const controller=window.CORE10_SALES_ORDER_ENTRY.attach(document.getElementById('sales-host'),{client,backendMode:'synthetic',lang,catalogProvider:provider,initialScope});
 window.NP03B_TEST={controller,signOut(){for(const e of [...events])e('SIGNED_OUT',null);}};
 await controller.ready;document.body.dataset.ready='1';
})().catch(e=>{document.body.dataset.error=String(e.code||e.message);});
