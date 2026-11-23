'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {reviewAccountSource,assertSource}=require('../field-review/chatgpt-246/c02-account-source.cjs');
const manifest=require('../field-review/ownership-246-1000.json');
const S={tenantId:'DEMO-TENANT-01',businessId:'DEMO-SHOP',siteId:'DEMO-SITE1'};
const scoped=r=>({...S,...r});
function sample(){
 return {scope:{...S,synthetic_only:true},
  provider:scoped({sourceRef:'DEMO-ACCOUNT-OPTIONS-SNAPSHOT',capability:'expense_10_2',
    hasAccounts:true,options:[scoped({accountId:'DEMO-IMP-01',sourceRef:'DEMO-SIGNED-OPTION-01',
     role:'IMPREST_CASH',action:'expense_10_2',status:'ACTIVE',canExpense:true}),
    scoped({accountId:'DEMO-BANK-01',sourceRef:'DEMO-SIGNED-OPTION-02',
     role:'BUSINESS_BANK',action:'expense_10_2',status:'ACTIVE',canExpense:true})]}),
  voucher:scoped({voucherRef:'DEMO-C02-101',money_account_id:'DEMO-IMP-01',
    pay_mode:'cash',salesDrawerUntouched:true})};
}
const edit=f=>{const x=sample();f(x);return reviewAccountSource(x);};
test('C02 money_account_id old formOpts/hasAccounts expression is source pinned, not executed',()=>{
 const p=assertSource();assert.equal(p.oldSourceExecuted,false);
 assert.equal(p.formOptsScope,'expense_10_2');
 for(const id of p.sourceFields)assert.ok(manifest.lane_B_chatgpt.mapped_150_keys.includes(id));
 const r=edit(()=>{});
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED');
 assert.equal(r.evidence.visibleByOriginalProviderRule,true);
 assert.equal(r.evidence.accountCount,2);
 assert.equal(r.evidence.selectedAccountId,'DEMO-IMP-01');
 assert.equal(r.evidence.sourceDigest,edit(()=>{}).evidence.sourceDigest);
 assert.equal(r.canPost,false);assert.equal(r.canonicalMoneyAccountReadVerified,false);
 assert.equal(r.providerSignatureAuthenticated,false);
});
test('C02 one account may serve cash imprest, while bank needs explicitly matching role',()=>{
 const bank=edit(x=>{x.voucher.money_account_id='DEMO-BANK-01';x.voucher.pay_mode='bank'});
 assert.equal(bank.status,'REVIEW_READY_NOT_APPROVED');
 assert.ok(edit(x=>{x.voucher.money_account_id='DEMO-BANK-01'})
  .blockers.includes('C02_PAYMENT_MODE_ACCOUNT_ROLE_MISMATCH'));
 assert.ok(edit(x=>{x.provider.options[0].role='SALES_DRAWER'})
  .blockers.includes('C02_SALES_DRAWER_PAYMENT_FORBIDDEN'));
});
test('C02 missing provider options, mismatched hasAccounts and no account do not default to live',()=>{
 const r=edit(x=>{x.provider.options=[];x.provider.hasAccounts=false;x.voucher.money_account_id=null});
 assert.equal(r.evidence.visibleByOriginalProviderRule,false);
 assert.equal(r.status,'BLOCK');
 assert.ok(r.blockers.includes('C02_SOURCE_ACCOUNT_OPTIONS_UNAVAILABLE'));
 assert.ok(r.blockers.includes('C02_EXPLICIT_ACCOUNT_SELECTION_REQUIRED'));
 assert.ok(edit(x=>{x.provider.hasAccounts=false})
  .blockers.includes('C02_SOURCE_HAS_ACCOUNTS_DECLARATION_MISMATCH'));
 assert.ok(edit(x=>{x.voucher.money_account_id='DEMO-NOT-OFFERED'})
  .blockers.includes('C02_ACCOUNT_NOT_IN_ORIGINAL_PROVIDER_OPTIONS'));
});
test('C02 old blank cash payment mode is held pending Owner policy, never inferred as bank/cash',()=>{
 const r=edit(x=>{x.voucher.pay_mode=''});
 assert.equal(r.status,'BLOCK');
 assert.ok(r.blockers.includes('C02_EMPTY_PAYMENT_MODE_OWNER_DECISION_REQUIRED'));
 assert.ok(edit(x=>{x.voucher.salesDrawerUntouched=false})
  .blockers.includes('C02_SALES_DRAWER_PROTECTION_NOT_ATTESTED'));
 assert.ok(edit(x=>{x.provider.options[0].status='FROZEN'})
  .blockers.includes('C02_INACTIVE_ACCOUNT_NOT_ALLOWED'));
 assert.ok(edit(x=>{x.provider.options[0].canExpense=false})
  .blockers.includes('C02_EXPENSE_ACCOUNT_CAPABILITY_NOT_GRANTED'));
 assert.throws(()=>edit(x=>{x.voucher.pay_mode='crypto'}),/UNSUPPORTED_PAYMENT_MODE/);
});
test('C02 account provider rejects cross tenant/business/site references, duplicates and malformed source',()=>{
 assert.throws(()=>edit(x=>{x.scope.synthetic_only=false}),/C02_SYNTHETIC_SCOPE_ONLY/);
 assert.throws(()=>edit(x=>{x.provider.tenantId='OTHER'}),/C02_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.provider.options[0].siteId='DEMO-SITE2'}),/C02_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.voucher.businessId='DEMO-DIFFERENT'}),/C02_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.provider.options[1].accountId=x.provider.options[0].accountId}),/C02_DUPLICATE_OR_REPLAYED_ACCOUNT_OPTION/);
 assert.throws(()=>edit(x=>{x.provider.options[1].sourceRef=x.provider.options[0].sourceRef}),/C02_DUPLICATE_OR_REPLAYED_ACCOUNT_OPTION/);
 assert.throws(()=>edit(x=>{x.provider.capability='sales'}),/C02_UNKNOWN_SOURCE_PROVIDER_ACTION/);
 assert.throws(()=>edit(x=>{x.provider.options[0].sourceRef=x.provider.sourceRef}),/C02_DUPLICATE_OR_REPLAYED_ACCOUNT_OPTION/);
});
