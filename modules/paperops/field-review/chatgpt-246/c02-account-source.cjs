'use strict';
/* C02-03 original moneySrc expense_10_2 provider condition; synthetic
 * source/tenant/account gate, never a signed Money account authorization.
 * C02-01 original blank pay_mode was historically documented as cash.
 * This stricter correction refuses a blank mode pending Owner policy.
 */
const {createHash}=require('node:crypto');
const frozen=require('./source-helper-conditions.cjs');
const manifest=require('../ownership-246-1000.json');
const OWN=new Set([...manifest.lane_B_chatgpt.critical_86_keys,
 ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
const FIELDS=['C-02:money_account_id','C-02:pay_mode'];
if(FIELDS.some(x=>!OWN.has(x)))throw Error('C02_OUTSIDE_EXCLUSIVE_246_SCOPE');
const ID=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
function id(x,label){if(typeof x!=='string'||!ID.test(x))throw Error('C02_INVALID_REF:'+label);return x;}
function scopeOf(s){if(!s||s.synthetic_only!==true||![s.tenantId,s.businessId,s.siteId].every(
 x=>typeof x==='string'&&x.startsWith('DEMO-')&&ID.test(x)))
 throw Error('C02_SYNTHETIC_SCOPE_ONLY');return s;}
function scoped(r,s,label){
 if(!r||r.tenantId!==s.tenantId||r.businessId!==s.businessId||r.siteId!==s.siteId)
  throw Error('C02_CROSS_TENANT_BUSINESS_SITE:'+label);
}
function assertSource(){
 const text=frozen.readFrozen('forms');frozen.verifyEvidence();
 const start=text.indexOf('e.forms["C-02"]='),end=text.indexOf('e.forms[',start+1);
 if(start<0)throw Error('C02_FROZEN_SOURCE_FORM_MISSING');
 const block=text.slice(start,end<0?text.length:end);
 const fragments=[
  '"money_account_id",t("Payment source","Payment source"),()=>e.moneySrc?e.moneySrc.formOpts("expense_10_2")():[]',
  'show:()=>!(!e.moneySrc||!e.moneySrc.hasAccounts("expense_10_2"))',
  '"pay_mode",t("কীভাবে দেওয়া হয়েছে (ফাঁকা = cash)","Paid how (empty = cash)")',
  '["cash",t("নগদ","Cash")]','["bank",t("ব্যাংক","Bank")]',
  '["mobile",t("মোবাইল","Mobile")]','["card",t("কার্ড","Card")]'
 ];
 for(const f of fragments)if(!block.includes(f))throw Error('C02_SOURCE_MONEY_PROVIDER_DRIFT:'+f);
 return Object.freeze({frozenBlob:frozen.PIN.forms,oldSourceExecuted:false,formOptsScope:'expense_10_2',
  sourceFields:FIELDS});
}
function reviewAccountSource({scope:raw,provider,voucher}={}){
 const provenance=assertSource(),s=scopeOf(raw);
 scoped(provider,s,'ACCOUNT_PROVIDER');scoped(voucher,s,'EXPENSE_VOUCHER');
 id(provider.sourceRef,'PROVIDER_SNAPSHOT');id(voucher.voucherRef,'C02_VOUCHER');
 if(provider.capability!=='expense_10_2')throw Error('C02_UNKNOWN_SOURCE_PROVIDER_ACTION');
 if(!Array.isArray(provider.options)||provider.options.length>200)
  throw Error('C02_ACCOUNT_PROVIDER_OPTIONS_REQUIRED');
 const blocked=[],flag=x=>{if(!blocked.includes(x))blocked.push(x);};
 const accounts=new Map(),sourceRefs=new Set([provider.sourceRef]);
 for(const row of provider.options){
  scoped(row,s,'PROVIDER_OPTION');
  id(row.accountId,'ACCOUNT');id(row.sourceRef,'ACCOUNT_PROOF');
  if(accounts.has(row.accountId)||sourceRefs.has(row.sourceRef))
   throw Error('C02_DUPLICATE_OR_REPLAYED_ACCOUNT_OPTION');
  accounts.set(row.accountId,row);sourceRefs.add(row.sourceRef);
  if(row.action!=='expense_10_2'||!['IMPREST_CASH','BUSINESS_BANK',
   'BUSINESS_MOBILE','BUSINESS_CARD','SALES_DRAWER'].includes(row.role))
   throw Error('C02_UNEXPECTED_PROVIDER_ACCOUNT_ROLE');
 }
 // A voucher is an independent source document. Never reuse the
 // provider snapshot or ANY option evidence reference, selected or not.
 if(sourceRefs.has(voucher.voucherRef))throw Error('C02_SOURCE_REFERENCE_COLLISION');
 // Original UI: hidden without moneySrc or when hasAccounts(scope) is false.
 // An empty snapshot is a safe *absence*, never invented as a default account.
 const actual=accounts.size>0;
 if(provider.hasAccounts!==actual)flag('C02_SOURCE_HAS_ACCOUNTS_DECLARATION_MISMATCH');
 if(!actual)flag('C02_SOURCE_ACCOUNT_OPTIONS_UNAVAILABLE');
 let selected=null;
 if(voucher.money_account_id===null||voucher.money_account_id===undefined||
    voucher.money_account_id==='')flag('C02_EXPLICIT_ACCOUNT_SELECTION_REQUIRED');
 else{
  id(voucher.money_account_id,'SELECTED_ACCOUNT');
  selected=accounts.get(voucher.money_account_id)||null;
  if(!selected)flag('C02_ACCOUNT_NOT_IN_ORIGINAL_PROVIDER_OPTIONS');
 }
 const kindMap={cash:'IMPREST_CASH',bank:'BUSINESS_BANK',
  mobile:'BUSINESS_MOBILE',card:'BUSINESS_CARD'};
 const mode=voucher.pay_mode;
 if(mode===null||mode===undefined||mode==='')flag('C02_EMPTY_PAYMENT_MODE_OWNER_DECISION_REQUIRED');
 else if(!Object.prototype.hasOwnProperty.call(kindMap,mode))
  throw Error('C02_UNSUPPORTED_PAYMENT_MODE');
 if(selected){
  if(selected.role==='SALES_DRAWER')flag('C02_SALES_DRAWER_PAYMENT_FORBIDDEN');
  if(selected.status!=='ACTIVE')flag('C02_INACTIVE_ACCOUNT_NOT_ALLOWED');
  if(selected.canExpense!==true)flag('C02_EXPENSE_ACCOUNT_CAPABILITY_NOT_GRANTED');
  if(kindMap[mode]&&selected.role!==kindMap[mode])flag('C02_PAYMENT_MODE_ACCOUNT_ROLE_MISMATCH');
 }
 if(voucher.salesDrawerUntouched!==true)flag('C02_SALES_DRAWER_PROTECTION_NOT_ATTESTED');
 const e={scope:{tenantId:s.tenantId,businessId:s.businessId,siteId:s.siteId},
  providerSourceRef:provider.sourceRef,providerHasAccounts:provider.hasAccounts,
  options:provider.options,voucher};
 return Object.freeze({sourceFields:provenance.sourceFields.slice(),status:blocked.length?
 'BLOCK':'REVIEW_READY_NOT_APPROVED',blockers:Object.freeze(blocked),
  evidence:Object.freeze({visibleByOriginalProviderRule:actual,accountCount:accounts.size,
   selectedAccountId:selected?.accountId||null,paymentMode:mode||null,
   sourceDigest:createHash('sha256').update(JSON.stringify(e)).digest('hex'),
   originalSourceBlob:provenance.frozenBlob}),
  syntheticOnly:true,originalProviderExecuted:false,providerSignatureAuthenticated:false,
  canonicalMoneyAccountReadVerified:false,signedPermissionVerified:false,
  sourceParityCertified:false,ownerPolicyAccepted:false,canPost:false});
}
module.exports={reviewAccountSource,assertSource};
