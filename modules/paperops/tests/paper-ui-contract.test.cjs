'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const folder=path.resolve(__dirname,'..');
function read(file){return fs.readFileSync(path.join(folder,file),'utf8');}
function scripts(html){
  const external=[...html.matchAll(/<script\s+src="([^"]+)"\s*><\/script>/g)].map(m=>m[1]);
  const inline=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
  return {external,inline};
}
test('both printable studio pages have syntactically valid inline JavaScript',()=>{
  for(const name of ['index.html','kit.html']){
    const x=scripts(read(name));
    assert.equal(x.inline.length,1,'one init script per page');
    assert.doesNotThrow(()=>new vm.Script(x.inline[0],{filename:name}),name+' invalid JS');
    assert.equal(x.external[0],'./paperops.js');
    assert.equal(x.external[1],'./form-packs.js');
    if(name==='kit.html')assert.equal(x.external[2],'./paper-kit.js');
    for(const src of x.external){
      assert.match(src,/^\.\/[a-z-]+\.js$/);
      assert.ok(fs.existsSync(path.join(folder,src)));
    }
  }
});
test('print pages stay offline and no remote scripts or tracking are injected',()=>{
  for(const name of ['index.html','kit.html']){
    const page=read(name);
    assert.match(page,/@media print/);
    assert.match(page,/@page\s*\{size:A4/);
    assert.doesNotMatch(page,/<(?:iframe|script|img)[^>]+src=["']https?:/i);
    assert.doesNotMatch(page,/fetch\s*\(|XMLHttpRequest|\.rpc\(|supabase\.co|analytics\./i);
  }
});
test('each form candidate and industry overlay remains print-only and needs field signoff',()=>{
  const src=read('form-packs.js');
  const api=require('../paperops.js');require('../form-packs.js');
  assert.equal(api.TEMPLATES.length, 32);
  assert.equal(api.TEMPLATES.filter(x=>x.status==='hypothesis').length,9); // original paint + eight new industries
  for(const form of api.TEMPLATES){
    assert.ok(['draft','hypothesis'].includes(form.status),form.id);
    assert.ok(form.rule.bn.length>10,form.id);
    assert.ok(form.rule.en.length>10,form.id);
    assert.ok(form.signatures.length>0,form.id);
  }
  assert.doesNotMatch(src,/(?:XMLHttpRequest|\.rpc\(|fetch\s*\()/);
});
