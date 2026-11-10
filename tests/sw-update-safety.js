// Offline-safety test for sw.js. Serves the repo root locally, installs the worker, then simulates an UPDATE
// where one precache asset fails (HTTP 500), then goes OFFLINE and reloads. PASS = old cache kept + app opens offline.
// Usage: NODE_PATH=$(npm root -g) node tests/sw-update-safety.js [path-to-sw.js]   (default: ./sw.js)
const http=require('http'),fs=require('fs'),path=require('path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'..'),swFile=path.resolve(process.argv[2]||path.join(root,'sw.js'));
const types={'.js':'text/javascript','.html':'text/html','.css':'text/css','.json':'application/json','.svg':'image/svg+xml','.webp':'image/webp','.webmanifest':'application/manifest+json'};
let swVersionTag='A',failMatch=null;
const server=http.createServer((q,r)=>{const u=new URL(q.url,'http://x');let p=decodeURIComponent(u.pathname);if(p==='/')p='/index.html';
  if(failMatch&&(u.pathname+u.search).includes(failMatch)){r.statusCode=500;return r.end('fail');}
  if(p==='/sw.js'){let s=fs.readFileSync(swFile,'utf8');if(swVersionTag==='B')s=s.replace(/const VERSION="([^"]+)"/,'const VERSION="$1-v2"');r.setHeader('content-type','text/javascript');r.setHeader('cache-control','no-store');return r.end(s);}
  const f=path.join(root,p);if(!f.startsWith(root)||!fs.existsSync(f)||fs.statSync(f).isDirectory()){r.statusCode=404;return r.end('nf');}
  r.setHeader('content-type',types[path.extname(f)]||'application/octet-stream');r.setHeader('cache-control','no-store');r.end(fs.readFileSync(f));});
(async()=>{await new Promise(r=>server.listen(0,r));const base='http://localhost:'+server.address().port+'/';
  const b=await chromium.launch();const ctx=await b.newContext();const p=await ctx.newPage();
  await p.goto(base,{waitUntil:'load'});
  await p.evaluate(()=>navigator.serviceWorker.register('/sw.js'));
  await p.waitForFunction(()=>navigator.serviceWorker.controller||false,null,{timeout:15000}).catch(()=>{});
  await p.evaluate(()=>navigator.serviceWorker.ready);await p.waitForTimeout(3000);
  const s1=await p.evaluate(async()=>{const k=await caches.keys();const out={};for(const n of k){out[n]=(await (await caches.open(n)).keys()).length}return out});
  console.log('after install, caches:',JSON.stringify(s1));
  swVersionTag='B';failMatch=process.env.FAIL||'index.html';   // new version published, but this download fails
  const upd=await p.evaluate(async()=>{const r=await navigator.serviceWorker.getRegistration();try{await r.update();}catch(e){return 'update threw: '+e.message}await new Promise(x=>setTimeout(x,4000));return 'waiting='+!!r.waiting+' installing='+!!r.installing});
  console.log('update attempt with failing asset:',upd);
  const s2=await p.evaluate(async()=>{const k=await caches.keys();const out={};for(const n of k){out[n]=(await (await caches.open(n)).keys()).length}return out});
  console.log('after failed update, caches:',JSON.stringify(s2));
  failMatch=null;await ctx.setOffline(true);
  let offlineOk=false,title='';try{await p.reload({waitUntil:'load',timeout:15000});title=await p.title();offlineOk=/ইসলামিয়া|ISLAMIYA|CORE/i.test(title);}catch(e){title='ERR '+e.message.slice(0,60)}
  console.log('offline reload title:',JSON.stringify(title));
  const oldKept=Object.keys(s1).some(n=>s2[n]>0);
  console.log(offlineOk&&oldKept?'RESULT: PASS (old cache kept, app opens offline)':'RESULT: FAIL (oldCacheKept='+oldKept+', offlineOpens='+offlineOk+')');
  await b.close();server.close();process.exit(offlineOk&&oldKept?0:1);})().catch(e=>{console.log('ERR',e.message);process.exit(2)});
