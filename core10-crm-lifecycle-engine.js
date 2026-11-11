/* C10-A056 CRM lifecycle PURE logic (no I/O). Mirrors SQL rules for client-side preview/validation only;
   the database remains the authority. Money is BigInt-based; unknown money is null, never zero. */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_CRM_ENGINE = api;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const REQ = /^[A-Za-z0-9_-]{8,100}$/;
  const CHANNELS = ["email", "sms", "phone", "whatsapp", "post"];
  const ACTIONS = ["consent.lift_suppression", "consent.write", "customer.export", "customer.merge", "customer.read", "customer.redact", "customer.write",
    "enquiry.triage", "finance.read", "finance.register", "followup.write", "intake.manage", "lead.write", "opportunity.stage", "opportunity.write",
    "quote.approve", "quote.convert", "quote.write", "report.read", "segment.write", "settings.write", "ticket.resolve", "ticket.write", "campaign.write", "campaign.dispatch"];
  function fail(code) { const e = new Error(code); e.code = code; throw e; }

  function escapeHtml(s) {
    return String(s == null ? "" : s).replace(/[&<>"'`\/]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;", "`": "&#96;", "/": "&#47;" }[c]));
  }
  /* OWASP CSV formula neutraliser, identical to SQL a056_csv_cell */
  function csvCell(v) {
    let s = v == null ? "" : String(v);
    if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
    return '"' + s.replace(/"/g, '""') + '"';
  }
  function csvRow(cells) { return cells.map(csvCell).join(","); }
  function hasControl(s) { return /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(s); }
  function text(v, max, required) {
    const s = v == null ? "" : String(v).trim();
    if (!s) { if (required) fail("A056_INVALID"); return null; }
    if (s.length > max || hasControl(s)) fail("A056_INVALID");
    return s;
  }
  function normalizeEmail(v) {
    const s = text(v, 254); if (s === null) return null;
    const l = s.toLowerCase(); if (!/^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/.test(l)) fail("A056_INVALID"); return l;
  }
  function normalizePhone(v) {
    const s = text(v, 32); if (s === null) return null;
    if (!/^[0-9 +()-]+$/.test(s)) fail("A056_INVALID");
    const d = s.replace(/[^0-9]/g, "").replace(/^00/, "");
    if (d.length < 7 || d.length > 15) fail("A056_INVALID"); return d;
  }
  function requestKey(prefix) {
    const rnd = (typeof crypto !== "undefined" && crypto.getRandomValues) ? Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("")
      : Math.random().toString(16).slice(2) + Date.now().toString(16);
    const k = (String(prefix || "req").replace(/[^A-Za-z0-9_-]/g, "") + "-" + rnd).slice(0, 100);
    return k.length >= 8 ? k : (k + "00000000").slice(0, 8);
  }

  /* ---- money (BigInt cents) ---- */
  function parseScaled(v, scale, max) {
    const s = String(v); if (!/^\d+(\.\d+)?$/.test(s)) fail("A056_INVALID");
    const [i, f = ""] = s.split("."); if (f.length > scale) fail("A056_INVALID");
    const n = BigInt(i + f.padEnd(scale, "0")); if (max !== undefined && n > max) fail("A056_INVALID"); return n;
  }
  function centsToString(c) { const neg = c < 0n; const a = neg ? -c : c; const s = a.toString().padStart(3, "0"); return (neg ? "-" : "") + s.slice(0, -2) + "." + s.slice(-2); }
  function quoteTotals(lines, approval) {
    if (!Array.isArray(lines) || lines.length < 1 || lines.length > 100) fail("A056_INVALID");
    let total = 0n, maxDisc = 0n; const out = [];
    lines.forEach((l, idx) => {
      const q = parseScaled(l.quantity, 3), u = parseScaled(l.unit_price, 2), d = parseScaled(l.discount_pct == null ? 0 : l.discount_pct, 2);
      if (q <= 0n || q > 1000000000n || u > 10000000000n || d > 10000n) fail("A056_INVALID");
      text(l.description, 200, true);
      const cents = (q * u * (10000n - d) + 5000000n) / 10000000n; // round half up, same as numeric round(,2) for non-negative
      total += cents; if (d > maxDisc) maxDisc = d;
      out.push({ line_no: idx + 1, line_total: centsToString(cents), net_unit_price: centsToString((u * (10000n - d) + 5000n) / 10000n) });
    });
    const a = (approval || {});
    const overDisc = a.discount_pct_over != null && maxDisc > parseScaled(a.discount_pct_over, 2);
    const overTotal = a.total_over != null && total > parseScaled(a.total_over, 2);
    return { total: centsToString(total), lines: out, max_discount_pct: (Number(maxDisc) / 100).toFixed(2), requires_approval: !!(overDisc || overTotal) };
  }
  /* unknown money shows as unavailable; never as zero */
  function formatMoney(v, label) {
    if (v === null || v === undefined || v === "" || Number.isNaN(Number(v))) return label || "NOT CERTIFIED";
    return "BDT " + Number(v).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }
  function financeLabel(f) {
    if (!f || f.status === "RESTRICTED") return { text: "Restricted", certified: false };
    if (f.status !== "CERTIFIED") return { text: f.status === "UNAVAILABLE" ? "Unavailable" : "NOT CERTIFIED", certified: false };
    return { text: formatMoney(f.balance_due, "Unavailable"), certified: true, test: !!f.test_source };
  }

  /* ---- duplicates ---- */
  function dedupeScore(a, b) {
    const ea = a.email && normalizeEmail(a.email), eb = b.email && normalizeEmail(b.email);
    const pa = a.phone && normalizePhone(a.phone), pb = b.phone && normalizePhone(b.phone);
    if (ea && ea === eb) return { score: 100, reason: "email_match" };
    if (pa && pa === pb) return { score: 90, reason: "phone_match" };
    if (a.kind === b.kind && a.display_name && b.display_name && a.display_name.toLowerCase() === b.display_name.toLowerCase()) return { score: 60, reason: "name_match" };
    return { score: 0, reason: "none" };
  }

  /* ---- consent (mirror of a056_consent_state) ---- */
  function consentDecision(input, now) {
    const t = (now || new Date()).getTime();
    const { customer, events = [], suppressions = [], channel, purpose } = input;
    if (!CHANNELS.includes(channel) || !["marketing", "service"].includes(purpose)) fail("A056_INVALID");
    if (!customer || customer.status !== "active") return { can_send: false, reason: "customer_inactive" };
    if (suppressions.some((s) => !s.lifted && s.channel === channel && (s.purpose === purpose || s.purpose === "service"))) return { can_send: false, reason: "opt_out_precedence" };
    const ev = events.filter((e) => e.channel === channel && e.purpose === purpose).sort((x, y) => y.id - x.id)[0];
    if (!ev) return { can_send: false, reason: "no_consent" };
    if (ev.status !== "granted") return { can_send: false, reason: "revoked" };
    if (ev.valid_until && new Date(ev.valid_until).getTime() <= t) return { can_send: false, reason: "expired" };
    return { can_send: true, reason: "granted" };
  }

  /* ---- support SLA ---- */
  function slaDue(createdAt, hours) { return new Date(new Date(createdAt).getTime() + hours * 3600e3).toISOString(); }
  function slaState(t, now) {
    const n = (now || new Date()).getTime(), due = new Date(t.sla_due_at).getTime();
    if (t.resolved_at && ["resolved", "closed"].includes(t.status)) return new Date(t.resolved_at).getTime() <= due ? "met" : "breached";
    if (n > due) return "breached";
    return due - n < t.sla_hours * 3600e3 * 0.2 ? "at_risk" : "ok";
  }

  /* ---- reports ---- */
  function rate(n, d) { return d ? Math.round((n / d) * 10000) / 10000 : null; }
  function funnel(counts) {
    const names = ["enquiries", "leads", "qualified_leads", "opportunities", "quotes_sent", "quotes_accepted", "orders_created", "orders_posted"];
    return names.map((n, i) => ({ stage: n, count: counts[n] || 0, rate_from_prev: i === 0 ? null : rate(counts[n] || 0, counts[names[i - 1]] || 0) }));
  }
  function avg(values) { return values.length ? Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 100) / 100 : null; }

  /* ---- config validation (mirror of a056_validate_config invariants) ---- */
  function validateConfig(c) {
    if (!c || !Array.isArray(c.stages) || c.stages.length < 2 || c.stages.length > 12) fail("A056_CONFIG_INVALID");
    const codes = new Set(); let won = 0, lost = 0;
    c.stages.forEach((s) => {
      if (!/^[a-z][a-z0-9_]{1,30}$/.test(s.code || "") || codes.has(s.code) || !s.label || s.label.length > 60 || !["open", "won", "lost"].includes(s.kind)) fail("A056_CONFIG_INVALID");
      codes.add(s.code); if (s.kind === "won") won++; if (s.kind === "lost") lost++;
    });
    if (won !== 1 || lost !== 1 || c.stages[0].kind !== "open") fail("A056_CONFIG_INVALID");
    const p = c.permissions || {};
    Object.keys(p).forEach((k) => { if (!ACTIONS.includes(k) || !["owner", "manager", "site"].includes(p[k])) fail("A056_CONFIG_INVALID"); });
    if (p["settings.write"] !== "owner" || p["customer.redact"] !== "owner" || p["finance.register"] !== "owner" ||
      !["owner", "manager"].includes(p["consent.lift_suppression"] || "manager")) fail("A056_CONFIG_INVARIANT");
    ["urgent", "standard", "low"].forEach((k) => { const h = Number(c.sla && c.sla[k]); if (!(h >= 1 && h <= 2160)) fail("A056_CONFIG_INVALID"); });
    return true;
  }

  /* ---- segments (whitelisted) ---- */
  function segmentMatch(cust, def, stats) {
    const s = stats || {}; const keys = Object.keys(def || {});
    const allowed = ["kind", "tags_any", "site_id", "min_posted_orders", "max_days_since_purchase", "has_consent"];
    if (keys.some((k) => !allowed.includes(k))) fail("A056_INVALID");
    if (cust.status !== "active") return false;
    if (def.kind && cust.kind !== def.kind) return false;
    if (def.tags_any && !def.tags_any.some((t) => (cust.tags || []).includes(t))) return false;
    if (def.site_id && cust.site_id !== def.site_id) return false;
    if (def.min_posted_orders != null && (s.posted_orders || 0) < def.min_posted_orders) return false;
    if (def.max_days_since_purchase != null && !(s.days_since_purchase != null && s.days_since_purchase <= def.max_days_since_purchase)) return false;
    if (def.has_consent && !(s.consent && s.consent.can_send)) return false;
    return true;
  }

  const ERROR_TEXT = {
    A056_DENIED: "You do not have permission for this action.", A056_NOT_FOUND: "Record not found.", A056_MODULE_DISABLED: "CRM is not enabled for this business yet (Owner must enable it).",
    A056_STALE_CUSTOMER: "This customer changed since you opened it. Reload and retry.", A056_STALE_QUOTATION: "Quotation changed; reload.", A056_STALE_SETTINGS: "Settings changed; reload.",
    A056_REQUEST_REPLAY_CONFLICT: "This request key was already used with different data.", A056_OPT_OUT_PRECEDENCE: "Customer opted out; marketing cannot be re-enabled without an authorised, audited lift.",
    A056_SELF_APPROVAL: "You cannot approve your own quotation.", A056_WON_REQUIRES_ORDER: "An opportunity can be Won only after its order is created.",
    A056_QUOTE_NOT_ACCEPTED: "Only an accepted quotation can become an order.", A056_THROTTLED: "Too many submissions; try later.", A056_TOKEN_INVALID: "Intake link is invalid or revoked.",
    A056_RESOLUTION_EVIDENCE_REQUIRED: "Resolution note and evidence are required.", A056_REDACT_BLOCKED_OPEN_WORK: "Close open tickets and follow-ups before redaction.",
    A056_CONFIG_INVARIANT: "Security, consent and financial rules cannot be weakened.", A056_STAGE_IN_USE: "A removed stage still has open opportunities."
  };
  function errorText(code) { return ERROR_TEXT[code] || "Request failed (" + (code || "unknown") + ")."; }

  return Object.freeze({ CHANNELS, ACTIONS, escapeHtml, csvCell, csvRow, text, normalizeEmail, normalizePhone, requestKey, REQ, quoteTotals, formatMoney, financeLabel,
    dedupeScore, consentDecision, slaDue, slaState, funnel, rate, avg, validateConfig, segmentMatch, errorText });
});
