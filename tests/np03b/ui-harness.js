/* TEST ONLY: browser -> real disposable SQL, synthetic Auth and Master. */
(async function(){'use strict';
 const q=new URLSearchParams(location.search),persona=q.get('persona')||'11111111-1111-4111-8111-111111111111',events=new Set();
 const client={auth:{async getUser(){return {data:{user:{id:persona}},error:null};},onAuthStateChange(fn){events.add(fn);return {data:{subscription:{unsubscribe(){events.delete(fn);}}}};}},schema(name){if(name!=='core10')throw Error('WRONG_SCHEMA');return {async rpc(name,args){try{const r=await fetch('/rpc/'+name,{method:'POST',headers:{'content-type':'application/json','x-test-persona':persona},body:JSON.stringify(args||{})});const value=await r.json();return r.ok?{data:value,error:null}:{data:null,error:value};}catch(e){return {data:null,error:{message:'NETWORK_UNCERTAIN'}};}}};}};
 const products=[['রসগোল্লা বক্স','Rasgulla Box',300],['সন্দেশ বক্স','Sandesh Box',420],['মিক্সড সুইটস ১ কেজি','Mixed Sweets 1kg',850],['চকলেট কেক','Chocolate Cake',1200],['বাটার কুকিজ','Butter Cookies',250]];
 const lang=q.get('lang')==='en'?'en':'bn';
 const provider=async({businessId,siteId})=>q.has('missing')||businessId!==101?null:{businessId,siteId,source:'synthetic_fixture',customers:[{id:7001,label:lang==='en'?'Synthetic walk-in customer':'সিনথেটিক খুচরা গ্রাহক'}],priceLists:[{id:7101,label:lang==='en'?'Retail · synthetic BDT':'খুচরা · সিনথেটিক BDT',currency:'BDT'},{id:7102,label:lang==='en'?'Wholesale · synthetic BDT':'পাইকারি · সিনথেটিক BDT',currency:'BDT'}],items:products.map((p,i)=>({id:8101+i,label:p[lang==='en'?1:0],variantId:7301,uomId:7201,uomLabel:lang==='en'?'Pack':'প্যাক',prices:{7101:p[2],7102:p[2]*.9}}))};
 const initialScope=q.has('scope')?{businessId:Number(q.get('scope')),siteId:Number(q.get('site'))}:undefined;
 const controller=window.CORE10_SALES_ORDER_ENTRY.attach(document.getElementById('sales-host'),{client,backendMode:'synthetic',lang,catalogProvider:provider,initialScope});
 window.NP03B_TEST={controller,signOut(){for(const e of [...events])e('SIGNED_OUT',null);}};
 await controller.ready;document.body.dataset.ready='1';
})().catch(e=>{document.body.dataset.error=String(e.code||e.message);});
