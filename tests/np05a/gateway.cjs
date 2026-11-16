'use strict';
// TEST ONLY. Local disposable SQL gateway, reusing the B-021 test approach.
// Synthetic subject claims are not GoTrue or signed production API proof.
const {spawnSync}=require('node:child_process'),fs=require('node:fs'),path=require('node:path'),http=require('node:http'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const allowed=new Set(['mfg_inspect_v1','mfg_material_requirements_v1','mfg_recipe_substitutions_v1','mfg_define_substitution_v1','mfg_preview_substitution_v1','mfg_material_waste_report_v1','mfg_record_material_waste_v1','mfg_create_recipe_v1','mfg_approve_recipe_v1','mfg_plan_batch_v1','mfg_release_batch_v1','mfg_record_output_v1','mfg_cancel_batch_v1','mfg_request_handoff_v1']);
function psql(sql){
 let command='psql',args=['-X','-q','-At','-v','ON_ERROR_STOP=1'];
 if(process.env.MFG_TEST_DOCKER){if(process.env.MFG_TEST_DOCKER!=='core10-np05a-disposable')throw Error('DISPOSABLE_CONTAINER_ONLY');command='docker';const db=process.env.PGDATABASE||'postgres';if(!/^(postgres|np05a_[a-z0-9_]+)$/.test(db))throw Error('DISPOSABLE_DATABASE_ONLY');args=['exec','-i','-e','PGUSER=postgres','-e','PGDATABASE='+db,process.env.MFG_TEST_DOCKER,'psql',...args.slice(1)];}
 else if(!['127.0.0.1','localhost'].includes(process.env.PGHOST))throw Error('LOOPBACK_DATABASE_ONLY');
 const r=spawnSync(command,args,{input:sql,encoding:'utf8'});if(r.status!==0)throw Error(r.stderr||r.error?.message);return r.stdout.trim();
}
function literal(s){let tag;do{tag='$m'+crypto.randomBytes(6).toString('hex')+'$';}while(s.includes(tag));return tag+s+tag;}
async function start(){
 const sig=JSON.parse(psql(`SELECT json_object_agg(proname,args) FROM (SELECT p.proname,json_agg(json_build_object('n',a.n,'t',format_type(a.t,NULL)) ORDER BY a.o) args FROM pg_proc p CROSS JOIN LATERAL unnest(p.proargnames,p.proargtypes::oid[]) WITH ORDINALITY a(n,t,o) WHERE p.pronamespace='core10'::regnamespace AND p.proname LIKE 'mfg_%' GROUP BY p.proname)s`));
 const server=http.createServer((req,res)=>{
  const send=(s,b,type='application/json')=>{res.writeHead(s,{'content-type':type,'cache-control':'no-store'});res.end(typeof b==='string'?b:JSON.stringify(b));};
  const url=new URL(req.url,'http://127.0.0.1');
  if(req.method==='GET'&&url.pathname==='/harness.html')return send(200,`<!doctype html><html lang="bn"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/core10-control-studio.css"><link rel="stylesheet" href="/core10-operational-flow.css"><link rel="stylesheet" href="/modules/manufacturing/manufacturing.css"><main id="manufacturing"></main><script type="module" src="/harness.mjs"></script></html>`,'text/html; charset=utf-8');
  if(req.method==='GET'&&url.pathname==='/harness.mjs')return send(200,`import {mountManufacturing} from '/modules/manufacturing/workbench.mjs'; const persona=new URLSearchParams(location.search).get('persona')||'95222222-2222-4222-8222-222222222222'; window.disposeMfg=mountManufacturing(document.querySelector('#manufacturing'),{synthetic:true,context:{tenant_id:951,business_id:9511,site_id:9521,label:'Fictional Sandesh QA'},rpc:async(name,args)=>{const r=await fetch('/rpc/'+name,{method:'POST',headers:{'content-type':'application/json','x-test-persona':persona},body:JSON.stringify(args)});const data=await r.json();return r.ok?{data}:{error:data};}});`,'application/javascript');
  if(req.method==='GET'&&(url.pathname.startsWith('/modules/manufacturing/')||['/core10-control-studio.css','/core10-operational-flow.css'].includes(url.pathname))){const file=path.resolve(root,'.'+url.pathname);if(!file.startsWith(root+'/')||!fs.existsSync(file))return send(404,{});return send(200,fs.readFileSync(file,'utf8'),file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'application/javascript');}
  if(req.method==='POST'&&url.pathname.startsWith('/rpc/')){
   const name=url.pathname.slice(5),persona=String(req.headers['x-test-persona']||'');if(!allowed.has(name)||!/^95[0-9a-f-]{34}$/.test(persona))return send(400,{message:'TEST_RPC_OR_PERSONA_DENIED'});
   let raw='';req.on('data',c=>{raw+=c;if(raw.length>65536)req.destroy();});req.on('end',()=>{try{const args=JSON.parse(raw),params=(sig[name]||[]).map(a=>a.n+'=>'+(args[a.n]===null?'NULL':literal(typeof args[a.n]==='object'?JSON.stringify(args[a.n]):String(args[a.n])))+'::'+a.t);
    const out=psql(`SET ROLE authenticated; DO $test$ BEGIN PERFORM set_config('request.jwt.claims',${literal(JSON.stringify({sub:persona}))},false); END $test$; SELECT core10.${name}(${params.join(',')});`);send(200,JSON.parse(out.split('\n').at(-1)));
   }catch(e){send(400,{message:(e.message.match(/ERROR:\s+(.*)/)||[])[1]||e.message});}});return;
  }send(404,{});
 });await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));return server;
}
module.exports={start,psql};
