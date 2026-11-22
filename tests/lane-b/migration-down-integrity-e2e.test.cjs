'use strict';
// Isolated Lane B mock-psql integration: never connects to a hosted database.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const cp=require('node:child_process');
const crypto=require('node:crypto');
const runner=fs.readFileSync(path.join(__dirname,'../../internal/migrations/run.sh'),'utf8');
function scenario({drift=false,missingDown=false,missingUp=false}={}) {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'core10-down-'));
 try {
  const migrations=path.join(dir,'migrations'); fs.mkdirSync(migrations);
  fs.writeFileSync(path.join(migrations,'run.sh'),runner);
  const name='0206_test'; const up='select 1;\n';
  if(!missingUp) fs.writeFileSync(path.join(migrations,name+'.up.sql'),drift?'select 2;\n':up);
  if(!missingDown) fs.writeFileSync(path.join(migrations,name+'.down.sql'),'select 1;\n');
  const bin=path.join(dir,'bin'); fs.mkdirSync(bin);
  const psql=path.join(bin,'psql');
  fs.writeFileSync(psql,`#!/bin/sh
case " $* " in
 *"select 1"*) echo 1;;
 *"to_regclass("*) echo t;;
 *"select version from core10.schema_migrations"*) echo 206;;
 *"select name from core10.schema_migrations"*) echo 0206_test;;
 *"select checksum from core10.schema_migrations"*) echo '${crypto.createHash('sha256').update(up).digest('hex')}';;
 *) echo invoked >> '${path.join(dir,'writes')}';;
esac
`); fs.chmodSync(psql,0o755);
  const result=cp.spawnSync('bash',[path.join(migrations,'run.sh'),'down'],{encoding:'utf8',env:{...process.env,PATH:bin+':'+process.env.PATH,DATABASE_URL:''}});
  return {result,writes:fs.existsSync(path.join(dir,'writes'))};
 } finally {fs.rmSync(dir,{recursive:true,force:true});}
}
test('drift refuses rollback before any SQL write',()=>{const x=scenario({drift:true});assert.notEqual(x.result.status,0);assert.match(x.result.stderr,/CHECKSUM_DRIFT/);assert.equal(x.writes,false)});
test('missing UP refuses rollback before any SQL write',()=>{const x=scenario({missingUp:true});assert.notEqual(x.result.status,0);assert.match(x.result.stderr,/MISSING_UP/);assert.equal(x.writes,false)});
test('missing DOWN refuses rollback before any SQL write',()=>{const x=scenario({missingDown:true});assert.notEqual(x.result.status,0);assert.match(x.result.stderr,/MISSING_DOWN/);assert.equal(x.writes,false)});
test('matching checksum permits transactional rollback invocation',()=>{const x=scenario();assert.equal(x.result.status,0,x.result.stderr);assert.match(x.result.stdout,/rolled back 0206_test/);assert.equal(x.writes,true)});
