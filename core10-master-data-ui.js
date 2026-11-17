/* CORE 10 CENTRAL | B-011 Master Data screen (NP02). Bangla/English, 390-1440px, Control Centre styles.
 * Renders only server data through textContent (no innerHTML). Unfinished neighbours are shown NOT_CONNECTED.
 */
(function (root, factory) {
  "use strict";
  const ui = factory();
  if (typeof module === "object" && module.exports) module.exports = ui;
  if (root) root.CORE10_MASTER_DATA_UI = ui;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const T = {
    title: ["মাস্টার ডেটা", "Master Data"], sub: ["পণ্য, গ্রাহক-সরবরাহকারী, দাম ও একক — এক ক্যানোনিকাল উৎস", "Items, customers & suppliers, prices and units — one canonical source"],
    business: ["ব্যবসা", "Business"], lang: ["English", "বাংলা"], items: ["পণ্য", "Items"], parties: ["গ্রাহক ও সরবরাহকারী", "Customers & suppliers"],
    prices: ["মূল্য তালিকা", "Price lists"], units: ["একক", "Units"], search: ["খুঁজুন (কোড, নাম, বারকোড)", "Search (code, name, barcode)"],
    more: ["আরও দেখুন", "Show more"], none: ["কিছু পাওয়া যায়নি", "Nothing found"], loading: ["লোড হচ্ছে…", "Loading…"],
    newItem: ["নতুন পণ্য", "New item"], newParty: ["নতুন পক্ষ", "New party"], edit: ["সম্পাদনা", "Edit"], save: ["সংরক্ষণ", "Save"], cancel: ["বাতিল", "Cancel"],
    saved: ["সংরক্ষিত হয়েছে", "Saved"], sku: ["SKU", "SKU"], code: ["কোড", "Code"], nameEn: ["নাম (ইংরেজি)", "Name (English)"], nameBn: ["নাম (বাংলা)", "Name (Bangla)"],
    kind: ["ধরন", "Kind"], status: ["অবস্থা", "Status"], baseUom: ["মূল একক", "Base unit"], category: ["শ্রেণি", "Category"], phone: ["ফোন", "Phone"],
    variants: ["ধরন (ভ্যারিয়েন্ট)", "Variants"], barcodes: ["বারকোড", "Barcodes"], priceLines: ["দাম", "Prices"], version: ["সংস্করণ", "Version"],
    readOnly: ["শুধু দেখা যাবে — পরিবর্তন মালিকের অধিকারে", "Read only — changes need owner rights"],
    pick: ["বাম দিক থেকে একটি নির্বাচন করুন", "Select an entry on the left"], conversions: ["রূপান্তর", "Conversions"],
    notConnected: ["এখনো যুক্ত নয় (NOT_CONNECTED)", "Not connected yet (NOT_CONNECTED)"],
    nc: [["স্টক পরিমাণ — স্টক পোর্ট B-012", "Stock on hand — stock port B-012"], ["বিক্রয়/POS-এ ব্যবহার — NP03B", "Use in sales/POS — NP03B"],
      ["উৎপাদন রেসিপি ও খরচ — NP05A", "Recipes and costing — NP05A"], ["প্রাপ্য/প্রদেয় হিসাব — NP06 পর্ব ২", "Receivables/payables — NP06 increment 2"]],
    err: {
      MASTER_SCOPE: ["এই ব্যবসা দেখার অনুমতি নেই", "You cannot see this business"], MASTER_AUTH_DENIED: ["পরিবর্তনের অনুমতি নেই", "You may not change this"],
      MASTER_STALE_OR_MISSING: ["অন্য কেউ আগে বদলেছে — আবার খুলুন", "Someone changed it first — reopen and retry"],
      MASTER_DUPLICATE: ["এই কোড/SKU আগেই আছে", "This code/SKU already exists"], MASTER_INVALID_VALUE: ["কোনো মান সঠিক নয়", "A value is not valid"],
      CONTROL_DISABLED: ["মালিক এই ফিচার বন্ধ রেখেছেন", "The owner has switched this feature off"], SESSION_CHANGED: ["সাইন-ইন বদলেছে — পাতা আবার খুলুন", "Sign-in changed — reload"],
      SIGNED_SESSION_REQUIRED: ["সাইন-ইন প্রয়োজন", "Sign-in required"], other: ["অনুরোধ সম্পন্ন হয়নি", "Request failed"]
    }
  };
  const KINDS = ["stock", "service", "raw_material", "finished_good", "packaging"], PARTY_KINDS = ["customer", "supplier", "both"];

  function mount(rootEl, opts) {
    const api = opts.api, doc = rootEl.ownerDocument;
    const st = { lang: opts.lang === "en" ? "en" : "bn", ctx: null, business: null, tab: "items", search: "", rows: [], next: null,
      selected: null, detail: null, uoms: null, cats: [], lists: [], form: null };
    const t = (k) => (T[k] || [k, k])[st.lang === "en" ? 1 : 0];
    const el = (tag, cls, txt) => { const e = doc.createElement(tag); if (cls) e.className = cls; if (txt !== undefined && txt !== null) e.textContent = String(txt); return e; };
    const status = el("p", "occ-status"); status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    const say = (m, kind) => { status.textContent = m || ""; if (kind) status.dataset.kind = kind; else delete status.dataset.kind; };
    const errText = (e) => { const c = e && e.code; const k = T.err[c] ? c : (String(c || "").startsWith("CONTROL_DISABLED") ? "CONTROL_DISABLED" : "other");
      return T.err[k][st.lang === "en" ? 1 : 0] + (c ? " (" + c + ")" : ""); };
    async function guard(fn) { try { return await fn(); } catch (e) { say(errText(e), "error"); return null; } }
    const canManage = () => !!(st.business && st.business.can_manage);
    const name = (r) => (st.lang === "bn" && r.name_bn) ? r.name_bn : (r.name_en || r.name_bn || r.code || r.sku || "");

    async function loadList(append) {
      if (!st.business) return;
      const b = st.business.id, after = append ? st.next : null;
      let res = null;
      if (st.tab === "items") res = await guard(() => api.items(b, { search: st.search, after }));
      else if (st.tab === "parties") res = await guard(() => api.parties(b, { search: st.search, after }));
      else if (st.tab === "prices") { const l = await guard(() => api.priceLists(b)); res = l ? { rows: l, next_after_id: null } : null; }
      else if (st.tab === "units") { st.uoms = await guard(() => api.uoms(b)); res = st.uoms ? { rows: st.uoms.uoms, next_after_id: null } : null; }
      if (!res) return;
      st.rows = append ? st.rows.concat(res.rows) : res.rows; st.next = res.next_after_id || null;
    }
    async function open(row) {
      st.selected = row; st.form = null; st.detail = null;
      if (st.tab === "items") st.detail = await guard(() => api.item(st.business.id, row.id));
      else if (st.tab === "prices") st.detail = await guard(() => api.priceList(st.business.id, row.id));
      else st.detail = row;
      render();
      const view = doc.defaultView, det = rootEl.querySelector(".occ-detail");
      if (det && view && view.innerWidth < 760 && typeof det.scrollIntoView === "function") det.scrollIntoView({ block: "start" });
    }
    async function selectBusiness(id) {
      st.business = (st.ctx.businesses || []).find((x) => x.id === id) || null; st.selected = null; st.detail = null; st.form = null;
      say(t("loading"));
      if (st.business) { st.cats = (await guard(() => api.categories(st.business.id))) || []; const u = await guard(() => api.uoms(st.business.id)); st.uoms = u; }
      await loadList(false); if (status.dataset.kind !== "error") say(""); render();
    }

    function field(label, input) { const w = el("div", "occ-field"); const id = "md-f-" + Math.random().toString(36).slice(2, 8);
      const l = el("label", null, label); l.htmlFor = id; input.id = id; w.append(l, input); return w; }
    function inputText(v, max) { const i = el("input"); i.type = "text"; i.maxLength = max || 160; i.value = v || ""; return i; }
    function select(values, v, labelOf) { const s = el("select"); values.forEach((x) => { const o = el("option", null, labelOf ? labelOf(x) : x); o.value = x === null ? "" : String(x); s.append(o); });
      s.value = v === null || v === undefined ? "" : String(v); return s; }

    function itemForm(base) {
      const f = el("form", "occ-panel"); f.setAttribute("aria-label", base ? t("edit") : t("newItem"));
      const sku = inputText(base && base.sku, 64); if (base) sku.disabled = true;
      const en = inputText(base && base.name_en), bn = inputText(base && base.name_bn);
      const kind = select(KINDS, base ? base.item_kind : "stock");
      const uomRows = (st.uoms && st.uoms.uoms) || [];
      const uom = select([null].concat(uomRows.map((u) => u.id)), base && base.base_uom_id, (id) => { const u = uomRows.find((x) => x.id === id); return u ? u.code + " · " + name(u) : "—"; });
      const cat = select([null].concat(st.cats.map((c) => c.id)), base && base.category_id, (id) => { const c = st.cats.find((x) => x.id === id); return c ? name(c) : "—"; });
      const stat = select(["active", "inactive", "draft"], base ? base.status : "active");
      const err = el("p", "occ-field-error"); err.setAttribute("role", "alert");
      const reqKey = "item_" + Date.now().toString(36) + Math.random().toString(36).slice(2);
      const actions = el("div", "occ-actions"), cancel = el("button", "occ-secondary", t("cancel")), ok = el("button", "occ-primary", t("save"));
      cancel.type = "button"; ok.type = "submit"; actions.append(cancel, ok);
      f.append(field(t("sku"), sku), field(t("nameEn"), en), field(t("nameBn"), bn), field(t("kind"), kind), field(t("baseUom"), uom), field(t("category"), cat), field(t("status"), stat), err, actions);
      cancel.addEventListener("click", () => { st.form = null; render(); });
      f.addEventListener("submit", async (ev) => {
        ev.preventDefault(); ok.disabled = true; err.textContent = "";
        try {
          const id = await api.saveItem(st.business.id, { sku: sku.value, nameEn: en.value, nameBn: bn.value, kind: kind.value, baseUom: uom.value || null,
            category: cat.value || null, status: stat.value, expectedVersion: base ? base.version : 0, requestKey: reqKey });
          say(t("saved")); st.form = null; await loadList(false); const row = st.rows.find((r) => r.id === id) || { id }; await open(row); return;
        } catch (e) { err.textContent = errText(e); ok.disabled = false; }
      });
      return f;
    }
    function partyForm(base) {
      const f = el("form", "occ-panel"); f.setAttribute("aria-label", base ? t("edit") : t("newParty"));
      const code = inputText(base && base.code, 32); if (base) code.disabled = true;
      const kind = select(PARTY_KINDS, base ? base.party_kind : "customer"), en = inputText(base && base.name_en), bn = inputText(base && base.name_bn), ph = inputText(base && base.phone, 24);
      const stat = select(["active", "inactive", "blocked"], base ? base.status : "active");
      const err = el("p", "occ-field-error"); err.setAttribute("role", "alert");
      const reqKey = "party_" + Date.now().toString(36) + Math.random().toString(36).slice(2);
      const actions = el("div", "occ-actions"), cancel = el("button", "occ-secondary", t("cancel")), ok = el("button", "occ-primary", t("save"));
      cancel.type = "button"; ok.type = "submit"; actions.append(cancel, ok);
      f.append(field(t("code"), code), field(t("kind"), kind), field(t("nameEn"), en), field(t("nameBn"), bn), field(t("phone"), ph), field(t("status"), stat), err, actions);
      cancel.addEventListener("click", () => { st.form = null; render(); });
      f.addEventListener("submit", async (ev) => {
        ev.preventDefault(); ok.disabled = true; err.textContent = "";
        try {
          const id = await api.saveParty(st.business.id, { code: code.value, kind: kind.value, nameEn: en.value, nameBn: bn.value, phone: ph.value, status: stat.value,
            expectedVersion: base ? base.version : 0, requestKey: reqKey });
          say(t("saved")); st.form = null; await loadList(false); await open(st.rows.find((r) => r.id === id) || { id }); return;
        } catch (e) { err.textContent = errText(e); ok.disabled = false; }
      });
      return f;
    }
    function table(head, rows) {
      const w = el("div", "md-table"); const tb = el("table"); const tr = el("tr"); head.forEach((h) => tr.append(el("th", null, h)));
      const th = el("thead"); th.append(tr); const body = el("tbody");
      rows.forEach((r) => { const x = el("tr"); r.forEach((c) => x.append(el("td", null, c))); body.append(x); });
      tb.append(th, body); w.append(tb); return w;
    }
    function detailPanel() {
      const d = el("section", "occ-detail"); d.setAttribute("aria-live", "polite");
      if (st.form) { d.append(el("h2", null, st.form.title), st.form.node); return d; }
      if (!st.detail) { d.append(el("p", "occ-empty", t("pick"))); return d; }
      const r = st.detail; d.append(el("h2", null, name(r)));
      if (st.tab === "items") {
        d.append(el("p", "occ-meta", "SKU " + r.sku + " · " + r.item_kind + " · " + r.status + " · " + t("version") + " " + r.version));
        d.append(el("h3", null, t("variants")), r.variants.length ? table([t("code"), t("nameEn"), t("status")], r.variants.map((v) => [v.code, name(v), v.status])) : el("p", "occ-empty", t("none")));
        d.append(el("h3", null, t("barcodes")), r.barcodes.length ? table([t("barcodes"), "UOM", t("status")], r.barcodes.map((b) => [b.barcode, b.uom_id || "—", b.active ? "✓" : "✗"])) : el("p", "occ-empty", t("none")));
        d.append(el("h3", null, t("priceLines")), r.prices.length ? table([t("prices"), "≥", "UOM", "৳"], r.prices.map((p) => [p.price_list_code, p.min_quantity, p.uom_id, p.unit_price + " " + p.currency])) : el("p", "occ-empty", t("none")));
        if (canManage()) { const b = el("button", "occ-secondary", t("edit")); b.type = "button"; b.addEventListener("click", () => { st.form = { title: t("edit"), node: itemForm(r) }; render(); }); d.append(b); }
      } else if (st.tab === "parties") {
        d.append(el("p", "occ-meta", r.code + " · " + r.party_kind + " · " + r.status + (r.phone ? " · " + r.phone : "") + " · " + t("version") + " " + r.version));
        if (canManage()) { const b = el("button", "occ-secondary", t("edit")); b.type = "button"; b.addEventListener("click", () => { st.form = { title: t("edit"), node: partyForm(r) }; render(); }); d.append(b); }
      } else if (st.tab === "prices") {
        d.append(el("p", "occ-meta", r.code + " · " + r.list_kind + " · " + r.currency + " · " + r.effective_from + (r.effective_to ? " → " + r.effective_to : "")));
        d.append(r.rows.length ? table([t("sku"), t("nameEn"), "UOM", "≥", r.currency], r.rows.map((p) => [p.sku, name(p), p.uom_code, p.min_quantity, p.unit_price])) : el("p", "occ-empty", t("none")));
      } else {
        d.append(el("p", "occ-meta", r.code + " · " + r.dimension + " · " + r.decimals));
        const conv = ((st.uoms && st.uoms.conversions) || []).filter((c) => c.from_uom_id === r.id || c.to_uom_id === r.id);
        const code = (id) => { const u = st.uoms.uoms.find((x) => x.id === id); return u ? u.code : id; };
        d.append(el("h3", null, t("conversions")), conv.length ? table(["1", "=", ""], conv.map((c) => [code(c.from_uom_id), c.factor, code(c.to_uom_id)])) : el("p", "occ-empty", t("none")));
      }
      return d;
    }
    function render() {
      const top = el("header", "occ-top"), brand = el("div", "occ-brand"); brand.append(el("h1", null, t("title")), el("p", null, t("sub")));
      const controls = el("div", "occ-controls");
      const bs = select((st.ctx && st.ctx.businesses || []).map((b) => b.id), st.business && st.business.id, (id) => { const b = st.ctx.businesses.find((x) => x.id === id); return b ? (b.label || b.slug || ("#" + b.id)) : id; });
      bs.setAttribute("aria-label", t("business")); bs.addEventListener("change", () => selectBusiness(Number(bs.value)));
      const lb = el("button", "occ-secondary", t("lang")); lb.type = "button"; lb.setAttribute("aria-label", "Language / ভাষা");
      lb.addEventListener("click", () => { st.lang = st.lang === "en" ? "bn" : "en"; try { localStorage.setItem("core10.md.lang", st.lang); } catch (_) {} rootEl.ownerDocument.documentElement.lang = st.lang; render(); });
      controls.append(bs, lb); top.append(brand, controls);
      const banner = el("aside", "occ-banner"); banner.setAttribute("aria-label", t("notConnected")); banner.dataset.state = "NOT_CONNECTED";
      banner.append(el("strong", null, t("notConnected")), (() => { const u = el("ul", "occ-summary"); T.nc.forEach((n) => u.append(el("li", null, n[st.lang === "en" ? 1 : 0]))); return u; })());
      const tabs = el("nav", "occ-tabs"); tabs.setAttribute("aria-label", t("title"));
      ["items", "parties", "prices", "units"].forEach((k) => { const b = el("button", st.tab === k ? "is-active" : null, t(k)); b.type = "button"; b.dataset.tab = k;
        if (st.tab === k) b.setAttribute("aria-current", "page");
        b.addEventListener("click", async () => { st.tab = k; st.search = ""; st.selected = null; st.detail = null; st.form = null; say(t("loading")); await loadList(false); if (status.dataset.kind !== "error") say(""); render(); });
        tabs.append(b); });
      const main = el("div", "occ-main"), list = el("section", "occ-list"); list.setAttribute("aria-label", t(st.tab));
      if (st.tab === "items" || st.tab === "parties") {
        const s = el("input"); s.type = "search"; s.value = st.search; s.placeholder = t("search"); s.setAttribute("aria-label", t("search"));
        s.addEventListener("keydown", async (ev) => { if (ev.key === "Enter") { ev.preventDefault(); st.search = s.value; await loadList(false); render(); } });
        list.append(s);
        if (canManage()) { const nb = el("button", "occ-primary", st.tab === "items" ? t("newItem") : t("newParty")); nb.type = "button";
          nb.addEventListener("click", () => { st.detail = null; st.form = { title: nb.textContent, node: st.tab === "items" ? itemForm(null) : partyForm(null) }; render(); }); list.append(nb); }
        else if (st.business) list.append(el("p", "occ-meta", t("readOnly")));
      }
      const ul = el("ul", "occ-list-plain");
      st.rows.forEach((r) => { const li = el("li"), b = el("button", "occ-row" + (st.selected && st.selected.id === r.id ? " is-active" : "")); b.type = "button";
        b.append(el("span", "occ-row-title", name(r)), el("span", "occ-row-key", r.sku || r.code || ""));
        const chips = el("span", "occ-chips"); [r.status || (r.active === false ? "inactive" : r.active ? "active" : null), r.item_kind || r.party_kind || r.list_kind || r.dimension].filter(Boolean)
          .forEach((c) => chips.append(el("span", "occ-chip" + (c === "active" ? " occ-chip-on" : c === "inactive" || c === "blocked" ? " occ-chip-off" : ""), c)));
        b.append(chips); b.addEventListener("click", () => open(r)); li.append(b); ul.append(li); });
      if (!st.rows.length) ul.append(el("li", "occ-empty", t("none")));
      list.append(ul);
      if (st.next) { const m = el("button", "occ-secondary", t("more")); m.type = "button"; m.addEventListener("click", async () => { await loadList(true); render(); }); list.append(m); }
      main.append(list, detailPanel());
      const wrap = el("div", "occ"); wrap.append(top, status, banner, tabs, main);
      rootEl.replaceChildren(wrap);
    }
    async function start() {
      say(t("loading")); rootEl.replaceChildren(status);
      st.ctx = await guard(() => api.context());
      if (!st.ctx) { render(); return; }
      const first = (st.ctx.businesses || [])[0];
      if (first) await selectBusiness(first.id); else render();
    }
    return { start, state: () => st };
  }
  return { mount, T };
});
