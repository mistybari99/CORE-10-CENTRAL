"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const src=fs.readFileSync(path.join(__dirname,"../apps/central/site/view/stock-signed.js"),"utf8");
function harness({wrong=false,anonymous=false}={}){
 const calls=[],events={},timers=[],authListeners=[],nodes={};let actor=anonymous?null:"owner",confirm=true,command={command_id:61,item_id:5,kind:"receive",quantity:2,status:"confirmed",version:2},pendingBalance=null;
 function node(tag){
  const n={tag,children:[],dataset:{},textContent:"",hidden:false,disabled:false,value:"",
   append(...x){this.children.push(...x);if(tag==="select"&&!this.value&&x[0])this.value=x[0].value;},
   replaceChildren(...x){this.children=[];if(tag==="select")this.value="";this.append(...x);},
   addEventListener(k,f){this[k]=f;},setAttribute(){},
   querySelector(q){return walk(this).find(x=>q.startsWith("#")?x.id===q.slice(1):x.tag===q);},
   get firstChild(){return this.children[0];},set id(v){this._id=v;nodes[v]=this;},get id(){return this._id;}};
  return n;
 }
 function walk(n){return [n,...n.children.flatMap(walk)];}
 const root=node("main");root.id="stock-root";
 const auth={getUser:async()=>actor?{data:{user:{id:actor}}}:{error:true},signInWithPassword:async()=>({error:true}),signOut:async()=>{actor=null;return{};},onAuthStateChange(fn){authListeners.push(fn);}};
 const db={from(name){calls.push(["from",name]);assert.equal(name,"stock_locations");return {select(){return this;},eq(){return this;},limit:async()=>({data:[{id:7,business_id:3,site_id:8,code:"MAIN"}]})};},
  async rpc(name,args){calls.push([name,args]);switch(name){
   case "build01_context_v1":return {data:{businesses:[{id:3,slug:"demo",can_manage:true}]}};
   case "master_list_items_v1":return {data:args.p_after_id===null?{rows:[{id:5,sku:"SWEET"}],next_after_id:5}:{rows:[{id:6,sku:"MILK"}],next_after_id:null}};
   case "inventory_list_commands_v1":return {data:args.p_before_id===null?{business_id:3,items:[command],next_before_id:61}:{business_id:3,items:[{command_id:60,item_id:6,kind:"receive",quantity:3,status:"posted",version:3}],next_before_id:null}};
   case "inventory_list_balances_v1":if(pendingBalance)return await pendingBalance;return {data:args.p_after_location===null?{business_id:3,items:[{location_id:7,item_id:5,site_label:"Site",location_code:"MAIN",sku:"SWEET",on_hand:10}],next_after:{location_id:7,item_id:5}}:{business_id:3,items:[{location_id:7,item_id:6,site_label:"Site",location_code:"MAIN",sku:"MILK",on_hand:4}],next_after:null}};
   case "advance_inventory_command_v1":command={...command,status:"cancelled",version:3};return {data:command};
   case "inventory_request_approval_v1":command={...command,approval_request_id:91};return {data:{command_id:61,approval_request_id:91,stages:1}};
   default:throw Error("unexpected RPC "+name);
  }}
 };
 const client={auth,schema(n){assert.equal(n,"core10");return db;}};
 const win={document:{getElementById:id=>nodes[id],createElement:node,documentElement:{}},location:{search:"?lang=en",reload(){}},crypto:{randomUUID:()=>"12345678-1234-1234-1234-123456789012"},CORE10_CONTROL_CENTRE_CONFIG:{url:wrong?"https://invalid.example":"https://rhrqhbyzrhaafynfhdaf.supabase.co",key:"sb_publishable_test"},supabase:{createClient(){return client;}},confirm:()=>confirm,setTimeout:f=>timers.push(f),addEventListener:(k,f)=>events[k]=f};
 vm.runInNewContext(src,{window:win,URLSearchParams});
 return {calls,nodes,root,events,timers,authListeners,click(label){const b=walk(root).find(n=>n.tag==="button"&&n.textContent===label);assert.ok(b,label);return b.click();},setConfirm(v){confirm=v;},signout(){actor=null;authListeners[0]("SIGNED_OUT",null);},holdBalance(p){pendingBalance=p;},visible:()=>walk(root).map(n=>n.textContent).join(" ")};
}
const tick=()=>new Promise(r=>setImmediate(r));
test("wrong backend and anonymous users cannot call Stock RPCs",async()=>{for(const h of [harness({wrong:true}),harness({anonymous:true})]){await tick();assert.equal(h.calls.length,0);}});
test("canonical Master paging and Stock balance and command pagination",async()=>{const h=harness();await tick();assert.match(h.visible(),/SWEET/);assert.equal(h.calls.filter(x=>x[0]==="master_list_items_v1").length,2);assert.ok(!h.calls.some(x=>x[0]==="from"&&x[1]==="items"));await h.click("More commands");assert.match(h.visible(),/#60/);assert.equal(h.calls.filter(x=>x[0]==="inventory_list_commands_v1").at(-1)[1].p_before_id,61);await h.click("More balances");assert.match(h.visible(),/MILK · 4/);assert.equal(h.calls.filter(x=>x[0]==="inventory_list_balances_v1").at(-1)[1].p_after_item,5);});
test("cancel is explicit, denial leaves server untouched, confirmed cancel uses canonical RPC",async()=>{const h=harness();await tick();h.setConfirm(false);await h.click("Cancel");assert.ok(!h.calls.some(x=>x[0]==="advance_inventory_command_v1"));h.setConfirm(true);await h.click("Cancel");const a=h.calls.find(x=>x[0]==="advance_inventory_command_v1")[1];assert.equal(a.p_action,"cancel");assert.equal(a.p_command,61);assert.equal(a.p_version,2);assert.match(h.visible(),/cancelled/);});
test("approval uses canonical request RPC and displays reference without posting",async()=>{const h=harness();await tick();await h.click("Request approval");assert.equal(h.calls.find(x=>x[0]==="inventory_request_approval_v1")[1].p_command,61);assert.match(h.visible(),/Approval reference #91/);assert.ok(!h.calls.some(x=>x[0]==="advance_inventory_command_v1"));});
test("in-flight balance read after sign-out does not restore private rows",async()=>{const h=harness();await tick();let release;h.holdBalance(new Promise(r=>release=r));const p=h.click("More balances");await tick();h.signout();assert.equal(h.root.children.length,0);h.timers.shift()();release({data:{business_id:3,items:[{location_id:7,item_id:6,sku:"PRIVATE"}],next_after:null}});await p;assert.doesNotMatch(h.visible(),/PRIVATE|SWEET/);assert.match(h.visible(),/Sign in/);});
test("pagehide clears signed rows",async()=>{const h=harness();await tick();h.events.pagehide();assert.equal(h.root.children.length,0);});
