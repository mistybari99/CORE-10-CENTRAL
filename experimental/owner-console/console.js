/* CORE 10 Owner Command Center — standalone synthetic preview (no build step, no network, no secrets).
 * Data comes ONLY from a provider (fixture by default). The UI never decides authorization; the fixture provider
 * imitates scoped server views. All text is inserted with textContent (no HTML injection from data). */
(function () {
  "use strict";
  var C = window.C10CONSOLE, P = C.providers, I = C.i18n;
  var NAV = [["overview", "◎"], ["businesses", "▣"], ["hierarchy", "⌂"], ["modules", "▦"], ["stock", "▤"], ["trade", "⇄"], ["reports", "◈"], ["approvals", "✓"], ["setup", "⚙"], ["connections", "⇋"]];
  var NEEDS_BUSINESS = { hierarchy: 1, modules: 1, stock: 1, trade: 1, reports: 1, setup: 1, connections: 1 };
  var ROLES = {
    master_owner: { role: "master_owner", tenantId: 1, businessIds: [101, 102] },
    business_owner_101: { role: "business_owner", tenantId: 1, businessIds: [101] },
    business_owner_102: { role: "business_owner", tenantId: 1, businessIds: [102] },
    staff_101: { role: "staff", tenantId: 1, businessIds: [101] }   // NOT an owner: Connections must deny
  };
  var q = new URLSearchParams(location.search);
  // Connections is Bangla-first: opening it by deep link (?view=connections) defaults to Bangla unless ?lang=en is given.
  var deepView = q.get("view") === "connections" ? "connections" : "overview";
  var state = { locale: (q.get("lang") || (deepView === "connections" ? "bn" : "en")) === "bn" ? "bn" : "en", roleKey: "master_owner", businessId: null, view: deepView,
    stockFilter: "all", approvalFilter: "all", sim: q.get("state") || "", token: 0 };
  var $ = function (id) { return document.getElementById(id); };
  function t(k) { return I.t(state.locale, k); }
  function el(tag, attrs, kids) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") n.textContent = attrs[k]; else if (k === "class") n.className = attrs[k];
      else if (k.slice(0, 2) === "on") n.addEventListener(k.slice(2), attrs[k]); else n.setAttribute(k, attrs[k]);
    });
    (kids || []).forEach(function (c) { if (c) n.appendChild(typeof c === "string" ? document.createTextNode(c) : c); });
    return n;
  }
  function num(v, frac) { return new Intl.NumberFormat(state.locale === "bn" ? "bn-BD" : "en-BD", { maximumFractionDigits: frac == null ? 2 : frac }).format(Number(v || 0)); }
  function money(v) { return num(v, 0) + " " + t("unit.bdt"); }
  function chip(kind, label) { return el("span", { class: "chip " + kind, text: label }); }
  function provider() { return P.createFixtureProvider({ session: ROLES[state.roleKey] }); }
  function card(title, value) { return el("div", { class: "card" }, [el("h3", { text: title }), el("div", { class: "num", text: value })]); }
  function table(heads, rows) {
    var thead = el("thead", {}, [el("tr", {}, heads.map(function (h) { return el("th", { scope: "col", text: h }); }))]);
    var tbody = el("tbody", {}, rows.map(function (r) { return el("tr", {}, r.map(function (c) { return el("td", {}, [c]); })); }));
    return el("div", { class: "tablewrap" }, [el("table", {}, [thead, tbody])]);
  }
  function announce(msg) { $("live").textContent = msg; }
  function stateBox(kind, onRetry) {
    var box = el("div", { class: "state " + kind, role: kind === "error" ? "alert" : "status" }, [el("p", { text: t("state." + kind) })]);
    if (kind === "error") box.appendChild(el("button", { type: "button", id: "retryBtn", class: "primary", onclick: onRetry, text: t("ctl.retry") }));
    return box;
  }

  /* ----- chrome ----- */
  function paintChrome() {
    document.documentElement.lang = state.locale;
    $("skip").textContent = t("skip"); $("appTitle").textContent = t("app"); document.title = t("app");
    $("lblViewAs").textContent = t("ctl.viewas"); $("lblBiz").textContent = t("ctl.business"); $("refreshBtn").textContent = t("ctl.refresh");
    $("langGroup").setAttribute("aria-label", t("ctl.language"));
    ["bn", "en"].forEach(function (l) { var b = $("lang" + (l === "bn" ? "Bn" : "En")); b.setAttribute("aria-pressed", String(state.locale === l)); b.textContent = t("lang." + l); });
    $("badge").textContent = t("badge_fixture");
    var role = $("roleSel"); role.innerHTML = "";
    Object.keys(ROLES).forEach(function (k) { var o = el("option", { value: k, text: t("role." + k) }); if (k === state.roleKey) o.selected = true; role.appendChild(o); });
    var biz = $("bizSel"); biz.innerHTML = "";
    var allowed = ROLES[state.roleKey].businessIds;
    if (ROLES[state.roleKey].role === "master_owner") biz.appendChild(el("option", { value: "", text: t("ctl.all") }));
    C.fixtures.businesses.filter(function (b) { return b.tenant_id === 1 && allowed.indexOf(b.id) !== -1; })
      .forEach(function (b) { var o = el("option", { value: String(b.id), text: b.name }); if (state.businessId === b.id) o.selected = true; biz.appendChild(o); });
    var nav = $("nav"); nav.setAttribute("aria-label", t("nav")); nav.innerHTML = "";
    NAV.forEach(function (n) {
      var b = el("button", { type: "button", "data-view": n[0], tabindex: n[0] === state.view ? "0" : "-1" }, [el("span", { class: "ico", "aria-hidden": "true", text: n[1] }), el("span", { text: t("nav." + n[0]) })]);
      if (n[0] === state.view) b.setAttribute("aria-current", "page");
      b.addEventListener("click", function () { go(n[0]); });
      nav.appendChild(b);
    });
  }
  function normalizeContext() {
    var allowed = ROLES[state.roleKey].businessIds;
    if (ROLES[state.roleKey].role !== "master_owner" && (state.businessId == null || allowed.indexOf(state.businessId) === -1)) state.businessId = allowed[0];
    if (state.businessId != null && allowed.indexOf(state.businessId) === -1) state.businessId = null;
  }
  function go(view) { state.view = view; render(true); }

  /* ----- views ----- */
  async function viewOverview(p, root) {
    var k = await p.getKpis(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("ov.title") }));
    var g = el("div", { class: "grid" });
    if (state.businessId == null) g.appendChild(card(t("ov.visible"), num(k.visible_businesses, 0)));
    g.appendChild(card(t("ov.revenue"), money(k.recorded_revenue))); g.appendChild(card(t("ov.costs"), money(k.recorded_costs)));
    g.appendChild(card(t("ov.profit"), money(k.net_manual_profit))); g.appendChild(card(t("ov.investor"), money(k.unpaid_investor_balance)));
    g.appendChild(card(t("ov.integrity"), num(k.stock_integrity_failures != null ? k.stock_integrity_failures : k.unreconciled_location_items, 0)));
    g.appendChild(card(t("ov.pending"), num(k.pending_owner_decisions, 0)));
    root.appendChild(g); root.appendChild(el("p", { class: "note", text: t("ov.note") }));
  }
  async function viewBusinesses(p, root) {
    var list = await p.listBusinesses();
    root.appendChild(el("h2", { id: "viewTitle", text: t("biz.title") }));
    if (state.businessId != null) {
      var b = list.filter(function (x) { return x.id === state.businessId; })[0];
      var k = await p.getKpis(state.businessId);
      var crumb = el("div", { class: "crumb" }, [el("strong", { text: t("biz.local") + " " + (b ? b.name : state.businessId) })]);
      if (ROLES[state.roleKey].role === "master_owner") crumb.appendChild(el("button", { type: "button", id: "backAll", onclick: function () { state.businessId = null; render(true); }, text: " ‹ " + t("biz.back") }));
      root.appendChild(crumb);
      var g = el("div", { class: "grid" }); g.appendChild(card(t("ov.revenue"), money(k.recorded_revenue))); g.appendChild(card(t("ov.profit"), money(k.net_manual_profit)));
      g.appendChild(card(t("ov.pending"), num(k.pending_owner_decisions, 0))); root.appendChild(g);
      return;
    }
    root.appendChild(table([t("biz.name"), t("biz.status"), t("biz.template"), t("biz.certified"), ""],
      list.map(function (b) { return [b.name, chip(b.status === "active" ? "show" : "hidden", b.status), b.template, t("biz.no"),
        el("button", { type: "button", "data-open": String(b.id), onclick: function () { state.businessId = b.id; render(true); }, text: t("biz.open") })]; })));
  }
  async function viewHierarchy(p, root) {
    var sites = await p.getHierarchy(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("hi.title") }));
    if (!sites.length) { root.appendChild(stateBox("empty")); return; }
    var ul = el("ul", { class: "tree" });
    sites.forEach(function (s) {
      var inner = el("ul", {}, s.locations.map(function (l) { return el("li", { text: l }); }));
      ul.appendChild(el("li", {}, [el("strong", { text: t("kind." + s.kind) + " — " + s.label }), el("div", { class: "note", text: t("hi.locations") }), inner]));
    });
    root.appendChild(ul);
  }
  async function viewModules(p, root) {
    var mods = await p.getModules(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("mod.title") }));
    root.appendChild(table([t("mod.module"), t("mod.state")], mods.map(function (m) { return [t("m." + m.module), chip(m.visibility, t("vis." + m.visibility))]; })));
    root.appendChild(el("p", { class: "note", text: t("mod.note") }));
  }
  async function viewStock(p, root) {
    var rows = await p.getStock(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("st.title") }));
    var bar = el("div", { class: "toolbar", role: "group", "aria-label": t("st.status") });
    ["all", "reconciled", "mismatch"].forEach(function (f) {
      bar.appendChild(el("button", { type: "button", "data-filter": f, "aria-pressed": String(state.stockFilter === f), onclick: function () { state.stockFilter = f; render(false); }, text: t("st." + f) }));
    });
    root.appendChild(bar);
    var shown = rows.filter(function (r) { return state.stockFilter === "all" || r.status === state.stockFilter; });
    if (!shown.length) { root.appendChild(stateBox("empty")); return; }
    root.appendChild(table([t("st.site"), t("st.item"), t("st.onhand"), t("st.ledger"), t("st.status")],
      shown.map(function (r) { return [r.site, r.item, num(r.on_hand, 3), num(r.ledger_units, 3), chip(r.status, t("st." + r.status))]; })));
  }
  async function viewTrade(p, root) {
    var o = await p.getOperations(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("tr.title") }));
    var g = el("div", { class: "grid" });
    g.appendChild(card(t("tr.purchases"), num(o.purchase_documents, 0))); g.appendChild(card(t("tr.purchase_net"), money(o.purchase_net)));
    g.appendChild(card(t("tr.sales"), num(o.sale_documents, 0))); g.appendChild(card(t("tr.sale_net"), money(o.sale_net))); g.appendChild(card(t("tr.returns"), num(o.returns, 0)));
    root.appendChild(g);
  }
  async function viewReports(p, root) {
    var o = await p.getOperations(state.businessId), k = await p.getKpis(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("rp.title") }));
    var g = el("div", { class: "grid" });
    g.appendChild(card(t("rp.batches"), num(o.production_batches, 0))); g.appendChild(card(t("rp.costed"), num(o.costed_batches, 0))); g.appendChild(card(t("rp.uncosted"), num(o.uncosted_batches, 0)));
    root.appendChild(g); root.appendChild(el("p", { class: "note", text: t("rp.cogs_note") }));
    root.appendChild(el("h3", { text: t("rp.finance") }));
    var f = el("div", { class: "grid" }); f.appendChild(card(t("ov.revenue"), money(k.recorded_revenue))); f.appendChild(card(t("ov.costs"), money(k.recorded_costs))); f.appendChild(card(t("ov.profit"), money(k.net_manual_profit)));
    root.appendChild(f);
  }
  async function viewApprovals(p, root) {
    var rows = await p.getApprovals(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("ap.title") }));
    var bar = el("div", { class: "toolbar", role: "group", "aria-label": t("ap.kind") });
    ["all", "module_request", "bom_approval", "return_approval"].forEach(function (f) {
      bar.appendChild(el("button", { type: "button", "data-filter": f, "aria-pressed": String(state.approvalFilter === f), onclick: function () { state.approvalFilter = f; render(false); }, text: t("ap." + f) }));
    });
    root.appendChild(bar);
    var shown = rows.filter(function (r) { return state.approvalFilter === "all" || r.kind === state.approvalFilter; });
    if (!shown.length) root.appendChild(stateBox("empty"));
    else root.appendChild(table([t("ap.kind"), t("ap.item")], shown.map(function (r) { return [t("ap." + r.kind), r.title]; })));
    root.appendChild(el("p", { class: "note", text: t("ap.readonly") }));
  }
  async function viewSetup(p, root) {
    var s = await p.getSetupSummary(state.businessId);
    root.appendChild(el("h2", { id: "viewTitle", text: t("su.title") }));
    root.appendChild(el("p", {}, [el("strong", { text: t("su.mode") + ": " }), chip("show", t("su." + s.mode))]));
    root.appendChild(table([t("su.title"), t("mod.state")], s.steps.map(function (st) { return [t("su." + st.key), chip(st.done ? "done" : "todo", st.done ? t("su.done") : t("su.todo"))]; })));
  }
  var portsStore = C.ports.createStore();   // in-memory synthetic store: lives only for this page load
  function viewConnections(p, root) {
    var pp = C.ports.createPortsProvider({ session: ROLES[state.roleKey], store: portsStore });
    return C.portsUI.view({ el: el, t: t, locale: state.locale, businessId: state.businessId, roleKey: state.roleKey, announce: announce,
      rerender: function () { return render(false); } }, pp, root);
  }
  var VIEWS = { overview: viewOverview, businesses: viewBusinesses, hierarchy: viewHierarchy, modules: viewModules, stock: viewStock, trade: viewTrade, reports: viewReports, approvals: viewApprovals, setup: viewSetup, connections: viewConnections };

  async function render(moveFocus) {
    var my = ++state.token;
    normalizeContext(); paintChrome();
    var root = $("view"); root.innerHTML = "";
    if (state.sim === "loading") { root.appendChild(stateBox("loading")); announce(t("state.loading")); return; }
    if (state.sim === "empty") { root.appendChild(el("h2", { id: "viewTitle", text: t("nav." + state.view) })); root.appendChild(stateBox("empty")); return; }
    var fragment = el("div", {});
    try {
      if (state.sim === "error") throw new Error("simulated");
      var p = provider();
      if (NEEDS_BUSINESS[state.view] && state.businessId == null) {
        // master owner without a chosen business: let the owner pick one (no dead end)
        var list = await p.listBusinesses();
        fragment.appendChild(el("h2", { id: "viewTitle", text: t("nav." + state.view) }));
        fragment.appendChild(table([t("biz.name"), ""], list.map(function (b) { return [b.name, el("button", { type: "button", "data-open": String(b.id), onclick: function () { state.businessId = b.id; render(true); }, text: t("biz.open") })]; })));
      } else await VIEWS[state.view](p, fragment);
    } catch (e) {
      if (my !== state.token) return;
      root.innerHTML = ""; root.appendChild(el("h2", { id: "viewTitle", text: t("nav." + state.view) }));
      root.appendChild(stateBox("error", function () { state.sim = ""; render(true); })); announce(t("state.error")); return;
    }
    if (my !== state.token) return;
    while (fragment.firstChild) root.appendChild(fragment.firstChild);
    announce($("viewTitle") ? $("viewTitle").textContent : "");
    if (moveFocus) root.focus();
  }

  /* ----- wiring ----- */
  $("langBn").addEventListener("click", function () { state.locale = "bn"; render(false); });
  $("langEn").addEventListener("click", function () { state.locale = "en"; render(false); });
  $("roleSel").addEventListener("change", function (e) { state.roleKey = e.target.value; state.businessId = null; render(true); });
  $("bizSel").addEventListener("change", function (e) { state.businessId = e.target.value ? Number(e.target.value) : null; render(true); });
  $("refreshBtn").addEventListener("click", function () { state.sim = ""; render(false); });
  $("skip").addEventListener("click", function (e) { e.preventDefault(); $("view").focus(); });
  $("nav").addEventListener("keydown", function (e) {
    var keys = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 };
    var btns = Array.prototype.slice.call($("nav").querySelectorAll("button")), i = btns.indexOf(document.activeElement);
    if (i === -1) return;
    var next = e.key === "Home" ? 0 : e.key === "End" ? btns.length - 1 : keys[e.key] ? (i + keys[e.key] + btns.length) % btns.length : -1;
    if (next === -1) return;
    e.preventDefault(); btns.forEach(function (b, j) { b.setAttribute("tabindex", j === next ? "0" : "-1"); }); btns[next].focus();
  });
  render(false);
})();
