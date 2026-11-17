/* CORE 10 CENTRAL | B-011 Master Data screen (NP02). Bangla/English, 390-1440px, Control Centre styles.
 * Renders server data through textContent only. Every change goes through a server-authorised master RPC;
 * edit controls appear only for owners (server can_manage) and the server still decides each write.
 */
(function (root, factory) {
  "use strict";
  const ui = factory();
  if (typeof module === "object" && module.exports) module.exports = ui;
  if (root) root.CORE10_MASTER_DATA_UI = ui;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const T = {
    title: ["মাস্টার ডেটা", "Master Data"], sub: ["পণ্য, গ্রাহক-সরবরাহকারী, দাম ও একক", "Items, customers & suppliers, prices and units"],
    business: ["ব্যবসা", "Business"], lang: ["English", "বাংলা"], items: ["পণ্য", "Items"], parties: ["গ্রাহক ও সরবরাহকারী", "Customers & suppliers"],
    prices: ["মূল্য তালিকা", "Price lists"], units: ["একক", "Units"], search: ["খুঁজুন (কোড, নাম, বারকোড)", "Search (code, name, barcode)"],
    more: ["আরও দেখুন", "Show more"], none: ["কিছু পাওয়া যায়নি", "Nothing found"], loading: ["লোড হচ্ছে…", "Loading…"],
    newItem: ["নতুন পণ্য", "New item"], newParty: ["নতুন পক্ষ", "New party"], newUnit: ["নতুন একক", "New unit"], newList: ["নতুন মূল্য তালিকা", "New price list"],
    addVariant: ["ধরন যোগ করুন", "Add variant"], addBarcode: ["বারকোড যোগ করুন", "Add barcode"], addPrice: ["দাম যোগ করুন", "Add price"], addConv: ["রূপান্তর যোগ করুন", "Add conversion"],
    edit: ["সম্পাদনা", "Edit"], save: ["সংরক্ষণ", "Save"], cancel: ["বাতিল", "Cancel"], saved: ["সংরক্ষিত হয়েছে", "Saved"],
    sku: ["SKU", "SKU"], code: ["কোড", "Code"], nameEn: ["নাম (ইংরেজি)", "Name (English)"], nameBn: ["নাম (বাংলা)", "Name (Bangla)"],
    kind: ["ধরন", "Kind"], status: ["অবস্থা", "Status"], baseUom: ["মূল একক", "Base unit"], category: ["শ্রেণি", "Category"], phone: ["ফোন", "Phone"],
    variants: ["ধরন (ভ্যারিয়েন্ট)", "Variants"], barcodes: ["বারকোড", "Barcodes"], priceLines: ["দাম", "Prices"], version: ["সংস্করণ", "Version"],
    dimension: ["পরিমাপের ধরন", "Measure"], decimals: ["দশমিক ঘর", "Decimals"], active: ["সক্রিয়", "Active"], conversions: ["রূপান্তর", "Conversions"],
    from: ["থেকে", "From"], to: ["পর্যন্ত", "To"], factor: ["গুণক (১ 'থেকে' = ? 'পর্যন্ত')", "Factor (1 'from' = ? 'to')"],
    listKind: ["তালিকার ধরন", "List type"], currency: ["মুদ্রা", "Currency"], effFrom: ["কার্যকর শুরু", "Effective from"], effTo: ["কার্যকর শেষ (ঐচ্ছিক)", "Effective to (optional)"],
    item: ["পণ্য", "Item"], variant: ["ধরন", "Variant"], unit: ["একক", "Unit"], minQty: ["ন্যূনতম পরিমাণ", "Minimum quantity"], unitPrice: ["একক মূল্য", "Unit price"],
    barcode: ["বারকোড", "Barcode"], anyVariant: ["সব ধরন", "Any variant"], noneOpt: ["—", "—"],
    readOnly: ["শুধু দেখা যাবে", "View only"], pick: ["বাম দিক থেকে একটি নির্বাচন করুন", "Select an entry on the left"],
    stockNote: ["স্টক পরিমাণ এখানে এখনো দেখানো হয় না।", "Stock on hand is not shown here yet."],
    dimFixed: ["তৈরির পর পরিমাপের ধরন বদলানো যায় না।", "The measure cannot change after creation."],
    listFixed: ["তৈরির পর তালিকার ধরন ও মুদ্রা বদলানো যায় না।", "List type and currency cannot change after creation."],
    required: ["এই ঘরটি পূরণ করুন", "Please fill in this field"],
    err: {
      MASTER_SCOPE: ["এই ব্যবসা দেখার অনুমতি নেই", "You cannot see this business"], MASTER_AUTH_DENIED: ["পরিবর্তনের অনুমতি নেই", "You may not change this"],
      MASTER_STALE_OR_MISSING: ["অন্য কেউ আগে বদলেছে — আবার খুলুন", "Someone changed it first — reopen and retry"],
      MASTER_DUPLICATE: ["এটি আগেই আছে (কোড/SKU/বারকোড)", "This already exists (code/SKU/barcode)"], MASTER_INVALID_VALUE: ["কোনো মান সঠিক নয়", "A value is not valid"],
      MASTER_UOM_DIMENSION_MISMATCH: ["দুটি একক একই পরিমাপের হতে হবে", "Both units must be the same measure"],
      INVALID_FACTOR: ["গুণক শূন্যের বেশি সংখ্যা হতে হবে", "Factor must be a number above zero"], INVALID_AMOUNT: ["সঠিক সংখ্যা দিন", "Enter a valid number"],
      INVALID_DATE: ["সঠিক তারিখ দিন", "Enter a valid date"], INVALID_DECIMALS: ["দশমিক ০–৬", "Decimals 0–6"],
      CONTROL_DISABLED: ["মালিক এই ফিচার বন্ধ রেখেছেন", "The owner has switched this feature off"], SESSION_CHANGED: ["সাইন-ইন বদলেছে — পাতা আবার খুলুন", "Sign-in changed — reload"],
      SIGNED_SESSION_REQUIRED: ["সাইন-ইন প্রয়োজন", "Sign-in required"], other: ["অনুরোধ সম্পন্ন হয়নি", "Request failed"]
    }
  };
  const KINDS = ["stock", "service", "raw_material", "finished_good", "packaging"], PARTY_KINDS = ["customer", "supplier", "both"];
  const DIMS = ["count", "mass", "volume", "length", "area", "time"];
  const reqKey = (p) => p + "_" + Date.now().toString(36) + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

  function mount(rootEl, opts) {
    const api = opts.api, doc = rootEl.ownerDocument;
    const st = { lang: opts.lang === "en" ? "en" : "bn", ctx: null, business: null, tab: "items", search: "", rows: [], next: null,
      selected: null, detail: null, uoms: null, cats: [], form: null };
    const L = () => (st.lang === "en" ? 1 : 0);
    const t = (k) => (T[k] || [k, k])[L()];
    const el = (tag, cls, txt) => { const e = doc.createElement(tag); if (cls) e.className = cls; if (txt !== undefined && txt !== null) e.textContent = String(txt); return e; };
    const status = el("p", "occ-status"); status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    const say = (m, kind) => { status.textContent = m || ""; if (kind) status.dataset.kind = kind; else delete status.dataset.kind; };
    const errText = (e) => { const c = e && e.code; const k = T.err[c] ? c : (String(c || "").startsWith("CONTROL_DISABLED") ? "CONTROL_DISABLED" : "other");
      return T.err[k][L()] + (c ? " (" + c + ")" : ""); };
    async function guard(fn) { try { return await fn(); } catch (e) { say(errText(e), "error"); return null; } }
    const canManage = () => !!(st.business && st.business.can_manage);
    const name = (r) => (st.lang === "bn" && r.name_bn) ? r.name_bn : (r.name_en || r.name_bn || r.code || r.sku || "");
    const uomRows = () => (st.uoms && st.uoms.uoms) || [];
    const uomCode = (id) => { const u = uomRows().find((x) => x.id === id); return u ? u.code : (id == null ? "—" : String(id)); };

    async function loadList(append) {
      if (!st.business) return;
      const b = st.business.id, after = append ? st.next : null; let res = null;
      if (st.tab === "items") res = await guard(() => api.items(b, { search: st.search, after }));
      else if (st.tab === "parties") res = await guard(() => api.parties(b, { search: st.search, after }));
      else if (st.tab === "prices") { const l = await guard(() => api.priceLists(b)); res = l ? { rows: l, next_after_id: null } : null; }
      else { st.uoms = await guard(() => api.uoms(b)); res = st.uoms ? { rows: st.uoms.uoms, next_after_id: null } : null; }
      if (!res) return;
      st.rows = append ? st.rows.concat(res.rows) : res.rows; st.next = res.next_after_id || null;
    }
    function focusDetail() {
      const view = doc.defaultView, det = rootEl.querySelector(".occ-detail");
      if (!det) return;
      if (view && view.innerWidth < 760 && typeof det.scrollIntoView === "function") det.scrollIntoView({ block: "start" });
      const first = det.querySelector("input:not([disabled]),select:not([disabled]),h2"); if (first) { if (first.tagName === "H2") first.tabIndex = -1; first.focus({ preventScroll: true }); }
    }
    async function open(row) {
      st.selected = row; st.form = null; st.detail = null;
      if (st.tab === "items") st.detail = await guard(() => api.item(st.business.id, row.id));
      else if (st.tab === "prices") st.detail = await guard(() => api.priceList(st.business.id, row.id));
      else if (st.tab === "units") st.detail = uomRows().find((u) => u.id === row.id) || row;
      else st.detail = row;
      render(); focusDetail();
    }
    async function refresh(reopenId) {
      if (st.tab !== "units") st.uoms = await guard(() => api.uoms(st.business.id));
      await loadList(false);
      const row = st.rows.find((r) => r.id === reopenId) || (st.selected && st.rows.find((r) => r.id === st.selected.id));
      if (row) await open(row); else render();
    }
    async function selectBusiness(id) {
      st.business = (st.ctx.businesses || []).find((x) => x.id === id) || null; st.selected = null; st.detail = null; st.form = null;
      say(t("loading"));
      if (st.business) { st.cats = (await guard(() => api.categories(st.business.id))) || []; st.uoms = await guard(() => api.uoms(st.business.id)); }
      await loadList(false); if (status.dataset.kind !== "error") say(""); render();
    }

    // ---- one accessible form builder for every master form ----
    // spec: { title, fields:[{k,label,type:text|select|date|number|check,value,options:[[v,label]],disabled,required,max,note}], submit(values,key) -> Promise<id>, after(id) }
    function openForm(spec) {
      const f = el("form", "occ-panel"); f.noValidate = true; f.setAttribute("aria-label", spec.title);
      const key = reqKey(spec.keyPrefix || "md"), inputs = {};
      spec.fields.forEach((d) => {
        const id = "md-" + d.k + "-" + Math.random().toString(36).slice(2, 7), w = el("div", "occ-field");
        let i;
        if (d.type === "select") { i = el("select"); d.options.forEach(([v, lbl]) => { const o = el("option", null, lbl); o.value = v == null ? "" : String(v); i.append(o); });
          i.value = d.value == null ? "" : String(d.value); }
        else if (d.type === "check") { i = el("input"); i.type = "checkbox"; i.checked = d.value !== false; }
        else { i = el("input"); i.type = d.type === "date" ? "date" : "text"; if (d.type === "number") i.inputMode = "decimal"; i.maxLength = d.max || 160; i.value = d.value == null ? "" : String(d.value); }
        i.id = id; if (d.disabled) i.disabled = true; if (d.required) i.required = true;
        const l = el("label", null, d.label + (d.required ? " *" : "")); l.htmlFor = id;
        if (d.type === "check") { w.className = "occ-switch"; w.append(i, l); } else w.append(l, i);
        if (d.note) { const n = el("p", "occ-meta", d.note); n.id = id + "-n"; i.setAttribute("aria-describedby", n.id); w.append(n); }
        inputs[d.k] = i; f.append(w);
      });
      const err = el("p", "occ-field-error"); err.setAttribute("role", "alert");
      const actions = el("div", "occ-actions"), cancel = el("button", "occ-secondary", t("cancel")), ok = el("button", "occ-primary", t("save"));
      cancel.type = "button"; ok.type = "submit"; actions.append(cancel, ok); f.append(err, actions);
      cancel.addEventListener("click", () => { st.form = null; render(); focusDetail(); });
      f.addEventListener("submit", async (ev) => {
        ev.preventDefault(); err.textContent = "";
        const missing = spec.fields.find((d) => d.required && !d.disabled && d.type !== "check" && !String(inputs[d.k].value).trim());
        if (missing) { err.textContent = t("required") + ": " + missing.label; inputs[missing.k].setAttribute("aria-invalid", "true"); inputs[missing.k].focus(); return; }
        const v = {}; Object.keys(inputs).forEach((k) => { v[k] = inputs[k].type === "checkbox" ? inputs[k].checked : inputs[k].value; });
        ok.disabled = true;
        try { const id = await spec.submit(v, key); say(t("saved")); st.form = null; await spec.after(id); }
        catch (e) { err.textContent = errText(e); ok.disabled = false; }
      });
      st.form = { title: spec.title, node: f }; render(); focusDetail();
    }
    const opt = (arr) => arr.map((x) => [x, x]);
    const uomOpts = (dim, withNone) => (withNone ? [[null, t("noneOpt")]] : []).concat(uomRows().filter((u) => !dim || u.dimension === dim).map((u) => [u.id, u.code + " · " + name(u)]));
    const B = () => st.business.id;

    function itemForm(base) {
      openForm({ title: base ? t("edit") : t("newItem"), keyPrefix: "item", fields: [
        { k: "sku", label: t("sku"), value: base && base.sku, disabled: !!base, required: true, max: 64 },
        { k: "nameEn", label: t("nameEn"), value: base && base.name_en, required: true }, { k: "nameBn", label: t("nameBn"), value: base && base.name_bn },
        { k: "kind", label: t("kind"), type: "select", options: opt(KINDS), value: base ? base.item_kind : "stock" },
        { k: "baseUom", label: t("baseUom"), type: "select", options: uomOpts(null, true), value: base && base.base_uom_id },
        { k: "category", label: t("category"), type: "select", options: [[null, t("noneOpt")]].concat(st.cats.map((c) => [c.id, name(c)])), value: base && base.category_id },
        { k: "status", label: t("status"), type: "select", options: opt(["active", "inactive", "draft"]), value: base ? base.status : "active" }],
        submit: (v, key) => api.saveItem(B(), { sku: v.sku, nameEn: v.nameEn, nameBn: v.nameBn, kind: v.kind, baseUom: v.baseUom || null, category: v.category || null,
          status: v.status, expectedVersion: base ? base.version : 0, requestKey: key }),
        after: (id) => refresh(id) });
    }
    function partyForm(base) {
      openForm({ title: base ? t("edit") : t("newParty"), keyPrefix: "party", fields: [
        { k: "code", label: t("code"), value: base && base.code, disabled: !!base, required: true, max: 32 },
        { k: "kind", label: t("kind"), type: "select", options: opt(PARTY_KINDS), value: base ? base.party_kind : "customer" },
        { k: "nameEn", label: t("nameEn"), value: base && base.name_en, required: true }, { k: "nameBn", label: t("nameBn"), value: base && base.name_bn },
        { k: "phone", label: t("phone"), value: base && base.phone, max: 24 },
        { k: "status", label: t("status"), type: "select", options: opt(["active", "inactive", "blocked"]), value: base ? base.status : "active" }],
        submit: (v, key) => api.saveParty(B(), { code: v.code, kind: v.kind, nameEn: v.nameEn, nameBn: v.nameBn, phone: v.phone, status: v.status,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: (id) => refresh(id) });
    }
    function unitForm(base) {
      openForm({ title: base ? t("edit") : t("newUnit"), keyPrefix: "uom", fields: [
        { k: "code", label: t("code"), value: base && base.code, disabled: !!base, required: true, max: 16, note: base ? null : "A–Z, 0–9, _" },
        { k: "nameEn", label: t("nameEn"), value: base && base.name_en, required: true, max: 80 }, { k: "nameBn", label: t("nameBn"), value: base && base.name_bn, max: 80 },
        { k: "dimension", label: t("dimension"), type: "select", options: opt(DIMS), value: base ? base.dimension : "count", disabled: !!base, note: base ? t("dimFixed") : null },
        { k: "decimals", label: t("decimals"), type: "number", value: base ? base.decimals : 0, required: true, max: 1 },
        { k: "active", label: t("active"), type: "check", value: base ? base.active : true }],
        submit: (v, key) => api.saveUom(B(), { code: base ? base.code : String(v.code).toUpperCase(), nameEn: v.nameEn, nameBn: v.nameBn, dimension: base ? base.dimension : v.dimension,
          decimals: v.decimals, active: v.active, expectedVersion: base ? base.version : 0, requestKey: key }),
        after: (id) => refresh(id) });
    }
    function convForm(unit, base) {
      openForm({ title: t("addConv"), keyPrefix: "conv", fields: [
        { k: "from", label: t("from"), type: "select", options: uomOpts(unit.dimension), value: base ? base.from_uom_id : unit.id, disabled: !!base },
        { k: "to", label: t("to"), type: "select", options: uomOpts(unit.dimension).filter(([id]) => base || id !== unit.id), value: base ? base.to_uom_id : null, disabled: !!base },
        { k: "factor", label: t("factor"), type: "number", value: base && base.factor, required: true, max: 30 },
        { k: "active", label: t("active"), type: "check", value: base ? base.active : true }],
        submit: (v, key) => api.saveConversion(B(), { from: base ? base.from_uom_id : v.from, to: base ? base.to_uom_id : v.to, factor: v.factor, active: v.active,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: () => refresh(unit.id) });
    }
    function variantForm(item, base) {
      openForm({ title: base ? t("edit") : t("addVariant"), keyPrefix: "var", fields: [
        { k: "code", label: t("code"), value: base && base.code, disabled: !!base, required: true, max: 64 },
        { k: "nameEn", label: t("nameEn"), value: base && base.name_en, required: true }, { k: "nameBn", label: t("nameBn"), value: base && base.name_bn },
        { k: "status", label: t("status"), type: "select", options: opt(["active", "inactive", "draft"]), value: base ? base.status : "active" }],
        submit: (v, key) => api.saveVariant(B(), { item: item.id, code: v.code, nameEn: v.nameEn, nameBn: v.nameBn, status: v.status,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: () => refresh(item.id) });
    }
    function barcodeForm(item, base) {
      openForm({ title: base ? t("edit") : t("addBarcode"), keyPrefix: "bc", fields: [
        { k: "barcode", label: t("barcode"), value: base && base.barcode, disabled: !!base, required: true, max: 64 },
        { k: "variant", label: t("variant"), type: "select", options: [[null, t("anyVariant")]].concat(item.variants.map((x) => [x.id, x.code + " · " + name(x)])), value: base && base.variant_id },
        { k: "uom", label: t("unit"), type: "select", options: uomOpts(null, true), value: base ? base.uom_id : item.base_uom_id },
        { k: "active", label: t("active"), type: "check", value: base ? base.active : true }],
        submit: (v, key) => api.saveBarcode(B(), { barcode: base ? base.barcode : v.barcode, item: item.id, variant: v.variant || null, uom: v.uom || null, active: v.active,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: () => refresh(item.id) });
    }
    function listForm(base) {
      openForm({ title: base ? t("edit") : t("newList"), keyPrefix: "pl", fields: [
        { k: "code", label: t("code"), value: base && base.code, disabled: !!base, required: true, max: 32 },
        { k: "nameEn", label: t("nameEn"), value: base && base.name_en, required: true, max: 120 }, { k: "nameBn", label: t("nameBn"), value: base && base.name_bn, max: 120 },
        { k: "kind", label: t("listKind"), type: "select", options: opt(["sales", "purchase"]), value: base ? base.list_kind : "sales", disabled: !!base, note: base ? t("listFixed") : null },
        { k: "currency", label: t("currency"), value: base ? base.currency : "BDT", disabled: !!base, required: true, max: 3 },
        { k: "from", label: t("effFrom"), type: "date", value: base ? base.effective_from : new Date().toISOString().slice(0, 10), required: true },
        { k: "to", label: t("effTo"), type: "date", value: base && base.effective_to },
        { k: "status", label: t("status"), type: "select", options: opt(["active", "inactive", "draft"]), value: base ? base.status : "active" }],
        submit: (v, key) => api.savePriceList(B(), { code: v.code || (base && base.code), nameEn: v.nameEn, nameBn: v.nameBn, kind: base ? base.list_kind : v.kind,
          currency: base ? base.currency : String(v.currency).toUpperCase(), site: base ? base.site_id : null, from: v.from, to: v.to, status: v.status,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: (id) => refresh(id) });
    }
    async function priceForm(list, base) {
      const items = (await guard(() => api.items(B(), { limit: 200 }))) || { rows: [] };
      const firstItem = base ? base.item_id : (items.rows[0] && items.rows[0].id);
      const detail = firstItem ? await guard(() => api.item(B(), firstItem)) : null;
      openForm({ title: base ? t("edit") : t("addPrice"), keyPrefix: "price", fields: [
        { k: "item", label: t("item"), type: "select", options: items.rows.map((i) => [i.id, i.sku + " · " + name(i)]), value: firstItem, disabled: !!base },
        { k: "variant", label: t("variant"), type: "select", options: [[null, t("anyVariant")]].concat(((detail && detail.variants) || []).map((x) => [x.id, x.code])), value: base && base.variant_id, disabled: !!base },
        { k: "uom", label: t("unit"), type: "select", options: uomOpts(null), value: base ? base.uom_id : detail && detail.base_uom_id, disabled: !!base },
        { k: "minQty", label: t("minQty"), type: "number", value: base ? base.min_quantity : "0", disabled: !!base, max: 24 },
        { k: "price", label: t("unitPrice") + " (" + list.currency + ")", type: "number", value: base && base.unit_price, required: true, max: 24 },
        { k: "active", label: t("active"), type: "check", value: base ? base.active : true }],
        submit: (v, key) => api.savePrice(B(), { priceList: list.id, item: base ? base.item_id : v.item, variant: base ? base.variant_id : (v.variant || null),
          uom: base ? base.uom_id : v.uom, minQuantity: base ? base.min_quantity : (v.minQty || "0"), unitPrice: v.price, active: v.active,
          expectedVersion: base ? base.version : 0, requestKey: key }),
        after: () => refresh(list.id) });
    }

    function table(head, rows, onEdit) {
      const w = el("div", "md-table"), tb = el("table"), tr = el("tr");
      head.concat(onEdit ? [""] : []).forEach((h) => tr.append(el("th", null, h)));
      const th = el("thead"); th.append(tr); const body = el("tbody");
      rows.forEach((r, i) => { const x = el("tr"); r.forEach((c) => x.append(el("td", null, c)));
        if (onEdit) { const td = el("td"), b = el("button", "occ-secondary md-mini", t("edit")); b.type = "button"; b.addEventListener("click", () => onEdit(i)); td.append(b); x.append(td); }
        body.append(x); });
      tb.append(th, body); w.append(tb); return w;
    }
    function addBtn(label, fn) { const b = el("button", "occ-secondary", label); b.type = "button"; b.addEventListener("click", fn); return b; }
    function detailPanel() {
      const d = el("section", "occ-detail"); d.setAttribute("aria-live", "polite");
      if (st.form) { d.append(el("h2", null, st.form.title), st.form.node); return d; }
      if (!st.detail) { d.append(el("p", "occ-empty", t("pick"))); return d; }
      const r = st.detail, m = canManage(); d.append(el("h2", null, name(r)));
      const sec = (title, node, btn) => { const h = el("div", "md-sec"); h.append(el("h3", null, title)); if (btn) h.append(btn); d.append(h, node); };
      if (st.tab === "items") {
        d.append(el("p", "occ-meta", "SKU " + r.sku + " · " + r.item_kind + " · " + r.status + " · " + t("version") + " " + r.version));
        if (m) d.append(addBtn(t("edit"), () => itemForm(r)));
        sec(t("variants"), r.variants.length ? table([t("code"), t("nameEn"), t("status")], r.variants.map((v) => [v.code, name(v), v.status]), m ? (i) => variantForm(r, r.variants[i]) : null)
          : el("p", "occ-empty", t("none")), m ? addBtn(t("addVariant"), () => variantForm(r, null)) : null);
        const vcode = (id) => { const v = r.variants.find((x) => x.id === id); return v ? v.code : t("anyVariant"); };
        sec(t("barcodes"), r.barcodes.length ? table([t("barcode"), t("variant"), t("unit"), t("active")], r.barcodes.map((b) => [b.barcode, vcode(b.variant_id), uomCode(b.uom_id), b.active ? "✓" : "✗"]),
          m ? (i) => barcodeForm(r, r.barcodes[i]) : null) : el("p", "occ-empty", t("none")), m ? addBtn(t("addBarcode"), () => barcodeForm(r, null)) : null);
        sec(t("priceLines"), r.prices.length ? table([t("prices"), t("variant"), t("unit"), "≥", t("unitPrice")],
          r.prices.map((p) => [p.price_list_code, vcode(p.variant_id), uomCode(p.uom_id), p.min_quantity, p.unit_price + " " + p.currency])) : el("p", "occ-empty", t("none")));
        d.append(el("p", "occ-meta md-note", t("stockNote")));
      } else if (st.tab === "parties") {
        d.append(el("p", "occ-meta", r.code + " · " + r.party_kind + " · " + r.status + (r.phone ? " · " + r.phone : "") + " · " + t("version") + " " + r.version));
        if (m) d.append(addBtn(t("edit"), () => partyForm(r)));
      } else if (st.tab === "prices") {
        d.append(el("p", "occ-meta", r.code + " · " + r.list_kind + " · " + r.currency + " · " + r.effective_from + (r.effective_to ? " → " + r.effective_to : "") + " · " + r.status + " · " + t("version") + " " + r.version));
        if (m) d.append(addBtn(t("edit"), () => listForm(r)));
        sec(t("priceLines"), r.rows.length ? table([t("sku"), t("item"), t("unit"), "≥", r.currency], r.rows.map((p) => [p.sku, name(p), p.uom_code, p.min_quantity, p.unit_price]),
          m ? (i) => priceForm(r, r.rows[i]) : null) : el("p", "occ-empty", t("none")), m ? addBtn(t("addPrice"), () => priceForm(r, null)) : null);
      } else {
        d.append(el("p", "occ-meta", r.code + " · " + r.dimension + " · " + t("decimals") + " " + r.decimals + " · " + (r.active ? t("active") : "✗") + " · " + t("version") + " " + r.version));
        if (m) d.append(addBtn(t("edit"), () => unitForm(r)));
        const conv = ((st.uoms && st.uoms.conversions) || []).filter((c) => c.from_uom_id === r.id || c.to_uom_id === r.id);
        sec(t("conversions"), conv.length ? table([t("from"), "×", t("to"), t("active")], conv.map((c) => ["1 " + uomCode(c.from_uom_id), c.factor, uomCode(c.to_uom_id), c.active ? "✓" : "✗"]),
          m ? (i) => convForm(r, conv[i]) : null) : el("p", "occ-empty", t("none")), m ? addBtn(t("addConv"), () => convForm(r, null)) : null);
      }
      return d;
    }
    function render() {
      const top = el("header", "occ-top"), brand = el("div", "occ-brand"); brand.append(el("h1", null, t("title")), el("p", null, t("sub")));
      const controls = el("div", "occ-controls");
      const bs = el("select"); (st.ctx && st.ctx.businesses || []).forEach((b) => { const o = el("option", null, b.label || b.slug || ("#" + b.id)); o.value = String(b.id); bs.append(o); });
      if (st.business) bs.value = String(st.business.id);
      bs.setAttribute("aria-label", t("business")); bs.addEventListener("change", () => selectBusiness(Number(bs.value)));
      const lb = el("button", "occ-secondary", t("lang")); lb.type = "button"; lb.setAttribute("aria-label", "Language / ভাষা");
      lb.addEventListener("click", () => { st.lang = st.lang === "en" ? "bn" : "en"; try { localStorage.setItem("core10.md.lang", st.lang); } catch (_) {} doc.documentElement.lang = st.lang; st.form = null; render(); });
      controls.append(bs, lb); top.append(brand, controls);
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
      }
      if (st.business && canManage()) {
        const map = { items: ["newItem", () => itemForm(null)], parties: ["newParty", () => partyForm(null)], prices: ["newList", () => listForm(null)], units: ["newUnit", () => unitForm(null)] }[st.tab];
        const nb = el("button", "occ-primary", t(map[0])); nb.type = "button"; nb.addEventListener("click", () => { st.detail = null; map[1](); }); list.append(nb);
      } else if (st.business) list.append(el("p", "occ-meta", t("readOnly")));
      const ul = el("ul", "occ-list-plain");
      st.rows.forEach((r) => { const li = el("li"), b = el("button", "occ-row" + (st.selected && st.selected.id === r.id ? " is-active" : "")); b.type = "button";
        b.append(el("span", "occ-row-title", name(r)), el("span", "occ-row-key", r.sku || r.code || ""));
        const chips = el("span", "occ-chips"); [r.status || (r.active === false ? "inactive" : r.active ? "active" : null), r.item_kind || r.party_kind || r.list_kind || r.dimension].filter(Boolean)
          .forEach((c) => chips.append(el("span", "occ-chip" + (c === "active" ? " occ-chip-on" : c === "inactive" || c === "blocked" ? " occ-chip-off" : ""), c)));
        b.append(chips); b.addEventListener("click", () => open(r)); li.append(b); ul.append(li); });
      if (!st.rows.length) ul.append(el("li", "occ-empty", t("none")));
      list.append(ul);
      if (st.next) { const mbtn = el("button", "occ-secondary", t("more")); mbtn.type = "button"; mbtn.addEventListener("click", async () => { await loadList(true); render(); }); list.append(mbtn); }
      main.append(list, detailPanel());
      const wrap = el("div", "occ"); wrap.append(top, status, tabs, main);
      rootEl.replaceChildren(wrap);
    }
    async function start() {
      say(t("loading")); rootEl.replaceChildren(status);
      st.ctx = await guard(() => api.context());
      if (!st.ctx) { render(); return; }
      // A preferred business (from the shell link) is honoured only if the signed CORE10 context returns it.
      const list = st.ctx.businesses || [], pick = list.find((b) => b.id === opts.preferBusiness) || list[0];
      if (pick) await selectBusiness(pick.id); else render();
    }
    return { start, state: () => st };
  }
  return { mount, T };
});
