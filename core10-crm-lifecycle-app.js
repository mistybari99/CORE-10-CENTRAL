/* C10-A056 CRM & Customer Lifecycle UI. Backend = window.CORE10_CRM_BACKEND (the SYNTHETIC TEST ADAPTER in demo mode,
 * or the signed client wrapper when supplied). All user content is escaped; no inline handlers/styles (CSP). */
(function () {
  "use strict";
  var B = window.CORE10_CRM_BACKEND, root = document.getElementById("crm-root");
  var S = { tenant: "T1", role: "owner", lang: "en", route: "dashboard", arg: null, nav: false, msg: null, tenants: [], session: null };
  try { var sv = JSON.parse(window.localStorage.getItem("c10a056-ui") || "{}"); if (sv.lang === "bn" || sv.lang === "en") S.lang = sv.lang; } catch (e) { /* storage optional */ }
  function esc(v) { return String(v == null ? "" : v).replace(/[&<>"'`]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;", "`": "&#96;" }[c]; }); }
  function T(en, bn) { return S.lang === "bn" ? bn : en; }
  function csvCell(v) { var s = String(v == null ? "" : v); if (/^[=+\-@\t\r]/.test(s)) s = "'" + s; return '"' + s.replace(/"/g, '""') + '"'; }
  function fdt(d) { return d ? String(d).slice(0, 16).replace("T", " ") : "-"; }
  function money(v) { return v == null ? '<span class="nc">' + T("unavailable", "পাওয়া যায়নি") + "</span>" : "৳" + Number(v).toLocaleString("en-US", { maximumFractionDigits: 2 }); }
  function pct(v) { return v == null ? '<span class="nc">n/a</span>' : (Math.round(v * 1000) / 10) + "%"; }
  function pill(t, c) { return '<span class="pill ' + (c || "") + '">' + esc(t) + "</span>"; }
  var SC = { OPEN: "warn", IN_PROGRESS: "warn", RESOLVED: "ok", CLOSED: "", APPROVED: "ok", REQUESTED: "warn", REJECTED: "bad", DELIVERED: "ok", PAID: "ok", UNPAID: "warn", ISSUED: "ok", SENT: "ok", ACCEPTED: "ok", DRAFT: "", PENDING_APPROVAL: "warn", breached: "bad", running: "warn", met: "ok" };
  function st(v) { return pill(v == null ? "-" : v, SC[v] || ((/NOT CERT|UNAVAIL/.test(v || "")) ? "warn" : "")); }
  function api(n, a) { return B.call(n, Object.assign({ tenant: S.tenant, role: S.role }, a || {})); }
  function can(cap) { return S.session && S.session.caps.indexOf(cap) >= 0; }
  var SYN = '<span class="pill syn">SYNTHETIC TEST ADAPTER</span>';

  /* ---- contextual help: what / why / when (Bangla + English) ---- */
  var HELP = {
    intake: ["Records an enquiry from website, POS, offline or phone as a RECEIVED lead. Nothing is ordered or charged.", "Every channel lands in one pipeline so no enquiry is lost.", "Whenever a customer asks for something, in any channel.",
      "যেকোনো চ্যানেলের (ওয়েবসাইট, POS, অফলাইন, ফোন) অনুসন্ধান 'RECEIVED' লিড হিসেবে রাখে। কোনো অর্ডার বা চার্জ হয় না।", "সব চ্যানেল এক পাইপলাইনে আসে, কোনো অনুসন্ধান হারায় না।", "গ্রাহক কিছু জানতে চাইলেই।"],
    convert: ["Qualifies the lead into an enquiry with a stated need and optional budget.", "Separates real demand from noise before staff time is spent.", "After a first call/check shows genuine interest.",
      "লিডকে প্রয়োজন ও বাজেটসহ অনুসন্ধানে রূপান্তর করে।", "প্রকৃত চাহিদা আলাদা করে কর্মীর সময় বাঁচায়।", "প্রথম যোগাযোগে আগ্রহ নিশ্চিত হলে।"],
    opp: ["Opens an opportunity on the pipeline and links (or creates) the customer; duplicates are matched by phone.", "Tracks value and stage until won or lost.", "When an enquiry is worth quoting.",
      "পাইপলাইনে সুযোগ খোলে এবং গ্রাহক লিংক/তৈরি করে; ফোন নম্বরে ডুপ্লিকেট মেলানো হয়।", "জিত বা হারা পর্যন্ত মূল্য ও ধাপ ট্র্যাক করে।", "অনুসন্ধানে কোটেশন দেওয়ার মতো হলে।"],
    quote: ["Saves a new immutable quotation version. A line without a source price stays UNAVAILABLE and blocks sending - it is never treated as zero.", "Keeps a revision history and stops accidental under-pricing.", "Each time terms or prices change.",
      "নতুন অপরিবর্তনীয় কোটেশন ভার্সন সংরক্ষণ করে। উৎস-মূল্যহীন লাইন 'পাওয়া যায়নি' থাকে ও পাঠানো আটকায় - শূন্য ধরা হয় না।", "পরিবর্তনের ইতিহাস রাখে ও ভুল কম দাম ঠেকায়।", "শর্ত বা দাম বদলালে।"],
    order: ["Sends an order REQUEST to the approved-order adapter. CRM itself never changes stock, money or accounts.", "Orders stay under the canonical order/stock controls.", "Only after the customer accepted the quotation.",
      "অনুমোদিত-অর্ডার অ্যাডাপ্টারে অর্ডার অনুরোধ পাঠায়। CRM নিজে স্টক, টাকা বা হিসাব বদলায় না।", "অর্ডার মূল অর্ডার/স্টক নিয়ন্ত্রণেই থাকে।", "গ্রাহক কোটেশন গ্রহণ করার পরই।"],
    adapter: ["Drives the SYNTHETIC adapter through approve, pick, dispatch, deliver, invoice and pay so the journey can be demonstrated.", "Shows the end-to-end flow without touching real stock/payments.", "Demo only; real systems replace this adapter.",
      "ডেমো দেখাতে সিন্থেটিক অ্যাডাপ্টারে অনুমোদন থেকে পেমেন্ট পর্যন্ত ধাপ চালায়।", "আসল স্টক/পেমেন্ট না ছুঁয়ে পুরো প্রবাহ দেখায়।", "শুধু ডেমোতে; বাস্তবে এই অ্যাডাপ্টার প্রতিস্থাপিত হবে।"],
    consent: ["Records per-channel consent: granted, revoked or none (with optional expiry).", "No consent, revoked or expired consent blocks marketing sends; opt-out always wins.", "When a customer agrees or withdraws, at shop, phone or web.",
      "চ্যানেলভিত্তিক সম্মতি: দেওয়া, প্রত্যাহার বা নেই (মেয়াদসহ)।", "সম্মতি না থাকলে, প্রত্যাহার বা মেয়াদ শেষ হলে মার্কেটিং বার্তা আটকায়; opt-out সর্বদা অগ্রাধিকার পায়।", "গ্রাহক সম্মতি দিলে বা তুললে।"],
    followup: ["Schedules a follow-up task with a due date.", "Prevents customers and quotes going cold.", "After any call, quote or ticket that needs a next step.",
      "নির্ধারিত তারিখসহ ফলো-আপ কাজ তৈরি করে।", "গ্রাহক বা কোটেশন ঠান্ডা হতে দেয় না।", "কল, কোটেশন বা টিকিটের পরবর্তী ধাপ দরকার হলে।"],
    ticket: ["Opens a support, warranty or return-request ticket with a priority-based SLA. Return requests only record intent: no refund or stock change.", "Makes resolution measurable and keeps finance/stock safe.", "When a customer reports a problem.",
      "অগ্রাধিকারভিত্তিক SLA-সহ সাপোর্ট, ওয়ারেন্টি বা রিটার্ন অনুরোধ টিকিট খোলে। রিটার্ন কেবল অনুরোধ রাখে: রিফান্ড বা স্টক বদলায় না।", "সমাধান পরিমাপযোগ্য রাখে, অর্থ/স্টক নিরাপদ রাখে।", "গ্রাহক সমস্যা জানালে।"],
    resolve: ["Resolving requires a written resolution and evidence.", "So the closure can be audited.", "When the problem is actually fixed.", "সমাধানের জন্য লিখিত সমাধান ও প্রমাণ লাগে।", "যাতে বন্ধ করা অডিটযোগ্য হয়।", "সমস্যা সত্যিই মিটলে।"],
    segment: ["Builds a customer segment from min orders, tag and channel.", "Targets campaigns; members without consent are flagged, not messaged.", "Before a campaign.", "ন্যূনতম অর্ডার, ট্যাগ ও চ্যানেল দিয়ে গ্রাহক সেগমেন্ট বানায়।", "ক্যাম্পেইন টার্গেট করে; সম্মতিহীনদের চিহ্নিত করে, বার্তা পাঠায় না।", "ক্যাম্পেইনের আগে।"],
    campaign: ["Sends to a segment through the provider. The provider is DISABLED, so the run is a NO-OP: consent is checked and counted, nothing leaves the system.", "Shows who would be reached and who is blocked, safely.", "When you want a dry-run of an outreach.", "সেগমেন্টে প্রোভাইডার দিয়ে পাঠায়। প্রোভাইডার DISABLED, তাই NO-OP: সম্মতি যাচাই ও গণনা হয়, কিছু বাইরে যায় না।", "কারা পাবে ও কারা আটকাবে নিরাপদে দেখায়।", "আউটরিচের ড্রাই-রান চাইলে।"],
    loyalty: ["Adds or removes loyalty points with a mandatory reason. Base points = delivered spend / 100.", "Keeps goodwill adjustments auditable.", "For corrections or goodwill.", "কারণসহ লয়্যালটি পয়েন্ট যোগ/বিয়োগ করে। মূল পয়েন্ট = ডেলিভারড খরচ / ১০০।", "গুডউইল সমন্বয় অডিটযোগ্য রাখে।", "সংশোধন বা সদিচ্ছায়।"],
    prefs: ["Stores preferred channel, language and quiet hours.", "Respects how the customer wants to be contacted.", "When the customer states a preference.", "পছন্দের চ্যানেল, ভাষা ও নীরব সময় সংরক্ষণ করে।", "গ্রাহকের পছন্দ মেনে যোগাযোগ করতে।", "গ্রাহক পছন্দ জানালে।"],
    stage: ["Adds or renames pipeline stages (Owner only).", "Each business sells differently.", "When your sales process changes. Stages holding opportunities cannot be deleted.", "পাইপলাইন ধাপ যোগ/নাম পরিবর্তন (শুধু মালিক)।", "প্রতিটি ব্যবসার বিক্রয়-প্রক্রিয়া আলাদা।", "প্রক্রিয়া বদলালে। যে ধাপে সুযোগ আছে তা মোছা যায় না।"],
    perms: ["Toggles which role may do which action. Owner rights and security invariants are locked.", "Least-privilege staff access.", "When roles change.", "কোন ভূমিকা কোন কাজ করতে পারবে তা ঠিক করে। মালিকের অধিকার ও নিরাপত্তা-নিয়ম লক করা।", "ন্যূনতম অধিকার নীতি।", "ভূমিকা বদলালে।"],
    approval: ["A quotation discount above this percentage needs Owner approval before it can be sent.", "Protects margin.", "Adjust to your discount policy.", "এই শতাংশের বেশি ডিসকাউন্টে পাঠানোর আগে মালিকের অনুমোদন লাগে।", "মার্জিন রক্ষা করে।", "ডিসকাউন্ট নীতি অনুযায়ী বদলান।"],
    sla: ["SLA hours per priority. Defaults are Owner-editable EXAMPLES, not promises.", "Drives breach warnings.", "When you set your service policy.", "অগ্রাধিকার অনুযায়ী SLA ঘণ্টা। ডিফল্ট মালিক-সম্পাদনযোগ্য উদাহরণ, প্রতিশ্রুতি নয়।", "লঙ্ঘন সতর্কতা চালায়।", "সেবা-নীতি ঠিক করলে।"],
    reports: ["Funnel, retention, follow-ups, tickets, consent and quotation value. Profit/COGS is NOT CERTIFIED.", "One place to judge the sales and service health.", "Weekly review.", "ফানেল, রিটেনশন, ফলো-আপ, টিকিট, সম্মতি ও কোটেশন মূল্য। মুনাফা/COGS সার্টিফায়েড নয়।", "বিক্রয় ও সেবার স্বাস্থ্য এক জায়গায়।", "সাপ্তাহিক পর্যালোচনা।"],
    dup: ["Duplicates are matched by phone number.", "One customer, one record.", "Shown when another record shares a phone.", "ফোন নম্বর দিয়ে ডুপ্লিকেট মেলানো হয়।", "এক গ্রাহক, এক রেকর্ড।", "অন্য রেকর্ডের একই ফোন থাকলে দেখায়।"]
  };
  function help(k) {
    var h = HELP[k], o = S.lang === "bn" ? 3 : 0; if (!h) return "";
    return '<button type="button" class="help" data-act="help" data-k="' + esc(k) + '" aria-label="' + esc(T("Help", "সহায়তা")) + '" aria-expanded="false">?</button>' +
      '<div class="helpbox" id="help-' + esc(k) + '" role="note" hidden><div><b>' + T("What", "কী") + ":</b> " + esc(h[o]) + "</div><div><b>" + T("Why", "কেন") + ":</b> " + esc(h[o + 1]) + "</div><div><b>" + T("When", "কখন") + ":</b> " + esc(h[o + 2]) + "</div></div>";
  }
  function gate(cap, html) { return can(cap) ? html : '<p class="mut small">' + esc(T("Your role cannot do this (" + cap + ").", "আপনার ভূমিকা এটি করতে পারে না (" + cap + ")।")) + "</p>"; }

  var NAV = [["dashboard", "Dashboard", "ড্যাশবোর্ড", "g1"], ["customers", "Customers & organizations", "গ্রাহক ও প্রতিষ্ঠান", "g1"], ["intake", "Intake simulator", "অনুসন্ধান ইনটেক", "g2"], ["leads", "Leads & enquiries", "লিড ও অনুসন্ধান", "g2"],
    ["pipeline", "Opportunity pipeline", "সুযোগ পাইপলাইন", "g2"], ["quotes", "Quotations & orders", "কোটেশন ও অর্ডার", "g2"], ["followups", "Follow-ups", "ফলো-আপ", "g2"], ["support", "Support tickets", "সাপোর্ট টিকিট", "g3"], ["segments", "Segments", "সেগমেন্ট", "g3"],
    ["campaigns", "Campaigns", "ক্যাম্পেইন", "g3"], ["loyalty", "Loyalty & preferences", "লয়্যালটি ও পছন্দ", "g3"], ["reports", "Reports", "রিপোর্ট", "g4"], ["settings", "Settings", "সেটিংস", "g4"], ["journey", "End-to-end journey", "এন্ড-টু-এন্ড যাত্রা", "g4"]];
  var GN = { g1: ["Overview", "সারসংক্ষেপ"], g2: ["Sales", "বিক্রয়"], g3: ["Service & marketing", "সেবা ও মার্কেটিং"], g4: ["Insight & control", "বিশ্লেষণ ও নিয়ন্ত্রণ"] };

  function shell(inner) {
    var g = "", last = "";
    NAV.forEach(function (n) { if (n[3] !== last) { last = n[3]; g += '<div class="grp">' + esc(T(GN[last][0], GN[last][1])) + "</div>"; } g += '<a id="nav-' + n[0] + '" href="#/' + n[0] + '"' + (S.route === n[0] || (S.route === "customer" && n[0] === "customers") || (S.route === "opp" && n[0] === "pipeline") ? ' aria-current="page"' : "") + ">" + esc(T(n[1], n[2])) + "</a>"; });
    var tn = S.tenants.map(function (t) { return '<option value="' + esc(t.id) + '"' + (t.id === S.tenant ? " selected" : "") + ">" + esc(t.name) + "</option>"; }).join("");
    var rl = ["owner", "sales", "support", "viewer"].map(function (r) { return '<option value="' + r + '"' + (r === S.role ? " selected" : "") + ">" + r + "</option>"; }).join("");
    return '<header class="bar"><button id="menu-btn" type="button" data-act="menu" aria-expanded="' + S.nav + '">' + esc(T("Menu", "মেনু")) + '</button><div class="brand">CORE 10 · CRM &amp; ' + esc(T("Customer Lifecycle", "গ্রাহক লাইফসাইকেল")) + "</div>" +
      '<label class="small" for="tenant-sel">' + esc(T("Business", "ব্যবসা")) + '</label><select id="tenant-sel" data-chg="tenant">' + tn + '</select><label class="small" for="role-sel">' + esc(T("Role", "ভূমিকা")) + '</label><select id="role-sel" data-chg="role">' + rl + "</select>" +
      '<button id="lang-btn" type="button" data-act="lang">' + (S.lang === "bn" ? "English" : "বাংলা") + "</button></header>" +
      '<div class="syn-banner" id="syn-banner">' + esc(T("SYNTHETIC TEST ADAPTER - in-memory demo data. No real messages, orders, stock, payments or accounting. Invoice/payment/profit are NOT CERTIFIED.", "সিন্থেটিক টেস্ট অ্যাডাপ্টার - ইন-মেমরি ডেমো ডেটা। কোনো আসল বার্তা, অর্ডার, স্টক, পেমেন্ট বা হিসাব নেই। ইনভয়েস/পেমেন্ট/মুনাফা সার্টিফায়েড নয়।")) + "</div>" +
      '<div class="shell"><nav class="side' + (S.nav ? " open" : "") + '" aria-label="' + esc(T("Sections", "বিভাগ")) + '">' + g + '</nav><main id="main" tabindex="-1">' + (S.msg ? '<div class="msg ' + (S.msg.t === "err" ? "err" : "okm") + '" role="status" id="toast">' + esc(S.msg.text) + "</div>" : "") + inner + "</main></div>";
  }

  function custOpts(list, sel) { return list.map(function (c) { return '<option value="' + esc(c.id) + '"' + (c.id === sel ? " selected" : "") + ">" + esc(c.name) + " (" + esc(c.id) + ")</option>"; }).join(""); }
  function table(head, rows, empty) {
    if (!rows.length) return '<p class="mut">' + esc(empty || T("Nothing here yet.", "এখনো কিছু নেই।")) + "</p>";
    return '<div class="tbl-wrap"><table><thead><tr>' + head.map(function (h) { return "<th>" + esc(h) + "</th>"; }).join("") + "</tr></thead><tbody>" + rows.map(function (r) { return "<tr>" + r.map(function (c) { return "<td>" + c + "</td>"; }).join("") + "</tr>"; }).join("") + "</tbody></table></div>";
  }
  function bar(label, n, max) { return '<div class="fr"><span class="small">' + esc(label) + '</span><div class="bar-h"><span data-w="' + (max ? Math.round(100 * n / max) : 0) + '"></span></div><b>' + esc(n) + "</b></div>"; }

  /* ---------------- views ---------------- */
  var V = {};
  V.dashboard = async function () {
    var d = await api("dashboard"), f = d.funnel, mx = Math.max(1, f.leads, f.enquiries, f.opportunities, f.quotes, f.orders);
    return "<h1>" + esc(T("Dashboard", "ড্যাশবোর্ড")) + '</h1><div class="grid c4">' +
      '<div class="card kpi" id="kpi-customers">' + esc(d.customers) + "<small>" + esc(T("Customers", "গ্রাহক")) + "</small></div>" +
      '<div class="card kpi" id="kpi-followups">' + esc(d.followups_pending) + "<small>" + esc(T("Pending follow-ups", "অপেক্ষমাণ ফলো-আপ")) + " · " + esc(d.followups_overdue) + " " + esc(T("overdue", "মেয়াদোত্তীর্ণ")) + "</small></div>" +
      '<div class="card kpi" id="kpi-tickets">' + esc(d.tickets_open) + "<small>" + esc(T("Open tickets", "খোলা টিকিট")) + " · " + esc(d.tickets_breached) + " " + esc(T("SLA breached", "SLA লঙ্ঘিত")) + "</small></div>" +
      '<div class="card kpi" id="kpi-retention">' + pct(d.retention.rate) + "<small>" + esc(T("Retention (repeat buyers)", "রিটেনশন (পুনরায় ক্রেতা)")) + " " + esc(d.retention.repeat) + "/" + esc(d.retention.buyers) + "</small></div></div>" +
      '<div class="grid c2"><div class="card funnel" id="funnel"><h2>' + esc(T("Conversion funnel", "কনভার্সন ফানেল")) + " " + help("reports") + "</h2>" +
      bar(T("Leads", "লিড"), f.leads, mx) + bar(T("Enquiries", "অনুসন্ধান"), f.enquiries, mx) + bar(T("Opportunities", "সুযোগ"), f.opportunities, mx) + bar(T("Quotations", "কোটেশন"), f.quotes, mx) + bar(T("Order requests", "অর্ডার অনুরোধ"), f.orders, mx) +
      "</div><div class=\"card\"><h2>" + esc(T("Quotation value (advisory)", "কোটেশন মূল্য (পরামর্শমূলক)")) + "</h2><div class=\"kpi\">" + money(d.pipeline_value) + "</div><p class=\"mut small\">" + esc(T("Unpriced lines are excluded, never counted as zero. Not revenue.", "মূল্যহীন লাইন বাদ, শূন্য ধরা হয় না। এটি রাজস্ব নয়।")) +
      '</p><p><a class="btn pri" href="#/journey">' + esc(T("Start the end-to-end journey", "এন্ড-টু-এন্ড যাত্রা শুরু করুন")) + "</a></p></div></div>";
  };

  V.customers = async function () {
    var list = await api("customers_list", { q: S.q || "" });
    return "<h1>" + esc(T("Customers & organizations", "গ্রাহক ও প্রতিষ্ঠান")) + '</h1><form class="row" data-form="cust_search"><input id="cust-q" name="q" aria-label="' + esc(T("Search", "খুঁজুন")) + '" placeholder="' + esc(T("Search name or phone", "নাম বা ফোন খুঁজুন")) + '" value="' + esc(S.q || "") + '"><button class="pri" type="submit">' + esc(T("Search", "খুঁজুন")) + "</button></form>" +
      '<div class="card">' + table([T("Name", "নাম"), T("Type", "ধরন"), T("Phone", "ফোন"), T("Orders", "অর্ডার"), T("Points", "পয়েন্ট")], list.map(function (c) { return ['<a href="#/customer/' + esc(c.id) + '">' + esc(c.name) + "</a>", esc(c.kind), esc(c.phone || "-"), esc(c.orders), esc(c.points)]; })) + "</div>" +
      '<div class="card"><h2>' + esc(T("Add customer / organization", "গ্রাহক / প্রতিষ্ঠান যোগ")) + "</h2>" + gate("customer_edit", '<form data-form="cust_create"><label for="cc-name">' + esc(T("Name", "নাম")) + '</label><input id="cc-name" name="name" required maxlength="120"><label for="cc-phone">' + esc(T("Phone", "ফোন")) + '</label><input id="cc-phone" name="phone" maxlength="30"><label for="cc-kind">' + esc(T("Type", "ধরন")) + '</label><select id="cc-kind" name="kind"><option value="person">person</option><option value="organization">organization</option></select><p><button class="pri" id="cc-save" type="submit">' + esc(T("Create", "তৈরি")) + "</button> " + help("dup") + "</p></form>") + "</div>";
  };

  V.customer = async function () {
    var d = await api("customer_get", { id: S.arg }), c = d.customer, b = d.balance;
    var balHtml = b.status === "SYNTHETIC" ? money(b.outstanding) + " " + SYN + ' <span class="nc">' + esc(b.label) + "</span>" : '<span class="nc" id="bal-status">' + esc(b.label) + "</span>";
    var cons = table([T("Channel", "চ্যানেল"), T("State", "অবস্থা"), T("Can send?", "পাঠানো যাবে?"), T("Change", "পরিবর্তন")], d.consent_checks.map(function (k) {
      return [esc(k.channel), st(k.state) + (k.expires ? ' <span class="small mut">' + esc(T("expires", "মেয়াদ")) + " " + esc(fdt(k.expires)) + "</span>" : ""), k.sendable ? pill(T("yes", "হ্যাঁ"), "ok") : pill(T("blocked: ", "আটকানো: ") + k.reason, "bad"),
        can("consent_edit") ? ["granted", "revoked", "none"].map(function (s) { return '<button type="button" id="cons-' + esc(c.id) + "-" + k.channel + "-" + s + '" data-act="consent" data-id="' + esc(c.id) + '" data-ch="' + k.channel + '" data-s="' + s + '">' + esc(s) + "</button>"; }).join(" ") : esc(T("no permission", "অনুমতি নেই"))];
    }));
    return '<p><a href="#/customers">&larr; ' + esc(T("Customers", "গ্রাহক")) + "</a></p><h1 id=\"cust-name\">" + esc(c.name) + " " + pill(c.kind) + "</h1><p class=\"mut wrap\">" + esc(c.id) + " · " + esc(c.phone || "-") + " · " + esc(c.email || "-") + " · " + c.tags.map(function (x) { return pill(x); }).join(" ") + "</p>" +
      (d.duplicates.length ? '<div class="msg err">' + esc(T("Possible duplicate: ", "সম্ভাব্য ডুপ্লিকেট: ")) + d.duplicates.map(function (x) { return esc(x.name) + " (" + esc(x.id) + ")"; }).join(", ") + "</div>" : "") +
      '<div class="grid c2"><div class="card"><h2>' + esc(T("Balance & payment status", "ব্যালেন্স ও পেমেন্ট অবস্থা")) + '</h2><p>' + balHtml + '</p><p class="mut small">' + esc(T("Shown only from a certified finance source. Missing = unavailable, never zero.", "শুধু সার্টিফায়েড ফাইন্যান্স উৎস থেকে। না থাকলে 'পাওয়া যায়নি', কখনো শূন্য নয়।")) + "</p>" +
      "<h3>" + esc(T("Orders", "অর্ডার")) + "</h3>" + table(["ID", T("Title", "শিরোনাম"), T("Total", "মোট"), T("State", "অবস্থা"), T("Payment", "পেমেন্ট")], d.orders.map(function (o) { return [esc(o.id), esc(o.title), money(o.total), st(o.state) + " " + st(o.fulfillment), st(o.payment)]; })) + "</div>" +
      '<div class="card"><h2>' + esc(T("Consent", "সম্মতি")) + " " + help("consent") + "</h2>" + cons + "</div></div>" +
      '<div class="grid c2"><div class="card"><h2>' + esc(T("Loyalty & preferences", "লয়্যালটি ও পছন্দ")) + " " + help("loyalty") + '</h2><p class="kpi" id="loy-points">' + esc(c.points) + "<small>" + esc(T("points", "পয়েন্ট")) + "</small></p>" +
      gate("loyalty_adjust", '<form class="row" data-form="loy" data-id="' + esc(c.id) + '"><input name="points" aria-label="points" placeholder="+50 / -20" required><input name="reason" aria-label="reason" placeholder="' + esc(T("Reason (required)", "কারণ (আবশ্যক)")) + '" required><button type="submit">' + esc(T("Adjust", "সমন্বয়")) + "</button></form>") +
      "<h3>" + esc(T("Communication preferences", "যোগাযোগ পছন্দ")) + " " + help("prefs") + "</h3>" + gate("customer_edit", '<form data-form="prefs" data-id="' + esc(c.id) + '"><label for="pf-ch">' + esc(T("Channel", "চ্যানেল")) + '</label><select id="pf-ch" name="channel">' + ["sms", "email", "whatsapp"].map(function (x) { return '<option value="' + x + '"' + (c.prefs.channel === x ? " selected" : "") + ">" + x + "</option>"; }).join("") + '</select><label for="pf-lang">' + esc(T("Language", "ভাষা")) + '</label><select id="pf-lang" name="lang"><option value="bn"' + (c.prefs.lang === "bn" ? " selected" : "") + '>বাংলা</option><option value="en"' + (c.prefs.lang === "en" ? " selected" : "") + '>English</option></select><label for="pf-q">' + esc(T("Quiet hours", "নীরব সময়")) + '</label><input id="pf-q" name="quiet" value="' + esc(c.prefs.quiet) + '"><p><button type="submit">' + esc(T("Save preferences", "সংরক্ষণ")) + "</button></p></form>") + "</div>" +
      '<div class="card"><h2>' + esc(T("360 timeline", "৩৬০ টাইমলাইন")) + '</h2><ul class="tl" id="timeline">' + (d.timeline.length ? d.timeline.map(function (e) { return "<li><time>" + esc(fdt(e.at)) + " · " + esc(e.type) + "</time>" + esc(e.text) + "</li>"; }).join("") : "<li>" + esc(T("No history", "ইতিহাস নেই")) + "</li>") + "</ul></div></div>" +
      '<div class="grid c2"><div class="card"><h2>' + esc(T("Tickets", "টিকিট")) + "</h2>" + table(["ID", T("Subject", "বিষয়"), T("Status", "অবস্থা"), "SLA"], d.tickets.map(function (k) { return [esc(k.id), esc(k.subject), st(k.status), st(k.sla)]; })) + "</div>" +
      '<div class="card"><h2>' + esc(T("Follow-ups", "ফলো-আপ")) + " " + help("followup") + "</h2>" + table([T("Due", "তারিখ"), T("Note", "নোট"), T("Status", "অবস্থা")], d.followups.map(function (f) { return [esc(fdt(f.due)), esc(f.note), st(f.status)]; })) +
      gate("customer_edit", '<form class="row" data-form="fu_create" data-id="' + esc(c.id) + '"><input name="note" aria-label="note" placeholder="' + esc(T("Next step", "পরবর্তী ধাপ")) + '" required><input name="due_days" aria-label="days" type="number" value="2" step="1"><button type="submit">' + esc(T("Schedule", "নির্ধারণ")) + "</button></form>") + "</div></div>";
  };

  V.intake = async function () {
    return "<h1>" + esc(T("Website / POS / offline enquiry intake simulator", "ওয়েবসাইট / POS / অফলাইন অনুসন্ধান ইনটেক সিমুলেটর")) + " " + help("intake") + "</h1><p class=\"mut\">" + esc(T("Simulates a request arriving from a channel. It is recorded as RECEIVED only; nothing is ordered, charged or sent.", "চ্যানেল থেকে আসা অনুরোধ অনুকরণ করে। কেবল RECEIVED হিসেবে রাখা হয়; অর্ডার, চার্জ বা বার্তা হয় না।")) + "</p>" +
      '<div class="card">' + gate("pipeline_edit", '<form data-form="intake"><label for="in-source">' + esc(T("Channel", "চ্যানেল")) + '</label><select id="in-source" name="source"><option value="website">website</option><option value="pos">pos</option><option value="offline">offline</option><option value="phone">phone</option></select><label for="in-name">' + esc(T("Name", "নাম")) + '</label><input id="in-name" name="name" required maxlength="120"><label for="in-contact">' + esc(T("Phone / contact", "ফোন / যোগাযোগ")) + '</label><input id="in-contact" name="contact" maxlength="60"><label for="in-note">' + esc(T("Request", "অনুরোধ")) + '</label><textarea id="in-note" name="note" maxlength="500"></textarea><p><button class="pri" id="in-submit" type="submit">' + esc(T("Submit enquiry", "অনুসন্ধান জমা")) + '</button> <a href="#/leads">' + esc(T("View leads", "লিড দেখুন")) + "</a></p></form>") + "</div>";
  };

  V.leads = async function () {
    var d = await api("leads_list");
    var lrows = d.leads.map(function (l) {
      var act = l.status === "RECEIVED" && can("pipeline_edit") ? '<form class="row" data-form="lead_convert" data-id="' + esc(l.id) + '"><input name="need" aria-label="need" placeholder="' + esc(T("Need", "প্রয়োজন")) + '" value="' + esc(l.note || "") + '"><input name="budget" aria-label="budget" type="number" min="0" placeholder="' + esc(T("Budget", "বাজেট")) + '"><button class="pri" id="lead-' + esc(l.id) + '-convert" name="op" value="convert">' + esc(T("To enquiry", "অনুসন্ধানে")) + '</button><input name="reason" aria-label="reason" placeholder="' + esc(T("Reason to disqualify", "বাতিলের কারণ")) + '"><button id="lead-' + esc(l.id) + '-dq" name="op" value="dq">' + esc(T("Disqualify", "বাতিল")) + "</button></form>" : "";
      return [esc(l.id), esc(l.name) + '<div class="mut small wrap">' + esc(l.note || "") + "</div>", esc(l.source), esc(l.contact || "-"), st(l.status), act];
    });
    var erows = d.enquiries.map(function (e) {
      return [esc(e.id), esc(e.need), e.budget == null ? money(null) : money(e.budget), st(e.status), e.opp_id ? '<a href="#/opp/' + esc(e.opp_id) + '">' + esc(e.opp_id) + "</a>" : (can("pipeline_edit") ? '<form class="row" data-form="enq_opp" data-id="' + esc(e.id) + '"><select name="kind" aria-label="kind"><option value="person">person</option><option value="organization">organization</option></select><button class="pri" id="enq-' + esc(e.id) + '-opp" type="submit">' + esc(T("Create opportunity", "সুযোগ তৈরি")) + "</button></form>" : "")];
    });
    return "<h1>" + esc(T("Leads & enquiries", "লিড ও অনুসন্ধান")) + " " + help("convert") + "</h1><div class=\"card\"><h2>" + esc(T("Leads", "লিড")) + "</h2>" + table(["ID", T("Name", "নাম"), T("Source", "উৎস"), T("Contact", "যোগাযোগ"), T("Status", "অবস্থা"), T("Action", "কাজ")], lrows) + "</div>" +
      '<div class="card"><h2>' + esc(T("Enquiries", "অনুসন্ধান")) + " " + help("opp") + "</h2>" + table(["ID", T("Need", "প্রয়োজন"), T("Budget", "বাজেট"), T("Status", "অবস্থা"), T("Action", "কাজ")], erows) + "</div>";
  };

  V.pipeline = async function () {
    var d = await api("pipeline"), cols = d.stages.map(function (s) {
      var os = d.opps.filter(function (o) { return o.stage === s.key; });
      return '<section class="col" aria-label="' + esc(S.lang === "bn" ? s.bn : s.en) + '"><h3><span>' + esc(S.lang === "bn" ? s.bn : s.en) + "</span><span>" + os.length + "</span></h3>" + os.map(function (o) {
        var opts = d.stages.filter(function (x) { return x.kind !== "lost"; }).map(function (x) { return '<option value="' + esc(x.key) + '"' + (x.key === o.stage ? " selected" : "") + ">" + esc(S.lang === "bn" ? x.bn : x.en) + "</option>"; }).join("");
        return '<div class="opp" id="card-' + esc(o.id) + '"><a href="#/opp/' + esc(o.id) + '"><b>' + esc(o.title) + "</b></a><div class=\"small mut\">" + esc(o.customer_name) + " · " + (o.est_value == null ? money(null) : money(o.est_value)) + "</div>" + (can("pipeline_edit") && s.kind === "open" ? '<select data-chg="opp_move" data-id="' + esc(o.id) + '" aria-label="' + esc(T("Move to stage", "ধাপে সরান")) + '">' + opts + "</select>" : "") + "</div>";
      }).join("") + "</section>";
    }).join("");
    return "<h1>" + esc(T("Opportunity pipeline", "সুযোগ পাইপলাইন")) + '</h1><p class="mut">' + esc(T("Stages are Owner-configurable in Settings. Moving to Won needs an approved order.", "ধাপ সেটিংসে মালিক কনফিগার করেন। 'জিত' এ যেতে অনুমোদিত অর্ডার লাগে।")) + '</p><div class="board" id="board">' + cols + "</div>";
  };

  var JSTEPS = [["Lead", "লিড"], ["Enquiry", "অনুসন্ধান"], ["Opportunity", "সুযোগ"], ["Quotation", "কোটেশন"], ["Approved order", "অনুমোদিত অর্ডার"], ["Fulfillment", "পূরণ"], ["Invoice", "ইনভয়েস"], ["Payment", "পেমেন্ট"], ["Support", "সাপোর্ট"], ["Retention", "রিটেনশন"], ["Reports", "রিপোর্ট"]];
  function qline(l, i) { return '<div class="row qrow"><input name="desc" aria-label="desc" placeholder="' + esc(T("Description", "বিবরণ")) + '" value="' + esc(l ? l.desc : "") + '"><input name="qty" aria-label="qty" type="number" min="0" step="any" value="' + esc(l ? l.qty : 1) + '"><input name="price" aria-label="price" type="number" min="0" step="any" placeholder="' + esc(T("unit price (empty = unavailable)", "একক দাম (খালি = পাওয়া যায়নি)")) + '" value="' + esc(l && l.price != null ? l.price : "") + '"></div>'; }
  V.opp = async function () {
    var d = await api("opp_get", { id: S.arg }), o = d.opp, q = d.quote, od = d.order, v = q ? q.versions[q.versions.length - 1] : null;
    var steps = [["done", "Lead"], ["done", "Enquiry"], ["done", "Opp"], [q ? "done" : "todo", q ? q.status : "none"], [od ? (od.state === "APPROVED" ? "done" : "todo") : "todo", od ? od.state : "none"], [od && od.fulfillment ? "done" : "todo", od && od.fulfillment || "-"], [od && od.invoice === "ISSUED" ? "done" : "todo", od ? od.invoice : "NOT CERTIFIED"], [od && od.payment === "PAID" ? "done" : "todo", od ? od.payment : "UNAVAILABLE"]];
    var stepper = '<div class="steps" id="journey-steps">' + JSTEPS.map(function (s, i) { var x = steps[i]; return pill((i + 1) + ". " + T(s[0], s[1]) + (x ? ": " + x[1] : ""), x ? (x[0] === "done" ? "ok" : "") : "") ; }).join("") + "</div>";
    var qb = gate("quote_edit", '<form data-form="quote_save" data-id="' + esc(o.id) + '"><div id="qlines">' + (v ? v.lines : [null, null]).map(qline).join("") + '</div><p><button type="button" id="q-add" data-act="addline">' + esc(T("+ Add line", "+ লাইন যোগ")) + '</button></p><div class="row"><label for="q-disc">' + esc(T("Discount %", "ডিসকাউন্ট %")) + '</label><input id="q-disc" name="discount_pct" type="number" min="0" max="100" step="any" value="' + esc(v ? v.discount_pct : 0) + '"><label for="q-note">' + esc(T("Version note", "ভার্সন নোট")) + '</label><input id="q-note" name="note" maxlength="200"></div><p><button class="pri" id="q-save" type="submit">' + esc(T("Save as new version", "নতুন ভার্সন সংরক্ষণ")) + "</button></p></form>");
    var qv = q ? table(["v", T("Total", "মোট"), T("Discount", "ডিসকাউন্ট"), T("Created", "তৈরি"), T("Lines", "লাইন")], q.versions.slice().reverse().map(function (x) { return [esc(x.v), money(x.total), esc(x.discount_pct) + "%", esc(fdt(x.created)), esc(x.lines.map(function (l) { return l.qty + "x " + l.desc + (l.price == null ? " (unpriced)" : ""); }).join("; "))]; })) : "";
    var qact = q ? '<p>' + st(q.status) + " " + (q.status === "DRAFT" && can("quote_edit") ? '<button class="pri" id="q-submit" data-act="qsubmit" data-id="' + esc(q.id) + '">' + esc(T("Submit / send", "জমা / পাঠান")) + "</button>" : "") +
      (q.status === "PENDING_APPROVAL" ? (can("discount_approve") ? '<button class="pri" id="q-approve" data-act="qapprove" data-id="' + esc(q.id) + '">' + esc(T("Owner: approve discount", "মালিক: ডিসকাউন্ট অনুমোদন")) + "</button>" : '<span class="mut small">' + esc(T("Awaiting Owner approval", "মালিকের অনুমোদনের অপেক্ষায়")) + "</span>") : "") +
      (q.status === "SENT" && can("quote_edit") ? '<button class="pri" id="q-accept" data-act="qaccept" data-id="' + esc(q.id) + '">' + esc(T("Customer accepted", "গ্রাহক গ্রহণ করেছেন")) + "</button>" : "") +
      (q.status === "ACCEPTED" && !od ? (can("order_request") ? '<button class="pri" id="order-request" data-act="orderreq" data-id="' + esc(q.id) + '">' + esc(T("Request order (adapter)", "অর্ডার অনুরোধ (অ্যাডাপ্টার)")) + "</button> " + help("order") : '<span class="mut small">' + esc(T("Your role cannot request orders", "আপনার ভূমিকা অর্ডার অনুরোধ করতে পারে না")) + "</span>") : "") + "</p>" : "";
    var adapter = od ? '<div class="card" id="adapter"><h2>' + esc(T("Approved-order adapter", "অনুমোদিত-অর্ডার অ্যাডাপ্টার")) + " " + SYN + " " + help("adapter") + "</h2><p>" + esc(od.id) + " · " + st(od.state) + " · " + esc(T("fulfillment", "পূরণ")) + ": " + st(od.fulfillment) + " · " + esc(T("invoice", "ইনভয়েস")) + ": " + st(od.invoice) + " · " + esc(T("payment", "পেমেন্ট")) + ": " + st(od.payment) + "</p><p class=\"mut small\">" + esc(T("Invoice and payment status are NOT CERTIFIED until a real certified finance source exists.", "সার্টিফায়েড ফাইন্যান্স উৎস না আসা পর্যন্ত ইনভয়েস ও পেমেন্ট অবস্থা সার্টিফায়েড নয়।")) + "</p>" +
      (can("order_request") ? ["approve", "reject", "pick", "dispatch", "deliver", "invoice", "pay"].map(function (s) { return '<button id="ad-' + s + '" data-act="adapter" data-id="' + esc(od.id) + '" data-step="' + s + '">' + esc(s) + "</button>"; }).join(" ") : "") + "</div>" : "";
    return '<p><a href="#/pipeline">&larr; ' + esc(T("Pipeline", "পাইপলাইন")) + '</a></p><h1 id="opp-title">' + esc(o.title) + "</h1><p class=\"mut wrap\">" + esc(o.id) + " · " + esc(T("Stage", "ধাপ")) + ": " + esc(o.stage) + " · <a href=\"#/customer/" + esc(d.customer.id) + '">' + esc(d.customer.name) + "</a></p>" + stepper +
      '<div class="grid c2"><div class="card"><h2>' + esc(T("Quotation builder", "কোটেশন বিল্ডার")) + " " + help("quote") + "</h2>" + qb + qact + qv + "</div><div>" + adapter +
      '<div class="card"><h2>' + esc(T("After the order", "অর্ডারের পর")) + '</h2><p><a class="btn" href="#/customer/' + esc(d.customer.id) + '">' + esc(T("Open Customer 360 (support, retention)", "গ্রাহক ৩৬০ (সাপোর্ট, রিটেনশন)")) + '</a> <a class="btn" href="#/support">' + esc(T("Support tickets", "সাপোর্ট টিকিট")) + '</a> <a class="btn" href="#/reports">' + esc(T("Reports", "রিপোর্ট")) + "</a></p></div>" +
      '<div class="card"><h2>' + esc(T("Mark lost", "হারানো চিহ্নিত")) + "</h2>" + gate("pipeline_edit", '<form class="row" data-form="opp_lost" data-id="' + esc(o.id) + '"><input name="reason" aria-label="reason" placeholder="' + esc(T("Reason (required)", "কারণ (আবশ্যক)")) + '" required><button class="bad" id="opp-lost" type="submit">' + esc(T("Mark lost", "হারানো")) + "</button></form>") + "</div></div></div>";
  };

  V.quotes = async function () {
    var qs = await api("quotes_list"), os = await api("orders_list");
    return "<h1>" + esc(T("Quotations & order requests", "কোটেশন ও অর্ডার অনুরোধ")) + '</h1><div class="card"><h2>' + esc(T("Quotations", "কোটেশন")) + "</h2>" + table(["ID", T("Customer", "গ্রাহক"), "v", T("Total", "মোট"), T("Discount", "ডিসকাউন্ট"), T("Status", "অবস্থা")], qs.map(function (q) { return ['<a href="#/opp/' + esc(q.opp_id) + '">' + esc(q.id) + "</a>", esc(q.customer_name), esc(q.version), money(q.total), esc(q.discount_pct) + "%", st(q.status)]; })) + '</div><div class="card"><h2>' + esc(T("Order requests (adapter)", "অর্ডার অনুরোধ (অ্যাডাপ্টার)")) + " " + SYN + "</h2>" +
      table(["ID", T("Customer", "গ্রাহক"), T("Total", "মোট"), T("State", "অবস্থা"), T("Fulfillment", "পূরণ"), T("Invoice", "ইনভয়েস"), T("Payment", "পেমেন্ট")], os.map(function (o) { return [o.opp_id ? '<a href="#/opp/' + esc(o.opp_id) + '">' + esc(o.id) + "</a>" : esc(o.id), esc(o.customer_name), money(o.total), st(o.state), st(o.fulfillment), st(o.invoice), st(o.payment)]; })) + "</div>";
  };

  V.followups = async function () {
    var fs = await api("followups_list"), cs = await api("customers_list");
    return "<h1>" + esc(T("Follow-ups", "ফলো-আপ")) + " " + help("followup") + '</h1><div class="card">' + table([T("Customer", "গ্রাহক"), T("Note", "নোট"), T("Due", "তারিখ"), T("Status", "অবস্থা"), ""], fs.map(function (f) { return [esc(f.customer_name), esc(f.note), esc(fdt(f.due)) + (f.overdue ? " " + pill(T("overdue", "মেয়াদোত্তীর্ণ"), "bad") : ""), st(f.status), f.status === "open" && can("customer_edit") ? '<button id="fu-' + esc(f.id) + '-done" data-act="fudone" data-id="' + esc(f.id) + '">' + esc(T("Done", "সম্পন্ন")) + "</button>" : ""]; })) + "</div>" +
      '<div class="card"><h2>' + esc(T("New follow-up", "নতুন ফলো-আপ")) + "</h2>" + gate("customer_edit", '<form data-form="fu_create"><label for="fu-c">' + esc(T("Customer", "গ্রাহক")) + '</label><select id="fu-c" name="customer_id">' + custOpts(cs) + '</select><label for="fu-n">' + esc(T("Note", "নোট")) + '</label><input id="fu-n" name="note" required><label for="fu-d">' + esc(T("Due in days", "কত দিন পরে")) + '</label><input id="fu-d" name="due_days" type="number" value="1"><p><button class="pri" type="submit">' + esc(T("Schedule", "নির্ধারণ")) + "</button></p></form>") + "</div>";
  };

  V.support = async function () {
    var ts = await api("tickets_list"), cs = await api("customers_list");
    var rows = ts.map(function (k) {
      var act = "";
      if (can("ticket_manage") && k.status !== "RESOLVED" && k.status !== "CLOSED") act = (k.status === "OPEN" ? '<button id="tk-' + esc(k.id) + '-start" data-act="tkstart" data-id="' + esc(k.id) + '">' + esc(T("Start", "শুরু")) + "</button> " : "") + '<form class="row" data-form="tk_resolve" data-id="' + esc(k.id) + '"><input name="resolution" aria-label="resolution" placeholder="' + esc(T("Resolution", "সমাধান")) + '" required><input name="evidence" aria-label="evidence" placeholder="' + esc(T("Evidence", "প্রমাণ")) + '" required><button class="pri" id="tk-' + esc(k.id) + '-resolve" type="submit">' + esc(T("Resolve", "সমাধান")) + "</button></form>";
      else if (k.resolution) act = '<span class="small wrap">' + esc(k.resolution) + " / " + esc(k.evidence) + "</span>";
      return [esc(k.id), esc(k.customer_name), esc(k.subject), esc(k.type) + " · " + esc(k.priority), st(k.status), st(k.sla) + '<div class="small mut">' + esc(fdt(k.sla_due)) + "</div>", act];
    });
    return "<h1>" + esc(T("Support tickets, SLA & resolution", "সাপোর্ট টিকিট, SLA ও সমাধান")) + " " + help("ticket") + '</h1><div class="card">' + table(["ID", T("Customer", "গ্রাহক"), T("Subject", "বিষয়"), T("Type / priority", "ধরন / অগ্রাধিকার"), T("Status", "অবস্থা"), "SLA", T("Action", "কাজ")], rows) + " " + help("resolve") + "</div>" +
      '<div class="card"><h2>' + esc(T("New ticket", "নতুন টিকিট")) + "</h2>" + gate("ticket_manage", '<form data-form="tk_create"><label for="tk-c">' + esc(T("Customer", "গ্রাহক")) + '</label><select id="tk-c" name="customer_id">' + custOpts(cs) + '</select><label for="tk-s">' + esc(T("Subject", "বিষয়")) + '</label><input id="tk-s" name="subject" required maxlength="200"><label for="tk-t">' + esc(T("Type", "ধরন")) + '</label><select id="tk-t" name="type"><option value="support">support</option><option value="warranty">warranty / service</option><option value="return_request">return request (intent only)</option></select><label for="tk-p">' + esc(T("Priority", "অগ্রাধিকার")) + '</label><select id="tk-p" name="priority"><option value="standard">standard</option><option value="urgent">urgent</option><option value="low">low</option></select><p><button class="pri" id="tk-create" type="submit">' + esc(T("Open ticket", "টিকিট খুলুন")) + "</button></p></form>") + "</div>";
  };

  V.segments = async function () {
    var ss = await api("segments_list"), mem = S.segMembers ? await api("segment_members", { id: S.segMembers }) : null;
    return "<h1>" + esc(T("Segments", "সেগমেন্ট")) + " " + help("segment") + '</h1><div class="card">' + table([T("Name", "নাম"), T("Rule", "নিয়ম"), T("Size", "আকার"), ""], ss.map(function (s) { return [esc(s.name), esc("orders>=" + s.rule.min_orders + (s.rule.tag ? ", tag=" + s.rule.tag : "") + ", " + s.rule.channel), esc(s.size), '<button id="seg-' + esc(s.id) + '-view" data-act="segview" data-id="' + esc(s.id) + '">' + esc(T("Members", "সদস্য")) + "</button>"]; })) + "</div>" +
      (mem ? '<div class="card" id="seg-members"><h2>' + esc(T("Members & consent", "সদস্য ও সম্মতি")) + "</h2>" + table([T("Name", "নাম"), T("Phone", "ফোন"), T("Sendable?", "পাঠানো যাবে?")], mem.map(function (m) { return [esc(m.name), esc(m.phone || "-"), m.sendable ? pill("yes", "ok") : pill("blocked: " + m.reason, "bad")]; })) + '<p><button id="seg-export" data-act="segexport" data-id="' + esc(S.segMembers) + '">' + esc(T("Export CSV", "CSV এক্সপোর্ট")) + "</button></p></div>" : "") +
      '<div class="card"><h2>' + esc(T("New segment", "নতুন সেগমেন্ট")) + "</h2>" + gate("campaign_send", '<form data-form="seg_create"><label for="sg-n">' + esc(T("Name", "নাম")) + '</label><input id="sg-n" name="name" required maxlength="80"><label for="sg-m">' + esc(T("Min delivered orders", "ন্যূনতম ডেলিভারড অর্ডার")) + '</label><input id="sg-m" name="min_orders" type="number" min="0" value="0"><label for="sg-t">' + esc(T("Tag (optional)", "ট্যাগ (ঐচ্ছিক)")) + '</label><input id="sg-t" name="tag"><label for="sg-c">' + esc(T("Channel", "চ্যানেল")) + '</label><select id="sg-c" name="channel"><option>sms</option><option>email</option><option>whatsapp</option></select><p><button class="pri" type="submit">' + esc(T("Create segment", "সেগমেন্ট তৈরি")) + "</button></p></form>") + "</div>";
  };

  V.campaigns = async function () {
    var d = await api("campaigns_list"), ss = await api("segments_list");
    var prov = Object.keys(d.providers).map(function (k) { return k + ": " + pill(d.providers[k] + " (no-op)", "warn"); }).join(" &nbsp; ");
    var rows = d.campaigns.map(function (c) {
      var r = c.result, det = r ? '<div class="small" id="res-' + esc(c.id) + '">' + pill(c.status, "warn") + " " + esc(T("external messages sent", "বাইরে পাঠানো বার্তা")) + ": <b>" + esc(r.external_messages_sent) + "</b> · " + esc(T("would-send (eligible)", "পাঠানো যেত (যোগ্য)")) + ": " + esc(r.eligible.length) + " · " + esc(T("blocked", "আটকানো")) + ": <b>" + esc(r.blocked.length) + "</b>" + (r.blocked.length ? "<ul>" + r.blocked.map(function (x) { return "<li>" + esc(x.name) + " - " + esc(x.reason) + "</li>"; }).join("") + "</ul>" : "") + "</div>" : "";
      return [esc(c.name), esc(c.channel), esc(c.message), st(c.status), (can("campaign_send") && !r ? '<button class="pri" id="cp-' + esc(c.id) + '-send" data-act="cpsend" data-id="' + esc(c.id) + '">' + esc(T("Send (consent-checked)", "পাঠান (সম্মতি যাচাইসহ)")) + "</button>" : "") + det];
    });
    return "<h1>" + esc(T("Campaigns & consent-aware sending", "ক্যাম্পেইন ও সম্মতি-সচেতন পাঠানো")) + " " + help("campaign") + '</h1><div class="card" id="providers"><h2>' + esc(T("Provider state", "প্রোভাইডার অবস্থা")) + "</h2><p>" + prov + '</p><p class="mut small">' + esc(T("NOT ENABLED: no approved provider or verified credentials. Sends are NO-OP; consent is still evaluated.", "চালু নয়: অনুমোদিত প্রোভাইডার বা যাচাইকৃত ক্রেডেনশিয়াল নেই। পাঠানো NO-OP; সম্মতি তবু যাচাই হয়।")) + "</p></div>" +
      '<div class="card">' + table([T("Name", "নাম"), T("Channel", "চ্যানেল"), T("Message", "বার্তা"), T("Status", "অবস্থা"), T("Action / result", "কাজ / ফল")], rows) + "</div>" +
      '<div class="card"><h2>' + esc(T("New campaign", "নতুন ক্যাম্পেইন")) + "</h2>" + gate("campaign_send", '<form data-form="cp_create"><label for="cp-n">' + esc(T("Name", "নাম")) + '</label><input id="cp-n" name="name" required maxlength="100"><label for="cp-s">' + esc(T("Segment", "সেগমেন্ট")) + '</label><select id="cp-s" name="segment_id">' + ss.map(function (s) { return '<option value="' + esc(s.id) + '">' + esc(s.name) + "</option>"; }).join("") + '</select><label for="cp-c">' + esc(T("Channel", "চ্যানেল")) + '</label><select id="cp-c" name="channel"><option>sms</option><option>email</option><option>whatsapp</option></select><label for="cp-m">' + esc(T("Message", "বার্তা")) + '</label><textarea id="cp-m" name="message" required maxlength="500"></textarea><p><button class="pri" id="cp-create" type="submit">' + esc(T("Create draft", "ড্রাফট তৈরি")) + "</button></p></form>") + "</div>";
  };

  V.loyalty = async function () {
    var cs = await api("customers_list");
    return "<h1>" + esc(T("Loyalty & communication preferences", "লয়্যালটি ও যোগাযোগ পছন্দ")) + " " + help("loyalty") + '</h1><div class="card">' + table([T("Customer", "গ্রাহক"), T("Points", "পয়েন্ট"), ""], cs.map(function (c) { return [esc(c.name), esc(c.points), '<a href="#/customer/' + esc(c.id) + '">' + esc(T("Points, consent & preferences", "পয়েন্ট, সম্মতি ও পছন্দ")) + "</a>"]; })) + "</div>";
  };

  V.reports = async function () {
    var r = await api("reports"), f = r.funnel, mx = Math.max(1, f.leads, f.enquiries, f.opportunities, f.quotes, f.orders, f.delivered);
    return "<h1>" + esc(T("Reports", "রিপোর্ট")) + " " + help("reports") + '</h1><div class="grid c2"><div class="card funnel"><h2>' + esc(T("Lead funnel", "লিড ফানেল")) + "</h2>" + bar(T("Leads", "লিড"), f.leads, mx) + bar(T("Enquiries", "অনুসন্ধান"), f.enquiries, mx) + bar(T("Opportunities", "সুযোগ"), f.opportunities, mx) + bar(T("Quotations", "কোটেশন"), f.quotes, mx) + bar(T("Orders", "অর্ডার"), f.orders, mx) + bar(T("Delivered", "ডেলিভারড"), f.delivered, mx) + bar(T("Invoiced", "ইনভয়েসড"), f.invoiced, mx) + bar(T("Paid", "পরিশোধিত"), f.paid, mx) + '<p class="small" id="rep-conv">' + esc(T("Lead to enquiry", "লিড→অনুসন্ধান")) + " " + pct(r.conversion.lead_to_enquiry) + " · " + esc(T("Opp to order", "সুযোগ→অর্ডার")) + " " + pct(r.conversion.opp_to_order) + "</p></div>" +
      '<div class="card"><h2>' + esc(T("Retention", "রিটেনশন")) + '</h2><p class="kpi">' + pct(r.retention.rate) + "<small>" + esc(r.retention.repeat) + " / " + esc(r.retention.buyers) + " " + esc(T("buyers repeat", "ক্রেতা পুনরায় কিনেছেন")) + "</small></p><h3>" + esc(T("Follow-ups", "ফলো-আপ")) + "</h3><p>" + esc(r.followups.pending) + " " + esc(T("pending", "অপেক্ষমাণ")) + ", " + esc(r.followups.overdue) + " " + esc(T("overdue", "মেয়াদোত্তীর্ণ")) + "</p><h3>" + esc(T("Tickets", "টিকিট")) + '</h3><p id="rep-tickets">' + esc(r.tickets.open) + " " + esc(T("open", "খোলা")) + ", " + esc(r.tickets.breached) + " " + esc(T("SLA breached", "SLA লঙ্ঘিত")) + ", " + esc(r.tickets.resolved) + " " + esc(T("resolved", "সমাধান")) + ", " + esc(T("avg resolution (h)", "গড় সমাধান (ঘণ্টা)")) + " " + (r.tickets.avg_resolution_hours == null ? '<span class="nc">n/a</span>' : esc(r.tickets.avg_resolution_hours.toFixed(1))) + "</p></div></div>" +
      '<div class="grid c3"><div class="card"><h2>' + esc(T("Consent coverage", "সম্মতি কভারেজ")) + "</h2>" + Object.keys(r.consent).map(function (k) { return "<p>" + esc(k) + ": <b>" + esc(r.consent[k].granted) + "</b> / " + esc(r.consent[k].total) + "</p>"; }).join("") + "</div>" +
      '<div class="card"><h2>' + esc(T("Campaigns", "ক্যাম্পেইন")) + "</h2><p>" + esc(T("runs", "রান")) + " " + esc(r.campaigns.runs) + " · " + esc(T("would-send", "পাঠানো যেত")) + " " + esc(r.campaigns.eligible) + " · " + esc(T("blocked (no consent)", "আটকানো (সম্মতি নেই)")) + " <b>" + esc(r.campaigns.blocked) + "</b> · " + esc(T("external sent", "বাইরে পাঠানো")) + " <b>" + esc(r.campaigns.external_sent) + "</b></p></div>" +
      '<div class="card"><h2>' + esc(T("Quotation value (advisory)", "কোটেশন মূল্য (পরামর্শমূলক)")) + "</h2><p class=\"kpi\">" + money(r.quotation.value_advisory) + "</p><p class=\"small mut\">" + esc(r.quotation.unpriced_quotes) + " " + esc(T("quotation(s) unpriced, excluded", "কোটেশন মূল্যহীন, বাদ")) + '</p><h3>' + esc(T("Profit / COGS", "মুনাফা / COGS")) + '</h3><p><span class="nc" id="rep-profit">NOT CERTIFIED</span></p><p class="small mut">' + esc(r.profit.reason) + "</p></div></div>" +
      '<p><button id="rep-export" data-act="repexport">' + esc(T("Export funnel CSV", "ফানেল CSV এক্সপোর্ট")) + "</button> <button id=\"cust-export\" data-act=\"custexport\">" + esc(T("Export customers CSV", "গ্রাহক CSV এক্সপোর্ট")) + "</button></p>";
  };

  V.settings = async function () {
    var d = await api("settings_get"), s = d.settings, own = can("settings_edit");
    var stg = table([T("Key", "কী"), T("English", "ইংরেজি"), T("বাংলা", "বাংলা"), T("Kind", "ধরন"), ""], s.stages.map(function (x) {
      return [esc(x.key), own ? '<form class="row" data-form="stage_save" data-key="' + esc(x.key) + '"><input name="en" aria-label="en" value="' + esc(x.en) + '"></td><td><input name="bn" aria-label="bn" value="' + esc(x.bn) + '"></td><td>' + esc(x.kind) + '</td><td><button id="stg-' + esc(x.key) + '-save" type="submit">' + esc(T("Save", "সংরক্ষণ")) + '</button> <button type="button" class="bad" id="stg-' + esc(x.key) + '-del" data-act="stagedel" data-key="' + esc(x.key) + '">' + esc(T("Delete", "মুছুন")) + "</button></form>" : esc(x.en) + "</td><td>" + esc(x.bn) + "</td><td>" + esc(x.kind) + "</td><td>"];
    }));
    stg = stg.replace(/<form class="row"([^>]*)><input name="en"/g, '<form class="row"$1><input name="en"');
    var matrix = '<div class="tbl-wrap"><table id="perm-matrix"><thead><tr><th>' + esc(T("Capability", "সক্ষমতা")) + "</th>" + d.roles.map(function (r) { return "<th>" + r + "</th>"; }).join("") + "</tr></thead><tbody>" + d.caps.map(function (c) {
      return "<tr><td>" + esc(c) + "</td>" + d.roles.map(function (r) { var on = s.perms[r].indexOf(c) >= 0; return '<td><input type="checkbox" aria-label="' + esc(r + " " + c) + '" data-chg="perm" data-role="' + r + '" data-cap="' + esc(c) + '"' + (on ? " checked" : "") + (r === "owner" || !own ? " disabled" : "") + "></td>"; }).join("") + "</tr>";
    }).join("") + "</tbody></table></div>";
    return "<h1>" + esc(T("Settings", "সেটিংস")) + '</h1><div class="grid c2"><div class="card" id="stages"><h2>' + esc(T("Pipeline stages", "পাইপলাইন ধাপ")) + " " + help("stage") + "</h2>" + stg + (own ? '<form data-form="stage_add"><div class="row"><input name="key" aria-label="key" placeholder="key" required><input name="en" aria-label="English" placeholder="English" required><input name="bn" aria-label="Bangla" placeholder="বাংলা" required></div><p><button class="pri" id="stg-add" type="submit">' + esc(T("Add stage", "ধাপ যোগ")) + "</button></p></form>" : "") + "</div>" +
      '<div class="card"><h2>' + esc(T("Quotation approval rule", "কোটেশন অনুমোদন নিয়ম")) + " " + help("approval") + "</h2>" + gate("settings_edit", '<form class="row" data-form="approval"><label for="ap-d">' + esc(T("Owner approval above discount %", "এর বেশি ডিসকাউন্টে মালিকের অনুমোদন %")) + '</label><input id="ap-d" name="discount_pct" type="number" min="0" max="100" value="' + esc(s.approval.discount_pct_owner_approval) + '"><button class="pri" type="submit">' + esc(T("Save", "সংরক্ষণ")) + "</button></form>") +
      "<h2>" + esc(T("Ticket SLA hours (examples, Owner-editable)", "টিকিট SLA ঘণ্টা (উদাহরণ, মালিক-সম্পাদনযোগ্য)")) + " " + help("sla") + "</h2>" + gate("settings_edit", '<form data-form="sla">' + ["urgent", "standard", "low"].map(function (k) { return '<label for="sla-' + k + '">' + k + '</label><input id="sla-' + k + '" name="' + k + '" type="number" min="1" value="' + esc(s.sla_hours[k]) + '">'; }).join("") + '<p><button class="pri" type="submit">' + esc(T("Save", "সংরক্ষণ")) + "</button></p></form>") + "</div></div>" +
      '<div class="card"><h2>' + esc(T("Permissions", "অনুমতি")) + " " + help("perms") + "</h2>" + matrix + '<h3>' + esc(T("Locked invariants (cannot be disabled)", "লক করা নিয়ম (বন্ধ করা যায় না)")) + "</h3><ul>" + d.locked.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul><p>" + esc(T("Messaging providers", "বার্তা প্রোভাইডার")) + ": " + Object.keys(s.providers).map(function (k) { return k + " " + pill(s.providers[k], "warn"); }).join(" ") + "</p></div>" +
      '<div class="card"><h2>' + esc(T("Audit trail", "অডিট ট্রেইল")) + "</h2>" + table([T("When", "কখন"), T("Role", "ভূমিকা"), T("Action", "কাজ"), T("Detail", "বিবরণ")], d.audit.map(function (a) { return [esc(fdt(a.at)), esc(a.role), esc(a.action), esc(a.detail)]; })) + "</div>";
  };

  V.journey = async function () {
    var steps = [["intake", "1. Lead - simulate a website/POS/offline enquiry", "১. লিড - ওয়েবসাইট/POS/অফলাইন অনুসন্ধান অনুকরণ"], ["leads", "2. Enquiry - qualify the lead, then 3. Opportunity", "২. অনুসন্ধান - লিড যোগ্য করুন, তারপর ৩. সুযোগ"], ["pipeline", "4. Quotation - open the opportunity and build a quotation (versions)", "৪. কোটেশন - সুযোগ খুলে কোটেশন বানান (ভার্সনসহ)"], ["quotes", "5. Approved order - request, approve and fulfil via the adapter; invoice/payment status", "৫. অনুমোদিত অর্ডার - অ্যাডাপ্টারে অনুরোধ, অনুমোদন, পূরণ; ইনভয়েস/পেমেন্ট অবস্থা"], ["support", "6. Support - open and resolve a ticket with evidence", "৬. সাপোর্ট - টিকিট খুলে প্রমাণসহ সমাধান"], ["loyalty", "7. Retention - loyalty and preferences", "৭. রিটেনশন - লয়্যালটি ও পছন্দ"], ["reports", "8. Reports - funnel, retention, tickets", "৮. রিপোর্ট - ফানেল, রিটেনশন, টিকিট"]];
    return "<h1>" + esc(T("End-to-end journey", "এন্ড-টু-এন্ড যাত্রা")) + '</h1><p class="mut">Lead &rarr; Enquiry &rarr; Opportunity &rarr; Quotation &rarr; Approved Order &rarr; Fulfillment &rarr; Invoice/Payment status &rarr; Support &rarr; Retention &rarr; Reports. ' + SYN + '</p><div class="card"><ol>' + steps.map(function (s) { return '<li><a href="#/' + s[0] + '">' + esc(T(s[1], s[2])) + "</a></li>"; }).join("") + '</ol><p><button id="reset-demo" class="bad" data-act="reset">' + esc(T("Reset demo data", "ডেমো ডেটা রিসেট")) + "</button></p></div>";
  };

  /* ---------------- render + events ---------------- */
  var seq = 0;
  async function render() {
    var my = ++seq, inner;
    try { S.session = await api("session"); inner = await V[S.route](); } catch (e) { S.session = S.session || { caps: [], stages: [] }; inner = '<div class="msg err" id="view-error">' + esc((e.code ? e.code + ": " : "") + e.message) + "</div>"; }
    if (my !== seq) return;
    root.innerHTML = shell(inner);
    Array.prototype.forEach.call(root.querySelectorAll("[data-w]"), function (el) { el.style.width = el.getAttribute("data-w") + "%"; });
    document.documentElement.lang = S.lang; document.title = "CORE 10 CRM - " + S.route;
    root.setAttribute("data-ready", S.route);
  }
  function msg(t, text) { S.msg = { t: t, text: text }; }
  async function run(fn, ok, then) {
    try { var r = await fn(); msg("ok", ok); if (then) then(r); } catch (e) { msg("err", (e.code ? e.code + ": " : "") + e.message); }
    await render();
  }
  function route() {
    var h = (location.hash || "").replace(/^#\/?/, "").split("/"), dflt = (document.querySelector('meta[name="c10-route"]') || {}).content || "dashboard";
    S.route = h[0] && V[h[0]] ? h[0] : dflt; S.arg = h[1] ? decodeURIComponent(h[1]) : null; S.nav = false; S.msg = null; render();
  }
  function download(name, rows) {
    var csv = rows.map(function (r) { return r.map(csvCell).join(","); }).join("\r\n"), a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" })); a.download = name; document.body.appendChild(a); a.click(); a.remove(); window.CORE10_LAST_CSV = csv;
  }
  var fv = function (form) { var o = {}; new FormData(form).forEach(function (v, k) { o[k] = v; }); return o; };

  root.addEventListener("click", function (ev) {
    var el = ev.target.closest("[data-act]"); if (!el) return; var a = el.getAttribute("data-act"), id = el.getAttribute("data-id");
    if (a === "help") { var box = document.getElementById("help-" + el.getAttribute("data-k")); box.hidden = !box.hidden; el.setAttribute("aria-expanded", String(!box.hidden)); return; }
    if (a === "menu") { S.nav = !S.nav; root.querySelector("nav.side").classList.toggle("open", S.nav); el.setAttribute("aria-expanded", String(S.nav)); return; }
    if (a === "lang") { S.lang = S.lang === "bn" ? "en" : "bn"; try { window.localStorage.setItem("c10a056-ui", JSON.stringify({ lang: S.lang })); } catch (e) { /* ignore */ } return render(); }
    if (a === "addline") { var d = document.createElement("div"); d.innerHTML = qline(null); document.getElementById("qlines").appendChild(d.firstChild); return; }
    if (a === "consent") return run(function () { return api("consent_set", { id: id, channel: el.getAttribute("data-ch"), state: el.getAttribute("data-s"), expires_days: el.getAttribute("data-s") === "granted" ? 365 : null }); }, T("Consent updated", "সম্মতি হালনাগাদ"));
    if (a === "qsubmit") return run(function () { return api("quote_submit", { id: id }); }, T("Quotation processed", "কোটেশন প্রক্রিয়াকৃত"));
    if (a === "qapprove") return run(function () { return api("quote_approve", { id: id }); }, T("Discount approved", "ডিসকাউন্ট অনুমোদিত"));
    if (a === "qaccept") return run(function () { return api("quote_accept", { id: id }); }, T("Quotation accepted", "কোটেশন গৃহীত"));
    if (a === "orderreq") return run(function () { return api("order_request", { quote_id: id }); }, T("Order request sent to the SYNTHETIC adapter", "সিন্থেটিক অ্যাডাপ্টারে অর্ডার অনুরোধ পাঠানো হয়েছে"));
    if (a === "adapter") return run(function () { return api("order_adapter_step", { id: id, step: el.getAttribute("data-step") }); }, T("Adapter step done (SYNTHETIC)", "অ্যাডাপ্টার ধাপ সম্পন্ন (সিন্থেটিক)"));
    if (a === "fudone") return run(function () { return api("followup_done", { id: id }); }, T("Follow-up completed", "ফলো-আপ সম্পন্ন"));
    if (a === "tkstart") return run(function () { return api("ticket_update", { id: id, status: "IN_PROGRESS" }); }, T("Ticket started", "টিকিট শুরু"));
    if (a === "segview") { S.segMembers = id; return render(); }
    if (a === "segexport") return api("segment_members", { id: id }).then(function (m) { download("segment.csv", [["id", "name", "phone", "sendable", "reason"]].concat(m.map(function (x) { return [x.id, x.name, x.phone, x.sendable, x.reason]; }))); msg("ok", T("CSV exported", "CSV এক্সপোর্ট হয়েছে")); render(); });
    if (a === "cpsend") return run(function () { return api("campaign_send", { id: id }); }, T("Campaign run (NO-OP provider): see consent results", "ক্যাম্পেইন চলেছে (NO-OP প্রোভাইডার): সম্মতি ফল দেখুন"));
    if (a === "stagedel") return run(function () { return api("stage_delete", { key: el.getAttribute("data-key") }); }, T("Stage deleted", "ধাপ মোছা হয়েছে"));
    if (a === "reset") return run(function () { return api("reset"); }, T("Demo data reset", "ডেমো ডেটা রিসেট"));
    if (a === "repexport") return api("reports").then(function (r) { var f = r.funnel; download("funnel.csv", [["metric", "value"]].concat(Object.keys(f).map(function (k) { return [k, f[k]]; }), [["profit", "NOT CERTIFIED"]])); msg("ok", T("CSV exported", "CSV এক্সপোর্ট হয়েছে")); render(); });
    if (a === "custexport") return api("customers_list").then(function (c) { download("customers.csv", [["id", "name", "kind", "phone"]].concat(c.map(function (x) { return [x.id, x.name, x.kind, x.phone]; }))); msg("ok", T("CSV exported", "CSV এক্সপোর্ট হয়েছে")); render(); });
  });
  root.addEventListener("change", function (ev) {
    var el = ev.target.closest("[data-chg]"); if (!el) return; var a = el.getAttribute("data-chg");
    if (a === "tenant") { S.tenant = el.value; S.segMembers = null; S.q = ""; if (S.route === "customer" || S.route === "opp") { location.hash = "#/" + (S.route === "opp" ? "pipeline" : "customers"); return; } return render(); }
    if (a === "role") { S.role = el.value; return render(); }
    if (a === "opp_move") return run(function () { return api("opp_move", { id: el.getAttribute("data-id"), stage: el.value }); }, T("Stage updated", "ধাপ হালনাগাদ"));
    if (a === "perm") return run(function () { return api("perm_set", { target_role: el.getAttribute("data-role"), cap: el.getAttribute("data-cap"), on: el.checked }); }, T("Permission updated", "অনুমতি হালনাগাদ"));
  });
  root.addEventListener("submit", function (ev) {
    var f = ev.target.closest("form[data-form]"); if (!f) return; ev.preventDefault();
    var k = f.getAttribute("data-form"), id = f.getAttribute("data-id"), v = fv(f), op = ev.submitter && ev.submitter.value;
    var ok = T("Saved", "সংরক্ষিত");
    switch (k) {
      case "cust_search": S.q = v.q; return render();
      case "cust_create": return run(function () { return api("customer_create", v); }, ok, function (c) { location.hash = "#/customer/" + c.id; });
      case "intake": return run(function () { return api("intake_submit", v); }, T("Enquiry received (RECEIVED)", "অনুসন্ধান গৃহীত (RECEIVED)"), function () { location.hash = "#/leads"; });
      case "lead_convert": return run(function () { return op === "dq" ? api("lead_disqualify", { id: id, reason: v.reason }) : api("lead_to_enquiry", { id: id, need: v.need, budget: v.budget }); }, op === "dq" ? T("Lead disqualified", "লিড বাতিল") : T("Enquiry created", "অনুসন্ধান তৈরি"));
      case "enq_opp": return run(function () { return api("enquiry_to_opportunity", { id: id, kind: v.kind }); }, T("Opportunity created", "সুযোগ তৈরি"), function (r) { location.hash = "#/opp/" + r.opp.id; });
      case "quote_save": {
        var d = f.querySelectorAll('[name="desc"]'), q = f.querySelectorAll('[name="qty"]'), p = f.querySelectorAll('[name="price"]'), lines = [];
        for (var i = 0; i < d.length; i++) if (d[i].value.trim() || p[i].value !== "") lines.push({ desc: d[i].value, qty: q[i].value, price: p[i].value });
        return run(function () { return api("quote_save", { opp_id: id, lines: lines, discount_pct: v.discount_pct, note: v.note }); }, T("New quotation version saved", "নতুন কোটেশন ভার্সন সংরক্ষিত"));
      }
      case "opp_lost": return run(function () { return api("opp_move", { id: id, stage: "lost", reason: v.reason }); }, T("Marked lost", "হারানো চিহ্নিত"));
      case "fu_create": return run(function () { return api("followup_create", { customer_id: id || v.customer_id, note: v.note, due_days: v.due_days }); }, T("Follow-up scheduled", "ফলো-আপ নির্ধারিত"));
      case "loy": return run(function () { return api("loyalty_adjust", { id: id, points: v.points, reason: v.reason }); }, T("Points adjusted", "পয়েন্ট সমন্বিত"));
      case "prefs": return run(function () { return api("prefs_set", { id: id, channel: v.channel, lang: v.lang, quiet: v.quiet }); }, ok);
      case "tk_create": return run(function () { return api("ticket_create", v); }, T("Ticket opened", "টিকিট খোলা হয়েছে"));
      case "tk_resolve": return run(function () { return api("ticket_update", { id: id, status: "RESOLVED", resolution: v.resolution, evidence: v.evidence }); }, T("Ticket resolved", "টিকিট সমাধান"));
      case "seg_create": return run(function () { return api("segment_create", v); }, ok);
      case "cp_create": return run(function () { return api("campaign_create", v); }, T("Campaign draft created", "ক্যাম্পেইন ড্রাফট তৈরি"));
      case "stage_save": return run(function () { return api("stage_save", { key: f.getAttribute("data-key"), en: v.en, bn: v.bn }); }, ok);
      case "stage_add": return run(function () { return api("stage_save", v); }, T("Stage added", "ধাপ যোগ"));
      case "approval": return run(function () { return api("approval_set", v); }, ok);
      case "sla": return run(function () { return api("sla_set", v); }, ok);
    }
  });
  window.addEventListener("hashchange", route);
  window.CORE10_CRM_UI = { esc: esc, csvCell: csvCell };
  (async function () { try { S.tenants = await B.call("tenants", {}); } catch (e) { S.tenants = []; } route(); })();
})();
