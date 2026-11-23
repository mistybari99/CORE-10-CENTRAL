'use strict';
/* Literal, pinned reconstruction of the frozen IMG form visibility helpers.
 * Old source is READ ONLY and is NEVER executed. All outputs are UI/source
 * condition suggestions, never signed authentication or posting permission.
 */
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const ROOT=path.resolve(__dirname,'../../../..');
const PIN=Object.freeze({
  forms:'f2cb1c5e09210496106ace1bf33ddc40d2d6df1d',
  entry:'402eba6436f0e619ebcbd15bb99c7c3cd0853585'
});
const EXACT=Object.freeze({
  formAlias:'r=e.num,n=e.has,s=e.sum',
  formO:'O=e=>t=>!t.cf||n(t.d[e])',
  entryHas:'$=e=>!(null==e||""===e||!1===e)',
  entryBind:'t.num=y,t.has=$,t.sum=w'
});
function gitBlob(bytes){
  return crypto.createHash('sha1').update('blob '+bytes.length+'\0').update(bytes).digest('hex');
}
function sourceFile(name){
  for(const dir of ['legacy/islamia-erp','']){
    const f=path.join(ROOT,dir,name);
    if(fs.existsSync(f))return fs.readFileSync(f);
  }
  throw Error('FROZEN_SOURCE_MISSING:'+name);
}
function verifyEvidence(forms=sourceFile('forms.js'),entry=sourceFile('entry.js')){
  const a=Buffer.isBuffer(forms)?forms:Buffer.from(forms);
  const b=Buffer.isBuffer(entry)?entry:Buffer.from(entry);
  if(gitBlob(a)!==PIN.forms||gitBlob(b)!==PIN.entry)
    throw Error('FROZEN_SOURCE_BLOB_CHANGED');
  const f=a.toString('utf8'),e=b.toString('utf8');
  if(!f.includes(EXACT.formAlias)||!f.includes(EXACT.formO)||
     !e.includes(EXACT.entryHas)||!e.includes(EXACT.entryBind))
    throw Error('FROZEN_OLD_HELPER_EXPRESSION_CHANGED');
  return Object.freeze({formsBlob:PIN.forms,entryBlob:PIN.entry,
    hasRecovered:true,oRecovered:true,executedLegacy:false,
    sourceRuleVerified:true,ownerApproved:false,erpPostAuthorized:false});
}
// Original entry.js: $=e=>!(null==e||""===e||!1===e).
// IMPORTANT: zero, whitespace and empty arrays count as PRESENT in the old source.
function legacyHas(v){return !(v==null||v===''||v===false);}
function oldO(field,normal){
  if(!['cash_now','open_counted','imp_cash'].includes(field))
    throw Error('SOURCE_FIELD_NOT_OWNED_BY_HELPER_GATE');
  if(!normal||typeof normal!=='object'||Array.isArray(normal)||typeof normal.cf!=='boolean')
    return Object.freeze({visible:null,why:'UNKNOWN_COUNT_FIRST'});
  if(normal.cf===false)return Object.freeze({visible:true,why:'SOURCE_COUNT_FIRST_DISABLED'});
  const data=normal.sourceData;
  if(!data||typeof data!=='object'||Array.isArray(data)||
     !Object.prototype.hasOwnProperty.call(data,field))
    return Object.freeze({visible:null,why:'RAW_SOURCE_FIELD_NOT_OBSERVED'});
  return Object.freeze({visible:legacyHas(data[field]),why:'EXACT_PINNED_N_AND_O_HELPERS'});
}
module.exports={PIN,EXACT,verifyEvidence,legacyHas,oldO};
