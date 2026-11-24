'use strict';
// Read-only release-candidate provenance guard; never evaluates frozen JavaScript.
// This pinned transfer can be updated only after reviewing the source and migration
// deltas, not by moving or resetting the shared integration trunk.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {execFileSync}=require('node:child_process');
const fs=require('node:fs');
const path=require('node:path');
const ROOT=path.resolve(__dirname,'..');
const git=(...args)=>execFileSync('git',args,{cwd:ROOT,encoding:'utf8'}).trim();
const read=(file)=>fs.readFileSync(path.join(ROOT,file),'utf8');

test('selective PaperOps subtree matches the exact verified #154 source tree',()=>{
  assert.equal(git('rev-parse','HEAD:modules/paperops'),'e368ee6c818286a945ab758a4e406e08fbecdec3');
  assert.equal(git('hash-object','modules/paperops/field-review/ownership-246-1000.json'),
    '458046bb79773c65565d92a4d2d4dd1a243332cc');
  for(const [p,pin] of [
    ['internal/migrations/0211_np03a_w02_custody_registry.up.sql','2c0837186d215a4a65f4a225058ce7a2ac574fd0'],
    ['internal/migrations/0211_np03a_w02_custody_registry.down.sql','858eacf61c13857782c4f64e6a2a6833e6ea1282'],
    ['.github/workflows/paperops-canonical-port.yml','a3cd68128304ef3c9288d5a104638937328240a3']
  ]) assert.equal(git('hash-object',p),pin,p+' changed during selective port');
});

test('1246 distinct original field IDs and both cross-form corrections survive unchanged',()=>{
  const manifest=JSON.parse(read('modules/paperops/field-review/ownership-246-1000.json'));
  const a=manifest.lane_A_codex.ownership_keys;
  const b=[...manifest.lane_B_chatgpt.critical_86_keys,
    ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys];
  assert.equal(a.length,1000);
  assert.equal(b.length,246);
  assert.equal(new Set([...a,...b]).size,1246);
  assert.equal(a[303],'R-01:cashier');
  assert.deepEqual(a.slice(919,922),['F-03:name','F-03:qty','F-03:unit']);
  const frozen=read('legacy/islamia-erp/forms_factory.js');
  for(const use of ['b("a",null,O(),{min:4})','b("b",null,O(),{min:5})',
    'b("c",null,O(),{min:2})']) assert.ok(frozen.includes(use),'source helper consumer missing');
});

test('newest trunk Sales migrations and protected W02 nonposting policy boundary remain present',()=>{
  const names=fs.readdirSync(path.join(ROOT,'internal/migrations'));
  for(let i=0;i<=5;i++){
    const prefix='030'+i+'_';
    assert.equal(names.filter(n=>n.startsWith(prefix)&&n.endsWith('.up.sql')).length,1,prefix+' up');
    assert.equal(names.filter(n=>n.startsWith(prefix)&&n.endsWith('.down.sql')).length,1,prefix+' down');
  }
  const adapter=read('modules/paperops/field-review/chatgpt-246/w02-canonical-stock-review.cjs');
  for(const marker of ['CORE10.W02.REGISTRY.V2','W02_CONTROL_OBSERVATION_CHANGED',
    'W02_VERIFIED_POSTING_DISABLED','canPost: false'])
    assert.ok(adapter.includes(marker),'policy/replay nonposting gate missing: '+marker);
  const registry=read('internal/migrations/0211_np03a_w02_custody_registry.up.sql');
  assert.ok(registry.includes('REVOKE ALL ON FUNCTION core10.w02_custody_snapshot_v1'));
  assert.ok(registry.includes('TO authenticated;'));
});
