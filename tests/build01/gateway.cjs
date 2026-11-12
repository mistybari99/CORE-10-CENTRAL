"use strict";
// Isolated development/test gateway only. Fixed loopback upstreams, no open proxy,
// no Auth admin/signup, no secret key in config, no production fallback.
const http=require("node:http"),fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const {build,verify,isAllowed}=require("../../internal/core10-pages-package");
const AUTH=new Map([["/token","POST"],["/user","GET"],["/logout","POST"],["/health","GET"]]);
const RPC=new Set(["build01_context_v1","build01_workspace_v1","build01_setup_v1","build01_site_v1","build01_set_access_v1"]);
const TYPES={".html":"text/html; charset=utf-8",".js":"application/javascript; charset=utf-8",".css":"text/css; charset=utf-8"};
function loopback(value){const u=new URL(value);if(u.protocol!=="http:"||!["localhost","127.0.0.1","[::1]"].includes(u.hostname)||u.username||u.password||u.pathname!=="/"||u.search||u.hash)throw Error("LOOPBACK_TARGET_REQUIRED");return u.origin;}
function createGateway(options){
 const auth=loopback(options.authUrl),rest=loopback(options.restUrl);
 if(typeof options.publishableKey!=="string"||!options.publishableKey)throw Error("ANON_KEY_REQUIRED");
 let role;try{role=JSON.parse(Buffer.from(options.publishableKey.split(".")[1],"base64url").toString()).role;}catch{throw Error("DISPOSABLE_ANON_KEY_REQUIRED");}
 if(role!=="anon")throw Error("ONLY_ANON_KEY_MAY_REACH_BROWSER");
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),"core10-build01-gateway-"));
 const publicRoot=path.join(temporary,"public");
 build(path.resolve(__dirname,"../.."),publicRoot);verify(publicRoot);
 const server=http.createServer(async(req,res)=>{
  const headers={"cache-control":"no-store","x-content-type-options":"nosniff","referrer-policy":"no-referrer","content-security-policy":"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; object-src 'none'; frame-ancestors 'none'"};
  function respond(status,body,type="text/plain; charset=utf-8"){res.writeHead(status,{...headers,"content-type":type});res.end(body);}
  try{
   const origin="http://127.0.0.1:"+server.address().port;
   if(req.headers.origin&&req.headers.origin!==origin)return respond(403,"Origin denied");
   const url=new URL(req.url,origin),p=decodeURIComponent(url.pathname);
   if(p==="/core10-build01-config.js"){
    if(!["GET","HEAD"].includes(req.method))return respond(405,"Method denied");
    return respond(200,req.method==="HEAD"?null:"window.CORE10_BUILD01_CONFIG=Object.freeze("+JSON.stringify({enabled:true,mode:"isolated-development",url:origin,publishableKey:options.publishableKey})+");","application/javascript; charset=utf-8");
   }
   let target;
   if(p.startsWith("/auth/v1/")){
    const suffix=p.slice("/auth/v1".length);
    if(AUTH.get(suffix)!==req.method)return respond(404,"Auth route unavailable");
    target=auth+suffix+url.search;
   }else if(p.startsWith("/rest/v1/rpc/")){
    if(req.method!=="POST"||url.search||!RPC.has(p.slice("/rest/v1/rpc/".length)))return respond(404,"RPC unavailable");
    target=rest+p.slice("/rest/v1".length);
   }
   if(target){
    const buffers=[];let size=0;
    for await(const b of req){size+=b.length;if(size>65536)return respond(413,"Request too large");buffers.push(b);}
    const forwarded={};
    for(const key of ["authorization","apikey","content-type","accept","accept-profile","content-profile","x-client-info","x-supabase-api-version"])
      if(req.headers[key])forwarded[key]=req.headers[key];
    // Never forward caller Host/cookies/hop-by-hop headers or follow redirects.
    const response=await fetch(target,{method:req.method,headers:forwarded,body:req.method==="GET"?undefined:Buffer.concat(buffers),redirect:"error",signal:AbortSignal.timeout(15000)});
    return respond(response.status,Buffer.from(await response.arrayBuffer()),response.headers.get("content-type")||"application/json");
   }
   if(!["GET","HEAD"].includes(req.method))return respond(405,"Method denied");
   const file=p==="/"?"core10-build01.html":p.slice(1);
   // Only this surface and its explicit original dependencies are reachable.
   const allowed=new Set(["core10-build01.html","core10-build01.js","core10-build01.css","core10-build01-client.js","core10-enterprise-client.js","core10-control-studio.css","vendor/supabase.js"]);
   if(!allowed.has(file)||!isAllowed(file))return respond(404,"Not found");
   const full=path.join(publicRoot,file);
   if(fs.realpathSync(full)!==full)return respond(404,"Not found");
   return respond(200,req.method==="HEAD"?null:fs.readFileSync(full),TYPES[path.extname(file)]||"text/plain");
  }catch(e){
   if(!res.headersSent)respond(e instanceof URIError?400:502,"Isolated service unavailable");
   else res.end();
  }
 });
 server.once("close",()=>fs.rmSync(temporary,{recursive:true,force:true}));
 return server;
}
module.exports={createGateway};
if(require.main===module){
 const server=createGateway({authUrl:process.env.BUILD01_AUTH_URL||"http://127.0.0.1:59999",restUrl:process.env.BUILD01_REST_URL||"http://127.0.0.1:55300",publishableKey:process.env.BUILD01_PUBLISHABLE_KEY});
 server.listen(Number(process.env.PORT||58081),"127.0.0.1",()=>console.log("Build 01 isolated gateway listening on loopback"));
}
