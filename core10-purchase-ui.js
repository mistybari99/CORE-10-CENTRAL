/* CORE 10 CENTRAL | B-012 Purchase and goods receipt screen (NP03A). Bangla/English, 390-1440px, Control Centre styles.
 * Renders server data through textContent only. Every change goes through a server-authorised procurement RPC; buttons
 * are shown from the signed context (role, site actions, creator) and the server still decides each write.
 */
(function (root, factory) {
  "use strict";
  const ui = factory();
  if (typeof module === "object" && module.exports) module.exports = ui;
  if (root) root.CORE10_PURCHASE_UI = ui;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const T = {
    title: ["ক্রয় ও মাল গ্রহণ", "Purchases & goods receipt"], sub: ["ক্রয় আদেশ, মাল গ্রহণ, মান যাচাই ও স্টকে তোলা", "Purchase orders, receiving, quality check and stock"],
    business: ["ব্যবসা", "Business"], site: ["স্থান", "Site"], allSites: ["সব স্থান", "All sites"], lang: ["English", "বাংলা"],
    all: ["সব", "All"], more: ["আরও দেখুন", "Show more"], none: ["কোনো ক্রয় আদেশ নেই", "No purchase orders"], loading: ["লোড হচ্ছে…", "Loading…"],
    noBusiness: ["আপনার দেখার মতো কোনো ব্যবসা নেই", "You have no business to view"],
    pick: ["বাম দিক থেকে একটি ক্রয় আদেশ নির্বাচন করুন", "Select a purchase order on the left"],
    newPo: ["নতুন ক্রয় আদেশ", "New purchase order"], editPo: ["খসড়া সম্পাদনা", "Edit draft"], po: ["ক্রয় আদেশ", "Purchase order"],
    supplier: ["সরবরাহকারী", "Supplier"], expectedOn: ["প্রত্যাশিত তারিখ (ঐচ্ছিক)", "Expected date (optional)"], note: ["মন্তব্য (ঐচ্ছিক)", "Note (optional)"],
    item: ["পণ্য", "Item"], qty: ["পরিমাণ", "Quantity"], price: ["একক মূল্য (৳)", "Unit price (৳)"], amount: ["মূল্য", "Amount"], total: ["মোট", "Total"],
    line: ["লাইন", "Line"], addLine: ["লাইন যোগ করুন", "Add line"], removeLine: ["লাইন সরান", "Remove line"],
    ordered: ["অর্ডার", "Ordered"], accepted: ["গ্রহণযোগ্য", "Accepted"], rejected: ["বাতিল", "Rejected"], open: ["বাকি", "Open"],
    save: ["সংরক্ষণ", "Save"], cancelForm: ["ফিরে যান", "Back"], saved: ["সংরক্ষিত হয়েছে", "Saved"], required: ["এই ঘরটি পূরণ করুন", "Please fill in this field"],
    approve: ["অনুমোদন করুন", "Approve"], approved: ["অনুমোদিত হয়েছে", "Approved"], requestApproval: ["অনুমোদনের জন্য পাঠান", "Send for approval"],
    cancelPo: ["আদেশ বাতিল", "Cancel order"], closePo: ["আদেশ বন্ধ করুন", "Close order"], yes: ["হ্যাঁ, নিশ্চিত", "Yes, confirm"], no: ["না", "No"],
    confirmCancel: ["আদেশটি বাতিল করবেন? এটি আর ফেরানো যাবে না।", "Cancel this order? This cannot be undone."],
    confirmClose: ["বাকি পরিমাণ আর আসবে না ধরে আদেশটি বন্ধ করবেন?", "Close this order? The open quantity will no longer be expected."],
    cancelled: ["আদেশ বাতিল হয়েছে", "Order cancelled"], closed: ["আদেশ বন্ধ হয়েছে", "Order closed"],
    receive: ["মাল গ্রহণ (GRN)", "Receive goods (GRN)"], location: ["গুদামের জায়গা", "Store location"], supplierRef: ["চালান নম্বর (ঐচ্ছিক)", "Delivery note no. (optional)"],
    receiveQty: ["এখন গ্রহণ", "Receive now"], receivedQty: ["গৃহীত পরিমাণ", "Received"], challan: ["চালান", "Delivery note"], lot: ["লট নম্বর", "Lot no."], mfg: ["উৎপাদনের তারিখ", "Made on"], exp: ["মেয়াদ শেষ", "Expires on"],
    received: ["মাল গ্রহণ হয়েছে — মান যাচাই বাকি", "Goods received — quality check pending"], receivedNoQc: ["মাল গ্রহণ হয়েছে — স্টকে তোলা বাকি", "Goods received — ready for stock"],
    qc: ["মান যাচাই", "Quality check"], qcNotes: ["যাচাইয়ের মন্তব্য", "Check notes"], inspected: ["মান যাচাই সম্পন্ন — স্টকে তোলা বাকি", "Checked — ready for stock"],
    post: ["স্টকে তুলুন", "Add to stock"], posted: ["স্টকে তোলা হয়েছে", "Added to stock"], receipts: ["মাল গ্রহণের রসিদ", "Goods receipts"], grn: ["রসিদ", "Receipt"],
    lines: ["আদেশের লাইন", "Order lines"], noReceipts: ["এখনো কোনো মাল গ্রহণ হয়নি", "No goods received yet"], nothingOpen: ["সব পরিমাণ গ্রহণ হয়ে গেছে", "Everything has been received"],
    pickLine: ["অন্তত একটি লাইনে গ্রহণের পরিমাণ দিন", "Enter a quantity on at least one line"], noLocation: ["এই স্থানে কোনো গুদামের জায়গা নেই", "This site has no store location"],
    noSupplier: ["মাস্টার ডেটায় কোনো সক্রিয় সরবরাহকারী নেই — আগে সরবরাহকারী যোগ করুন।", "There is no active supplier in Master Data — add a supplier first."],
    noItem: ["মাস্টার ডেটায় কোনো সক্রিয় পণ্য নেই।", "There is no active item in Master Data."],
    createdBy: ["তৈরি করেছেন", "Created by"], you: ["আপনি", "you"], version: ["সংস্করণ", "Version"], expected: ["প্রত্যাশিত", "Expected"],
    viewOnly: ["আপনি এই ব্যবসায় শুধু মাল গ্রহণ ও যাচাই করতে পারেন", "In this business you can receive and check goods only"],
    requested: ["অনুমোদনের জন্য পাঠানো হয়েছে। অনুমোদন তালিকায় সিদ্ধান্তের পর ম্যানেজার বা মালিক আদেশটি অনুমোদন করবেন।",
      "Sent for approval. After the decision in the approval inbox, a manager or the owner approves the order here."],
    approvalHint: ["অনুমোদনের ধাপ চালু থাকলে প্রস্তুতকারী আগে অনুমোদনের জন্য পাঠান।", "When approval steps are on, the creator sends the order for approval first."],
    helpTotal: ["হিসাব: প্রতিটি লাইনের মূল্য = পরিমাণ × একক মূল্য; মোট = সব লাইনের যোগফল (পয়সা পর্যন্ত)।", "Formula: line amount = quantity × unit price; total = sum of all lines (to the paisa)."],
    helpOpen: ["বাকি = অর্ডার − স্টকে তোলা গ্রহণযোগ্য পরিমাণ − অপেক্ষমাণ রসিদের পরিমাণ।", "Open = ordered − accepted already in stock − quantity on receipts not yet in stock."],
    helpQc: ["বাতিল = গৃহীত পরিমাণ − গ্রহণযোগ্য পরিমাণ। বাতিল পরিমাণ কখনো স্টকে যায় না।", "Rejected = received − accepted. Rejected quantity never reaches stock."],
    helpPost: ["স্টকে তুললে শুধু গ্রহণযোগ্য পরিমাণ এই গুদামের স্টকে যোগ হয়; মালিকের ড্যাশবোর্ডে স্টক দেখা যাবে।", "Adding to stock adds only the accepted quantity to this store; see it on the Owner dashboard."],
    dashLink: ["মালিকের ড্যাশবোর্ডে স্টক দেখুন", "See stock on the Owner dashboard"], masterLink: ["মাস্টার ডেটা খুলুন", "Open Master Data"],
    status: {
      draft: ["খসড়া", "Draft"], approved: ["অনুমোদিত", "Approved"], partially_received: ["আংশিক গৃহীত", "Partly received"],
      received: ["সম্পূর্ণ গৃহীত", "Fully received"], closed: ["বন্ধ", "Closed"], cancelled: ["বাতিল", "Cancelled"]
    },
    feature: {
      "procurement.purchase_order": ["ক্রয় আদেশ", "Purchase orders"], "procurement.goods_receipt": ["মাল গ্রহণ ও মান যাচাই", "Goods receipt and quality check"],
      "inventory.stock_event": ["স্টক হালনাগাদ", "Stock updates"], "gov002.review": ["অনুমোদন পর্যালোচনা", "Approval review"]
    },
    limit: {
      max_lines: ["আদেশের লাইনের সংখ্যা মালিকের নির্ধারিত সীমা ছাড়িয়েছে", "The order has more lines than the owner allows"],
      max_po_amount: ["আদেশের মোট মূল্য মালিকের নির্ধারিত সর্বোচ্চ সীমা ছাড়িয়েছে", "The order total is above the owner's maximum"],
      over_receipt_pct: ["অর্ডারের বাকি পরিমাণের চেয়ে বেশি গ্রহণ করা যাবে না", "You cannot receive more than the open quantity allows"],
      other: ["মালিকের নির্ধারিত সীমা ছাড়িয়েছে", "This is above a limit the owner set"]
    },
    err: {
      PROC_SCOPE: ["এটি দেখার অনুমতি আপনার নেই", "You cannot see this"], PROC_PERMISSION_DENIED: ["এই কাজের অনুমতি আপনার নেই", "You are not allowed to do this"],
      PROC_SITE_SCOPE: ["স্থানটি এই ব্যবসার নয়", "That site is not in this business"], PROC_LOCATION_SCOPE: ["গুদামের জায়গাটি এই আদেশের স্থানের নয়", "That store location is not at this order's site"],
      PROC_SUPPLIER_INVALID: ["সরবরাহকারী সক্রিয় নয় বা সরবরাহকারী নয়", "The supplier is not an active supplier"],
      PROC_ITEM_NOT_USABLE: ["একটি পণ্য সক্রিয় নয়", "An item is not active"], PROC_LINES_INVALID: ["কোনো লাইনের মান সঠিক নয়", "A line has a value that is not valid"],
      PROC_LINES_DUPLICATE_ITEM: ["একই পণ্য দুই লাইনে আছে — এক লাইনে যোগ করুন", "The same item is on two lines — combine them"],
      PROC_STALE_OR_NOT_DRAFT: ["অন্য কেউ এর মধ্যে বদলেছে বা এটি আর খসড়া নয় — নতুন তথ্য দেখানো হলো", "Someone changed it meanwhile or it is no longer a draft — latest shown"],
      PROC_STALE_VERSION: ["অন্য কেউ এর মধ্যে বদলেছে — নতুন তথ্য দেখানো হলো, আবার চেষ্টা করুন", "Someone changed it meanwhile — latest shown, please try again"],
      PROC_INVALID_TRANSITION: ["এই অবস্থায় এ কাজ করা যায় না", "This cannot be done in the current state"],
      PROC_SAME_ACTOR: ["যিনি তৈরি বা গ্রহণ করেছেন তিনি নিজে অনুমোদন/যাচাই করতে পারেন না", "The person who created or received it cannot also approve or check it"],
      PROC_APPROVAL_REQUIRED: ["এই আদেশে অনুমোদনের ধাপ চালু আছে। প্রস্তুতকারী আগে ‘অনুমোদনের জন্য পাঠান’ চাপবেন; অনুমোদন তালিকায় সিদ্ধান্তের পর এখানে অনুমোদন করুন।",
        "Approval steps are on for this order. The creator first presses ‘Send for approval’; after the decision in the approval inbox, approve it here."],
      PROC_APPROVAL_NOT_EFFECTIVE: ["অনুমোদন তালিকায় এখনো সিদ্ধান্ত হয়নি", "The approval inbox has not decided yet"],
      PROC_APPROVAL_RECEIPTS_INCOMPLETE: ["অনুমোদনের সব ধাপ এখনো শেষ হয়নি", "Not every approval step is complete yet"],
      PROC_APPROVAL_ROUTE_MISMATCH: ["অনুমোদনের ধাপ মালিকের সেটিংয়ের সঙ্গে মিলছে না — মালিককে জানান", "The approval steps do not match the owner's settings — tell the owner"],
      PROC_APPROVAL_REQUEST_SCOPE: ["অনুমোদনের আবেদনটি এই আদেশের নয়", "The approval request does not belong to this order"],
      PROC_APPROVAL_MAKER_DENIED: ["শুধু যিনি আদেশটি তৈরি করেছেন তিনিই অনুমোদনের জন্য পাঠাতে পারেন", "Only the person who created the order can send it for approval"],
      PROC_APPROVAL_STAGES_REQUIRED: ["অনুমোদনের কোনো ধাপ চালু নেই — ম্যানেজার বা মালিক সরাসরি অনুমোদন করতে পারেন", "No approval step is on — a manager or the owner can approve directly"],
      PROC_APPROVAL_ALREADY_REQUESTED: ["এই সংস্করণ আগেই অনুমোদনের জন্য পাঠানো হয়েছে", "This version was already sent for approval"],
      PROC_APPROVAL_NOT_CONNECTED: ["অনুমোদন ব্যবস্থা এখনো যুক্ত নয়", "Approval is not available yet"],
      PROC_PO_NOT_OPEN: ["আদেশটি মাল গ্রহণের জন্য খোলা নেই", "This order is not open for receiving"],
      PROC_LOT_REQUIRED: ["লট নম্বর দিন (তারিখ দিলে লট নম্বরও লাগবে)", "Enter a lot number (dates need a lot number too)"],
      PROC_EXPIRY_REQUIRED: ["মেয়াদ শেষের তারিখ দিন", "Enter the expiry date"], PROC_LOT_EXPIRED: ["মেয়াদ পেরিয়ে যাওয়া মাল গ্রহণ করা যাবে না", "Expired goods cannot be received"],
      PROC_LOT_CONFLICT: ["এই লট নম্বর আগে অন্য তারিখে নেওয়া হয়েছে", "This lot number was recorded earlier with other dates"],
      PROC_QC_LINES_INCOMPLETE: ["প্রতিটি লাইনের যাচাই দিন", "Check every line"], PROC_QC_QUANTITY_INVALID: ["গ্রহণযোগ্য পরিমাণ গৃহীত পরিমাণের বেশি হতে পারে না", "Accepted cannot be more than received"],
      PROC_REPLAY_CONFLICT: ["একই অনুরোধ ভিন্ন তথ্যে আগেই পাঠানো হয়েছে — ফর্মটি আবার খুলুন", "This request was already sent with other details — reopen the form"],
      PROC_INVALID_FILTER: ["ফিল্টারটি সঠিক নয়", "That filter is not valid"],
      INVALID_QUANTITY: ["পরিমাণ শূন্যের বেশি সংখ্যা দিন (৩ দশমিক পর্যন্ত)", "Enter a quantity above zero (up to 3 decimals)"],
      INVALID_PRICE: ["একক মূল্য সঠিক সংখ্যায় দিন (২ দশমিক পর্যন্ত)", "Enter a valid unit price (up to 2 decimals)"],
      INVALID_DATE: ["সঠিক তারিখ দিন", "Enter a valid date"], INVALID_LOT: ["লট নম্বরে শুধু অক্ষর, সংখ্যা ও / _ . - চলবে (২–৬০)", "Lot no.: letters, digits and / _ . - only (2–60)"],
      INVALID_SUPPLIER: ["সরবরাহকারী বেছে নিন", "Choose a supplier"], INVALID_ITEM: ["প্রতিটি লাইনে পণ্য বেছে নিন", "Choose an item on every line"],
      INVALID_LOCATION: ["গুদামের জায়গা বেছে নিন", "Choose a store location"], INVALID_SITE: ["স্থান বেছে নিন", "Choose a site"],
      INVALID_NOTE: ["মন্তব্য খুব বড়", "The note is too long"], INVALID_REFERENCE: ["চালান নম্বর খুব বড়", "The delivery note no. is too long"],
      CONTROL_DISABLED: ["মালিক এই সুবিধাটি বন্ধ রেখেছেন", "The owner has switched this off"], CONTROL_SCOPE: ["এটি দেখার অনুমতি আপনার নেই", "You cannot see this"],
      MASTER_SCOPE: ["এই ব্যবসা দেখার অনুমতি নেই", "You cannot see this business"],
      SESSION_CHANGED: ["সাইন-ইন বদলেছে — পাতা আবার খুলুন", "Sign-in changed — reload the page"], SIGNED_SESSION_REQUIRED: ["সাইন-ইন প্রয়োজন", "Sign-in required"],
      other: ["অনুরোধ সম্পন্ন হয়নি — আবার চেষ্টা করুন", "The request did not complete — please try again"]
    }
  };
  const BN = "০১২৩৪৫৬৭৮৯";

  function mount(rootEl, opts) {
    const api = opts.api, P = opts.lib || (typeof window !== "undefined" ? window.CORE10_PURCHASE_API : null), doc = rootEl.ownerDocument;
    const st = { lang: opts.lang === "en" ? "en" : "bn", ctx: null, business: null, site: null, status: null, rows: [], next: null,
      detail: null, form: null, confirm: null, suppliers: [], items: [], keys: {}, flash: null };
    const L = () => (st.lang === "en" ? 1 : 0);
    const t = (k) => (T[k] || [k, k])[L()];
    const digits = (x) => (st.lang === "bn" ? String(x).replace(/[0-9]/g, (d) => BN[d]) : String(x));
    const num = (x) => { if (x === null || x === undefined || x === "") return "—"; const n = Number(x); return digits(Number.isFinite(n) ? String(Math.round(n * 1000) / 1000) : x); };
    const money = (x) => "৳ " + digits(Number(x || 0).toFixed(2));
    const el = (tag, cls, txt) => { const e = doc.createElement(tag); if (cls) e.className = cls; if (txt !== undefined && txt !== null) e.textContent = String(txt); return e; };
    const status = el("p", "occ-status"); status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    const say = (m, kind, code) => { status.textContent = m || ""; if (kind) status.dataset.kind = kind; else delete status.dataset.kind;
      if (code) status.dataset.code = code; else delete status.dataset.code; };
    function errText(e) {
      const c = (e && e.code) || "", d = e && e.detail;
      if (c === "CONTROL_DISABLED") { const f = T.feature[d]; return T.err.CONTROL_DISABLED[L()] + (f ? ": " + f[L()] : ""); }
      if (c === "CONTROL_LIMIT") return (T.limit[d] || T.limit.other)[L()];
      return (T.err[c] || T.err.other)[L()];
    }
    const showErr = (e) => say(errText(e), "error", (e && e.code) || "other");
    // Result of a button action, repeated next to the buttons so it is visible on a phone too.
    const flash = (po, text, code) => { st.flash = { po, text, code: code || null }; };
    async function guard(fn) { try { return await fn(); } catch (e) { showErr(e); if (/STALE/.test(e && e.code)) await reloadDetail(); return null; } }
    const name = (r) => (st.lang === "bn" && r.name_bn) ? r.name_bn : (r.name_en || r.name_bn || r.code || r.sku || "");
    const supplierName = (p) => (st.lang === "bn" && p.supplier_name_bn) ? p.supplier_name_bn : (p.supplier_name_en || "");
    const sites = () => ((st.ctx && st.ctx.sites) || []).filter((s) => st.business && s.business_id === st.business.id);
    const siteLabel = (id) => { const s = sites().find((x) => x.id === id); return s ? s.label : digits("#" + id); };
    const canPost = (siteId) => { const s = sites().find((x) => x.id === siteId); return !!(s && (s.allowed_actions || []).includes("stock.post")); };
    const canBuy = () => !!(st.business && st.business.role !== "site_staff");
    const canManage = () => !!(st.business && st.business.can_manage);
    const isCreator = (po) => !!(po && api.userId() && po.created_by === api.userId());
    const keyFor = (k) => (st.keys[k] = st.keys[k] || P.newKey("pu"));
    const statusLabel = (s) => (T.status[s] || [s, s])[L()];

    // ---------- data ----------
    async function loadList(append) {
      if (!st.business) return;
      const res = await guard(() => api.list(st.business.id, { site: st.site, status: st.status, before: append ? st.next : null }));
      if (!res) return;
      st.rows = append ? st.rows.concat(res.items) : res.items; st.next = res.next_before_id || null;
    }
    async function loadMaster() {
      st.suppliers = []; st.items = [];
      if (!canBuy()) return;
      const pages = async (fn) => { let out = [], after = null;
        for (let i = 0; i < 5; i++) { const r = await guard(() => fn(after)); if (!r) break; out = out.concat(r.rows); after = r.next_after_id; if (!after) break; }
        return out; };
      st.suppliers = await pages((after) => api.suppliers(st.business.id, { after }));
      st.items = await pages((after) => api.items(st.business.id, { after }));
    }
    async function open(poId) {
      st.form = null; st.confirm = null; st.flash = null;
      const d = await guard(() => api.get(poId)); if (d) st.detail = d;
      render(); focusDetail();
    }
    async function reloadDetail() { if (st.detail) { const d = await (async () => { try { return await api.get(st.detail.po_id); } catch (_) { return null; } })(); if (d) st.detail = d; } }
    async function afterWrite(msg, poId) {
      st.form = null; st.confirm = null; flash(poId, msg);
      await loadList(false);
      const d = await guard(() => api.get(poId)); if (d) st.detail = d;
      say(msg); render(); focusDetail();
    }
    async function selectBusiness(id) {
      st.business = ((st.ctx && st.ctx.businesses) || []).find((x) => x.id === id) || null;
      st.site = null; st.status = null; st.flash = null; st.detail = null; st.form = null; st.confirm = null; st.rows = []; st.next = null;
      say(t("loading"));
      if (st.business) { await loadMaster(); await loadList(false); }
      if (status.dataset.kind !== "error") say(""); render();
    }
    function focusDetail() {
      const view = doc.defaultView, det = rootEl.querySelector(".occ-detail");
      if (!det) return;
      if (view && view.innerWidth < 760 && typeof det.scrollIntoView === "function") det.scrollIntoView({ block: "start" });
      const first = det.querySelector("input:not([disabled]),select:not([disabled]),h2");
      if (first) { if (first.tagName === "H2") first.tabIndex = -1; first.focus({ preventScroll: true }); }
    }

    // ---------- small builders ----------
    let uid = 0;
    function field(label, input, note) {
      const w = el("div", "occ-field"), id = "pu-f" + (++uid); input.id = id;
      const l = el("label", null, label); l.htmlFor = id; w.append(l, input);
      if (note) { const n = el("p", "occ-meta", note); n.id = id + "-n"; input.setAttribute("aria-describedby", n.id); w.append(n); }
      return w;
    }
    function input(type, value, max) { const i = el("input"); i.type = type === "date" ? "date" : "text"; if (type === "number") i.inputMode = "decimal";
      if (max) i.maxLength = max; i.value = value == null ? "" : String(value); return i; }
    function select(options, value) { const s = el("select"); options.forEach(([v, lbl]) => { const o = el("option", null, lbl); o.value = v == null ? "" : String(v); s.append(o); });
      s.value = value == null ? "" : String(value); return s; }
    function button(cls, label, fn) { const b = el("button", cls, label); b.type = "button"; b.addEventListener("click", fn); return b; }
    function table(head, rows) {
      const w = el("div", "md-table"), tb = el("table"), tr = el("tr"); head.forEach((h) => tr.append(el("th", null, h)));
      const th = el("thead"); th.append(tr); const body = el("tbody");
      rows.forEach((r) => { const x = el("tr"); r.forEach((c) => x.append(el("td", null, c))); body.append(x); });
      tb.append(th, body); w.append(tb); return w;
    }
    // Form frame: error line, Back + submit. submit(values) throws on failure.
    function frame(title, body, submitLabel, submit) {
      const f = el("form", "occ-panel"); f.noValidate = true; f.setAttribute("aria-label", title);
      const err = el("p", "occ-field-error"); err.setAttribute("role", "alert");
      const actions = el("div", "occ-actions"), back = button("occ-secondary", t("cancelForm"), () => { st.form = null; render(); focusDetail(); });
      const ok = el("button", "occ-primary", submitLabel); ok.type = "submit"; actions.append(back, ok);
      body.forEach((n) => f.append(n)); f.append(err, actions);
      f.addEventListener("submit", async (ev) => {
        ev.preventDefault(); err.textContent = ""; delete err.dataset.code; ok.disabled = true;
        try { await submit((m, focus) => { err.textContent = m; if (focus) { focus.setAttribute("aria-invalid", "true"); focus.focus(); } throw Object.assign(new Error("LOCAL"), { local: true }); }); }
        catch (e) { if (!e.local) { err.textContent = errText(e); err.dataset.code = e.code || "other"; if (/STALE/.test(e.code)) await reloadDetail(); } ok.disabled = false; }
      });
      st.form = { title, node: f }; render(); focusDetail();
    }

    // ---------- purchase order form ----------
    function poForm(base) {
      if (!st.suppliers.length) { say(t("noSupplier"), "error", "NO_SUPPLIER"); return; }
      if (!st.items.length) { say(t("noItem"), "error", "NO_ITEM"); return; }
      const reqKey = P.newKey("po");
      const lines = base ? base.lines.map((l) => ({ item: l.item_id, quantity: String(l.quantity), unitPrice: String(l.unit_price) })) : [{ item: "", quantity: "", unitPrice: "" }];
      const siteSel = select(sites().map((s) => [s.id, s.label]), base ? base.site_id : (st.site || (sites()[0] && sites()[0].id)));
      const supSel = select([[null, "—"]].concat(st.suppliers.map((p) => [p.id, name(p) + " · " + p.code])), base ? base.supplier_id : null);
      const dateIn = input("date", base && base.expected_on), noteIn = input("text", base && base.note, 500);
      const box = el("div", "pu-lines"), totalOut = el("p", "pu-total"); totalOut.setAttribute("aria-live", "polite");
      const itemOpts = [[null, "—"]].concat(st.items.map((i) => [i.id, i.sku + " · " + name(i) + (i.base_uom_code ? " (" + i.base_uom_code + ")" : "")]));
      function retotal() {
        let sum = 0n, ok = true;
        lines.forEach((l, i) => { const a = P.lineAmount(l.quantity, l.unitPrice); const out = box.querySelector("[data-line-amount='" + i + "']");
          if (out) out.textContent = a === null ? "—" : "৳ " + digits(P.paisaText(a)); if (a === null) ok = false; else sum += a; });
        totalOut.textContent = t("total") + ": " + (ok ? "৳ " + digits(P.paisaText(sum)) : "—");
      }
      function drawLines() {
        box.replaceChildren();
        lines.forEach((l, i) => {
          const fs = el("fieldset", "occ-field pu-line"); fs.dataset.line = String(i + 1); fs.append(el("legend", null, t("line") + " " + digits(i + 1)));
          const it = select(itemOpts, l.item), q = input("number", l.quantity, 12), pr = input("number", l.unitPrice, 14);
          it.addEventListener("change", () => { l.item = it.value; }); q.addEventListener("input", () => { l.quantity = q.value; retotal(); });
          pr.addEventListener("input", () => { l.unitPrice = pr.value; retotal(); });
          it.dataset.k = "item"; q.dataset.k = "qty"; pr.dataset.k = "price";
          const row = el("div", "pu-line-grid"); row.append(field(t("qty"), q), field(t("price"), pr));
          const amt = el("p", "occ-meta"); amt.append(el("span", null, t("amount") + ": ")); const v = el("span"); v.dataset.lineAmount = String(i); amt.append(v);
          fs.append(field(t("item"), it), row, amt);
          if (lines.length > 1) fs.append(button("occ-secondary md-mini", t("removeLine"), () => { lines.splice(i, 1); drawLines(); }));
          box.append(fs);
        });
        retotal();
      }
      drawLines();
      const add = button("occ-secondary", t("addLine"), () => { if (lines.length < 200) { lines.push({ item: "", quantity: "", unitPrice: "" }); drawLines();
        const last = box.querySelector("fieldset:last-child select"); if (last) last.focus(); } });
      frame(base ? t("editPo") + " · #" + digits(base.po_id) : t("newPo"), [field(t("site"), siteSel), field(t("supplier") + " *", supSel), box, add, totalOut,
        el("p", "occ-meta", t("helpTotal")), field(t("expectedOn"), dateIn), field(t("note"), noteIn)], t("save"), async (bad) => {
        if (!supSel.value) bad(t("required") + ": " + t("supplier"), supSel);
        const missing = lines.findIndex((l) => !l.item || !String(l.quantity).trim() || !String(l.unitPrice).trim());
        if (missing >= 0) bad(t("required") + ": " + t("line") + " " + digits(missing + 1), box.querySelectorAll("fieldset")[missing].querySelector("select"));
        const r = await api.savePo(st.business.id, { po: base ? base.po_id : null, expectedVersion: base ? base.version : 0, site: siteSel.value,
          supplier: supSel.value, lines, expectedOn: dateIn.value, note: noteIn.value, requestKey: reqKey });
        await afterWrite(t("saved"), r.po_id);
      });
    }

    // ---------- receive goods ----------
    function openQty(po) {
      const m = {}; po.lines.forEach((l) => { m[l.line_no] = Number(l.quantity); });
      (po.receipts || []).forEach((g) => g.lines.forEach((gl) => { m[gl.line_no] -= Number(g.status === "posted" ? gl.accepted_qty : gl.received_qty); }));
      Object.keys(m).forEach((k) => { m[k] = Math.max(0, Math.round(m[k] * 1000) / 1000); }); return m;
    }
    async function receiveForm(po) {
      const locs = (await guard(() => api.locations(st.business.id, po.site_id))) || [];
      if (!locs.length) { if (status.dataset.kind !== "error") say(t("noLocation"), "error", "NO_LOCATION"); render(); return; }
      const reqKey = P.newKey("grn"), open = openQty(po);
      const locSel = select(locs.map((l) => [l.id, l.code]), locs[0].id), ref = input("text", "", 80);
      const rows = [], box = el("div", "pu-lines");
      po.lines.filter((l) => open[l.line_no] > 0).forEach((l) => {
        const fs = el("fieldset", "occ-field pu-line"); fs.dataset.line = String(l.line_no);
        fs.append(el("legend", null, name(l) + " · " + l.sku));
        fs.append(el("p", "occ-meta", t("ordered") + " " + num(l.quantity) + " · " + t("open") + " " + num(open[l.line_no])));
        const q = input("number", String(open[l.line_no]), 12), lot = input("text", "", 60), mfg = input("date", ""), exp = input("date", "");
        q.dataset.k = "qty"; lot.dataset.k = "lot"; mfg.dataset.k = "mfg"; exp.dataset.k = "exp";
        const g1 = el("div", "pu-line-grid"); g1.append(field(t("receiveQty"), q), field(t("lot"), lot));
        const g2 = el("div", "pu-line-grid"); g2.append(field(t("mfg"), mfg), field(t("exp"), exp));
        fs.append(g1, g2); box.append(fs); rows.push({ l, q, lot, mfg, exp });
      });
      if (!rows.length) { say(t("nothingOpen")); render(); return; }
      frame(t("receive") + " · #" + digits(po.po_id), [field(t("location"), locSel), field(t("supplierRef"), ref), el("p", "occ-meta", t("helpOpen")), box], t("receive"), async (bad) => {
        const chosen = rows.filter((r) => String(r.q.value).trim() && Number(P.ascii(r.q.value)) !== 0);
        if (!chosen.length) bad(t("pickLine"), rows[0].q);
        const g = await api.receive(po.po_id, { location: locSel.value, supplierRef: ref.value, requestKey: reqKey,
          lines: chosen.map((r) => ({ lineNo: r.l.line_no, quantity: r.q.value, lot: r.lot.value, manufacturedOn: r.mfg.value, expiresOn: r.exp.value })) });
        await afterWrite(g && g.status === "inspected" ? t("receivedNoQc") : t("received"), po.po_id);
      });
    }

    // ---------- quality check ----------
    function qcForm(po, g) {
      const reqKey = P.newKey("qc"), rows = [], box = el("div", "pu-lines");
      g.lines.forEach((gl) => {
        const pl = po.lines.find((l) => l.line_no === gl.line_no) || {};
        const fs = el("fieldset", "occ-field pu-line"); fs.dataset.line = String(gl.line_no);
        fs.append(el("legend", null, name(pl) + (gl.lot_code ? " · " + t("lot") + " " + gl.lot_code : "")));
        const acc = input("number", String(gl.received_qty), 12), notes = input("text", "", 500), rej = el("p", "occ-meta");
        acc.dataset.k = "accepted"; notes.dataset.k = "notes"; rej.setAttribute("aria-live", "polite");
        const upd = () => { const a = Number(P.ascii(acc.value)); rej.textContent = t("rejected") + ": " + (Number.isFinite(a) && String(acc.value).trim() ? num(Math.max(0, Number(gl.received_qty) - a)) : "—"); };
        acc.addEventListener("input", upd); upd();
        fs.append(el("p", "occ-meta", t("receivedQty") + ": " + num(gl.received_qty)));
        const grid = el("div", "pu-line-grid"); grid.append(field(t("accepted"), acc), field(t("qcNotes"), notes));
        fs.append(grid, rej); box.append(fs); rows.push({ gl, acc, notes });
      });
      frame(t("qc") + " · " + t("grn") + " #" + digits(g.grn_id), [el("p", "occ-meta", t("helpQc")), box], t("qc"), async (bad) => {
        const miss = rows.find((r) => !String(r.acc.value).trim()); if (miss) bad(t("required") + ": " + t("accepted"), miss.acc);
        await api.inspect(g.grn_id, { version: g.version, requestKey: reqKey, lines: rows.map((r) => ({ lineNo: r.gl.line_no, accepted: r.acc.value, notes: r.notes.value })) });
        await afterWrite(t("inspected"), po.po_id);
      });
    }

    // ---------- actions ----------
    async function act(po, action, okMsg) {
      const k = keyFor(po.po_id + ":" + action + ":" + po.version);
      say(t("loading"));
      try { await api.advance(po.po_id, action, po.version, k); await afterWrite(okMsg, po.po_id); }
      catch (e) { st.confirm = null; showErr(e); flash(po.po_id, errText(e), e.code || "other"); if (/STALE/.test(e.code)) await reloadDetail(); render(); }
    }
    async function requestApproval(po) {
      const k = keyFor(po.po_id + ":request:" + po.version);
      try { await api.requestApproval(po.po_id, k); await afterWrite(t("requested"), po.po_id); }
      catch (e) { showErr(e); flash(po.po_id, errText(e), e.code || "other"); render(); }
    }
    async function postGrn(po, g) {
      const k = keyFor("grn:" + g.grn_id + ":post:" + g.version);
      say(t("loading"));
      try { await api.post(g.grn_id, g.version, k); await afterWrite(t("posted"), po.po_id); }
      catch (e) { showErr(e); flash(po.po_id, errText(e), e.code || "other"); if (/STALE/.test(e.code)) await reloadDetail(); render(); }
    }

    // ---------- detail ----------
    function grnStatus(g) { return g.status === "posted" ? t("posted") : g.status === "inspected" ? t("inspected") : t("received"); }
    function detailPanel() {
      const d = el("section", "occ-detail"); d.setAttribute("aria-live", "polite");
      if (st.form) { d.append(el("h2", null, st.form.title), st.form.node); return d; }
      const po = st.detail;
      if (!po) { d.append(el("p", "occ-empty", t("pick"))); return d; }
      d.dataset.po = String(po.po_id); d.dataset.status = po.status;
      d.append(el("h2", null, t("po") + " #" + digits(po.po_id)));
      const chips = el("p", "occ-chips"); chips.append(el("span", "occ-chip pu-st-" + po.status, statusLabel(po.status))); d.append(chips);
      d.append(el("p", "occ-meta", t("supplier") + ": " + supplierName(po) + " · " + t("site") + ": " + siteLabel(po.site_id)
        + (po.expected_on ? " · " + t("expected") + ": " + digits(po.expected_on) : "") + " · " + t("version") + " " + digits(po.version)
        + (isCreator(po) ? " · " + t("createdBy") + ": " + t("you") : "")));
      if (po.note) d.append(el("p", "occ-meta pu-note", po.note));
      const bar = el("div", "occ-actions pu-actions");
      if (po.status === "draft") {
        if (canBuy()) bar.append(button("occ-secondary", t("editPo"), () => poForm(po)));
        if (isCreator(po)) bar.append(button("occ-secondary", t("requestApproval"), () => requestApproval(po)));
        if (canManage() || isCreator(po)) bar.append(button("occ-secondary", t("cancelPo"), () => { st.confirm = "cancel"; render(); }));
        if (canManage()) bar.append(button("occ-primary", t("approve"), () => act(po, "approve", t("approved"))));
      } else if (po.status === "approved" || po.status === "partially_received") {
        if (canManage() && po.status === "approved" && !(po.receipts || []).length) bar.append(button("occ-secondary", t("cancelPo"), () => { st.confirm = "cancel"; render(); }));
        if (canManage()) bar.append(button("occ-secondary", t("closePo"), () => { st.confirm = "close"; render(); }));
        if (canPost(po.site_id)) bar.append(button("occ-primary", t("receive"), () => receiveForm(po)));
      }
      if (bar.childNodes.length) d.append(bar);
      if (st.flash && st.flash.po === po.po_id) {
        const f = el("p", st.flash.code ? "occ-field-error pu-flash" : "occ-note pu-flash", st.flash.text);
        f.setAttribute("role", st.flash.code ? "alert" : "status"); if (st.flash.code) f.dataset.code = st.flash.code; d.append(f);
      }
      if (po.status === "draft" && isCreator(po)) d.append(el("p", "occ-meta", t("approvalHint")));
      if (st.confirm) {
        const c = el("div", "occ-lock pu-confirm"); c.setAttribute("role", "alertdialog"); c.setAttribute("aria-label", t(st.confirm === "cancel" ? "cancelPo" : "closePo"));
        c.append(el("p", null, t(st.confirm === "cancel" ? "confirmCancel" : "confirmClose")));
        const a = el("div", "occ-actions"); const what = st.confirm;
        a.append(button("occ-secondary", t("no"), () => { st.confirm = null; render(); }),
          button("occ-primary", t("yes"), () => act(po, what, t(what === "cancel" ? "cancelled" : "closed"))));
        c.append(a); d.append(c);
      }
      const open = openQty(po);
      const h = el("div", "md-sec"); h.append(el("h3", null, t("lines"))); d.append(h);
      d.append(table([t("item"), t("ordered"), t("price"), t("amount"), t("accepted"), t("rejected"), t("open")],
        po.lines.map((l) => [name(l) + " · " + l.sku, num(l.quantity), digits(Number(l.unit_price).toFixed(2)), digits(Number(l.amount).toFixed(2)),
          num(l.accepted_qty), num(l.rejected_qty), num(open[l.line_no])])));
      d.append(el("p", "pu-total", t("total") + ": " + money(po.total_amount)));
      const h2 = el("div", "md-sec"); h2.append(el("h3", null, t("receipts"))); d.append(h2);
      if (!(po.receipts || []).length) d.append(el("p", "occ-empty", t("noReceipts")));
      (po.receipts || []).forEach((g) => {
        const box = el("article", "occ-hist pu-grn"); box.dataset.grn = String(g.grn_id); box.dataset.status = g.status;
        box.append(el("strong", null, t("grn") + " #" + digits(g.grn_id) + " · " + grnStatus(g)));
        box.append(el("p", "occ-meta", (g.supplier_ref ? t("challan") + ": " + g.supplier_ref + " · " : "") + digits(String(g.received_at || "").slice(0, 10))));
        box.append(table([t("item"), t("receivedQty"), t("accepted"), t("rejected"), t("lot"), t("mfg"), t("exp")],
          g.lines.map((gl) => { const pl = po.lines.find((l) => l.line_no === gl.line_no) || {};
            return [name(pl) || ("#" + gl.item_id), num(gl.received_qty), num(gl.accepted_qty), num(gl.rejected_qty), gl.lot_code || "—",
              gl.manufactured_on ? digits(gl.manufactured_on) : "—", gl.expires_on ? digits(gl.expires_on) : "—"]; })));
        if (canPost(g.site_id) && g.status === "received") { const a = el("div", "occ-actions"); a.append(button("occ-primary", t("qc"), () => qcForm(po, g))); box.append(a); }
        if (canPost(g.site_id) && g.status === "inspected") {
          box.append(el("p", "occ-meta", t("helpPost")));
          const a = el("div", "occ-actions"); a.append(button("occ-primary", t("post"), () => postGrn(po, g))); box.append(a);
        }
        d.append(box);
      });
      const links = el("p", "occ-meta md-note"), dash = el("a", null, t("dashLink")); dash.href = "./core10-owner-dashboard.html"; links.append(dash);
      d.append(links);
      return d;
    }

    function render() {
      doc.documentElement.lang = st.lang;
      const top = el("header", "occ-top"), brand = el("div", "occ-brand"); brand.append(el("h1", null, t("title")), el("p", null, t("sub")));
      const controls = el("div", "occ-controls");
      const bs = el("select"); bs.dataset.k = "business"; ((st.ctx && st.ctx.businesses) || []).forEach((b) => { const o = el("option", null, b.label || b.slug || ("#" + b.id)); o.value = String(b.id); bs.append(o); });
      if (st.business) bs.value = String(st.business.id);
      bs.setAttribute("aria-label", t("business")); bs.addEventListener("change", () => selectBusiness(Number(bs.value)));
      const ss = select([[null, t("allSites")]].concat(sites().map((s) => [s.id, s.label])), st.site); ss.dataset.k = "site"; ss.setAttribute("aria-label", t("site"));
      ss.addEventListener("change", async () => { st.site = ss.value ? Number(ss.value) : null; st.detail = null; st.form = null; await loadList(false); render(); });
      const lb = button("occ-secondary", t("lang"), () => { st.lang = st.lang === "en" ? "bn" : "en"; try { localStorage.setItem("core10.pu.lang", st.lang); } catch (_) {} render(); });
      lb.setAttribute("aria-label", "Language / ভাষা"); lb.dataset.k = "lang";
      if (st.business) controls.append(bs, ss); controls.append(lb); top.append(brand, controls);
      const wrap = el("div", "occ");
      if (!st.business) { wrap.append(top, status); if (st.ctx && status.dataset.kind !== "error") wrap.append(el("p", "occ-empty pu-empty", t("noBusiness"))); rootEl.replaceChildren(wrap); return; }
      const tabs = el("nav", "occ-tabs"); tabs.setAttribute("aria-label", t("po"));
      [null].concat(P.STATUSES).forEach((s) => { const b = el("button", st.status === s ? "is-active" : null, s ? statusLabel(s) : t("all")); b.type = "button"; b.dataset.status = s || "all";
        if (st.status === s) b.setAttribute("aria-current", "page");
        b.addEventListener("click", async () => { st.status = s; st.detail = null; st.form = null; st.confirm = null; say(t("loading")); await loadList(false); if (status.dataset.kind !== "error") say(""); render(); });
        tabs.append(b); });
      const main = el("div", "occ-main"), list = el("section", "occ-list"); list.setAttribute("aria-label", t("po"));
      if (canBuy()) { const nb = button("occ-primary", t("newPo"), () => { st.detail = null; poForm(null); }); nb.dataset.k = "new"; list.append(nb); }
      else list.append(el("p", "occ-meta", t("viewOnly")));
      const ul = el("ul", "occ-list-plain");
      st.rows.forEach((r) => { const li = el("li"), b = el("button", "occ-row" + (st.detail && st.detail.po_id === r.po_id ? " is-active" : "")); b.type = "button"; b.dataset.po = String(r.po_id);
        b.append(el("span", "occ-row-title", "#" + digits(r.po_id) + " · " + supplierName(r)), el("span", "occ-row-key", siteLabel(r.site_id) + " · " + money(r.total_amount)));
        const chips = el("span", "occ-chips"); chips.append(el("span", "occ-chip pu-st-" + r.status, statusLabel(r.status))); b.append(chips);
        b.addEventListener("click", () => open(r.po_id)); li.append(b); ul.append(li); });
      if (!st.rows.length) ul.append(el("li", "occ-empty", t("none")));
      list.append(ul);
      if (st.next) { const m = button("occ-secondary", t("more"), async () => { await loadList(true); render(); }); m.dataset.k = "more"; list.append(m); }
      main.append(list, detailPanel());
      wrap.append(top, status, tabs, main);
      rootEl.replaceChildren(wrap);
    }
    async function start() {
      say(t("loading")); rootEl.replaceChildren(status);
      st.ctx = await guard(() => api.context());
      if (!st.ctx) { render(); return; }
      if (status.dataset.kind !== "error") say("");
      // A preferred business (from the shell link) is honoured only if the signed CORE10 context returns it.
      const list = st.ctx.businesses || [], pick = list.find((b) => b.id === opts.preferBusiness) || list[0];
      if (pick) await selectBusiness(pick.id); else render();
    }
    return { start, state: () => st };
  }
  return { mount, T };
});
