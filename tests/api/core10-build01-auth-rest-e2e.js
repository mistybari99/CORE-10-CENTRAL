"use strict";
// Actual GoTrue-issued users/password sessions; no hand-signed user token is
// counted as login proof. The sole admin token is confined to this Node fixture.
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const AUTH=process.env.CORE10_BUILD01_AUTH_URL,REST=process.env.CORE10_BUILD01_REST_URL;
for(const url of [AUTH,REST]){
 const u=new URL(url||"http://invalid");
 assert(["localhost","127.0.0.1"].includes(u.hostname)&&u.protocol==="http:","Loopback test runtime required");
}
assert.equal(process.env.CORE10_BUILD01_DISPOSABLE_ACK,"I_CONFIRM_BUILD01_DISPOSABLE");
const secret=process.env.CORE10_BUILD01_TEST_SECRET;
assert(secret&&secret.length>=32,"Disposable signer required");
const PASSWORD="Synthetic-Only_Build01_2026!";
const personas={
 owner:["11111111-1111-4111-8111-111111111111","owner"],
 businessOwner:["22222222-2222-4222-8222-222222222222","business-owner"],
 manager:["33333333-3333-4333-8333-333333333333","manager"],
 staff:["44444444-4444-4444-8444-444444444444","staff"],
 investor:["55555555-5555-4555-8555-555555555555","investor"],
 revoked:["66666666-6666-4666-8666-666666666666","revoked"],
 otherOwner:["77777777-7777-4777-8777-777777777777","other-owner"],
 otherStaff:["88888888-8888-4888-8888-888888888888","other-staff"],
 operator:["99999999-9999-4999-8999-999999999999","operator"],
 unassigned:["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","unassigned"]
};
const email=who=>"build01-"+personas[who][1]+"@example.test";
const uid=who=>personas[who][0];
function signed(claims){const b=x=>Buffer.from(JSON.stringify(x)).toString("base64url"),body=b({alg:"HS256",typ:"JWT"})+"."+b(claims);return body+"."+crypto.createHmac("sha256",secret).update(body).digest("base64url");}
async function http(base,path,{token,method="GET",body}={}){
 const res=await fetch(base+path,{method,headers:{accept:"application/json",...(token?{authorization:"Bearer "+token}:{}),...(body!==undefined?{"content-type":"application/json"}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 const text=await res.text();let data;try{data=JSON.parse(text)}catch{data=text}
 return {status:res.status,data};
}
function ok(r,label){assert(r.status>=200&&r.status<300,label+": "+r.status+" "+JSON.stringify(r.data));return r.data;}
function denied(r,label){assert(r.status>=400,label+" unexpectedly allowed: "+JSON.stringify(r.data));return r;}
const rpc=(token,name,args={})=>http(REST,"/rpc/"+name,{token,method:"POST",body:args});
const claims=token=>JSON.parse(Buffer.from(token.split(".")[1],"base64url").toString());
async function login(who){
 const x=ok(await http(AUTH,"/token?grant_type=password",{method:"POST",body:{email:email(who),password:PASSWORD}}),"Actual password login "+who);
 assert.equal(x.user.id,uid(who));assert(x.access_token&&x.refresh_token);assert(claims(x.access_token).session_id,"GoTrue session_id missing");
 ok(await http(AUTH,"/user",{token:x.access_token}),"GoTrue getUser "+who);
 return x;
}
async function seed(){
 const token=signed({role:"service_role",aud:"authenticated",iss:"supabase",exp:Math.floor(Date.now()/1000)+300});
 for(const who of Object.keys(personas)){
  const x=ok(await http(AUTH,"/admin/users",{token,method:"POST",body:{id:uid(who),email:email(who),password:PASSWORD,email_confirm:true,role:"authenticated",aud:"authenticated"}}),"Create synthetic GoTrue user "+who);
  assert.equal(x.id,uid(who));
 }
 console.log("PASS actual GoTrue Admin API created10canonical synthetic users; no external email or production identity");
}
async function test(){
 const owner=await login("owner"),staff=await login("staff"),manager=await login("manager"),other=await login("otherOwner");
 const O=owner.access_token,S=staff.access_token,M=manager.access_token,T=other.access_token;
 const context=ok(await rpc(O,"build01_context_v1"),"Owner context");
 assert.equal(context.actor_uid,uid("owner"));assert.equal(context.real_auth_account_verified,true);
 assert(context.businesses.some(x=>x.id===101||x.business_id===101));
 assert(!context.businesses.some(x=>x.id===201||x.business_id===201));
 denied(await http(AUTH,"/token?grant_type=password",{method:"POST",body:{email:email("owner"),password:"Wrong-synthetic-password"}}),"Wrong password");
 denied(await rpc(null,"build01_context_v1"),"Anonymous context");
 denied(await rpc(O.slice(0,-3)+"abc","build01_context_v1"),"Bad signature");
 denied(await rpc(T,"build01_workspace_v1",{p_business:101}),"Foreign tenant workspace");
 for(const who of ["revoked","operator","unassigned"]){
  const x=await login(who),c=ok(await rpc(x.access_token,"build01_context_v1"),who+" context");
  assert.equal(c.businesses.length,0,who+" must have no implicit business rights");
 }
 const qargs={p_legal:11,p_slug:"build01-http-quick",p_template:"food_manufacturing",p_display_name:"Synthetic HTTP Quick",p_mode:"quick",p_sites:null,p_request:"build01-http-setup-quick",p_brand_hex:"#334155"};
 const quick=ok(await rpc(O,"build01_setup_v1",qargs),"Quick setup");
 assert(quick.business_id);assert.deepEqual(ok(await rpc(O,"build01_setup_v1",qargs),"Setup replay"),quick);
 denied(await rpc(O,"build01_setup_v1",{...qargs,p_display_name:"Changed"}),"Changed payload replay");
 denied(await rpc(T,"build01_setup_v1",{...qargs,p_slug:"foreign",p_request:"foreign-setup"}),"Foreign legal entity setup");
 const advanced=ok(await rpc(O,"build01_setup_v1",{...qargs,p_slug:"build01-http-advanced",p_display_name:"Synthetic HTTP Advanced",p_mode:"advanced",p_sites:[{kind:"factory",label:"Factory"},{kind:"warehouse",label:"Warehouse"}],p_request:"build01-http-setup-advanced"}),"Advanced setup");
 assert.notEqual(advanced.business_id,quick.business_id);
 // Exercise the existing ten-family draft engine through genuine user sessions,
 // not just SQL claims; industry modules remain locked and uncertified.
 const families=["sweets_bakery","restaurant","paint_hardware","retail_wholesale","general_manufacturing","construction","import_export","ecommerce","technology_digital","services"];
 for(const family of families){
  assert(context.templates.some(t=>t.code===family&&t.draft_supported),"Missing draft family "+family);
  for(const mode of ["quick","advanced"]){
   const args={...qargs,p_slug:("http-"+family+"-"+mode).replaceAll("_","-"),p_template:family,p_mode:mode,p_sites:mode==="quick"?[]:[{kind:"showroom",label:"Synthetic Counter"},{kind:"warehouse",label:"Synthetic Storage"}],p_request:"http-family-"+family+"-"+mode};
   const created=ok(await rpc(O,"build01_setup_v1",args),family+" "+mode);
   assert.equal(created.status,"draft");assert.equal(created.production_certified,false);
   assert.deepEqual(ok(await rpc(O,"build01_setup_v1",args),family+" exact replay"),created);
   const w=ok(await rpc(O,"build01_workspace_v1",{p_business:created.business_id}),family+" scoped workspace");
   assert.equal(w.sites.length,mode==="quick"?1:2);
  }
 }
 console.log("PASS all10 industry families Quick/Advanced draft setup + exact replay through actual GoTrue sessions");
 const site=ok(await rpc(O,"build01_site_v1",{p_business:quick.business_id,p_kind:"warehouse",p_label:"HTTP Test Warehouse",p_request:"build01-http-add-site"}),"Add canonical site");
 assert(site.site_id);
 const access={p_business:quick.business_id,p_subject:uid("staff"),p_command:"site_grant.grant",p_role:null,p_site:site.site_id,p_actions:["stock.read","stock.post"],p_denied_actions:[],p_valid_until:null,p_request:"build01-http-grant-staff"};
 const grant=ok(await rpc(O,"build01_set_access_v1",access),"Grant canonical site");
 const replays=await Promise.all(Array.from({length:6},()=>rpc(O,"build01_set_access_v1",access)));
 for(const r of replays)assert.deepEqual(ok(r,"Concurrent grant replay"),grant);
 let workspace=ok(await rpc(S,"build01_workspace_v1",{p_business:quick.business_id}),"Staff allowed after grant");
 assert(workspace.sites.some(x=>x.id===site.site_id||x.site_id===site.site_id));
 denied(await rpc(S,"build01_set_access_v1",{...access,p_subject:uid("manager"),p_request:"staff-tries-grant"}),"Staff cannot grant");
 denied(await rpc(O,"build01_set_access_v1",{...access,p_subject:uid("owner"),p_request:"owner-self-grant"}),"Owner cannot mutate own access");
 denied(await rpc(O,"build01_set_access_v1",{...access,p_subject:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",p_request:"unknown-subject"}),"Nonexistent Auth subject");
 // Explicit per-site deny must beat broad manager inheritance, using the same
 // canonical can_site() called by the original A018 posting function.
 const policy={...access,p_business:101,p_subject:uid("manager"),p_site:1001,p_denied_actions:["stock.post"],p_request:"build01-http-manager-deny"};
 ok(await rpc(O,"build01_set_access_v1",policy),"Manager explicit deny");
 denied(await rpc(M,"post_stock_event",{p_location:5001,p_item:8001,p_delta:1,p_request:"build01-denied-manager-post"}),"Deny overrides manager posting");
 ok(await http(AUTH,"/user",{token:M,method:"PUT",body:{data:{role:"tenant_owner",is_owner:true,tenant_id:1}}}),"User-editable metadata update");
 denied(await rpc(M,"build01_setup_v1",{...qargs,p_slug:"forged-role",p_request:"forged-role-setup"}),"Metadata role forgery");
 // A short-lived grant expires in the database while the actual JWT is valid.
 const expiry={...access,p_business:101,p_site:1002,p_valid_until:new Date(Date.now()+1500).toISOString(),p_request:"build01-http-expiring-grant"};
 ok(await rpc(O,"build01_set_access_v1",expiry),"Expiring grant");
 await new Promise(resolve=>setTimeout(resolve,1800));
 const rows=ok(await http(REST,"/sites?id=eq.1002&select=id",{token:S}),"Expired-site RLS read");
 assert.equal(rows.length,0,"Expired grant must remove rows despite valid token");
 ok(await rpc(O,"build01_set_access_v1",{...access,p_command:"site_grant.revoke",p_actions:[],p_request:"build01-http-revoke-staff"}),"Revoke canonical site");
 denied(await rpc(S,"build01_workspace_v1",{p_business:quick.business_id}),"Existing JWT denied immediately after revoke");
 workspace=ok(await rpc(O,"build01_workspace_v1",{p_business:quick.business_id}),"Owner audit workspace");
 assert(workspace.audit.length>=3,"Setup/grant/revoke audit missing");
 denied(await http(REST,"/site_grants",{token:S,method:"POST",body:{tenant_id:1,business_id:101,site_id:1002,user_id:uid("staff"),active:true,actions:["stock.post"]}}),"Direct grant-table mutation");
 // Logout revokes the server session, so even the old correctly signed access
 // JWT must be rejected by the strict session-aware canonical actor resolver.
 ok(await http(AUTH,"/logout?scope=local",{token:S,method:"POST"}),"Actual GoTrue logout");
 denied(await rpc(S,"build01_context_v1"),"Logged-out signed JWT no longer has a live session");
 denied(await http(AUTH,"/token?grant_type=refresh_token",{method:"POST",body:{refresh_token:staff.refresh_token}}),"Logged-out refresh token");
 console.log("PASS Build01 ACTUAL GoTrue password/getUser/logout + setup/site + grant/deny/expiry/revoke + immutable audit/RLS + wrong-password/signature/tenant/metadata negatives");
}
(process.argv[2]==="seed"?seed():test()).catch(e=>{console.error(e.message);process.exitCode=1;});
