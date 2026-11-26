'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process'),ROOT=path.resolve(__dirname,'..');
const git=(...args)=>execFileSync('git',args,{cwd:ROOT,encoding:'utf8'}).trim();
const info=require('../docs/coordination/STOCK_PAPEROPS_FORWARD_PORT_20261126.json');
test('exact 12 forward-renumbered migration blobs and eight Stock regression files',()=>{
 assert.equal(info.migration_map.length,12);
 assert.equal(info.stock_tests.length,8);
 for(const e of [...info.migration_map,...info.stock_tests])assert.equal(git('hash-object',e.path),e.sha,e.path);
 for(const e of info.migration_map)assert.ok(!fs.existsSync(path.join(ROOT,e.original)),'duplicate old version '+e.original);
 assert.equal(git('rev-parse','HEAD:modules/paperops'),info.paperops_tree);
});
test('preserve 1000/246 unique original field IDs and nonposting boundary',()=>{
 const m=require('../modules/paperops/field-review/ownership-246-1000.json');
 const a=m.lane_A_codex.ownership_keys,b=[...m.lane_B_chatgpt.critical_86_keys,...m.lane_B_chatgpt.mapped_150_keys,...m.lane_B_chatgpt.reserved_next_10_keys];
 assert.equal(a.length,1000);assert.equal(b.length,246);assert.equal(new Set([...a,...b]).size,1246);
 assert.equal(a[303],'R-01:cashier');assert.deepEqual(a.slice(919,922),['F-03:name','F-03:qty','F-03:unit']);
 const frozen=fs.readFileSync(path.join(ROOT,'legacy/islamia-erp/forms_factory.js'),'utf8');
 for(const x of ['b("a",null,O(),{min:4})','b("b",null,O(),{min:5})','b("c",null,O(),{min:2})'])assert.ok(frozen.includes(x));
 const adapter=fs.readFileSync(path.join(ROOT,'modules/paperops/field-review/chatgpt-246/w02-canonical-stock-review.cjs'),'utf8');
 for(const x of ['CORE10.W02.REGISTRY.V2','W02_CONTROL_OBSERVATION_CHANGED','W02_VERIFIED_POSTING_DISABLED','canPost: false'])assert.ok(adapter.includes(x),x);
 const names=fs.readdirSync(path.join(ROOT,'internal/migrations'));
 for(let i=0;i<=5;i++)for(const suffix of ['.up.sql','.down.sql'])assert.equal(names.filter(n=>n.startsWith('030'+i+'_')&&n.endsWith(suffix)).length,1);
});
