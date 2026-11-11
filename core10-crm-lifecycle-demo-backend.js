/* C10-A056 SYNTHETIC TEST ADAPTER -- in-memory demo backend for the CRM / Customer Lifecycle UI.
 * NOT a real backend: no network, no database, no real messaging, no real orders/stock/payments/accounting.
 * Data is synthetic and tenant-partitioned; every call needs an explicit tenant and is rejected for unknown tenants.
 * RPC NAMES BELOW ARE FRONTEND-DEFINED (crm_*_demo) because docs/architecture/C10_A056_RPC_CONTRACT.md was not yet
 * available when written; the backend agent should map these 1:1 to the signed RPC contract (see RPC_MAP at the end).
 * The A049 order adapter, invoice and payment states are SYNTHETIC and always labelled NOT CERTIFIED. */
(function () {
  "use strict";
  var KEY = "c10a056-demo-v1", DAY = 864e5;
  function iso(off) { return new Date(Date.now() + (off || 0) * DAY).toISOString(); }
  function fail(code, msg) { var e = new Error(msg || code); e.code = code; throw e; }
  var ROLES = ["owner", "sales", "support", "viewer"];
  var CAPS = ["customer_edit", "consent_edit", "pipeline_edit", "quote_edit", "discount_approve", "order_request", "ticket_manage", "campaign_send", "loyalty_adjust", "view_balances", "settings_edit"];
  function defaultPerms() {
    return {
      owner: CAPS.slice(),
      sales: ["customer_edit", "pipeline_edit", "quote_edit", "order_request", "campaign_send", "view_balances"],
      support: ["customer_edit", "ticket_manage", "consent_edit"],
      viewer: []
    };
  }
  function stages() {
    return [
      { key: "new", en: "New", bn: "নতুন", kind: "open" },
      { key: "qualified", en: "Qualified", bn: "যোগ্য", kind: "open" },
      { key: "quoted", en: "Quoted", bn: "কোটেশন দেওয়া", kind: "open" },
      { key: "negotiation", en: "Negotiation", bn: "দরকষাকষি", kind: "open" },
      { key: "won", en: "Won", bn: "জিত", kind: "won" },
      { key: "lost", en: "Lost", bn: "হারানো", kind: "lost" }
    ];
  }
  function tenantSeed(id) {
    var t = { id: id, seq: 1000, customers: [], leads: [], enquiries: [], opps: [], quotes: [], orders: [], followups: [], tickets: [], segments: [], campaigns: [], events: [], audit: [], intake: [],
      settings: { stages: stages(), perms: defaultPerms(), approval: { discount_pct_owner_approval: 10, example: true },
        sla_hours: { urgent: 4, standard: 24, low: 72 }, providers: { sms: "DISABLED", email: "DISABLED", whatsapp: "DISABLED" } } };
    function C(name, kind, phone, cons, extra) {
      var c = Object.assign({ id: "C-" + (++t.seq), name: name, kind: kind, phone: phone, email: null, tags: [], created: iso(-120), points: 0,
        consent: { sms: { state: "none" }, email: { state: "none" }, whatsapp: { state: "none" } }, prefs: { channel: "sms", lang: "bn", quiet: "21:00-08:00" } }, extra || {});
      Object.keys(cons || {}).forEach(function (ch) { c.consent[ch] = cons[ch]; });
      t.customers.push(c); return c;
    }
    function O(c, total, off, pay) {
      var o = { id: "O-" + (++t.seq), customer_id: c.id, title: "Historic order", total: total, created: iso(off), state: "APPROVED", fulfillment: "DELIVERED", invoice: "ISSUED", payment: pay || "PAID", adapter: "SYNTHETIC TEST ADAPTER", historic: true };
      t.orders.push(o); return o;
    }
    function ev(c, type, text, off) { t.events.push({ customer_id: c.id, at: iso(off || 0), type: type, text: text }); }
    if (id === "T1") {
      var a = C("Nusrat Jahan", "person", "+8801711000101", { whatsapp: { state: "granted", at: iso(-60) }, sms: { state: "granted", at: iso(-60), expires: iso(200) } }, { tags: ["wedding", "vip"] });
      var b = C("Karim Uddin", "person", "+8801711000102", {});
      var d = C("Dhanmondi Event Planners Ltd", "organization", "+8801711000103", { email: { state: "granted", at: iso(-30) }, sms: { state: "revoked", at: iso(-10) } }, { email: "events@planners.example", tags: ["b2b"] });
      var e = C("Salma Begum", "person", "+8801711000104", { sms: { state: "granted", at: iso(-40), expires: iso(-1) } });
      O(a, 4200, -90); O(a, 6800, -40); O(a, 2500, -12); O(d, 18500, -30); O(b, 1200, -70, "PAID");
      ev(a, "order", "Order delivered (synthetic history)", -12); ev(a, "consent", "WhatsApp + SMS consent granted at shop (POS)", -60); ev(d, "consent", "SMS revoked by customer", -10); ev(b, "note", "Walk-in customer, no marketing consent captured", -70);
      t.followups.push({ id: "F-" + (++t.seq), customer_id: a.id, note: "Call about Eid sweet box repeat order", due: iso(-1), status: "open", assignee: "sales" });
      t.followups.push({ id: "F-" + (++t.seq), customer_id: d.id, note: "Send catering quote reminder", due: iso(2), status: "open", assignee: "sales" });
      t.tickets.push({ id: "TK-" + (++t.seq), customer_id: b.id, subject: "Box arrived damaged", type: "support", priority: "urgent", status: "OPEN", assignee: "support", created: iso(-2), sla_due: iso(-2 + 4 / 24), resolution: null, evidence: null });
      t.segments.push({ id: "S-" + (++t.seq), name: "Repeat buyers (2+ orders)", rule: { min_orders: 2, tag: "", channel: "sms" } });
      t.leads.push({ id: "L-" + (++t.seq), name: "Rafiq (custom cake enquiry)", contact: "+8801711000105", source: "website", status: "RECEIVED", created: iso(-1), note: "Birthday cake for 40 guests" });
    } else {
      var p = C("Meghna Construction Co.", "organization", "+8801811000201", { email: { state: "granted", at: iso(-50) } }, { email: "buy@meghna.example", tags: ["contractor"] });
      var q = C("Padma Interiors", "organization", "+8801811000202", {}, { tags: ["interior"] });
      O(p, 240000, -80); O(p, 310000, -30); O(q, 90000, -45);
      ev(p, "order", "Order delivered (synthetic history)", -30); ev(q, "note", "Quote requested via phone, awaiting site visit", -45);
      t.followups.push({ id: "F-" + (++t.seq), customer_id: q.id, note: "Site visit follow-up", due: iso(-3), status: "open", assignee: "sales" });
      t.segments.push({ id: "S-" + (++t.seq), name: "Email-consented contractors", rule: { min_orders: 0, tag: "contractor", channel: "email" } });
    }
    return t;
  }
  var db;
  function load() {
    try { var s = window.sessionStorage.getItem(KEY); if (s) { db = JSON.parse(s); return; } } catch (e) { /* storage may be blocked */ }
    db = { meta: { synthetic: true }, tenants: { T1: tenantSeed("T1"), T2: tenantSeed("T2") } };
  }
  function save() { try { window.sessionStorage.setItem(KEY, JSON.stringify(db)); } catch (e) { /* ignore */ } }
  load();
  var TENANTS = [{ id: "T1", name: "Rahman Sweets & Catering (B2C)", industry: "sweets custom-order" }, { id: "T2", name: "Apex Paints Ltd (B2B)", industry: "paint / construction quote" }];

  function T(a) { var t = db.tenants[a && a.tenant]; if (!t) fail("TENANT_UNKNOWN", "Unknown tenant"); return t; }
  function need(a, cap) { var t = T(a), perms = t.settings.perms[a.role]; if (!perms) fail("ROLE_UNKNOWN", "Unknown role"); if (perms.indexOf(cap) < 0) fail("FORBIDDEN", "Role '" + a.role + "' lacks capability '" + cap + "'"); }
  function id(t, p) { return p + "-" + (++t.seq); }
  function audit(t, a, action, detail) { t.audit.unshift({ at: iso(), role: a.role, action: action, detail: detail || "" }); }
  function ev(t, cid, type, text) { t.events.push({ customer_id: cid, at: iso(), type: type, text: text }); }
  function cust(t, cid) { var c = t.customers.filter(function (x) { return x.id === cid; })[0]; if (!c) fail("NOT_FOUND", "Customer not found in this tenant"); return c; }
  function find(arr, i, what) { var r = arr.filter(function (x) { return x.id === i; })[0]; if (!r) fail("NOT_FOUND", what + " not found"); return r; }
  function str(v, max, req, label) { v = (v == null ? "" : String(v)).trim(); if (req && !v) fail("VALIDATION", (label || "Field") + " is required"); if (v.length > (max || 300)) fail("VALIDATION", (label || "Field") + " too long"); return v; }
  function consentOk(c, ch, now) {
    var k = c.consent[ch]; if (!k || k.state !== "granted") return { ok: false, reason: k && k.state === "revoked" ? "opted out" : "no consent" };
    if (k.expires && new Date(k.expires).getTime() < (now || Date.now())) return { ok: false, reason: "consent expired" };
    return { ok: true };
  }
  function quoteTotal(v) {
    var sum = 0; for (var i = 0; i < v.lines.length; i++) { var l = v.lines[i]; if (l.price == null) return null; sum += l.qty * l.price; }
    return Math.round(sum * (1 - (v.discount_pct || 0) / 100) * 100) / 100;
  }
  function slaState(tk) { if (tk.status === "RESOLVED" || tk.status === "CLOSED") return "met"; return new Date(tk.sla_due).getTime() < Date.now() ? "breached" : "running"; }
  function ordersOf(t, cid) { return t.orders.filter(function (o) { return o.customer_id === cid; }); }
  function loyalty(t, c) { var spend = ordersOf(t, c.id).filter(function (o) { return o.fulfillment === "DELIVERED"; }).reduce(function (s, o) { return s + (o.total || 0); }, 0); return Math.floor(spend / 100) + (c.points || 0); }
  function segMatch(t, s, c) {
    var n = ordersOf(t, c.id).filter(function (o) { return o.fulfillment === "DELIVERED"; }).length;
    return n >= (s.rule.min_orders || 0) && (!s.rule.tag || c.tags.indexOf(s.rule.tag) >= 0);
  }
  function findDupe(t, phone) { return phone ? t.customers.filter(function (c) { return c.phone === phone; })[0] : null; }
  function ensureCustomer(t, a, name, phone, kind) {
    var c = findDupe(t, phone);
    if (c) return { c: c, created: false };
    c = { id: id(t, "C"), name: name, kind: kind || "person", phone: phone || null, email: null, tags: [], created: iso(), points: 0,
      consent: { sms: { state: "none" }, email: { state: "none" }, whatsapp: { state: "none" } }, prefs: { channel: "sms", lang: "bn", quiet: "21:00-08:00" } };
    t.customers.push(c); audit(t, a, "customer.create", c.id); return { c: c, created: true };
  }

  var H = {
    tenants: function () { return TENANTS.slice(); },
    session: function (a) { var t = T(a); return { tenant: a.tenant, role: a.role, caps: t.settings.perms[a.role] || [], stages: t.settings.stages, providers: t.settings.providers, synthetic: true, adapter: "SYNTHETIC TEST ADAPTER" }; },
    reset: function () { db = { meta: { synthetic: true }, tenants: { T1: tenantSeed("T1"), T2: tenantSeed("T2") } }; save(); return true; },

    dashboard: function (a) {
      var t = T(a), r = H.reports(a), now = Date.now();
      return { funnel: r.funnel, retention: r.retention, followups_pending: t.followups.filter(function (f) { return f.status === "open"; }).length,
        followups_overdue: t.followups.filter(function (f) { return f.status === "open" && new Date(f.due).getTime() < now; }).length,
        tickets_open: t.tickets.filter(function (k) { return k.status === "OPEN" || k.status === "IN_PROGRESS"; }).length,
        tickets_breached: t.tickets.filter(function (k) { return slaState(k) === "breached"; }).length, customers: t.customers.length,
        pipeline_value: r.quotation.value_advisory };
    },

    customers_list: function (a) {
      var t = T(a), q = String(a.q || "").toLowerCase();
      return t.customers.filter(function (c) { return !q || c.name.toLowerCase().indexOf(q) >= 0 || (c.phone || "").indexOf(q) >= 0; }).map(function (c) {
        return { id: c.id, name: c.name, kind: c.kind, phone: c.phone, tags: c.tags, orders: ordersOf(t, c.id).length, points: loyalty(t, c) };
      });
    },
    customer_get: function (a) {
      var t = T(a), c = cust(t, a.id), os = ordersOf(t, c.id), canBal = t.settings.perms[a.role].indexOf("view_balances") >= 0, bal;
      var issued = os.filter(function (o) { return o.invoice === "ISSUED"; });
      if (!canBal) bal = { status: "RESTRICTED", label: "Not permitted for this role" };
      else if (!issued.length) bal = { status: "NOT CERTIFIED", label: "NOT CERTIFIED / unavailable" };
      else bal = { status: "SYNTHETIC", outstanding: issued.filter(function (o) { return o.payment !== "PAID"; }).reduce(function (s, o) { return s + o.total; }, 0), label: "SYNTHETIC adapter figure - NOT CERTIFIED" };
      return { customer: Object.assign({}, c, { points: loyalty(t, c) }), orders: os, balance: bal, consent_checks: ["sms", "email", "whatsapp"].map(function (ch) { var k = consentOk(c, ch); return { channel: ch, state: c.consent[ch].state, expires: c.consent[ch].expires || null, sendable: k.ok, reason: k.reason || null }; }),
        timeline: t.events.filter(function (e) { return e.customer_id === c.id; }).sort(function (x, y) { return y.at < x.at ? -1 : 1; }),
        tickets: t.tickets.filter(function (k) { return k.customer_id === c.id; }).map(function (k) { return Object.assign({ sla: slaState(k) }, k); }),
        followups: t.followups.filter(function (f) { return f.customer_id === c.id; }), opps: t.opps.filter(function (o) { return o.customer_id === c.id; }),
        duplicates: t.customers.filter(function (x) { return x.id !== c.id && c.phone && x.phone === c.phone; }).map(function (x) { return { id: x.id, name: x.name }; }) };
    },
    customer_create: function (a) {
      need(a, "customer_edit"); var t = T(a), name = str(a.name, 120, true, "Name"), phone = str(a.phone, 30);
      var r = ensureCustomer(t, a, name, phone, a.kind === "organization" ? "organization" : "person");
      if (!r.created) fail("DUPLICATE", "A customer with this phone already exists: " + r.c.name + " (" + r.c.id + ")");
      ev(t, r.c.id, "note", "Customer created"); save(); return r.c;
    },
    consent_set: function (a) {
      need(a, "consent_edit"); var t = T(a), c = cust(t, a.id), ch = a.channel;
      if (["sms", "email", "whatsapp"].indexOf(ch) < 0) fail("VALIDATION", "Unknown channel");
      if (["granted", "revoked", "none"].indexOf(a.state) < 0) fail("VALIDATION", "Unknown consent state");
      var rec = { state: a.state, at: iso() }; if (a.state === "granted" && a.expires_days) rec.expires = iso(Number(a.expires_days));
      c.consent[ch] = rec; ev(t, c.id, "consent", ch.toUpperCase() + " consent -> " + a.state); audit(t, a, "consent.set", c.id + ":" + ch + ":" + a.state); save(); return rec;
    },
    prefs_set: function (a) {
      need(a, "customer_edit"); var t = T(a), c = cust(t, a.id); c.prefs = { channel: a.channel || "sms", lang: a.lang === "en" ? "en" : "bn", quiet: str(a.quiet, 20) }; ev(t, c.id, "note", "Communication preferences updated"); save(); return c.prefs;
    },
    loyalty_adjust: function (a) {
      need(a, "loyalty_adjust"); var t = T(a), c = cust(t, a.id), pts = parseInt(a.points, 10), reason = str(a.reason, 200, true, "Reason");
      if (!isFinite(pts) || !pts) fail("VALIDATION", "Points must be a non-zero integer");
      c.points = (c.points || 0) + pts; ev(t, c.id, "loyalty", "Loyalty points " + (pts > 0 ? "+" : "") + pts + " (" + reason + ")"); audit(t, a, "loyalty.adjust", c.id + ":" + pts); save(); return loyalty(t, c);
    },

    intake_submit: function (a) {
      need(a, "pipeline_edit"); var t = T(a), ch = a.source;
      if (["website", "pos", "offline", "phone"].indexOf(ch) < 0) fail("VALIDATION", "Unknown source");
      var l = { id: id(t, "L"), name: str(a.name, 120, true, "Name"), contact: str(a.contact, 60), source: ch, status: "RECEIVED", created: iso(), note: str(a.note, 500) };
      t.leads.push(l); audit(t, a, "lead.intake", l.id + ":" + ch); save(); return l;
    },
    leads_list: function (a) { var t = T(a); return { leads: t.leads.slice().reverse(), enquiries: t.enquiries.slice().reverse() }; },
    lead_to_enquiry: function (a) {
      need(a, "pipeline_edit"); var t = T(a), l = find(t.leads, a.id, "Lead");
      if (l.status !== "RECEIVED") fail("STATE", "Lead already " + l.status);
      var en = { id: id(t, "E"), lead_id: l.id, need: str(a.need || l.note, 500, true, "Need"), budget: a.budget === "" || a.budget == null ? null : Number(a.budget), status: "QUALIFIED", created: iso() };
      if (en.budget != null && !isFinite(en.budget)) fail("VALIDATION", "Budget must be numeric");
      l.status = "CONVERTED"; t.enquiries.push(en); audit(t, a, "lead.convert", l.id + "->" + en.id); save(); return en;
    },
    lead_disqualify: function (a) { need(a, "pipeline_edit"); var t = T(a), l = find(t.leads, a.id, "Lead"); l.status = "DISQUALIFIED"; l.reason = str(a.reason, 200, true, "Reason"); audit(t, a, "lead.disqualify", l.id); save(); return l; },
    enquiry_to_opportunity: function (a) {
      need(a, "pipeline_edit"); var t = T(a), en = find(t.enquiries, a.id, "Enquiry"), l = find(t.leads, en.lead_id, "Lead");
      if (en.opp_id) fail("STATE", "Opportunity already exists: " + en.opp_id);
      var r = ensureCustomer(t, a, l.name, l.contact, a.kind === "organization" ? "organization" : "person");
      var o = { id: id(t, "OP"), enquiry_id: en.id, customer_id: r.c.id, title: str(a.title || en.need, 160, true, "Title"), stage: t.settings.stages[0].key, created: iso(), est_value: en.budget, lost_reason: null };
      en.opp_id = o.id; en.status = "OPPORTUNITY"; t.opps.push(o);
      ev(t, r.c.id, "opportunity", "Opportunity " + o.id + " opened from " + l.source + " enquiry"); audit(t, a, "opp.create", o.id); save(); return { opp: o, customer_created: r.created };
    },
    pipeline: function (a) {
      var t = T(a); return { stages: t.settings.stages, opps: t.opps.map(function (o) { var c = cust(t, o.customer_id); return Object.assign({ customer_name: c.name }, o); }) };
    },
    opp_get: function (a) {
      var t = T(a), o = find(t.opps, a.id, "Opportunity"), c = cust(t, o.customer_id);
      return { opp: o, customer: { id: c.id, name: c.name }, quote: t.quotes.filter(function (q) { return q.opp_id === o.id; })[0] || null,
        order: t.orders.filter(function (x) { return x.opp_id === o.id; })[0] || null, stages: t.settings.stages, followups: t.followups.filter(function (f) { return f.opp_id === o.id; }),
        tickets: t.tickets.filter(function (k) { return k.opp_id === o.id; }) };
    },
    opp_move: function (a) {
      need(a, "pipeline_edit"); var t = T(a), o = find(t.opps, a.id, "Opportunity"), st = t.settings.stages.filter(function (s) { return s.key === a.stage; })[0];
      if (!st) fail("VALIDATION", "Unknown stage");
      if (st.kind === "won" && !t.orders.some(function (x) { return x.opp_id === o.id && x.state === "APPROVED"; })) fail("STATE", "Won requires an APPROVED order (via the approved-order adapter)");
      if (st.kind === "lost") o.lost_reason = str(a.reason, 200, true, "Lost reason");
      o.stage = st.key; ev(t, o.customer_id, "opportunity", o.id + " moved to " + st.en); audit(t, a, "opp.move", o.id + ":" + st.key); save(); return o;
    },

    quote_save: function (a) {
      need(a, "quote_edit"); var t = T(a), o = find(t.opps, a.opp_id, "Opportunity"), lines = (a.lines || []).map(function (l) {
        var price = l.price === "" || l.price == null ? null : Number(l.price), qty = Number(l.qty);
        if (!isFinite(qty) || qty <= 0) fail("VALIDATION", "Quantity must be positive"); if (price != null && (!isFinite(price) || price < 0)) fail("VALIDATION", "Price must be >= 0 or empty (unavailable)");
        return { desc: str(l.desc, 200, true, "Description"), qty: qty, price: price };
      });
      if (!lines.length) fail("VALIDATION", "At least one line is required");
      var disc = Number(a.discount_pct || 0); if (!isFinite(disc) || disc < 0 || disc > 100) fail("VALIDATION", "Discount must be 0-100");
      var q = t.quotes.filter(function (x) { return x.opp_id === o.id; })[0];
      if (!q) { q = { id: id(t, "Q"), opp_id: o.id, customer_id: o.customer_id, versions: [], status: "DRAFT" }; t.quotes.push(q); }
      if (q.status === "ACCEPTED") fail("STATE", "Accepted quotation is locked; start a new opportunity");
      var v = { v: q.versions.length + 1, lines: lines, discount_pct: disc, created: iso(), by: a.role, note: str(a.note, 200) }; v.total = quoteTotal(v); q.versions.push(v); q.status = "DRAFT";
      ev(t, o.customer_id, "quote", "Quotation " + q.id + " version " + v.v + " saved"); audit(t, a, "quote.save", q.id + ":v" + v.v); save(); return q;
    },
    quote_submit: function (a) {
      need(a, "quote_edit"); var t = T(a), q = find(t.quotes, a.id, "Quotation"), v = q.versions[q.versions.length - 1];
      if (v.total == null) fail("UNPRICED", "Cannot send: a line has no source price (unavailable is never treated as zero)");
      var needOwner = v.discount_pct > t.settings.approval.discount_pct_owner_approval;
      q.status = needOwner ? "PENDING_APPROVAL" : "SENT"; var o = find(t.opps, q.opp_id, "Opportunity"); if (!needOwner && (o.stage === "new" || o.stage === "qualified") && t.settings.stages.some(function (s) { return s.key === "quoted"; })) o.stage = "quoted";
      ev(t, q.customer_id, "quote", "Quotation v" + v.v + " " + (needOwner ? "awaiting Owner approval (discount " + v.discount_pct + "%)" : "sent")); audit(t, a, "quote.submit", q.id + ":" + q.status); save(); return q;
    },
    quote_approve: function (a) {
      need(a, "discount_approve"); var t = T(a), q = find(t.quotes, a.id, "Quotation"); if (q.status !== "PENDING_APPROVAL") fail("STATE", "Not awaiting approval");
      q.status = "SENT"; var o = find(t.opps, q.opp_id, "Opportunity"); if ((o.stage === "new" || o.stage === "qualified") && t.settings.stages.some(function (s) { return s.key === "quoted"; })) o.stage = "quoted"; audit(t, a, "quote.approve", q.id); ev(t, q.customer_id, "quote", "Discount approved by Owner; quotation sent"); save(); return q;
    },
    quote_accept: function (a) { need(a, "quote_edit"); var t = T(a), q = find(t.quotes, a.id, "Quotation"); if (q.status !== "SENT") fail("STATE", "Only a SENT quotation can be accepted"); q.status = "ACCEPTED"; ev(t, q.customer_id, "quote", "Customer accepted quotation " + q.id); audit(t, a, "quote.accept", q.id); save(); return q; },

    /* ---- approved-order adapter (SYNTHETIC; stands in for the A049 guarded signed adapter) ---- */
    order_request: function (a) {
      need(a, "order_request"); var t = T(a), q = find(t.quotes, a.quote_id, "Quotation"); if (q.status !== "ACCEPTED") fail("STATE", "Order request needs an ACCEPTED quotation");
      if (t.orders.some(function (o) { return o.quote_id === q.id; })) fail("DUPLICATE", "Order already requested for this quotation (idempotent)");
      var v = q.versions[q.versions.length - 1], o = { id: id(t, "O"), quote_id: q.id, opp_id: q.opp_id, customer_id: q.customer_id, title: "Order request from " + q.id + " v" + v.v, total: v.total, created: iso(), state: "REQUESTED", fulfillment: null, invoice: "NOT CERTIFIED", payment: "UNAVAILABLE", adapter: "SYNTHETIC TEST ADAPTER" };
      t.orders.push(o); ev(t, q.customer_id, "order", "Order request " + o.id + " submitted to approved-order adapter (SYNTHETIC) - no stock or money changed by CRM"); audit(t, a, "order.request", o.id); save(); return o;
    },
    order_adapter_step: function (a) {
      need(a, "order_request"); var t = T(a), o = find(t.orders, a.id, "Order"), s = a.step;
      var flow = { approve: ["REQUESTED", function () { o.state = "APPROVED"; var op = t.opps.filter(function (x) { return x.id === o.opp_id; })[0]; var won = t.settings.stages.filter(function (x) { return x.kind === "won"; })[0]; if (op && won) op.stage = won.key; }],
        reject: ["REQUESTED", function () { o.state = "REJECTED"; }],
        pick: ["APPROVED", function () { o.fulfillment = "PICKING"; }], dispatch: ["APPROVED", function () { if (o.fulfillment !== "PICKING") fail("STATE", "Pick first"); o.fulfillment = "DISPATCHED"; }],
        deliver: ["APPROVED", function () { if (o.fulfillment !== "DISPATCHED") fail("STATE", "Dispatch first"); o.fulfillment = "DELIVERED"; }],
        invoice: ["APPROVED", function () { if (o.fulfillment !== "DELIVERED") fail("STATE", "Deliver first"); o.invoice = "ISSUED"; o.payment = "UNPAID"; }],
        pay: ["APPROVED", function () { if (o.invoice !== "ISSUED") fail("STATE", "Invoice first"); o.payment = "PAID"; }] };
      var f = flow[s]; if (!f) fail("VALIDATION", "Unknown adapter step"); if (o.state !== f[0]) fail("STATE", "Order is " + o.state + "; step '" + s + "' needs " + f[0]);
      f[1](); ev(t, o.customer_id, "order", "Adapter (SYNTHETIC) step '" + s + "' on " + o.id); audit(t, a, "order.adapter." + s, o.id); save(); return o;
    },

    quotes_list: function (a) { var t = T(a); return t.quotes.map(function (q) { var v = q.versions[q.versions.length - 1]; return { id: q.id, opp_id: q.opp_id, customer_name: cust(t, q.customer_id).name, status: q.status, version: v.v, total: v.total, discount_pct: v.discount_pct }; }); },
    orders_list: function (a) { var t = T(a); return t.orders.map(function (o) { return Object.assign({ customer_name: cust(t, o.customer_id).name }, o); }); },
    followups_list: function (a) { var t = T(a); return t.followups.map(function (f) { var c = cust(t, f.customer_id); return Object.assign({ customer_name: c.name, overdue: f.status === "open" && new Date(f.due).getTime() < Date.now() }, f); }); },
    followup_create: function (a) {
      need(a, "customer_edit"); var t = T(a), c = cust(t, a.customer_id), days = Number(a.due_days);
      if (!isFinite(days)) fail("VALIDATION", "Due days must be numeric");
      var f = { id: id(t, "F"), customer_id: c.id, opp_id: a.opp_id || null, note: str(a.note, 300, true, "Note"), due: iso(days), status: "open", assignee: a.role }; t.followups.push(f); ev(t, c.id, "followup", "Follow-up scheduled: " + f.note); save(); return f;
    },
    followup_done: function (a) { need(a, "customer_edit"); var t = T(a), f = find(t.followups, a.id, "Follow-up"); f.status = "done"; f.done = iso(); ev(t, f.customer_id, "followup", "Follow-up completed: " + f.note); save(); return f; },

    tickets_list: function (a) { var t = T(a); return t.tickets.map(function (k) { return Object.assign({ customer_name: cust(t, k.customer_id).name, sla: slaState(k) }, k); }); },
    ticket_create: function (a) {
      need(a, "ticket_manage"); var t = T(a), c = cust(t, a.customer_id), pr = a.priority;
      if (!t.settings.sla_hours[pr]) fail("VALIDATION", "Unknown priority");
      var type = ["support", "warranty", "return_request"].indexOf(a.type) >= 0 ? a.type : "support";
      var k = { id: id(t, "TK"), customer_id: c.id, opp_id: a.opp_id || null, subject: str(a.subject, 200, true, "Subject"), type: type, priority: pr, status: "OPEN", assignee: "support", created: iso(), sla_due: iso(t.settings.sla_hours[pr] / 24), resolution: null, evidence: null };
      t.tickets.push(k); ev(t, c.id, "ticket", "Ticket " + k.id + " opened (" + type + ", " + pr + ")" + (type === "return_request" ? " - request only; CRM executes no refund/stock/finance change" : "")); audit(t, a, "ticket.create", k.id); save(); return k;
    },
    ticket_update: function (a) {
      need(a, "ticket_manage"); var t = T(a), k = find(t.tickets, a.id, "Ticket");
      if (a.assignee) k.assignee = str(a.assignee, 40);
      if (a.status) {
        if (["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"].indexOf(a.status) < 0) fail("VALIDATION", "Unknown status");
        if (a.status === "RESOLVED") { k.resolution = str(a.resolution, 500, true, "Resolution"); k.evidence = str(a.evidence, 300, true, "Resolution evidence"); k.resolved = iso(); }
        k.status = a.status;
      }
      ev(t, k.customer_id, "ticket", "Ticket " + k.id + " -> " + k.status); audit(t, a, "ticket.update", k.id + ":" + k.status); save(); return k;
    },

    segments_list: function (a) { var t = T(a); return t.segments.map(function (s) { return Object.assign({ size: t.customers.filter(function (c) { return segMatch(t, s, c); }).length }, s); }); },
    segment_create: function (a) {
      need(a, "campaign_send"); var t = T(a), mo = Number(a.min_orders || 0); if (!isFinite(mo) || mo < 0) fail("VALIDATION", "Min orders invalid");
      var s = { id: id(t, "S"), name: str(a.name, 80, true, "Name"), rule: { min_orders: mo, tag: str(a.tag, 40), channel: a.channel || "sms" } }; t.segments.push(s); audit(t, a, "segment.create", s.id); save(); return s;
    },
    segment_members: function (a) {
      var t = T(a), s = find(t.segments, a.id, "Segment"); return t.customers.filter(function (c) { return segMatch(t, s, c); }).map(function (c) { var k = consentOk(c, s.rule.channel); return { id: c.id, name: c.name, phone: c.phone, sendable: k.ok, reason: k.reason || null }; });
    },
    campaigns_list: function (a) { var t = T(a); return { campaigns: t.campaigns.slice().reverse(), providers: t.settings.providers }; },
    campaign_create: function (a) {
      need(a, "campaign_send"); var t = T(a), s = find(t.segments, a.segment_id, "Segment"), ch = a.channel;
      if (["sms", "email", "whatsapp"].indexOf(ch) < 0) fail("VALIDATION", "Unknown channel");
      var c = { id: id(t, "CP"), name: str(a.name, 100, true, "Name"), segment_id: s.id, channel: ch, message: str(a.message, 500, true, "Message"), status: "DRAFT", result: null }; t.campaigns.push(c); audit(t, a, "campaign.create", c.id); save(); return c;
    },
    campaign_send: function (a) {
      need(a, "campaign_send"); var t = T(a), c = find(t.campaigns, a.id, "Campaign"), s = find(t.segments, c.segment_id, "Segment");
      var provider = t.settings.providers[c.channel], elig = [], blocked = [];
      t.customers.filter(function (x) { return segMatch(t, s, x); }).forEach(function (x) { var k = consentOk(x, c.channel); (k.ok ? elig : blocked).push({ id: x.id, name: x.name, reason: k.reason || null }); });
      c.status = provider === "DISABLED" ? "NO_OP_PROVIDER_DISABLED" : "SENT";
      c.result = { provider: provider, external_messages_sent: 0, eligible: elig, blocked: blocked, at: iso(), note: "No-op: provider is DISABLED, nothing left this system. Eligible = would be sent only if an approved provider with verified credentials were enabled." };
      elig.forEach(function (x) { ev(t, x.id, "campaign", "Campaign '" + c.name + "' simulated (no-op) over " + c.channel); }); blocked.forEach(function (x) { ev(t, x.id, "campaign", "Campaign '" + c.name + "' BLOCKED: " + x.reason); });
      audit(t, a, "campaign.send", c.id + ":elig=" + elig.length + ":blocked=" + blocked.length); save(); return c;
    },

    reports: function (a) {
      var t = T(a), d = function (arr, f) { return arr.filter(f).length; }, orders = t.orders.filter(function (o) { return !o.historic; });
      var funnel = { leads: t.leads.length, enquiries: t.enquiries.length, opportunities: t.opps.length, quotes: t.quotes.length, orders: orders.length, delivered: d(orders, function (o) { return o.fulfillment === "DELIVERED"; }), invoiced: d(orders, function (o) { return o.invoice === "ISSUED"; }), paid: d(orders, function (o) { return o.payment === "PAID"; }) };
      var bought = t.customers.filter(function (c) { return ordersOf(t, c.id).some(function (o) { return o.fulfillment === "DELIVERED"; }); }), repeat = bought.filter(function (c) { return ordersOf(t, c.id).filter(function (o) { return o.fulfillment === "DELIVERED"; }).length >= 2; });
      var priced = 0, unpriced = 0; t.quotes.forEach(function (q) { var v = q.versions[q.versions.length - 1]; if (v.total == null) unpriced++; else priced += v.total; });
      var res = t.tickets.filter(function (k) { return k.resolved; }), hrs = res.length ? res.reduce(function (s, k) { return s + (new Date(k.resolved) - new Date(k.created)) / 36e5; }, 0) / res.length : null;
      var cons = {}; ["sms", "email", "whatsapp"].forEach(function (ch) { cons[ch] = { granted: d(t.customers, function (c) { return consentOk(c, ch).ok; }), total: t.customers.length }; });
      var cs = t.campaigns.filter(function (c) { return c.result; });
      return { funnel: funnel, conversion: { lead_to_enquiry: funnel.leads ? funnel.enquiries / funnel.leads : null, enquiry_to_opp: funnel.enquiries ? funnel.opportunities / funnel.enquiries : null, opp_to_order: funnel.opportunities ? funnel.orders / funnel.opportunities : null },
        retention: { buyers: bought.length, repeat: repeat.length, rate: bought.length ? repeat.length / bought.length : null },
        followups: { pending: d(t.followups, function (f) { return f.status === "open"; }), overdue: d(t.followups, function (f) { return f.status === "open" && new Date(f.due) < new Date(); }) },
        tickets: { open: d(t.tickets, function (k) { return k.status === "OPEN" || k.status === "IN_PROGRESS"; }), breached: d(t.tickets, function (k) { return slaState(k) === "breached"; }), resolved: res.length, avg_resolution_hours: hrs },
        quotation: { value_advisory: priced, unpriced_quotes: unpriced }, consent: cons,
        campaigns: { runs: cs.length, eligible: cs.reduce(function (s, c) { return s + c.result.eligible.length; }, 0), blocked: cs.reduce(function (s, c) { return s + c.result.blocked.length; }, 0), external_sent: 0 },
        profit: { status: "NOT CERTIFIED", reason: "COGS / margin source not certified; never derived from CRM quotes" } };
    },

    settings_get: function (a) { var t = T(a); return { settings: t.settings, roles: ROLES, caps: CAPS, locked: ["Consent enforcement (no consent = no send)", "CRM never mutates stock, money, payroll or accounts", "Tenant isolation", "Audit trail"], audit: t.audit.slice(0, 40) }; },
    stage_save: function (a) {
      need(a, "settings_edit"); var t = T(a), st = t.settings.stages, key = str(a.key, 30, true, "Key").toLowerCase();
      if (!/^[a-z0-9_]+$/.test(key)) fail("VALIDATION", "Key: letters, digits, underscore only");
      var ex = st.filter(function (s) { return s.key === key; })[0], kind = ["open", "won", "lost"].indexOf(a.kind) >= 0 ? a.kind : "open";
      if (ex) { ex.en = str(a.en, 40, true, "English label"); ex.bn = str(a.bn, 40, true, "Bangla label"); }
      else { var lost = st.map(function (s) { return s.kind; }).lastIndexOf("open"); st.splice(lost + 1, 0, { key: key, en: str(a.en, 40, true, "English label"), bn: str(a.bn, 40, true, "Bangla label"), kind: kind }); }
      audit(t, a, "stage.save", key); save(); return st;
    },
    stage_delete: function (a) {
      need(a, "settings_edit"); var t = T(a), st = t.settings.stages, s = st.filter(function (x) { return x.key === a.key; })[0]; if (!s) fail("NOT_FOUND", "Stage not found");
      if (t.opps.some(function (o) { return o.stage === s.key; })) fail("STATE", "Stage has opportunities; move them first");
      if (s.kind !== "open" && st.filter(function (x) { return x.kind === s.kind; }).length < 2) fail("STATE", "Keep at least one " + s.kind + " stage");
      if (st.length <= 3) fail("STATE", "Keep at least 3 stages");
      t.settings.stages = st.filter(function (x) { return x !== s; }); audit(t, a, "stage.delete", s.key); save(); return t.settings.stages;
    },
    perm_set: function (a) {
      need(a, "settings_edit"); var t = T(a), p = t.settings.perms;
      if (!p[a.target_role] || CAPS.indexOf(a.cap) < 0) fail("VALIDATION", "Unknown role/capability");
      if (a.target_role === "owner") fail("LOCKED", "Owner capabilities are locked (security invariant)");
      var i = p[a.target_role].indexOf(a.cap); if (a.on && i < 0) p[a.target_role].push(a.cap); if (!a.on && i >= 0) p[a.target_role].splice(i, 1);
      audit(t, a, "perm.set", a.target_role + ":" + a.cap + ":" + !!a.on); save(); return p;
    },
    approval_set: function (a) { need(a, "settings_edit"); var t = T(a), v = Number(a.discount_pct); if (!isFinite(v) || v < 0 || v > 100) fail("VALIDATION", "0-100"); t.settings.approval.discount_pct_owner_approval = v; audit(t, a, "approval.set", String(v)); save(); return t.settings.approval; },
    sla_set: function (a) {
      need(a, "settings_edit"); var t = T(a), s = {}; ["urgent", "standard", "low"].forEach(function (k) { var v = Number(a[k]); if (!isFinite(v) || v <= 0) fail("VALIDATION", "SLA hours must be > 0"); s[k] = v; });
      t.settings.sla_hours = s; audit(t, a, "sla.set", JSON.stringify(s)); save(); return s;
    }
  };

  /* Frontend UI call -> intended signed RPC in docs/architecture/C10_A056_RPC_CONTRACT.md (names align; argument/return shapes are
   * simplified in this synthetic adapter and a real client wrapper must translate p_* args, p_request idempotency keys and
   * p_expected versions). Calls with null have no 1:1 contract RPC yet (reconcile). */
  var RPC_MAP = {
    dashboard: "a056_report_dashboard_v1", customers_list: "a056_list_customers_v1", customer_get: "a056_read_customer360_v1", customer_create: "a056_create_customer_v1",
    consent_set: "a056_record_consent_v1", prefs_set: "a056_set_comm_prefs_v1", loyalty_adjust: null, intake_submit: "a056_create_lead_v1", leads_list: "a056_list_leads_v1",
    lead_to_enquiry: "a056_create_enquiry_v1", lead_disqualify: "a056_qualify_lead_v1", enquiry_to_opportunity: "a056_create_opportunity_v1", pipeline: "a056_read_pipeline_v1",
    opp_get: "a056_list_opportunities_v1", opp_move: "a056_move_opportunity_stage_v1", quote_save: "a056_create_quotation_v1/a056_revise_quotation_v1", quote_submit: "a056_decide_quotation_v1(submit)",
    quote_approve: "a056_decide_quotation_v1(approve)", quote_accept: "a056_decide_quotation_v1(accept)", order_request: "a056_convert_quote_to_order_v1", order_adapter_step: "a056_TEST_ADAPTER_create_order_v1 (synthetic only)",
    quotes_list: "a056_list_quotations_v1", orders_list: "a056_read_order_links_v1", followups_list: "a056_list_followups_v1", followup_create: "a056_create_followup_v1", followup_done: "a056_complete_followup_v1", tickets_list: "a056_list_tickets_v1", ticket_create: "a056_create_ticket_v1",
    ticket_update: "a056_update_ticket_v1", segments_list: "a056_list_segments_v1", segment_create: "a056_save_segment_v1", segment_members: "a056_evaluate_segment_v1", campaigns_list: "a056_list_campaigns_v1",
    campaign_create: "a056_create_campaign_v1", campaign_send: "a056_dispatch_campaign_v1", reports: "a056_report_*_v1", settings_get: "a056_read_settings_v1", stage_save: "a056_set_settings_v1",
    stage_delete: "a056_set_settings_v1", perm_set: "a056_set_settings_v1", approval_set: "a056_set_settings_v1", sla_set: "a056_set_settings_v1"
  };

  window.CORE10_CRM_BACKEND = {
    synthetic: true, label: "SYNTHETIC TEST ADAPTER (in-memory, not a real backend)", RPC_MAP: RPC_MAP,
    call: function (name, args) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          try { if (!H[name]) fail("NOT_IMPLEMENTED", "Unknown call " + name); var r = H[name](JSON.parse(JSON.stringify(args || {}))); resolve(JSON.parse(JSON.stringify(r === undefined ? null : r))); }
          catch (e) { reject(e); }
        }, 0);
      });
    }
  };
})();
