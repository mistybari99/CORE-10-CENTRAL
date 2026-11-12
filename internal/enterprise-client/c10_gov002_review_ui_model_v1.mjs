/** CORE 10 GOV-002 — non-authoritative presentation model.
 * Source for all rows MUST be a signed-user server-scoped projection. Rendering
 * or filtering never confers approval privileges. Server RPCs remain decisive.
 */
export const APPROVAL_TABS = Object.freeze([
  ['pending', 'অপেক্ষমাণ'], ['approved', 'অনুমোদিত'],
  ['rejected', 'বাতিল'], ['deferred', 'স্থগিত'],
  ['withdrawn', 'প্রত্যাহার'], ['expired', 'মেয়াদোত্তীর্ণ'], ['all', 'সব']
]);
const PENDING_DISPLAYS = new Set(['pending', 'awaiting_stage_1', 'awaiting_stage_2']);
const APPROVED_DISPLAYS = new Set(['approved', 'executed', 'approved_pending_execution']);
const TEXT_LIMIT = 300;
export function validBusinessId(id) { return Number.isSafeInteger(id) && id > 0; }
export function safeText(value, max = TEXT_LIMIT) {
  if (value == null) return '—';
  return String(value).replace(/[\u0000-\u001f\u007f]/gu, ' ').slice(0, max);
}
export function verifiedBusinessRows(rows, businessId, kind) {
  if (!validBusinessId(businessId) || !Array.isArray(rows) || rows.length > 1000)
    throw new Error('invalid_scoped_projection');
  const idKey = kind === 'status' ? 'request_id' : kind === 'exceptions' ? 'escalation_id' : 'activity_id';
  if (!['status', 'exceptions', 'activity'].includes(kind)) throw new Error('invalid_projection_kind');
  const seen = new Set();
  return rows.map(row => {
    if (!row || typeof row !== 'object' || Array.isArray(row) ||
        !Number.isSafeInteger(Number(row.business_id)) || Number(row.business_id) !== businessId ||
        (kind === 'activity' ? !/^(?:approval|exception):[1-9][0-9]*$/u.test(row[idKey] || '')
          : !/^[1-9][0-9]*$/u.test(String(row[idKey] ?? ''))) ||
        seen.has(String(row[idKey]))) throw new Error('server_scope_or_identity_mismatch');
    seen.add(String(row[idKey]));
    return Object.freeze({ ...row });
  });
}
export function approvalState(row, now = Date.now()) {
  const stored = String(row?.stored_status || '').toLowerCase();
  const shown = String(row?.display_status || '').toLowerCase();
  if (stored === 'pending') {
    if (shown === 'expired' || (row.expires_at && Number.isFinite(Date.parse(row.expires_at)) && Date.parse(row.expires_at) <= now))
      return 'expired';
    return 'pending';
  }
  if (stored === 'approved' || APPROVED_DISPLAYS.has(shown)) return 'approved';
  if (['rejected', 'deferred', 'withdrawn'].includes(stored)) return stored;
  return 'unknown';
}
export function approvalStageText(row) {
  const d = String(row?.display_status || '').toLowerCase();
  if (d === 'awaiting_stage_1') return 'প্রথম ধাপ (Stage 1)';
  if (d === 'awaiting_stage_2') return 'দ্বিতীয় ধাপ (Stage 2)';
  if (/^awaiting_stage_[3-5]$/u.test(d)) {
    const labels = {3:'তৃতীয়',4:'চতুর্থ',5:'পঞ্চম'};
    const stage = Number(d.at(-1));
    return `${labels[stage]} ধাপ (Stage ${stage})`;
  }
  if (d === 'approved_pending_execution') return 'অনুমোদিত · কার্যকর হয়নি';
  if (d === 'executed') return 'Synthetic execution receipt';
  const names = {
    pending:'অপেক্ষমাণ', approved:'অনুমোদিত', rejected:'বাতিল',
    deferred:'স্থগিত', withdrawn:'প্রত্যাহার', expired:'মেয়াদ শেষ'
  };
  return names[approvalState(row)] || 'অজানা অবস্থা';
}
export function filteredApprovals(rows, {tab='pending', search=''} = {}) {
  const term = String(search).trim().toLocaleLowerCase();
  return rows.filter(row => {
    const state = approvalState(row);
    if (tab !== 'all' && state !== tab) return false;
    if (!term) return true;
    return ['request_id','domain','action_code','source_key','requested_by']
      .some(k => String(row[k] ?? '').toLocaleLowerCase().includes(term));
  });
}
export function summaryCounts(rows) {
  const c = Object.fromEntries(APPROVAL_TABS.map(([s]) => [s,0]));
  for (const row of rows) {
    const state = approvalState(row);
    c.all++;
    if (state in c) c[state]++;
  }
  return c;
}
/** UI visibility is NOT an access check. A denied server call remains denied. */
export function canOfferApprovalAction(row, action) {
  return ['approve','reject','defer','withdraw','request_exception'].includes(action)
    && approvalState(row) === 'pending';
}
export function canOfferExceptionAction(row, action, now = Date.now()) {
  return ['acknowledged','declined','withdrawn'].includes(action)
    && row?.stored_status === 'pending'
    && row?.display_status === 'pending'
    && row?.parent_approval_status === 'pending'
    && (!row.expires_at || Date.parse(row.expires_at) > now);
}
export function readableError(error) {
  const code = String(error?.code ?? '');
  const status = Number(error?.status ?? error?.statusCode ?? 0);
  const raw = String(error?.message || error || '').toLowerCase();
  if (status === 401 || /auth_required|jwt|session|unauthenticated/u.test(raw))
    return 'সেশন শেষ বা লগইন নেই। আবার নিরাপদভাবে লগইন করুন।';
  if (status === 403 || code === '42501' || /permission|denied|unauthoriz|rls|not allowed/u.test(raw))
    return 'অনুমতি নেই (Permission denied)। বর্তমান ব্যবহারকারীর অধিকার সার্ভার যাচাই করেছে।';
  if (/expire|stale|version|fingerprint|source|conflict|already|final/u.test(raw) || status === 409)
    return 'অনুরোধের মেয়াদ/উৎস/অবস্থা বদলেছে। Refresh করে আবার যাচাই করুন।';
  return 'সার্ভার অনুরোধ সম্পন্ন করতে পারেনি। পুনরায় যাচাই করুন।';
}