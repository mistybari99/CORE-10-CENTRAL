/* CORE 10 CENTRAL | B-012 Owner multi-business dashboard screen (NP03A). Bangla/English, 390-1440px, Control Centre styles.
 * All businesses -> one business's sites -> one site's stock, purchases and stock commands. Read-only; every figure comes
 * from a server read RPC and is rendered with textContent only. Parts not connected yet are named in one short line.
 */
(function (root, factory) {
  "use strict";
  const ui = factory();
  if (typeof module === "object" && module.exports) module.exports = ui;
  if (root) root.CORE10_OWNER_DASHBOARD_UI = ui;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const T = {
    title: ["মালিকের ড্যাশবোর্ড", "Owner dashboard"], sub: ["সব ব্যবসা, শাখা, কারখানা ও গুদাম এক জায়গায়", "All businesses, branches, factories and warehouses in one place"],
    lang: ["English", "বাংলা"], all: ["সব ব্যবসা", "All businesses"], businesses: ["ব্যবসা", "Businesses"], sites: ["শাখা/স্থান", "Sites"],
    items: ["পণ্য (স্টকে)", "Items in stock"], units: ["মোট পরিমাণ", "Total quantity"], openPos: ["খোলা ক্রয় আদেশ", "Open purchase orders"],
    openAmount: ["খোলা ক্রয়ের মূল্য", "Open purchase value"], qc: ["মান যাচাইয়ের অপেক্ষায়", "Awaiting quality check"],
    toPost: ["স্টকে তোলার অপেক্ষায়", "Awaiting stock posting"], commands: ["অসম্পূর্ণ স্টক কাজ", "Open stock tasks"],
    approvals: ["অনুমোদনের অপেক্ষায়", "Waiting for approval"], nc: ["বিক্রি ও নগদ: এখনো যুক্ত নয়", "Sales and cash: not connected yet"],
    allKinds: ["সব", "All"], more: ["আরও দেখুন", "Show more"], none: ["কিছু নেই", "Nothing here"], loading: ["লোড হচ্ছে…", "Loading…"],
    empty: ["আপনার দেখার মতো কোনো ব্যবসা নেই", "There is no business for you to oversee"],
    site: ["স্থান", "Site"], kind: ["ধরন", "Type"], locations: ["স্টক স্থান", "Stock locations"], waiting: ["অপেক্ষমাণ গ্রহণ", "Receipts waiting"],
    stock: ["স্টক", "Stock"], purchases: ["ক্রয় আদেশ", "Purchase orders"], tasks: ["স্টক কাজ", "Stock tasks"], item: ["পণ্য", "Item"],
    qty: ["পরিমাণ", "Quantity"], supplier: ["সরবরাহকারী", "Supplier"], status: ["অবস্থা", "Status"], amount: ["মূল্য", "Amount"],
    task: ["কাজ", "Task"], refresh: ["হালনাগাদ", "Refresh"],
    K: { showroom: ["শাখা", "Branch"], factory: ["কারখানা", "Factory"], godown: ["গুদাম", "Godown"], warehouse: ["ওয়্যারহাউস", "Warehouse"], project: ["প্রকল্প", "Project"] },
    S: { draft: ["খসড়া", "Draft"], confirmed: ["নিশ্চিত", "Confirmed"], posted: ["সম্পন্ন", "Posted"], cancelled: ["বাতিল", "Cancelled"],
      approved: ["অনুমোদিত", "Approved"], partially_received: ["আংশিক গৃহীত", "Partly received"], received: ["গৃহীত", "Received"], closed: ["বন্ধ", "Closed"] },
    C: { receive: ["গ্রহণ", "Receive"], issue: ["ইস্যু", "Issue"], transfer: ["স্থানান্তর", "Transfer"], adjust_in: ["সমন্বয় (+)", "Adjust (+)"], adjust_out: ["সমন্বয় (−)", "Adjust (−)"] },
    err: { DASH_SCOPE: ["এটি দেখার অনুমতি নেই", "You cannot see this"], INV_SCOPE: ["এটি দেখার অনুমতি নেই", "You cannot see this"],
      PROC_SCOPE: ["এটি দেখার অনুমতি নেই", "You cannot see this"], SESSION_CHANGED: ["সাইন-ইন বদলেছে — পাতা আবার খুলুন", "Sign-in changed — reload the page"],
      SIGNED_SESSION_REQUIRED: ["সাইন-ইন প্রয়োজন", "Sign-in required"], other: ["তথ্য আনা যায়নি", "Could not load the data"] }
  };
  const KINDS = ["showroom", "factory", "godown", "warehouse", "project"];

  function mount(rootEl, opts) {
    const api = opts.api, doc = rootEl.ownerDocument;
    const st = { lang: opts.lang === "en" ? "en" : "bn", view: "portfolio", pf: null, biz: null, kind: null, sites: [], nextSite: null,
      site: null, detail: null };
    const L = () => (st.lang === "en" ? 1 : 0);
    const t = (k) => (T[k] || [k, k])[L()];
    const tk = (grp, k) => ((T[grp] && T[grp][k]) || [k, k])[L()];
    const num = (n, frac) => new Intl.NumberFormat(st.lang === "en" ? "en-US" : "bn-BD", { maximumFractionDigits: frac == null ? 3 : frac }).format(Number(n || 0));
    const el = (tag, cls, txt) => { const e = doc.createElement(tag); if (cls) e.className = cls; if (txt !== undefined && txt !== null) e.textContent = String(txt); return e; };
    const status = el("p", "occ-status"); status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    const say = (m, kind) => { status.textContent = m || ""; if (kind) status.dataset.kind = kind; else delete status.dataset.kind; };
    const errText = (e) => { const c = e && e.code; return (T.err[c] || T.err.other)[L()] + (c ? " (" + c + ")" : ""); };
    async function guard(fn) { try { return await fn(); } catch (e) { say(errText(e), "error"); return null; } }
    const bizName = (b) => b.slug;
    function kpis(pairs) {
      const dl = el("dl", "od-kpis");
      pairs.forEach(([k, v]) => { if (v === null || v === undefined) return; dl.append(el("dt", null, t(k)), el("dd", null, v)); });
      return dl;
    }
    function table(head, rows) {
      const wrap = el("div", "md-table"), tb = el("table"), thead = el("thead"), tr = el("tr");
      head.forEach((h) => tr.append(el("th", null, h))); thead.append(tr); tb.append(thead);
      const body = el("tbody"); rows.forEach((r) => { const row = el("tr"); r.forEach((c) => { const td = el("td"); if (c instanceof Node) td.append(c); else td.textContent = c; row.append(td); }); body.append(row); });
      tb.append(body); wrap.append(tb); return wrap;
    }

    async function loadPortfolio() { const r = await guard(() => api.portfolio()); if (r) st.pf = r.businesses || []; }
    async function loadSites(append) {
      const r = await guard(() => api.sites(st.biz.business_id, { kind: st.kind, after: append ? st.nextSite : null, limit: 50 }));
      if (!r) return; st.sites = append ? st.sites.concat(r.items) : r.items; st.nextSite = r.next_after_site || null;
    }
    async function openBusiness(b) { st.biz = b; st.kind = null; st.view = "business"; say(t("loading")); await loadSites(false); if (status.dataset.kind !== "error") say(""); render(); }
    async function openSite(s) {
      st.site = s; st.view = "site"; say(t("loading"));
      const b = st.biz.business_id;
      const [bal, pos, cmd] = [await guard(() => api.balances(b, s.site_id)), await guard(() => api.purchases(b, s.site_id)), await guard(() => api.commands(b, s.site_id))];
      st.detail = { bal: bal ? bal.items : [], pos: pos ? pos.items : [], cmd: cmd ? cmd.items : [] };
      if (status.dataset.kind !== "error") say(""); render();
    }
    const crumb = (label, fn) => { const b = el("button", "occ-secondary md-mini", label); b.type = "button"; b.addEventListener("click", fn); return b; };

    function renderPortfolio(main) {
      const list = st.pf || [];
      if (!list.length) { main.append(el("p", "occ-note", t("empty"))); return; }
      const tot = list.reduce((a, b) => ({ sites: a.sites + b.sites, units: a.units + Number(b.stock.units), pos: a.pos + b.purchase.open_pos,
        appr: a.appr + (b.approvals_pending || 0) }), { sites: 0, units: 0, pos: 0, appr: 0 });
      const totals = el("div", "od-totals");
      [["businesses", num(list.length)], ["sites", num(tot.sites)], ["units", num(tot.units)], ["openPos", num(tot.pos)], ["approvals", num(tot.appr)]]
        .forEach(([k, v]) => totals.append(el("span", "occ-chip", t(k) + ": " + v)));
      main.append(totals);
      const grid = el("div", "od-grid");
      list.forEach((b) => {
        const card = el("button", "od-card"); card.type = "button"; card.dataset.business = b.business_id;
        card.append(el("h2", null, bizName(b)), el("p", "occ-note", b.template_code));
        const kinds = Object.entries(b.sites_by_kind || {}).map(([k, n]) => tk("K", k) + " " + num(n)).join(" · ");
        card.append(el("p", null, t("sites") + ": " + num(b.sites) + (kinds ? " (" + kinds + ")" : "")));
        card.append(kpis([["items", num(b.stock.items)], ["units", num(b.stock.units)], ["openPos", num(b.purchase.open_pos)],
          ["openAmount", num(b.purchase.open_amount, 2)], ["qc", num(b.purchase.awaiting_qc)], ["toPost", num(b.purchase.awaiting_post)],
          ["commands", num(b.stock_commands.draft + b.stock_commands.confirmed)], ["approvals", b.approvals_pending == null ? null : num(b.approvals_pending)]]));
        card.addEventListener("click", () => openBusiness(b));
        grid.append(card);
      });
      main.append(grid, el("p", "od-nc", t("nc")));
    }
    function renderBusiness(main) {
      const b = st.biz;
      main.append(el("h2", null, bizName(b)));
      const f = el("div", "od-filter"); f.setAttribute("role", "group");
      [null].concat(KINDS).forEach((k) => {
        const btn = el("button", "occ-secondary md-mini" + (st.kind === k ? " is-active" : ""), k ? tk("K", k) : t("allKinds"));
        btn.type = "button"; btn.dataset.kind = k || "all"; btn.setAttribute("aria-pressed", String(st.kind === k));
        btn.addEventListener("click", async () => { st.kind = k; await loadSites(false); render(); }); f.append(btn);
      });
      main.append(f);
      if (!st.sites.length) { main.append(el("p", "occ-note", t("none"))); return; }
      main.append(table([t("site"), t("kind"), t("locations"), t("units"), t("openPos"), t("waiting"), t("commands")], st.sites.map((s) => {
        const a = el("button", "od-row-btn", s.label); a.type = "button"; a.dataset.site = s.site_id; a.addEventListener("click", () => openSite(s));
        return [a, tk("K", s.kind), num(s.locations), num(s.units), num(s.open_pos), num(s.receipts_waiting), num(s.commands_open)];
      })));
      if (st.nextSite) { const m = el("button", "occ-secondary", t("more")); m.type = "button"; m.addEventListener("click", async () => { await loadSites(true); render(); }); main.append(m); }
    }
    function renderSite(main) {
      const s = st.site, d = st.detail || { bal: [], pos: [], cmd: [] };
      main.append(el("h2", null, s.label + " · " + tk("K", s.kind)));
      const name = (r) => (st.lang === "bn" && r.name_bn) ? r.name_bn : (r.name_en || r.sku);
      main.append(el("h3", null, t("stock")));
      main.append(d.bal.length ? table([t("item"), "SKU", t("locations"), t("qty")], d.bal.map((r) => [name(r), r.sku, r.location_code, num(r.on_hand)])) : el("p", "occ-note", t("none")));
      main.append(el("h3", null, t("purchases")));
      main.append(d.pos.length ? table(["#", t("supplier"), t("status"), t("amount")], d.pos.map((p) => [String(p.po_id),
        (st.lang === "bn" && p.supplier_name_bn) ? p.supplier_name_bn : p.supplier_name_en, tk("S", p.status), num(p.total_amount, 2)])) : el("p", "occ-note", t("none")));
      main.append(el("h3", null, t("tasks")));
      main.append(d.cmd.length ? table(["#", t("task"), t("qty"), t("status")], d.cmd.map((c) => [String(c.command_id), tk("C", c.kind), num(c.quantity), tk("S", c.status)])) : el("p", "occ-note", t("none")));
    }
    function render() {
      const top = el("header", "occ-top"), brand = el("div", "occ-brand"); brand.append(el("h1", null, t("title")), el("p", null, t("sub")));
      const acts = el("div", "occ-actions");
      const rb = el("button", "occ-secondary", t("refresh")); rb.type = "button";
      rb.addEventListener("click", async () => { if (st.view === "portfolio") await loadPortfolio(); else if (st.view === "business") await loadSites(false); else await openSite(st.site); render(); });
      const lb = el("button", "occ-secondary", t("lang")); lb.type = "button"; lb.setAttribute("aria-label", "Language / ভাষা");
      lb.addEventListener("click", () => { st.lang = st.lang === "en" ? "bn" : "en"; try { localStorage.setItem("core10.od.lang", st.lang); } catch (_) {} doc.documentElement.lang = st.lang; render(); });
      acts.append(rb, lb); top.append(brand, acts);
      const main = el("section", "occ-panel od-main");
      if (st.view !== "portfolio") {
        const c = el("nav", "od-crumbs"); c.setAttribute("aria-label", "breadcrumb");
        c.append(crumb(t("all"), async () => { st.view = "portfolio"; st.biz = null; st.site = null; render(); }));
        if (st.view === "site") c.append(crumb(bizName(st.biz), () => { st.view = "business"; st.site = null; render(); }));
        main.append(c);
      }
      if (st.view === "portfolio") renderPortfolio(main); else if (st.view === "business") renderBusiness(main); else renderSite(main);
      const wrap = el("div", "occ"); wrap.append(top, status, main);
      rootEl.replaceChildren(wrap);
    }
    async function start() { doc.documentElement.lang = st.lang; say(t("loading")); render(); await loadPortfolio(); if (status.dataset.kind !== "error") say(""); render(); }
    return { start, state: () => st };
  }
  return { mount, T };
});
