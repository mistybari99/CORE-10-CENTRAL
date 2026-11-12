// GOV-003 feature 08: pure, zero-dependency risk matchers that mirror the SQL detection rules in
// internal/gov003/sql/080_risk.sql (run_risk_detection). DEMO / NOT LIVE contract.
//
// Output objects are ADVISORY and REVIEW-ONLY: they explain why something looks unusual, link the
// evidence, and ask for a human decision. They are never accusations and never carry an action
// (no freeze / block / fire / transfer / approve / privilege change). A parity test compares this module
// with the SQL detector on the same deterministic fake events.
import { canonicalJson, sha256Hex } from './grant-diff.mjs';

export const DISPOSITION = 'advisory_review_only';
export const OWNER_ROLES = Object.freeze(['tenant_owner', 'business_owner']);
export const ACK_REASONS = Object.freeze(['followup_required', 'under_investigation', 'known_issue']);
export const DISMISS_REASONS = Object.freeze(['false_positive', 'expected_activity', 'duplicate_signal', 'test_activity', 'accepted_risk']);
export const BUCKET_ORIGIN_MS = Date.parse('2000-01-01T00:00:00Z');
export const ACCUSATORY = /(fraud|theft|thief|steal|stole|embezzl|criminal|guilty|culprit|crime)/i;
/** Keys that would turn an advisory into an autonomous action. None may ever appear on a signal. */
export const FORBIDDEN_ACTION_KEYS = Object.freeze([
  'freeze', 'block', 'fire', 'terminate', 'transfer', 'debit', 'payment', 'approve', 'grant_role',
  'revoke_role', 'suspend', 'auto_action', 'remediation_sql', 'law_enforcement',
]);

export const DEFAULT_RULES = Object.freeze({
  dup_key: { enabled: true, params: { min_attempts: 3 } },
  dup_content: { enabled: true, params: { min_duplicates: 3, window_seconds: 3600 } },
  volume_spike: { enabled: true, params: { window_seconds: 600, max_events: 20 } },
  stale_source: { enabled: true, params: { max_silence_seconds: 3600, min_events: 2, basis: 'event_time' } },
  unauthorized_command: {
    enabled: true,
    params: { sensitive_prefixes: ['approval.', 'grant.', 'role.', 'policy.', 'privilege.', 'freeze.', 'payment.'] },
  },
});

const bytewise = (a, b) => Buffer.compare(Buffer.from(String(a)), Buffer.from(String(b)));
export const toMs = (v) => (v instanceof Date ? v.getTime() : Date.parse(v));
/** Same shape as utc_iso() in SQL: microsecond precision, trailing Z. */
export const utcIso = (ms) => new Date(ms).toISOString().replace(/\.(\d{3})Z$/, '.$1000Z');
const strip = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== null && v !== undefined));

export function looksSecret(p) {
  return /eyJ[A-Za-z0-9_-]{8,}/.test(p)
    || /(bearer\s|service[_-]?role|passw(or)?d|secret|api[_-]?key|token|private[_-]?key|authorization)/i.test(p)
    || /[^\s@]+@[^\s@]+\.[A-Za-z]{2,}/.test(p)
    || /(^|[^0-9A-Za-z-])[0-9]{13,19}($|[^0-9A-Za-z-])/.test(p)
    || /^[0-9]{9,}$/.test(p)
    || /\n\s+at /.test(p);
}
export const safeRef = (p) => (typeof p === 'string' && /^[A-Za-z0-9_.:/#-]{1,128}$/.test(p) && !looksSecret(p) ? p : null);

/** Mirror of has_scope_role() in 010: an ACTIVE membership covering the exact scope; site rows never cover business-level targets. */
export function hasScopeRole(memberships, identity, tenant, business, site, roles) {
  return memberships.some((m) => m.identity_id === identity && m.status === 'active' && m.tenant_id === tenant
    && roles.includes(m.role)
    && (m.business_id === null || m.business_id === undefined || m.business_id === business)
    && (m.site_id === null || m.site_id === undefined || (site !== null && site !== undefined && m.site_id === site)));
}

const uniqSorted = (arr) => [...new Set(arr)].sort(bytewise);
const evEvent = (id) => ({ kind: 'audit_event', event_id: id });
const isOwn = (e) => String(e.source_domain).startsWith('gov003.');

function advisory(o) {
  return {
    disposition: DISPOSITION, source_domain: null, window_start: null, window_end: null, ...o,
    evidence_actor_ids: uniqSorted(o.evidence_actor_ids ?? []),
  };
}

/**
 * Evaluate every enabled rule over one business' fake/real audit events.
 * @param {{tenantId:string,businessId:string,events:object[],logs?:object[],memberships?:object[],rules?:object,asOf?:string|Date|number}} input
 * events: rows of audit_events (snake_case); logs: rows of idempotency_conflict_log; memberships: rows of memberships.
 * @returns {object[]} advisory signals in the same emission order as run_risk_detection().
 */
export function evaluateRisk({ tenantId, businessId, events, logs = [], memberships = [], rules = DEFAULT_RULES, asOf }) {
  const asOfMs = asOf === undefined || asOf === null ? Date.now() : toMs(asOf);
  const scope = (r) => r.tenant_id === tenantId && r.business_id === businessId;
  const ev = events.filter(scope).map((e) => ({ ...e, t: toMs(e.event_time), ing: toMs(e.ingest_time), seq: Number(e.stream_seq) }));
  const out = [];
  const rule = (id) => (rules[id] && rules[id].enabled !== false ? rules[id].params ?? {} : null);
  const byById = new Map(ev.map((e) => [e.event_id, e]));

  // (a1) idempotency key replayed / conflicting repeatedly
  let p = rule('dup_key');
  if (p) {
    const minatt = p.min_attempts ?? 3;
    const groups = new Map();
    for (const l of logs.filter(scope)) {
      if (!groups.has(l.idempotency_key)) groups.set(l.idempotency_key, []);
      groups.get(l.idempotency_key).push(l);
    }
    for (const ikey of [...groups.keys()].sort(bytewise)) {
      const g = groups.get(ikey).sort((a, b) => Number(a.log_id) - Number(b.log_id));
      if (g.length < minatt) continue;
      const attempts = g.length;
      const conflicts = g.filter((l) => l.outcome === 'conflict').length;
      const orig = g[0].original_event_id;
      const sev = conflicts >= 2 ? 'high' : (conflicts === 1 || attempts >= 2 * minatt ? 'medium' : 'low');
      const origActor = byById.get(orig)?.actor_id;
      out.push(advisory({
        rule_id: 'dup_key', signal_key: `dupkey:${ikey}`, severity: sev,
        confidence_pct: Math.min(95, 55 + 10 * conflicts + 5 * (attempts - minatt)),
        reason: `Advisory only: an idempotency key was submitted ${attempts} time(s) after its first use (${conflicts} with changed content). `
          + 'This may indicate a retry loop or a client defect. Human review is required; no action was taken.',
        context: strip({ entity_ref: safeRef(ikey), count: String(attempts), expected_count: String(minatt), detail_code: 'idempotency_resubmitted' }),
        evidence: [evEvent(orig), ...g.slice(0, 10).map((l) => ({ kind: 'idempotency_log', log_id: Number(l.log_id) }))],
        evidence_actor_ids: [...g.map((l) => l.actor_id), ...(origActor ? [origActor] : [])],
      }));
    }
  }

  // (a2) identical command content resubmitted under different keys
  p = rule('dup_content');
  if (p) {
    const mindup = p.min_duplicates ?? 3; const win = p.window_seconds ?? 3600;
    const groups = new Map();
    for (const e of ev.filter((x) => !isOwn(x) && x.t <= asOfMs)) {
      const k = JSON.stringify([e.source_domain, e.source_id, e.action, e.payload_sha256]);
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(e);
    }
    const cands = [...groups.values()].filter((g) => {
      const ts = g.map((e) => e.t);
      return g.length >= mindup && Math.max(...ts) - Math.min(...ts) <= win * 1000;
    }).sort((a, b) => bytewise(a[0].source_domain, b[0].source_domain) || bytewise(a[0].source_id, b[0].source_id)
      || bytewise(a[0].action, b[0].action) || bytewise(a[0].payload_sha256, b[0].payload_sha256));
    for (const g of cands) {
      g.sort((a, b) => a.seq - b.seq);
      const n = g.length; const t0 = Math.min(...g.map((e) => e.t)); const t1 = Math.max(...g.map((e) => e.t));
      const f = g[0];
      out.push(advisory({
        rule_id: 'dup_content',
        signal_key: `dupcontent:${f.source_domain}:${f.source_id}:${f.action}:${f.payload_sha256.slice(0, 16)}`,
        severity: n >= 2 * mindup ? 'high' : 'medium', confidence_pct: Math.min(90, 50 + 10 * (n - mindup)),
        reason: `Advisory only: ${n} events with identical content were recorded for the same source reference and command `
          + `within ${win} seconds, each under a different idempotency key. This may be a duplicate submission; `
          + 'human review is required and no action was taken.',
        source_domain: f.source_domain, window_start: t0, window_end: t1,
        context: strip({ source_ref: safeRef(f.source_id), count: String(n), expected_count: '1', window_start: utcIso(t0), window_end: utcIso(t1), detail_code: 'content_resubmitted' }),
        evidence: g.slice(0, 10).map((e) => evEvent(e.event_id)),
        evidence_actor_ids: g.map((e) => e.actor_id),
      }));
    }
  }

  // (b1) unexpected volume in one fixed window
  p = rule('volume_spike');
  if (p) {
    const win = p.window_seconds ?? 600; const maxev = p.max_events ?? 20; const winMs = win * 1000;
    const groups = new Map();
    for (const e of ev.filter((x) => !isOwn(x) && x.t <= asOfMs)) {
      const b = BUCKET_ORIGIN_MS + Math.floor((e.t - BUCKET_ORIGIN_MS) / winMs) * winMs;
      const k = `${e.source_domain}\u0000${b}`;
      if (!groups.has(k)) groups.set(k, { sd: e.source_domain, b, list: [] });
      groups.get(k).list.push(e);
    }
    const cands = [...groups.values()].filter((g) => g.list.length > maxev)
      .sort((a, b) => bytewise(a.sd, b.sd) || a.b - b.b);
    for (const g of cands) {
      g.list.sort((a, b) => a.seq - b.seq);
      const n = g.list.length;
      out.push(advisory({
        rule_id: 'volume_spike', signal_key: `volume:${g.sd}:${g.b / 1000}`,
        severity: n >= 3 * maxev ? 'high' : 'medium',
        confidence_pct: Math.min(90, 50 + Math.floor(((n - maxev) * 40) / maxev)),
        reason: `Advisory only: ${n} events from source "${g.sd}" fell inside one ${win}-second window, above the configured `
          + `expected maximum of ${maxev}. This may be a legitimate burst or a duplicated feed; human review is `
          + 'required and no action was taken.',
        source_domain: g.sd, window_start: g.b, window_end: g.b + winMs,
        context: strip({ source_ref: safeRef(g.sd), count: String(n), expected_count: String(maxev), window_start: utcIso(g.b), window_end: utcIso(g.b + winMs), detail_code: 'volume_above_expected' }),
        evidence: g.list.slice(0, 10).map((e) => evEvent(e.event_id)),
        evidence_actor_ids: g.list.map((e) => e.actor_id),
      }));
    }
  }

  // (b2) stale source
  p = rule('stale_source');
  if (p) {
    const maxsil = p.max_silence_seconds ?? 3600; const minev = p.min_events ?? 2;
    const basis = p.basis === 'ingest_time' ? 'ing' : 't';
    const groups = new Map();
    for (const e of ev.filter((x) => !isOwn(x))) {
      if (!groups.has(e.source_domain)) groups.set(e.source_domain, []);
      groups.get(e.source_domain).push(e);
    }
    for (const sd of [...groups.keys()].sort(bytewise)) {
      const g = groups.get(sd);
      if (g.length < minev) continue;
      g.sort((a, b) => (b[basis] - a[basis]) || (b.seq - a.seq));
      const last = g[0]; const lastseen = last[basis];
      const silence = Math.floor((asOfMs - lastseen) / 1000);
      if (silence <= maxsil) continue;
      const long = silence > 3 * maxsil;
      out.push(advisory({
        rule_id: 'stale_source', signal_key: `stale:${sd}:${last.event_id}`,
        severity: long ? 'medium' : 'low', confidence_pct: long ? 80 : 60,
        reason: `Advisory only: no events were received from source "${sd}" for ${silence} seconds, longer than the configured `
          + `limit of ${maxsil} seconds. The source may be paused or disconnected; human review is required and no `
          + 'action was taken.',
        source_domain: sd, window_start: lastseen, window_end: asOfMs,
        context: strip({ source_ref: safeRef(sd), last_seen_at: utcIso(lastseen), observed_at: utcIso(asOfMs), count: String(silence), expected_count: String(maxsil), detail_code: 'source_silent' }),
        evidence: [evEvent(last.event_id)], evidence_actor_ids: [last.actor_id],
      }));
    }
  }

  // (c1) sensitive command from an identity without an owner role
  p = rule('unauthorized_command');
  if (p) {
    const prefixes = p.sensitive_prefixes ?? [];
    const hits = ev.filter((e) => !isOwn(e) && e.t <= asOfMs && prefixes.some((x) => e.action.startsWith(x))
      && !hasScopeRole(memberships, e.actor_id, e.tenant_id, e.business_id, e.site_id ?? null, OWNER_ROLES))
      .sort((a, b) => a.seq - b.seq);
    for (const e of hits) {
      const staff = hasScopeRole(memberships, e.actor_id, e.tenant_id, e.business_id, e.site_id ?? null, ['staff']);
      out.push(advisory({
        rule_id: 'unauthorized_command', signal_key: `unauth:${e.event_id}`,
        severity: staff ? 'medium' : 'high', confidence_pct: staff ? 70 : 85,
        reason: `Advisory only: command "${e.action}" is on the configured sensitive list but was submitted by an identity that `
          + 'currently holds no owner role for this scope. It may reflect a permission gap or a role change; '
          + 'human review is required and no action was taken.',
        source_domain: e.source_domain, window_start: e.t, window_end: e.t,
        context: strip({ source_ref: safeRef(e.source_domain), observed_at: utcIso(e.t), detail_code: staff ? 'role_insufficient' : 'no_active_role' }),
        evidence: [evEvent(e.event_id)], evidence_actor_ids: [e.actor_id],
      }));
    }
  }
  return out;
}

/** Build the advisory a catalog diff (feature 09) would raise. Mirrors diff_against_baseline() in 090. */
export function grantDiffAdvisory({ diff, baselineId, diffId, detectorId }) {
  if (!diff || diff.finding_count < 1) return null;
  return advisory({
    rule_id: 'grant_policy_diff', signal_key: `grantdiff:${baselineId}:${sha256Hex(canonicalJson(diff))}`,
    severity: diff.max_severity, confidence_pct: 90,
    reason: `Advisory only: the live permission catalog differs from the owner-approved baseline in ${diff.finding_count} item(s), `
      + `highest advisory severity ${diff.max_severity}. The change may be intentional; human review is required. `
      + 'No permission was changed automatically.',
    source_domain: 'gov003.grants',
    context: strip({ entity_ref: diffId, count: String(diff.finding_count), severity: diff.max_severity, detail_code: 'catalog_differs' }),
    evidence: [{ kind: 'catalog_diff', ref: diffId }], evidence_actor_ids: detectorId ? [detectorId] : [],
  });
}

/** Language guard: a signal must read as an advisory, never as an accusation or an executable action. */
export function assertAdvisoryOnly(signal) {
  const problems = [];
  if (signal.disposition !== DISPOSITION) problems.push('disposition must be advisory_review_only');
  if (!/advisory/i.test(signal.reason ?? '')) problems.push('reason must state it is advisory');
  if (ACCUSATORY.test(signal.reason ?? '')) problems.push('reason must not accuse');
  if (!/human review/i.test(signal.reason ?? '')) problems.push('reason must request human review');
  for (const k of Object.keys(signal)) if (FORBIDDEN_ACTION_KEYS.includes(k)) problems.push(`forbidden action key: ${k}`);
  if (problems.length) throw new Error(`not_advisory_only: ${problems.join('; ')}`);
  return true;
}

/**
 * Review eligibility, same order as review_signal() in SQL. Returns the SQLSTATE-like code the server would raise.
 * G3A02 scope (also unknown signal) | G3A03 invalid input | G3A06 reviewer is an evidence actor | G3C02 already reviewed.
 */
export function reviewEligibility({ signal, reviewerId, memberships, decision, reasonCode, existingReview = null }) {
  if (!signal || !hasScopeRole(memberships, reviewerId, signal.tenant_id, signal.business_id, null, OWNER_ROLES)) {
    return { ok: false, code: 'G3A02', message: 'scope_denied' };
  }
  const reasons = decision === 'acknowledge' ? ACK_REASONS : decision === 'dismiss' ? DISMISS_REASONS : null;
  if (!reasons || !reasons.includes(reasonCode)) return { ok: false, code: 'G3A03', message: 'invalid_review_input' };
  if ((signal.evidence_actor_ids ?? []).includes(reviewerId)) {
    return { ok: false, code: 'G3A06', message: 'independent_review_required' };
  }
  if (existingReview) return { ok: false, code: 'G3C02', message: 'signal_already_reviewed' };
  return { ok: true, code: null, message: 'eligible' };
}
