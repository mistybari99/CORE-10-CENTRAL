import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)), src=path.resolve(dir,'../migrations');
const m=JSON.parse(fs.readFileSync(path.join(dir,'manifest.json'),'utf8'));
assert.equal(m.baseline_count,20);assert.equal(m.source_count,71);assert.equal(m.through_version,504);
const actual=fs.readdirSync(dir).filter(f=>f.endsWith('.sql')).sort();
assert.deepEqual(actual,m.groups.map(g=>g.file));
const originals=fs.readdirSync(src).filter(f=>/^\d{4}_.+\.up\.sql$/.test(f)&&Number(f.slice(0,4))<=m.through_version).sort();
assert.equal(originals.length,m.source_count);
const used=[];let bytes=0;
for(const [i,g] of m.groups.entries()){
 assert.equal(g.file.slice(0,2),String(i+1).padStart(2,'0'));
 const files=originals.filter(f=>Number(f.slice(0,4))>=g.from&&Number(f.slice(0,4))<=g.to);
 assert.ok(files.length>0);used.push(...files);
 const parts=files.map(f=>{const raw=fs.readFileSync(path.join(src,f));const sql=raw.toString('utf8');assert.ok(Buffer.from(sql).equals(raw)&&sql.endsWith('\n'));const sum=crypto.createHash('sha256').update(raw).digest('hex');const n=f.slice(0,-7);return '-- CORE10 BASELINE SOURCE '+f+' SHA256 '+sum+'\n'+sql+'INSERT INTO core10.schema_migrations(version,name,checksum) VALUES('+Number(f.slice(0,4))+",'"+n+"','"+sum+"');\n";});
 const expected='-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.\n'+parts.join('\n');
 const got=fs.readFileSync(path.join(dir,g.file));assert.deepEqual(got,Buffer.from(expected),g.file+' drift');bytes+=got.length;
 console.log(g.file+' '+files.length+' originals '+got.length+' bytes');
}
assert.deepEqual(used,originals,'source coverage/order/duplication');
console.log('BASELINE20_EXACT_71_OF_71_OK '+bytes+' bytes');
