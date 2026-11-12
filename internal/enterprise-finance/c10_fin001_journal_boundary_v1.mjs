/**
 * CORE 10 CENTRAL | C10-CAP-FIN-001 | Build 11 first independent slice
 * Pure accounting boundary. NOT a ledger, posting API, tax engine, auth layer,
 * Supabase migration, or finance certification.
 *
 * Integration rule: caller MUST use an authenticated server-owned adapter to
 * resolve context, account catalog, posted receipt, approval and period state.
 * Never import this module as an authority to post stock, money or journals.
 */
import { createHash } from 'node:crypto';

export class FinanceGateError extends Error {
  constructor(code) {
    super(code);
    this.name = 'FinanceGateError';
    this.code = code;
  }
}
function deny(code) { throw new FinanceGateError(code); }
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
function requiredObject(x, code) { if (!object(x)) deny(code); return x; }
function id(x, code) {
  if (typeof x !== 'string' || !/^[A-Za-z0-9:_-]{1,100}$/.test(x)) deny(code);
  return x;
}
function key(x) {
  if (typeof x !== 'string' || !/^[A-Za-z0-9_-]{12,100}$/.test(x)) deny('FIN_REQUEST_KEY_INVALID');
  return x;
}
function exactDay(x, code) {
  if (typeof x !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(x) ||
      !Number.isFinite(Date.parse(x + 'T00:00:00Z')) ||
      new Date(x + 'T00:00:00Z').toISOString().slice(0,10) !== x) deny(code);
  return x;
}
function equalScope(a, b) {
  return a.tenantId === b.tenantId && a.businessId === b.businessId &&
    a.legalEntityId === b.legalEntityId;
}
export function assertTrustedAccountingContext(context, right = 'finance.propose') {
  requiredObject(context, 'FIN_SIGNED_CONTEXT_REQUIRED');
  if (context.authenticated !== true || context.resolvedBy !== 'server_verified_signed_actor' ||
      context.effectiveGrantChecked !== true || context.revocationChecked !== true ||
      !Array.isArray(context.effectiveRights) ||
      !context.effectiveRights.includes(right)) deny('FIN_SIGNED_CONTEXT_REQUIRED');
  for (const prop of ['actorId','tenantId','businessId','legalEntityId']) id(context[prop], 'FIN_SCOPE_INVALID');
  id(context.grantVersion, 'FIN_GRANT_VERSION_REQUIRED');
  return context;
}
export function parseMoneyMinor(value, scale = 2) {
  if (!Number.isInteger(scale) || scale < 0 || scale > 4) deny('FIN_CURRENCY_PRECISION_UNSUPPORTED');
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,12})(\.\d{1,4})?$/.test(value)) deny('FIN_MONEY_FORMAT_INVALID');
  const parts = value.split('.');
  if ((parts[1] || '').length > scale) deny('FIN_MONEY_PRECISION_INVALID');
  const v = BigInt(parts[0]) * 10n ** BigInt(scale) +
    BigInt((parts[1] || '').padEnd(scale, '0') || '0');
  if (v > 9999999999999999n) deny('FIN_MONEY_OVERFLOW');
  return v;
}
export function minorToMoney(value, scale = 2) {
  if (typeof value !== 'bigint' || !Number.isInteger(scale) || scale < 0 || scale > 4)
    deny('FIN_MONEY_FORMAT_INVALID');
  const sign = value < 0n ? '-' : '';
  const n = value < 0n ? -value : value;
  const factor = 10n ** BigInt(scale);
  return sign + (n / factor).toString() +
    (scale ? '.' + (n % factor).toString().padStart(scale, '0') : '');
}
function digest(x) {
  return createHash('sha256').update(JSON.stringify(x)).digest('hex');
}
function assertPeriod(period, context, bookedOn) {
  requiredObject(period, 'FIN_PERIOD_UNVERIFIED');
  if (period.authoritative !== true || !equalScope(period,context)) deny('FIN_PERIOD_UNVERIFIED');
  id(period.id, 'FIN_PERIOD_UNVERIFIED');
  const from=exactDay(period.startDay, 'FIN_PERIOD_INVALID');
  const to=exactDay(period.endDayExclusive, 'FIN_PERIOD_INVALID');
  if (!(from < to) || bookedOn < from || bookedOn >= to) deny('FIN_DATE_OUTSIDE_PERIOD');
  if (period.status !== 'OPEN' || period.closeVersion === undefined) deny('FIN_PERIOD_CLOSED');
  id(period.closeVersion, 'FIN_PERIOD_VERSION_REQUIRED');
}
function assertApproval(approval, context, source, makerId) {
  requiredObject(approval, 'FIN_APPROVAL_MISSING');
  if (approval.verifiedByServer !== true || approval.status !== 'APPROVED' ||
      !equalScope(context, approval) || approval.sourceId !== source.sourceId ||
      approval.sourceVersion !== source.sourceVersion ||
      approval.sourceHash !== source.sourceHash ||
      approval.policyVersion !== source.policyVersion)
    deny('FIN_APPROVAL_SOURCE_MISMATCH');
  id(approval.approverId, 'FIN_APPROVER_MISSING');
  if (approval.approverId === makerId) deny('FIN_MAKER_CHECKER_VIOLATION');
  id(approval.approvalReceiptId, 'FIN_APPROVAL_RECEIPT_MISSING');
}
function assertSource(source, context, certifiedSources) {
  requiredObject(source, 'FIN_SOURCE_UNVERIFIED');
  if (source.authoritative !== true || !equalScope(context,source))
    deny('FIN_SOURCE_UNVERIFIED');
  const sourceType = id(source.type, 'FIN_SOURCE_INVALID');
  if (!(certifiedSources instanceof Set) || !certifiedSources.has(sourceType))
    deny('FIN_SOURCE_TYPE_NOT_CERTIFIED');
  id(source.sourceId, 'FIN_SOURCE_INVALID');
  id(source.sourceVersion, 'FIN_SOURCE_VERSION_INVALID');
  id(source.policyVersion, 'FIN_POLICY_VERSION_INVALID');
  if (typeof source.sourceHash !== 'string' || !/^[a-f0-9]{64}$/.test(source.sourceHash))
    deny('FIN_SOURCE_HASH_INVALID');
  id(source.makerId, 'FIN_MAKER_REQUIRED');
  exactDay(source.bookedOn, 'FIN_BOOKING_DATE_INVALID');
}
function assertChart(accounts, context, currency) {
  if (!Array.isArray(accounts) || accounts.length === 0 || accounts.length > 5000)
    deny('FIN_CHART_NOT_RESOLVED');
  const map = new Map();
  for (const a of accounts) {
    requiredObject(a, 'FIN_ACCOUNT_INVALID');
    id(a.id,'FIN_ACCOUNT_INVALID');
    if (map.has(a.id)) deny('FIN_ACCOUNT_DUPLICATE');
    if (a.authoritative !== true || !equalScope(a,context) ||
        a.currency !== currency || a.status !== 'POSTABLE' ||
        a.isControlAccount === true)
      deny('FIN_ACCOUNT_NOT_POSTABLE_IN_SCOPE');
    map.set(a.id, a);
  }
  return map;
}
function normalizeLines(lines, catalog, scale) {
  if (!Array.isArray(lines) || lines.length < 2 || lines.length > 200)
    deny('FIN_LINES_COUNT_INVALID');
  let debit=0n, credit=0n;
  const output=[];
  for (const line of lines) {
    requiredObject(line, 'FIN_LINE_INVALID');
    const accountId = id(line.accountId, 'FIN_LINE_ACCOUNT_INVALID');
    if (!catalog.has(accountId)) deny('FIN_ACCOUNT_NOT_POSTABLE_IN_SCOPE');
    if (!['DEBIT','CREDIT'].includes(line.side)) deny('FIN_LINE_SIDE_INVALID');
    const amountMinor = parseMoneyMinor(line.amount,scale);
    if (amountMinor <= 0n) deny('FIN_ZERO_LINE_FORBIDDEN');
    if (line.side === 'DEBIT') debit += amountMinor;
    else credit += amountMinor;
    output.push(Object.freeze({accountId, side:line.side, amountMinor:amountMinor.toString()}));
  }
  if (debit !== credit) deny('FIN_JOURNAL_UNBALANCED');
  if (debit > 9999999999999999n) deny('FIN_MONEY_OVERFLOW');
  return { lines:output, totalMinor:debit.toString() };
}
/**
 * Prepares a reproducible, balanced, server-authorized voucher envelope.
 * No INSERT, UPDATE, RPC, HTTP request or balance mutation is performed.
 * "certifiedSources" and "accounts" MUST come from an independent server registry.
 */
export function prepareJournalProposal({context,source,period,approval,accounts,lines,
   certifiedSources,requestKey,currency='BDT',scale=2}) {
  assertTrustedAccountingContext(context);
  key(requestKey);
  assertSource(source,context,certifiedSources);
  if (currency !== 'BDT' || scale !== 2 || source.currency !== currency)
    deny('FIN_UNAPPROVED_CURRENCY_POLICY');
  assertPeriod(period,context,source.bookedOn);
  assertApproval(approval,context,source,source.makerId);
  const catalog=assertChart(accounts,context,currency);
  const normalized=normalizeLines(lines,catalog,scale);
  const envelope={
    contract:'CORE10_FIN001_JOURNAL_PROPOSAL_V1',
    scope:{tenantId:context.tenantId,businessId:context.businessId,legalEntityId:context.legalEntityId},
    provenance:{sourceType:source.type,sourceId:source.sourceId,sourceVersion:source.sourceVersion,
      sourceHash:source.sourceHash,policyVersion:source.policyVersion,bookedOn:source.bookedOn,
      makerId:source.makerId,approvalReceiptId:approval.approvalReceiptId,
      approverId:approval.approverId,periodId:period.id,closeVersion:period.closeVersion,
      grantVersion:context.grantVersion},
    currency, scale, lines:normalized.lines, totalMinor:normalized.totalMinor,
    requestKey,
  };
  return Object.freeze({
    ...envelope, fingerprint:digest(envelope), state:'VALIDATED_NOT_POSTED',
    canPost:false, canonicalPostRequired:true,
  });
}
/** The adapter refuses any direct post. Canonical database posting will own
 * row locks, unique (source,event), period recheck, effective permissions and
 * immutable receipts, after independent integration and staging certification.
 */
export function postJournal() { deny('FIN_CANONICAL_POSTING_ADAPTER_NOT_CONNECTED'); }
export function markAsPosted() { deny('FIN_CANONICAL_RECEIPT_REQUIRED'); }
/** An immutable original must first be read back from the certified journal. */
export function prepareReversalProposal({context,original,period,approval,accounts,
  requestKey,reason,certifiedSources}) {
  assertTrustedAccountingContext(context,'finance.reverse.propose');
  if (!object(original) || original.verifiedCanonicalRead !== true ||
      original.status !== 'POSTED' || !equalScope(original,context) ||
      !/^[a-f0-9]{64}$/.test(original.fingerprint || '') ||
      !Array.isArray(original.lines) || original.lines.length < 2)
    deny('FIN_ORIGINAL_CANONICAL_RECEIPT_REQUIRED');
  id(original.journalId, 'FIN_ORIGINAL_CANONICAL_RECEIPT_REQUIRED');
  if (original.reversed === true) deny('FIN_ORIGINAL_ALREADY_REVERSED');
  if (typeof reason !== 'string' || reason.trim().length < 12 || reason.length > 500)
    deny('FIN_REVERSAL_REASON_REQUIRED');
  if (!object(original.provenance)) deny('FIN_ORIGINAL_CANONICAL_RECEIPT_REQUIRED');
  const sourceId='reverse:' + original.journalId;
  const sourceHash=digest({journalId:original.journalId,fingerprint:original.fingerprint,reason:reason.trim()});
  const source={
    authoritative:true, tenantId:context.tenantId,businessId:context.businessId,
    legalEntityId:context.legalEntityId, type:'journal_reversal',
    sourceId,sourceVersion:'1',sourceHash,policyVersion:original.provenance.policyVersion,
    makerId:original.provenance.makerId,bookedOn:period.bookedOn,currency:'BDT'
  };
  const lines=original.lines.map(x=>({
    accountId:x.accountId,side:x.side==='DEBIT'?'CREDIT':'DEBIT',
    amount:minorToMoney(BigInt(x.amountMinor),2)
  }));
  const proposal=prepareJournalProposal({context,source,period,approval,accounts,
    lines,certifiedSources,requestKey});
  return Object.freeze({...proposal,reversesJournalId:original.journalId,
    reversalReason:reason.trim(),state:'VALIDATED_REVERSAL_NOT_POSTED'});
}
/**
 * Fail-closed read-side reconciliation of an authenticated, complete snapshot.
 * This never treats a partial page or unknown data as certified financials.
 */
export function reconcileTrialBalance({context,period,entries,accounts,snapshot}) {
  assertTrustedAccountingContext(context,'finance.report');
  requiredObject(snapshot, 'FIN_SIGNED_SNAPSHOT_REQUIRED');
  if (snapshot.verifiedByServer!==true || snapshot.complete!==true ||
      !equalScope(snapshot,context) || snapshot.periodId!==period?.id ||
      !snapshot.snapshotId || !snapshot.canonicalJournalReadback)
    deny('FIN_SIGNED_SNAPSHOT_REQUIRED');
  if (!object(period) || !equalScope(context,period)) deny('FIN_PERIOD_UNVERIFIED');
  const catalog=assertChart(accounts,context,'BDT');
  if (!Array.isArray(entries) || entries.length>50000) deny('FIN_REPORT_BOUND_EXCEEDED');
  const perAccount=new Map(), seen=new Set();
  let debits=0n,credits=0n;
  for (const j of entries) {
    if (!object(j) || j.status!=='POSTED' || !equalScope(j,context) ||
        j.periodId!==period.id || !j.verifiedCanonicalRead)
      deny('FIN_UNVERIFIED_REPORT_ENTRY');
    const journalId=id(j.journalId,'FIN_UNVERIFIED_REPORT_ENTRY');
    if (seen.has(journalId)) deny('FIN_DUPLICATE_JOURNAL');
    seen.add(journalId);
    const result=normalizeLines(j.lines.map(x=>({
      accountId:x.accountId,side:x.side,amount:x.amount
    })),catalog,2);
    for (const l of result.lines) {
      const current=perAccount.get(l.accountId)||{debit:0n,credit:0n};
      const n=BigInt(l.amountMinor);
      current[l.side==='DEBIT'?'debit':'credit']+=n;
      perAccount.set(l.accountId,current);
      if(l.side==='DEBIT') debits+=n; else credits+=n;
    }
  }
  if(debits!==credits) deny('FIN_TRIAL_BALANCE_UNBALANCED');
  return Object.freeze({
    status:'RECONCILED_COMPLETE_SIGNED_INPUT_NOT_CERTIFIED_FINANCIAL_STATEMENTS',
    snapshotId:snapshot.snapshotId, periodId:period.id, currency:'BDT',
    journalCount:entries.length,totalDebits:minorToMoney(debits),
    totalCredits:minorToMoney(credits),
    accounts:[...perAccount.entries()].sort((a,b)=>a[0].localeCompare(b[0]))
      .map(([accountId,v])=>({accountId,debit:minorToMoney(v.debit),
        credit:minorToMoney(v.credit),netDebit:minorToMoney(v.debit-v.credit)}))
  });
}
