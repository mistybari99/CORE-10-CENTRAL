/**
 * GOV-002 signed scoped pagination and bounded activity CSV export.
 * NOT a point-in-time database snapshot, permanent audit evidence, or
 * replacement for GOV003. Uses ONLY the existing current-user view API.
 */
import {makeApprovalActivityCsv} from './c10_gov002_activity_csv_v1.mjs';
import {verifiedBusinessRows,validBusinessId} from './c10_gov002_review_ui_model_v1.mjs';

export const GOV002_PAGED_COVERAGE='SIGNED_RLS_OFFSET_WINDOW_NOT_ATOMIC';
const TYPES=Object.freeze({status:'listStatusPage',exceptions:'listExceptionsPage',activity:'listActivityPage'});
const MAX_ROWS=5000,MAX_PAGE=1000;
function positiveLimit(value,max=MAX_PAGE){
 if(!Number.isSafeInteger(value)||value<1||value>max)throw new Error('invalid_paged_limit');return value;
}
function offset(value){
 if(!Number.isSafeInteger(value)||value<0||value>50000)throw new Error('invalid_paged_offset');return value;
}
function validatePage(kind,businessId,start,size,page){
 if(!page||typeof page!=='object'||page.business_id!==businessId||
    page.offset!==start||page.limit!==size||page.coverage!==GOV002_PAGED_COVERAGE||
    !Array.isArray(page.rows)||page.rows.length>size||typeof page.has_more!=='boolean')
    throw new Error('paged_server_contract_mismatch');
 if(page.has_more && page.rows.length!==size)throw new Error('paged_has_more_inconsistent');
 return verifiedBusinessRows(page.rows,businessId,kind);
}
export function createGov002BoundedReportPager(signedReviewClient){
 if(!signedReviewClient||Object.values(TYPES).some(k=>typeof signedReviewClient[k]!=='function'))
  throw new Error('signed_scoped_paged_client_required');
 async function readScopedPage({businessId,kind,offset:start=0,limit=250}={}){
  if(!validBusinessId(businessId)||!(kind in TYPES))throw new Error('invalid_paged_scope');
  const n=positiveLimit(limit),at=offset(start);
  const page=await signedReviewClient[TYPES[kind]]({businessId,offset:at,limit:n});
  const rows=validatePage(kind,businessId,at,n,page);
  return Object.freeze({kind,business_id:businessId,offset:at,limit:n,
    rows:Object.freeze(rows),may_have_more:page.has_more,coverage:GOV002_PAGED_COVERAGE,
    is_consistent_snapshot:false,not_certified_audit:true});
 }
 async function exportBoundedActivityCsv({businessId,pageSize=250,maxRows=MAX_ROWS}={}){
  if(!validBusinessId(businessId))throw new Error('invalid_paged_scope');
  const n=positiveLimit(pageSize),cap=positiveLimit(maxRows,MAX_ROWS);
  const seen=new Set(),all=[];
  let at=0,hasMore=true,pages=0;
  while(hasMore && at<cap){
   const size=Math.min(n,cap-at);
   const page=await readScopedPage({businessId,kind:'activity',offset:at,limit:size});
   for(const row of page.rows){
    if(!/^(approval|exception):[1-9][0-9]*$/u.test(row.activity_id)||seen.has(row.activity_id))
      throw new Error('paged_duplicate_or_invalid_event');
    seen.add(row.activity_id);all.push(row);
   }
   pages++;
   // Offset windows can change while activity is being appended. This
   // export never claims full, stable, audit-grade coverage.
   at+=page.rows.length;
   hasMore=page.may_have_more;
   if(hasMore && page.rows.length===0)throw new Error('paged_no_forward_progress');
  }
  return Object.freeze({csv:makeApprovalActivityCsv(all,{businessId}),business_id:businessId,
    rows_exported:all.length,pages_read:pages,may_have_more:hasMore,
    coverage:GOV002_PAGED_COVERAGE,is_consistent_snapshot:false,
    full_audit_archive:false,production_certified:false});
 }
 return Object.freeze({readScopedPage,exportBoundedActivityCsv});
}