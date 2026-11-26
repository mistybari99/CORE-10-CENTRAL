'use strict';
/* Synthetic workbench only. Reconciles signed-source references, not ERP accounting postings. */
const fixture=require('./source-books-fixture.json');
const books=require('./source-books.cjs');
function run(data=fixture){
 if(data?.synthetic_only!==true)throw Error('SYNTHETIC_FIXTURE_ONLY');
 const packaging=books.packagingLedger(data.packaging);
 const expenses=books.expenseCashbookReconcile(data.expense);
 const ok=packaging.status==='REVIEW_READY_NOT_APPROVED'&&expenses.status==='REVIEW_READY_NOT_APPROVED';
 return {status:ok?'SYNTHETIC_SOURCE_BOOKS_MATCH_NOT_APPROVED':'SYNTHETIC_SOURCE_BOOKS_BLOCKED',
  packaging,expenses,sourceParityCertified:false,ownerAccepted:false,
  readyForERPPosting:false,readyForLive:false};
}
if(require.main===module){
 const result=run();
 console.log(JSON.stringify({status:result.status,
   packagingMovements:result.packaging.entries.length,
   packagingClosing:result.packaging.balances,
   voucherCount:result.expenses.voucherCount,
   voucherTotals:result.expenses.totals,
   blockers:[...result.packaging.blockers,...result.expenses.blockers],
   readyForERPPosting:false,ownerAccepted:false},null,2));
 if(result.status!=='SYNTHETIC_SOURCE_BOOKS_MATCH_NOT_APPROVED')process.exitCode=1;
}
module.exports={run};
