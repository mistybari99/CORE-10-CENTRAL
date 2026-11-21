'use strict';
// Adapted from tests/control-centre/sql-gateway.cjs. TEST-ONLY loopback gateway:
// real PG17 functions under authenticated + inert UUID claims, NOT GoTrue/JWT.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');const ROOT=path.resolve(__dirname,'../..');
const RPCS={
 read_sales_invoice_drafts_v1:[['p_business','bigint'],['p_site','bigint'],['p_invoice','bigint']],
 save_sales_invoice_draft_v1:[['p_business','bigint'],['p_site','bigint'],['p_invoice','bigint'],['p_expected','bigint'],['p_order','bigint'],['p_order_version','bigint'],['p_lines','jsonb'],['p_memo','text'],['p_key','text']],
 validate_sales_invoice_draft_v1:[['p_business','bigint'],['p_site','bigint'],['p_invoice','bigint'],['p_expected','bigint'],['p_approval','bigint'],['p_key','text']],
 master_list_items_v1:[['p_business','bigint'],['p_search','text'],['p_status','text'],['p_category','bigint'],['p_limit','integer'],['p_after_id','bigint']],
 master_list_parties_v1:[['p_business','bigint'],['p_kind','text'],['p_search','text'],['p_status','text'],['p_limit','integer'],['p_after_id','bigint']],
 master_list_uoms_v1:[['p_business','bigint']],
 master_list_price_lists_v1:[['p_business','bigint'],['p_kind','text']],
 master_get_price_list_v1:[['p_business','bigint'],['p_price_list','bigint'],['p_limit','integer'],['p_after_id','bigint']],
 build01_context_v1:[],build01_workspace_v1:[['p_business','bigint']],mfg_inspect_v1:[['p_business','bigint'],['p_site','bigint']],control_read_v1:[['p_business','bigint'],['p_site','bigint']],
 read_sales_orders_v1:[['p_business','bigint'],['p_site','bigint'],['p_order','bigint']],
 read_sales_order_audit_v1:[['p_business','bigint'],['p_site','bigint'],['p_order','bigint']],
 save_sales_order_v1:[['p_business','bigint'],['p_site','bigint'],['p_order','bigint'],['p_expected','bigint'],['p_document','jsonb'],['p_key','text']],
 transition_sales_order_v1:[['p_business','bigint'],['p_site','bigint'],['p_order','bigint'],['p_action','text'],['p_expected','bigint'],['p_approval','bigint'],['p_key','text']]
};
const FILES=['core10-control-studio.css','core10-build01.css','core10-sales-order.css','core10-sales-order-client.js','core10-sales-order-ui.js','core10-sales-order-entry.js','core10-sales-invoice-ui.js'];
function sql(s){const box=process.env.NP03B_TEST_CONTAINER;if(box&&!/^core10-np03b-[a-z0-9-]+$/.test(box))throw Error('BAD_TEST_CONTAINER');
 const args=box?['exec','-i','-e','PGUSER=postgres','-e','PGDATABASE='+process.env.PGDATABASE,box,'psql','-X','-q','-At','-v','ON_ERROR_STOP=1']:['-X','-q','-At','-v','ON_ERROR_STOP=1'];
 return spawnSync(box?'docker':'psql',args,{input:s,encoding:'utf8',env:process.env});}
function quote(s){let tag;do{tag='$np'+crypto.randomBytes(6).toString('hex')+'$';}while(s.includes(tag));return tag+s+tag;}
function start(port=0){
 if(!['127.0.0.1','localhost'].includes(process.env.PGHOST)||!/^core10_np03b_(ci|local)/.test(process.env.PGDATABASE||''))throw Error('NP03B_LOOPBACK_DISPOSABLE_ONLY');
 const check=sql("SELECT current_setting('server_version_num')::int BETWEEN 170000 AND 179999 AND current_database() ~ '^core10_np03b_(ci|local)' AND to_regclass('auth.users') IS NULL;");if(check.status!==0||check.stdout.trim()!=='t')throw Error('NP03B_PG17_NO_AUTH_USERS_REQUIRED');
 const server=http.createServer((req,res)=>{const url=new URL(req.url,'http://127.0.0.1');
  function send(status,body,type='application/json'){res.writeHead(status,{'content-type':type,'cache-control':'no-store','content-security-policy':"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'"});res.end(typeof body==='string'?body:JSON.stringify(body));}
  if(req.method==='GET'&&url.pathname==='/harness.html'){
   let html=fs.readFileSync(path.join(ROOT,'core10-build01.html'),'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'');
   html=html.replace(/<main\b[^>]*>[\s\S]*?<\/main>/i,'<main id="b01-main"><p class="muted">LOCAL TEST HARNESS · inert UUID claims, canonical Master + synthetic fixtures; not GoTrue or hosted backend</p><div id="sales-host"></div></main>')
    .replace('</head>','<link rel="stylesheet" href="/core10-sales-order.css"></head>')
    .replace('</body>','<script src="/core10-sales-master-catalog.js"></script><script src="/core10-sales-order-client.js"></script><script src="/core10-sales-order-ui.js"></script><script src="/core10-sales-invoice-ui.js"></script><script src="/core10-sales-order-entry.js"></script><script src="/harness.js"></script></body>');
   return send(200,html,'text/html; charset=utf-8');
  }
  if(req.method==='GET'&&url.pathname==='/harness.js')return send(200,fs.readFileSync(path.join(__dirname,'ui-harness.js'),'utf8'),'application/javascript');
  const file=url.pathname.slice(1);if(req.method==='GET'&&(FILES.includes(file)||file==='core10-sales-master-catalog.js'))return send(200,fs.readFileSync(path.join(ROOT,file),'utf8'),file.endsWith('.css')?'text/css':'application/javascript');
  if(req.method==='POST'&&url.pathname.startsWith('/rpc/')){
   const name=url.pathname.slice(5),persona=String(req.headers['x-test-persona']||'');if(!Object.hasOwn(RPCS,name))return send(404,{message:'RPC_NOT_ALLOWED'});
   if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(persona))return send(403,{message:'SALES_SCOPE_DENIED'});
   let raw='';req.on('data',b=>{raw+=b;if(raw.length>262144)req.destroy();});req.on('end',()=>{let args;try{args=JSON.parse(raw||'{}');}catch{return send(400,{message:'BAD_JSON'});}
    if(!args||typeof args!=='object'||Array.isArray(args)||Object.keys(args).some(k=>!RPCS[name].some(([n])=>n===k)))return send(400,{message:'BAD_ARGS'});
    const params=RPCS[name].filter(([n])=>Object.hasOwn(args,n)).map(([n,t])=>n+' => '+(args[n]===null?'NULL':quote(typeof args[n]==='object'?JSON.stringify(args[n]):String(args[n])))+'::'+t).join(',');
    const r=sql(`SET ROLE authenticated; DO $test$ BEGIN PERFORM set_config('request.jwt.claim.sub',${quote(persona)},false); END $test$; SELECT to_jsonb(core10.${name}(${params}));`);
    if(r.status!==0)return send(400,{message:(r.stderr.match(/ERROR:\s+(.*)/)||[])[1]||'RPC_FAILED'});
    try{return send(200,JSON.parse(r.stdout.trim().split('\n').at(-1)));}catch{return send(500,{message:'BAD_SQL_RESPONSE'});}
   });return;
  }send(404,{message:'NOT_FOUND'});
 });return new Promise(resolve=>server.listen(port,'127.0.0.1',()=>resolve(server)));
}
module.exports={start,sql};
if(require.main===module)start(Number(process.env.PORT||58219)).then(s=>console.log('NP03B local test gateway:',s.address().port));
