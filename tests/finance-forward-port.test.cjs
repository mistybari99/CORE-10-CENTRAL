'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{execFileSync}=require('node:child_process'),path=require('node:path');
const root=path.resolve(__dirname,'..'),m=require('../docs/coordination/FINANCE_FORWARD_PORT_20261126.json'),git=(...args)=>execFileSync('git',args,{cwd:root,encoding:'utf8'}).trim();
test('exact F3 and bridge migration blobs and immutable canonical baseline',()=>{assert.equal(m.migrations.length,12);for(const x of [...m.migrations,...m.test_source,m.bridge_test])assert.equal(git('hash-object',x.path),x.sha,x.path);for(const p of git('ls-tree','-r','--name-only',m.base,'internal/migrations').split('\n').filter(Boolean))assert.equal(git('hash-object',p),git('rev-parse',m.base+':'+p),p);});
