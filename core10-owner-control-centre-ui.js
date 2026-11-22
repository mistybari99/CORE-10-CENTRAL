/* CORE 10 CENTRAL | B-021 Owner Control Centre UI (DEC-08).
 * Renders with createElement/textContent only. Every change goes through the canonical
 * core10.control_* RPCs; the server decides permission. View-only roles see disabled controls.
 */
(function (root, factory) {
  "use strict";
  const ui = factory();
  if (typeof module === "object" && module.exports) module.exports = ui;
  if (root) root.CORE10_OWNER_CONTROL_UI = ui;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const T = {
    bn: {
      title: "মালিক নিয়ন্ত্রণ কেন্দ্র", sub: "CORE 10 · প্রতিটি ফিচার আপনার হাতে", business: "ব্যবসা", site: "সাইট",
      allSites: "পুরো ব্যবসা (ডিফল্ট)", lang: "English", search: "ফিচার খুঁজুন", loading: "লোড হচ্ছে…",
      on: "চালু", off: "বন্ধ", stagesN: "অনুমোদন ধাপ: ", src_default: "ডিফল্ট", src_business: "ব্যবসা", src_site: "সাইট",
      scheduled: "নির্ধারিত পরিবর্তন", locked: "সুরক্ষিত", tabSettings: "সেটিংস", tabHistory: "ইতিহাস",
      tabExceptions: "ব্যতিক্রম", tabAudit: "অডিট", viewOnly: "শুধু দেখার অনুমতি: নিয়ন্ত্রণ বদলাতে পারেন শুধু মালিক বা ব্যবসার মালিক।",
      invariant: "এটি স্থায়ী সুরক্ষা। কখনো বন্ধ বা ব্যতিক্রম করা যায় না।", scope: "কোথায় প্রযোজ্য",
      scopeSite: "শুধু এই সাইটের জন্য আলাদা", scopeInherit: "ব্যবসার সেটিং মেনে চলুক", enabled: "ফিচার চালু",
      stages: "অনুমোদনের ধাপ (০ = সরাসরি)", params: "সীমা ও মান", when: "কবে থেকে", now: "এখনই",
      schedule: "নির্দিষ্ট সময় থেকে", reason: "কারণ (৫–৫০০ অক্ষর)", save: "সংরক্ষণ", cancel: "বাতিল", confirm: "নিশ্চিত করুন",
      confirmTitle: "পরিবর্তন নিশ্চিত করুন", saved: "সংরক্ষিত · সংস্করণ ", noHistory: "এখনো কোনো পরিবর্তন নেই",
      revert: "এই অবস্থায় ফেরান", revertTitle: "আগের সেটিংয়ে ফেরানো", reverted: "আগের অবস্থায় ফেরানো হয়েছে · সংস্করণ ",
      noExceptions: "কোনো ব্যতিক্রম নেই", grant: "একবারের ব্যতিক্রম দিন", hours: "মেয়াদ (ঘণ্টা, ১–১৬৮)",
      grantTitle: "একবারের ব্যতিক্রম", granted: "ব্যতিক্রম দেওয়া হয়েছে", revoke: "প্রত্যাহার",
      revokeTitle: "ব্যতিক্রম প্রত্যাহার", revoked: "ব্যতিক্রম প্রত্যাহার হয়েছে", st_open: "খোলা", st_consumed: "ব্যবহৃত",
      st_revoked: "প্রত্যাহৃত", st_expired: "মেয়াদোত্তীর্ণ", noAudit: "এই ফিচারের কোনো অডিট ঘটনা নেই",
      chainOk: "অডিট শৃঙ্খল অক্ষত", chainBad: "অডিট শৃঙ্খলে সমস্যা", chainNA: "শৃঙ্খল যাচাই এই ভূমিকায় নেই",
      noBusiness: "এই অ্যাকাউন্টে কোনো ব্যবসা নেই।", noFeatures: "কোনো ফিচার পাওয়া যায়নি", choose: "বাঁ দিক থেকে একটি ফিচার বেছে নিন",
      version: "সংস্করণ ", by: "করেছেন ", from: "কার্যকর ", needSchedule: "সময় দিন", wholeBiz: "পুরো ব্যবসা",
      bootstrapTitle: "নতুন ব্যবসা তৈরি", tenant: "টেন্যান্ট",
      bootstrapHelp: "এই টেন্যান্টে নতুন ব্যবসা ও সেটআপের পুনরায় অনুরোধ নিয়ন্ত্রণ করুন।",
      bootstrapOn: "নতুন ব্যবসা তৈরি চালু করুন", bootstrapOff: "নতুন ব্যবসা তৈরি বন্ধ করুন",
      scopeOf: "পরিধি", reloaded: "অন্য কেউ এটি বদলেছেন; সর্বশেষ অবস্থা আনা হয়েছে। আবার চেষ্টা করুন।"
    },
    en: {
      title: "Owner Control Centre", sub: "CORE 10 · every feature under your control", business: "Business", site: "Site",
      allSites: "Whole business (default)", lang: "বাংলা", search: "Search features", loading: "Loading…",
      on: "On", off: "Off", stagesN: "Approval stages: ", src_default: "Default", src_business: "Business", src_site: "Site",
      scheduled: "Scheduled change", locked: "Protected", tabSettings: "Settings", tabHistory: "History",
      tabExceptions: "Exceptions", tabAudit: "Audit", viewOnly: "View only: only the owner or a business owner can change controls.",
      invariant: "This is a permanent protection. It can never be switched off or excepted.", scope: "Applies to",
      scopeSite: "A separate setting for this site", scopeInherit: "Follow the business setting", enabled: "Feature on",
      stages: "Approval stages (0 = direct)", params: "Limits and values", when: "Effective from", now: "Now",
      schedule: "From a set time", reason: "Reason (5–500 characters)", save: "Save", cancel: "Cancel", confirm: "Confirm",
      confirmTitle: "Confirm the change", saved: "Saved · version ", noHistory: "No changes yet",
      revert: "Restore this", revertTitle: "Restore an earlier setting", reverted: "Restored · version ",
      noExceptions: "No exceptions", grant: "Grant a one-time exception", hours: "Valid for (hours, 1–168)",
      grantTitle: "One-time exception", granted: "Exception granted", revoke: "Revoke",
      revokeTitle: "Revoke the exception", revoked: "Exception revoked", st_open: "Open", st_consumed: "Used",
      st_revoked: "Revoked", st_expired: "Expired", noAudit: "No audit events for this feature",
      chainOk: "Audit chain intact", chainBad: "Audit chain problem", chainNA: "Chain check not available to this role",
      noBusiness: "No business is available to this account.", noFeatures: "No features found", choose: "Choose a feature from the list",
      version: "Version ", by: "by ", from: "effective ", needSchedule: "Enter a time", wholeBiz: "Whole business",
      bootstrapTitle: "Business creation", tenant: "Tenant",
      bootstrapHelp: "Control new business creation and setup retries for this tenant.",
      bootstrapOn: "Enable business creation", bootstrapOff: "Disable business creation",
      scopeOf: "Scope", reloaded: "Someone else changed this; the latest state is loaded. Try again."
    }
  };
  const ERR = {
    bn: { BOOTSTRAP_POLICY_DENIED: "এই টেন্যান্টের নীতি বদলানোর অনুমতি আপনার নেই।", CONTROL_SCOPE: "এই ব্যবসা আপনার অনুমতির বাইরে।", CONTROL_FORBIDDEN: "এটি বদলানোর অনুমতি আপনার নেই।",
      CONTROL_INVARIANT: "স্থায়ী সুরক্ষা বদলানো যায় না।", CONTROL_PARAM_RANGE: "মান সীমার বাইরে", CONTROL_PARAM_TYPE: "মানের ধরন ঠিক নয়",
      CONTROL_PARAM_ENUM: "তালিকার বাইরের মান", CONTROL_PARAM_UNKNOWN: "অচেনা মান", CONTROL_STAGES: "অনুমোদনের ধাপ অনুমোদিত সীমার বাইরে।",
      CONTROL_EFFECTIVE_PAST: "অতীতের তারিখ দেওয়া যায় না।", CONTROL_EFFECTIVE_FUTURE: "এক বছরের বেশি পরের তারিখ দেওয়া যায় না।",
      CONTROL_BAD_REASON: "কারণ ৫ থেকে ৫০০ অক্ষরের মধ্যে লিখুন।", CONTROL_BAD_HOURS: "মেয়াদ ১ থেকে ১৬৮ ঘণ্টা।",
      CONTROL_OVERRIDE_CLOSED: "ব্যতিক্রমটি আগেই বন্ধ হয়েছে।", CONTROL_REPLAY_CONFLICT: "একই অনুরোধ ভিন্ন তথ্যসহ এসেছে।",
      SIGNED_SESSION_REQUIRED: "সাইন-ইন প্রয়োজন।", SESSION_CHANGED: "সাইন-ইন বদলেছে; পাতাটি আবার খুলুন।",
      CONTROL_RPC_UNAVAILABLE: "সার্ভারে পৌঁছানো যায়নি।" },
    en: { BOOTSTRAP_POLICY_DENIED: "You do not have access to this tenant policy.", CONTROL_SCOPE: "This business is outside your access.", CONTROL_FORBIDDEN: "You are not allowed to change this.",
      CONTROL_INVARIANT: "A permanent protection cannot be changed.", CONTROL_PARAM_RANGE: "Value is out of range", CONTROL_PARAM_TYPE: "Wrong kind of value",
      CONTROL_PARAM_ENUM: "Value is not in the list", CONTROL_PARAM_UNKNOWN: "Unknown value", CONTROL_STAGES: "Approval stages are outside the allowed limit.",
      CONTROL_EFFECTIVE_PAST: "A past time cannot be used.", CONTROL_EFFECTIVE_FUTURE: "More than a year ahead is not allowed.",
      CONTROL_BAD_REASON: "Write a reason of 5 to 500 characters.", CONTROL_BAD_HOURS: "Validity is 1 to 168 hours.",
      CONTROL_OVERRIDE_CLOSED: "The exception is already closed.", CONTROL_REPLAY_CONFLICT: "The same request arrived with different data.",
      SIGNED_SESSION_REQUIRED: "Please sign in.", SESSION_CHANGED: "The sign-in changed; open the page again.",
      CONTROL_RPC_UNAVAILABLE: "The server could not be reached." }
  };

  function el(tag, attrs, children) {
    const n = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (v === undefined || v === null || v === false) continue;
      if (k === "text") n.textContent = String(v);
      else if (k === "class") n.className = v;
      else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
      else if (k === "checked" || k === "disabled" || k === "selected" || k === "hidden") n[k] = true;
      else n.setAttribute(k, v === true ? "" : String(v));
    }
    for (const c of [].concat(children || [])) if (c) n.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    return n;
  }

  function mount(rootEl, options) {
    const api = options.api;
    const st = { lang: options.lang === "en" ? "en" : "bn", ctx: null, business: null, site: null, features: [],
      tenant: null, bootstrap: null, selected: null, tab: "settings", history: [], overrides: [], audit: null, query: "", fieldErrors: {} };
    const t = (k) => T[st.lang][k] || k;
    const errText = (e) => {
      const code = (e && e.code) || "CONTROL_RPC_UNAVAILABLE";
      const base = ERR[st.lang][code] || code;
      return e && e.detail && /^CONTROL_PARAM_/.test(code) ? base + ": " + e.detail : base;
    };
    const fmt = (iso) => iso ? new Date(iso).toLocaleString(st.lang === "bn" ? "bn-BD" : "en-GB") : "";
    const canManage = () => !!(st.business && st.business.can_manage);
    const feat = () => st.features.find((f) => f.feature_key === st.selected) || null;
    const featTitle = (f) => st.lang === "bn" ? f.title_bn : f.title_en;

    const status = el("p", { class: "occ-status", role: "status", "aria-live": "polite" });
    const app = el("div", { class: "occ", lang: st.lang });
    rootEl.replaceChildren(app);

    function say(text, isError) { status.textContent = text || ""; status.dataset.kind = isError ? "error" : "ok"; }

    function scopeMax(siteId) {
      let m = 0;
      for (const h of st.history) if ((h.site_id || null) === (siteId || null) && h.feature_key === st.selected) m = Math.max(m, h.version);
      return m;
    }

    async function guard(fn) {
      app.setAttribute("aria-busy", "true");
      try { return await fn(); }
      catch (e) { say(errText(e) + " (" + (e.code || "error") + ")", true); return undefined; }
      finally { app.removeAttribute("aria-busy"); }
    }

    // ---------------------------------------------------------------- dialog
    function dialog({ title, lines, needReason, extra }) {
      return new Promise((resolve) => {
        const prev = document.activeElement;
        const reasonBox = needReason ? el("textarea", { id: "occ-dialog-reason", rows: "3", maxlength: "500" }) : null;
        const err = el("p", { class: "occ-field-error", role: "alert" });
        const close = (val) => { back.remove(); if (prev && prev.focus) prev.focus(); resolve(val); };
        const ok = el("button", { class: "occ-primary", type: "button", text: t("confirm"), onclick: () => {
          if (reasonBox && reasonBox.value.trim().length < 5) { err.textContent = ERR[st.lang].CONTROL_BAD_REASON; reasonBox.focus(); return; }
          close({ ok: true, reason: reasonBox ? reasonBox.value.trim() : null });
        } });
        const box = el("div", { class: "occ-dialog", role: "dialog", "aria-modal": "true", "aria-labelledby": "occ-dialog-title" }, [
          el("h3", { id: "occ-dialog-title", text: title }),
          el("ul", { class: "occ-summary" }, (lines || []).map((l) => el("li", { text: l }))),
          extra || null,
          needReason ? el("label", { for: "occ-dialog-reason", text: t("reason") }) : null, reasonBox, err,
          el("div", { class: "occ-actions" }, [el("button", { type: "button", text: t("cancel"), onclick: () => close({ ok: false }) }), ok])
        ]);
        const back = el("div", { class: "occ-backdrop", onkeydown: (ev) => { if (ev.key === "Escape") close({ ok: false }); } }, [box]);
        document.body.appendChild(back);
        (reasonBox || ok).focus();
      });
    }

    // ---------------------------------------------------------------- loading
    async function loadFeatures() {
      const rows = await guard(() => api.read(st.business.id, st.site));
      if (!rows) return;
      st.features = rows;
      if (st.selected && !feat()) st.selected = null;
      if (st.selected && canManage()) await loadHistory();
    }
    async function loadHistory() {
      const rows = await guard(() => api.history(st.business.id, st.selected, 100));
      st.history = rows || [];
    }
    async function openTab(tab) {
      st.tab = tab;
      if (tab === "exceptions") st.overrides = (await guard(() => api.overrides(st.business.id))) || [];
      if (tab === "audit") st.audit = (await guard(() => api.audit(st.business.id, 200))) || null;
      render();
    }
    async function selectBusiness(id) {
      st.business = st.ctx.businesses.find((b) => b.id === id) || null;
      st.site = null; st.selected = null; st.tab = "settings";
      say(t("loading"));
      await loadFeatures();
      if (status.dataset.kind !== "error") say("");
      render();
    }

    // ---------------------------------------------------------------- actions
    function readForm(f) {
      const q = (id) => app.querySelector("#" + id);
      const inherit = !!(st.site && q("occ-scope-inherit") && q("occ-scope-inherit").checked);
      const params = {};
      for (const [name, d] of Object.entries(f.param_schema || {})) {
        const input = q("occ-p-" + name);
        if (!input) continue;
        if (d.type === "bool") params[name] = input.checked;
        else if (d.type === "int" || d.type === "numeric") params[name] = input.value === "" ? null : Number(input.value);
        else params[name] = input.value;
      }
      const scheduled = q("occ-when-schedule") && q("occ-when-schedule").checked;
      const at = q("occ-when-at") ? q("occ-when-at").value : "";
      return { inherit, enabled: q("occ-enabled") ? q("occ-enabled").checked : f.enabled,
        stages: q("occ-stages") ? Number(q("occ-stages").value) : f.stages, params, scheduled, at,
        reason: q("occ-reason") ? q("occ-reason").value.trim() : "" };
    }
    async function save() {
      const f = feat(); if (!f) return;
      st.fieldErrors = {};
      const v = readForm(f);
      if (v.reason.length < 5) { say(ERR[st.lang].CONTROL_BAD_REASON, true); app.querySelector("#occ-reason").focus(); return; }
      if (v.scheduled && !v.at) { say(t("needSchedule"), true); return; }
      const effectiveFrom = v.scheduled ? new Date(v.at).toISOString() : null;
      const lines = [t("scopeOf") + ": " + (st.site ? t("site") + " #" + st.site + (v.inherit ? " → " + t("scopeInherit") : "") : t("wholeBiz"))];
      if (!v.inherit) {
        lines.push(t("enabled") + ": " + (f.enabled ? t("on") : t("off")) + " → " + (v.enabled ? t("on") : t("off")));
        lines.push(t("stages") + ": " + f.stages + " → " + v.stages);
        for (const [k, val] of Object.entries(v.params)) if (JSON.stringify(val) !== JSON.stringify((f.params || {})[k]))
          lines.push(k + ": " + JSON.stringify((f.params || {})[k]) + " → " + JSON.stringify(val));
      }
      lines.push(t("when") + ": " + (effectiveFrom ? fmt(effectiveFrom) : t("now")));
      lines.push(t("reason") + ": " + v.reason);
      const answer = await dialog({ title: t("confirmTitle") + " · " + featTitle(f), lines });
      if (!answer.ok) return;
      const key = CORE10_KEY("ctl");
      const res = await guard(() => api.set({ business: st.business.id, site: st.site, feature: f.feature_key,
        enabled: v.enabled, stages: v.stages, params: v.params, effectiveFrom, inherit: v.inherit,
        expectedVersion: scopeMax(st.site), reason: v.reason, requestKey: key }).catch((e) => {
          if (e.code && /^CONTROL_PARAM_/.test(e.code) && e.detail) st.fieldErrors[e.detail] = errText(e);
          throw e;
        }));
      if (!res) {
        if (/CONTROL_STALE_VERSION/.test(status.textContent)) { await loadFeatures(); say(t("reloaded"), true); }
        render(); return;
      }
      await loadFeatures();
      say(t("saved") + res.version);
      render();
    }
    async function revertTo(h) {
      const f = feat(); if (!f) return;
      const lines = [t("version") + h.version + " · " + (h.site_id ? t("site") + " #" + h.site_id : t("wholeBiz")),
        (h.enabled ? t("on") : t("off")) + " · " + t("stagesN") + h.stages];
      const answer = await dialog({ title: t("revertTitle") + " · " + featTitle(f), lines, needReason: true });
      if (!answer.ok) return;
      const res = await guard(() => api.revert({ business: st.business.id, site: h.site_id, feature: f.feature_key,
        toVersion: h.version, expectedVersion: scopeMax(h.site_id), reason: answer.reason, requestKey: CORE10_KEY("rev") }));
      if (res) { await loadFeatures(); say(t("reverted") + res.version); }
      render();
    }
    async function grant() {
      const f = feat(); if (!f) return;
      const hours = Number((app.querySelector("#occ-hours") || {}).value || 0);
      const lines = [featTitle(f), t("hours") + ": " + hours, t("scopeOf") + ": " + (st.site ? t("site") + " #" + st.site : t("wholeBiz"))];
      const answer = await dialog({ title: t("grantTitle"), lines, needReason: true });
      if (!answer.ok) return;
      const res = await guard(() => api.grantOverride({ business: st.business.id, site: st.site, feature: f.feature_key,
        hours, reason: answer.reason, requestKey: CORE10_KEY("ovr") }));
      if (res) { say(t("granted")); await openTab("exceptions"); return; }
      render();
    }
    async function revoke(o) {
      const answer = await dialog({ title: t("revokeTitle"), lines: ["#" + o.id + " · " + o.reason], needReason: true });
      if (!answer.ok) return;
      const res = await guard(() => api.revokeOverride({ business: st.business.id, overrideId: o.id, reason: answer.reason,
        requestKey: CORE10_KEY("rvk") }));
      if (res) { say(t("revoked")); await openTab("exceptions"); return; }
      render();
    }
    function CORE10_KEY(p) { return (globalThis.CORE10_OWNER_CONTROL_API && globalThis.CORE10_OWNER_CONTROL_API.newKey)
      ? globalThis.CORE10_OWNER_CONTROL_API.newKey(p) : p + "_" + Date.now().toString(36) + Math.random().toString(36).slice(2); }

    // ---------------------------------------------------------------- render
    function chip(text, kind) { return el("span", { class: "occ-chip occ-chip-" + kind, text }); }
    function featureRow(f) {
      const chips = [f.invariant ? chip(t("locked"), "lock") : chip(f.enabled ? t("on") : t("off"), f.enabled ? "on" : "off"),
        f.max_stages > 0 ? chip(t("stagesN") + f.stages, "stages") : null, chip(t("src_" + f.source), "src"),
        f.scheduled ? chip(t("scheduled"), "sched") : null];
      return el("li", {}, [el("button", { type: "button", class: "occ-row" + (f.feature_key === st.selected ? " is-active" : ""),
        "aria-pressed": f.feature_key === st.selected ? "true" : "false", "data-feature": f.feature_key,
        onclick: async () => { st.selected = f.feature_key; st.tab = "settings"; st.fieldErrors = {};
          if (canManage()) await loadHistory(); render();
          const d = app.querySelector(".occ-detail"); if (d && d.scrollIntoView) d.scrollIntoView({ block: "nearest" }); } },
        [el("span", { class: "occ-row-title", text: featTitle(f) }), el("span", { class: "occ-row-key", text: f.feature_key }),
         el("span", { class: "occ-chips" }, chips)])]);
    }
    function paramInput(name, d, value, disabled) {
      const id = "occ-p-" + name;
      let input;
      if (d.type === "bool") input = el("input", { id, type: "checkbox", checked: !!value, disabled });
      else if (d.type === "enum") input = el("select", { id, disabled }, (d.values || []).map((x) => el("option", { value: x, text: x, selected: x === value })));
      else if (d.type === "text") input = el("input", { id, type: "text", maxlength: String(d.maxlen || 200), value: value == null ? "" : value, disabled });
      else input = el("input", { id, type: "number", inputmode: d.type === "int" ? "numeric" : "decimal", min: String(d.min), max: String(d.max),
        step: d.type === "int" ? "1" : "any", value: value == null ? "" : String(value), disabled });
      const errId = "occ-err-" + name;
      if (st.fieldErrors[name]) input.setAttribute("aria-describedby", errId);
      const text = (st.lang === "bn" ? d.label_bn : d.label_en) || name.replace(/_/g, " ");
      const label = el("label", { for: id, text: text + (d.type === "int" || d.type === "numeric" ? " (" + d.min + "–" + d.max + ")" : "") });
      const err = st.fieldErrors[name] ? el("p", { id: errId, class: "occ-field-error", role: "alert", text: st.fieldErrors[name] }) : null;
      if (d.type === "bool") return el("div", { class: "occ-field" }, [el("div", { class: "occ-switch" }, [input, label]), err]);
      return el("div", { class: "occ-field" }, [label, input, err]);
    }
    function settingsPanel(f) {
      if (f.invariant) return el("div", { class: "occ-panel" }, [el("p", { class: "occ-lock", text: "🔒 " + t("invariant") })]);
      const ro = !canManage();
      const kids = [];
      if (st.site) kids.push(el("fieldset", { class: "occ-field" }, [el("legend", { text: t("scope") }),
        el("label", { class: "occ-radio" }, [el("input", { type: "radio", name: "occ-scope", id: "occ-scope-site", checked: f.source === "site", disabled: ro }), t("scopeSite")]),
        el("label", { class: "occ-radio" }, [el("input", { type: "radio", name: "occ-scope", id: "occ-scope-inherit", checked: f.source !== "site", disabled: ro }), t("scopeInherit")])]));
      kids.push(el("div", { class: "occ-field occ-switch" }, [el("input", { id: "occ-enabled", type: "checkbox", role: "switch", checked: !!f.enabled, disabled: ro }),
        el("label", { for: "occ-enabled", text: t("enabled") })]));
      kids.push(el("div", { class: "occ-field" }, [el("label", { for: "occ-stages", text: t("stages") }),
        el("select", { id: "occ-stages", disabled: ro || f.max_stages === 0 }, Array.from({ length: f.max_stages + 1 }, (_, i) => el("option", { value: String(i), text: String(i), selected: i === f.stages })))]));
      const schema = f.param_schema || {};
      if (Object.keys(schema).length) kids.push(el("fieldset", { class: "occ-field" }, [el("legend", { text: t("params") })]
        .concat(Object.entries(schema).map(([n, d]) => paramInput(n, d, (f.params || {})[n], ro)))));
      if (!ro) {
        kids.push(el("fieldset", { class: "occ-field" }, [el("legend", { text: t("when") }),
          el("label", { class: "occ-radio" }, [el("input", { type: "radio", name: "occ-when", id: "occ-when-now", checked: true,
            onchange: () => { app.querySelector("#occ-when-at").disabled = true; } }), t("now")]),
          el("label", { class: "occ-radio" }, [el("input", { type: "radio", name: "occ-when", id: "occ-when-schedule",
            onchange: () => { app.querySelector("#occ-when-at").disabled = false; } }), t("schedule")]),
          el("label", { for: "occ-when-at", class: "occ-sr", text: t("schedule") }), el("input", { id: "occ-when-at", type: "datetime-local", disabled: true })]));
        kids.push(el("div", { class: "occ-field" }, [el("label", { for: "occ-reason", text: t("reason") }),
          el("textarea", { id: "occ-reason", rows: "2", maxlength: "500" })]));
        kids.push(el("div", { class: "occ-actions" }, [el("button", { type: "button", class: "occ-primary", id: "occ-save", text: t("save"), onclick: save })]));
      }
      if (f.scheduled) kids.unshift(el("p", { class: "occ-note", text: t("scheduled") + ": " + t("version") + f.scheduled.version + " · " +
        (f.scheduled.enabled ? t("on") : t("off")) + " · " + t("from") + fmt(f.scheduled.effective_from) }));
      return el("div", { class: "occ-panel" }, kids);
    }
    function historyPanel(f) {
      const rows = st.history.filter((h) => h.feature_key === f.feature_key);
      if (!rows.length) return el("p", { class: "occ-empty", text: t("noHistory") });
      return el("ol", { class: "occ-list-plain" }, rows.map((h) => el("li", { class: "occ-hist" }, [
        el("strong", { text: t("version") + h.version + " · " + (h.site_id ? t("site") + " #" + h.site_id : t("wholeBiz")) }),
        el("span", { text: h.inherit ? t("scopeInherit") : (h.enabled ? t("on") : t("off")) + " · " + t("stagesN") + h.stages +
          (h.params && Object.keys(h.params).length ? " · " + JSON.stringify(h.params) : "") }),
        el("span", { class: "occ-meta", text: t("from") + fmt(h.effective_from) + " · " + t("by") + String(h.changed_by).slice(0, 8) +
          (h.reverted_from ? " · ↩ v" + h.reverted_from : "") }),
        el("span", { class: "occ-reason-text", text: h.reason }),
        el("button", { type: "button", class: "occ-secondary", text: t("revert"), "data-revert": String(h.version), onclick: () => revertTo(h) })])));
    }
    function exceptionsPanel(f) {
      const list = st.overrides.filter((o) => o.feature_key === f.feature_key);
      const items = list.length ? el("ul", { class: "occ-list-plain" }, list.map((o) => el("li", { class: "occ-hist" }, [
        el("strong", { text: "#" + o.id + " · " + (o.site_id ? t("site") + " #" + o.site_id : t("wholeBiz")) }),
        chip(t("st_" + o.status), o.status), el("span", { class: "occ-meta", text: fmt(o.granted_at) + " → " + fmt(o.expires_at) }),
        el("span", { class: "occ-reason-text", text: o.reason }),
        o.status === "open" ? el("button", { type: "button", class: "occ-secondary", text: t("revoke"), "data-revoke": String(o.id), onclick: () => revoke(o) }) : null])))
        : el("p", { class: "occ-empty", text: t("noExceptions") });
      return el("div", { class: "occ-panel" }, [items, el("div", { class: "occ-field" }, [
        el("label", { for: "occ-hours", text: t("hours") }), el("input", { id: "occ-hours", type: "number", min: "1", max: "168", step: "1", value: "24" })]),
        el("div", { class: "occ-actions" }, [el("button", { type: "button", class: "occ-primary", id: "occ-grant", text: t("grant"), onclick: grant })])]);
    }
    function auditPanel(f) {
      if (!st.audit) return el("p", { class: "occ-empty", text: t("noAudit") });
      const c = st.audit.chain || {};
      const events = (st.audit.events || []).filter((e) => e.payload && e.payload.feature_key === f.feature_key);
      return el("div", { class: "occ-panel" }, [el("p", { class: "occ-note", text: c.ok === true ? "✓ " + t("chainOk") : c.ok === false ? "⚠ " + t("chainBad") : t("chainNA") }),
        events.length ? el("ol", { class: "occ-list-plain" }, events.map((e) => el("li", { class: "occ-hist" }, [
          el("strong", { text: "#" + e.stream_seq + " · " + e.action }), el("span", { class: "occ-meta", text: fmt(e.event_at) + " · " + t("by") + String(e.actor_id).slice(0, 8) }),
          el("code", { text: String(e.event_digest).slice(0, 16) })]))) : el("p", { class: "occ-empty", text: t("noAudit") })]);
    }
    function detail() {
      const f = feat();
      if (!f) return el("section", { class: "occ-detail", "aria-label": t("tabSettings") }, [el("p", { class: "occ-empty", text: t("choose") })]);
      const tabs = ["settings"].concat(canManage() && !f.invariant ? ["history", "exceptions", "audit"] : []);
      const names = { settings: t("tabSettings"), history: t("tabHistory"), exceptions: t("tabExceptions"), audit: t("tabAudit") };
      const panel = st.tab === "history" ? historyPanel(f) : st.tab === "exceptions" ? exceptionsPanel(f) : st.tab === "audit" ? auditPanel(f) : settingsPanel(f);
      return el("section", { class: "occ-detail", "aria-labelledby": "occ-detail-title" }, [
        el("h2", { id: "occ-detail-title", text: featTitle(f) }),
        el("p", { class: "occ-meta", text: f.feature_key + " · " + f.pack + " · " + t("version") + f.version + " · " + t("src_" + f.source) }),
        el("div", { class: "occ-tabs", role: "tablist" }, tabs.map((k) => el("button", { type: "button", role: "tab", id: "occ-tab-" + k,
          "aria-selected": st.tab === k ? "true" : "false", class: st.tab === k ? "is-active" : "", text: names[k],
          onclick: () => openTab(k) }))),
        el("div", { role: "tabpanel", "aria-labelledby": "occ-tab-" + st.tab }, [panel])]);
    }
    async function selectBootstrapTenant(id) {
      st.tenant = st.ctx.tenants.find((tenant) => tenant.id === id) || null;
      st.bootstrap = null;
      if (!st.tenant) return;
      const tenant = st.tenant;
      const policy = await guard(() => api.readBootstrap(tenant.id));
      if (st.tenant === tenant) st.bootstrap = policy || null;
    }

    async function saveBootstrap() {
      const tenant = st.tenant;
      const before = st.bootstrap;
      if (!tenant || !before) return;
      const enabled = !before.enabled;
      const label = t(enabled ? "bootstrapOn" : "bootstrapOff");
      const response = await dialog({ title: label, lines: [tenant.slug, t("bootstrapHelp")], needReason: true });
      if (!response.ok || st.tenant !== tenant) return;
      const saved = await guard(() => api.setBootstrap({
        tenant: tenant.id, enabled, reason: response.reason, expectedVersion: before.latest_version
      }));
      if (st.tenant !== tenant) return;
      await selectBootstrapTenant(tenant.id);
      if (saved && st.bootstrap) say(t("saved") + saved.version);
      render();
    }

    function bootstrapPanel() {
      const tenants = st.ctx.tenants;
      if (!tenants.length) return null;
      const policy = st.bootstrap;
      return el("section", { class: "occ-detail", "aria-labelledby": "occ-bootstrap-title" }, [
        el("h2", { id: "occ-bootstrap-title", text: t("bootstrapTitle") }),
        el("label", { for: "occ-bootstrap-tenant", text: t("tenant") }),
        el("select", { id: "occ-bootstrap-tenant", onchange: async (ev) => {
          await selectBootstrapTenant(Number(ev.target.value));
          render();
        } }, tenants.map((tenant) => el("option", {
          value: String(tenant.id), text: tenant.slug, selected: tenant === st.tenant
        }))),
        policy && el("p", { id: "occ-bootstrap-state", role: "status",
          text: t(policy.enabled ? "on" : "off") + " · " + t("version") + policy.effective_version }),
        policy && el("button", { id: "occ-bootstrap-save", type: "button", class: "occ-primary",
          text: t(policy.enabled ? "bootstrapOff" : "bootstrapOn"), onclick: saveBootstrap })
      ]);
    }

    function render() {
      app.setAttribute("lang", st.lang);
      const bizSelect = el("select", { id: "occ-business", onchange: (ev) => selectBusiness(Number(ev.target.value)) },
        (st.ctx ? st.ctx.businesses : []).map((b) => el("option", { value: String(b.id), text: (b.label || b.slug) + " · #" + b.id, selected: st.business && b.id === st.business.id })));
      const sites = st.ctx && st.business ? st.ctx.sites.filter((s) => s.business_id === st.business.id) : [];
      const siteSelect = el("select", { id: "occ-site", onchange: async (ev) => { st.site = ev.target.value ? Number(ev.target.value) : null; await loadFeatures(); render(); } },
        [el("option", { value: "", text: t("allSites"), selected: !st.site })].concat(sites.map((s) => el("option", { value: String(s.id), text: s.label + " · #" + s.id, selected: s.id === st.site }))));
      const header = el("header", { class: "occ-top" }, [
        el("div", { class: "occ-brand" }, [el("h1", { text: t("title") }), el("p", { text: t("sub") })]),
        el("div", { class: "occ-controls" }, [
          el("label", { for: "occ-business", text: t("business") }), bizSelect,
          el("label", { for: "occ-site", text: t("site") }), siteSelect,
          el("button", { type: "button", class: "occ-secondary", id: "occ-lang", text: t("lang"), onclick: () => {
            st.lang = st.lang === "bn" ? "en" : "bn"; try { localStorage.setItem("core10.occ.lang", st.lang); } catch (_) {} render(); } })])]);
      const kids = [header, status];
      if (!st.ctx) { app.replaceChildren(...kids); return; }
      const bootstrap = bootstrapPanel();
      if (bootstrap) kids.push(bootstrap);
      if (!st.ctx.businesses.length) { kids.push(el("p", { class: "occ-empty", id: "occ-no-business", text: t("noBusiness") })); app.replaceChildren(...kids); return; }
      if (!canManage()) kids.push(el("p", { class: "occ-banner", id: "occ-view-only", role: "note", text: t("viewOnly") }));
      const q = st.query.trim().toLowerCase();
      const shown = st.features.filter((f) => !q || f.feature_key.includes(q) || (f.title_en || "").toLowerCase().includes(q) || (f.title_bn || "").includes(st.query.trim()));
      const groups = {};
      for (const f of shown) (groups[f.pack] = groups[f.pack] || []).push(f);
      const search = el("input", { id: "occ-search", type: "search", value: st.query, placeholder: t("search"), "aria-label": t("search"),
        oninput: (ev) => { st.query = ev.target.value; render(); const s = app.querySelector("#occ-search"); s.focus(); s.setSelectionRange(s.value.length, s.value.length); } });
      const list = el("section", { class: "occ-list", "aria-label": t("search") }, [search].concat(
        shown.length ? Object.keys(groups).sort().map((p) => el("div", { class: "occ-group" }, [el("h3", { text: p }), el("ul", { class: "occ-list-plain" }, groups[p].map(featureRow))]))
        : [el("p", { class: "occ-empty", text: t("noFeatures") })]));
      kids.push(el("div", { class: "occ-main" }, [list, detail()]));
      app.replaceChildren(...kids);
    }

    async function start() {
      say(t("loading"));
      render();
      const ctx = await guard(() => api.context());
      if (!ctx) { render(); return; }
      st.ctx = {
        businesses: ctx.businesses || [], sites: ctx.sites || [],
        tenants: (ctx.tenants || []).filter((tenant) => tenant.can_manage_bootstrap === true)
      };
      if (st.ctx.tenants.length) await selectBootstrapTenant(st.ctx.tenants[0].id);
      if (!st.ctx.businesses.length) {
        if (status.dataset.kind !== "error") say("");
        render();
        return;
      }
      const first = st.ctx.businesses.find((b) => b.can_manage) || st.ctx.businesses[0];
      await selectBusiness(first.id);
    }
    return { start, state: st };
  }
  return { mount, T, ERR };
});
