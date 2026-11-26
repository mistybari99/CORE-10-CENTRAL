"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const {execFileSync}=require("node:child_process");
const root=path.resolve(__dirname,".."),site=path.join(root,"apps/central/site"),src=fs.readFileSync(path.join(site,"view/sales-signed.js"),"utf8");
test("signed Sales assets are exact canonical blobs, replay stays isolated",()=>{
 const bundle=fs.readFileSync(path.join(root,"apps/central/dist/worker.mjs"),"utf8");
 const files=JSON.parse(bundle.split("\n").find(l=>l.startsWith("const FILES=")).slice(12,-1));
 for(const name of ["core10-sales-order.css","core10-sales-master-catalog.js","core10-sales-order-client.js","core10-sales-order-ui.js","core10-sales-invoice-ui.js","core10-sales-order-entry.js"])assert.deepEqual(Buffer.from(files["/signed-sales/"+name][1],"base64"),execFileSync("git",["show","3e008e8ec7db896f46a94ab8ca3d91271905d71d:"+name],{cwd:root}),name);
 const html=fs.readFileSync(path.join(site,"view/sales-signed.html"),"utf8");
 assert.doesNotMatch(html,/replay\.js|sales-data\.js/);
 assert.match(html,/core10-sales-invoice-ui\.js/);
 assert.match(fs.readFileSync(path.join(site,"view/sales.html"),"utf8"),/replay\.js/);
});
function harness({signed=false,wrongBackend=false,delay=false}={}){
 const timers=[],events={},nodes={},calls={mount:0,destroy:0,auth:0},authListeners=[];
 function node(tag){return {tag,textContent:"",children:[],addEventListener(name,f){this[name]=f;},setAttribute(){},append(...x){this.children.push(...x);},replaceChildren(...x){this.children=x;},set id(v){nodes[v]=this;},get id(){return Object.keys(nodes).find(k=>nodes[k]===this);}};}
 const host=node("main");nodes["sales-signed-root"]=host;let resolveUser;
 const client={auth:{getUser(){calls.auth++;if(delay)return new Promise(r=>resolveUser=r);return Promise.resolve(signed?{data:{user:{id:"owner"}}}:{error:true});},onAuthStateChange(fn){authListeners.push(fn);return {data:{subscription:{unsubscribe(){}}}};},signInWithPassword:async()=>({error:true}),signOut:async()=>({})}};
 const win={document:{getElementById:id=>nodes[id],createElement:node,documentElement:{}},localStorage:{getItem:()=>"en"},CORE10_CONTROL_CENTRE_CONFIG:{url:wrongBackend?"https://wrong.invalid":"https://rhrqhbyzrhaafynfhdaf.supabase.co",key:"sb_publishable_test"},supabase:{createClient(){return client;}},CORE10_SALES_INVOICE_UI:{},CORE10_SALES_ORDER_ENTRY:{attach(h,o){assert.equal(o.backendMode,"signed");assert.equal(o.client,client);calls.mount++;return {ready:Promise.resolve(),destroy(){calls.destroy++;h.replaceChildren();}};}},setTimeout:f=>timers.push(f),addEventListener:(k,f)=>events[k]=f,location:{reload(){}}};
 vm.runInNewContext(src,{window:win});return {nodes,host,calls,authListeners,timers,events,resolve:(v)=>resolveUser(v)};
}
const tick=()=>new Promise(r=>setImmediate(r));
test("wrong backend never authenticates or mounts",()=>{const h=harness({wrongBackend:true});assert.equal(h.calls.auth,0);assert.equal(h.calls.mount,0);});
test("anonymous and bad password never mount Sales",async()=>{const h=harness();await tick();assert.ok(h.nodes["sales-login"]);h.nodes["sales-email"].value="nobody@example.invalid";h.nodes["sales-password"].value="bad";await h.nodes["sales-login"].submit({preventDefault(){}});assert.equal(h.calls.mount,0);assert.equal(h.nodes["sales-password"].value,"");assert.match(h.nodes["sales-login-error"].textContent,/failed/);});
test("signed mount and signout purge",async()=>{const h=harness({signed:true});await tick();assert.equal(h.calls.mount,1);h.authListeners[0]("SIGNED_OUT");assert.equal(h.calls.destroy,1);h.timers.shift()();await tick();assert.equal(h.calls.mount,1);assert.ok(h.nodes["sales-login"]);});
test("late user response cannot resurrect signed-out workspace",async()=>{const h=harness({delay:true});h.authListeners[0]("SIGNED_OUT");h.timers.shift()();h.resolve({data:{user:{id:"owner"}}});await tick();assert.equal(h.calls.mount,0);});
