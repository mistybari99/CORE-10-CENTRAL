/* CORE 10 Owner Connections (P6) — UI for the "Connections" view. Synthetic fixture provider only.
 * SECRET RULES: secret inputs are type=password, have no name and no value attribute, are never copied into DOM text,
 * URL or any storage, and are cleared as soon as the form is submitted. Text is inserted with textContent only. */
(function () {
  "use strict";
  var C = window.C10CONSOLE, I = C.i18n, PF = C.portsFixtures;
  var ui = { key: "", selected: null, confirmLive: false, flash: null };

  function reset(key) { ui.key = key; ui.selected = null; ui.confirmLive = false; ui.flash = null; }
  function hasKey(k) { return Object.prototype.hasOwnProperty.call(I.en, k); }

  function view(ctx, p, root) {
    var el = ctx.el, t = ctx.t, biz = ctx.businessId;
    var key = ctx.roleKey + ":" + biz;
    if (ui.key !== key) reset(key);
    root.appendChild(el("h2", { id: "viewTitle", text: t("cx.title") }));
    return Promise.all([p.listAccounts(biz), p.listAudit(biz), p.getSimulation(biz)]).then(function (res) {
      paint(ctx, p, root, res[0], res[1], res[2]);
    }, function (e) {
      if (e && e.code === "integration_denied") { root.appendChild(el("div", { class: "state denied", id: "cxDenied", role: "alert" }, [el("p", { text: t("cx.denied") })])); ctx.announce(t("cx.denied")); return; }
      throw e;
    });
  }

  function paint(ctx, p, root, accounts, audit, simFail) {
    var el = ctx.el, t = ctx.t, biz = ctx.businessId, loc = ctx.locale;
    function label(a) { return loc === "bn" ? a.label_bn : a.label_en; }
    function errText(e) { var k = "cx.err." + (e && e.code); return t(hasKey(k) ? k : "cx.err.generic"); }
    function modeChip(a) { return el("span", { class: "chip mode-" + a.mode, "data-mode": a.mode, text: t("mode." + a.mode) }); }
    function statusChip(a) { return el("span", { class: "chip st-" + a.status, "data-status": a.status, text: t("cs." + a.status) }); }
    function refresh(focusSel) {
      return ctx.rerender().then(function () { var n = focusSel && document.querySelector(focusSel); if (n) n.focus(); });
    }
    function run(fn, okText, focusSel) {
      return Promise.resolve().then(fn).then(function (r) { ui.flash = { kind: "ok", text: typeof okText === "function" ? okText(r) : okText }; },
        function (e) { ui.flash = { kind: "err", text: errText(e) }; }).then(function () { return refresh(focusSel); });
    }

    root.appendChild(el("p", { class: "note", text: t("cx.intro") }));
    root.appendChild(el("p", { class: "note", text: t("cx.synthetic") }));
    var flash = el("p", { id: "cxFlash", class: "flash" + (ui.flash ? " " + ui.flash.kind : ""), role: ui.flash && ui.flash.kind === "err" ? "alert" : "status", tabindex: "-1", text: ui.flash ? ui.flash.text : "" });
    if (ui.flash) ctx.announce(ui.flash.text);
    root.appendChild(flash);

    /* kill switch + fixture control */
    var kill = el("div", { class: "kill" }, [
      el("button", { type: "button", id: "cxKill", class: "danger", onclick: function () {
        run(function () { return p.killSwitch(biz); }, function (n) { return t("cx.kill_done") + n; }, "#cxKill"); }, text: t("cx.kill") }),
      el("p", { class: "note", text: t("cx.kill_note") })
    ]);
    root.appendChild(kill);
    var simBox = el("label", { class: "sim" }, [
      el("input", { type: "checkbox", id: "cxSim", onchange: function (e) { var on = e.target.checked; p.setSimulation(biz, on).then(function () { return refresh("#cxSim"); }); } }),
      el("span", { text: " " + t("cx.sim") + " — " + t("cx.sim_note") })
    ]);
    simBox.firstChild.checked = !!simFail;
    root.appendChild(simBox);

    var sel = ui.selected && accounts.filter(function (a) { return a.provider_code === ui.selected; })[0];
    if (sel) paintDetail(sel); else paintList();
    paintAudit();

    function paintList() {
      PF.FAMILIES.forEach(function (fam) {
        var rows = accounts.filter(function (a) { return a.family === fam; });
        if (!rows.length) return;
        var sec = el("section", { class: "fam", "aria-labelledby": "fam-" + fam }, [el("h3", { id: "fam-" + fam, text: t("fam." + fam) })]);
        var ul = el("ul", { class: "ports" });
        rows.forEach(function (a) {
          ul.appendChild(el("li", { class: "port", "data-port-row": a.provider_code }, [
            el("div", { class: "pname" }, [el("strong", { text: label(a) })]),
            el("div", { class: "pbadges" }, [modeChip(a), statusChip(a)]),
            el("button", { type: "button", "data-port": a.provider_code, "aria-label": t("cx.open") + ": " + label(a), onclick: function () {
              ui.selected = a.provider_code; ui.confirmLive = false; ui.flash = null; refresh("#cxBack"); }, text: t("cx.open") })
          ]));
        });
        sec.appendChild(ul); root.appendChild(sec);
      });
    }

    function paintDetail(a) {
      var box = el("section", { class: "detail", "aria-labelledby": "cxPortTitle" });
      box.appendChild(el("button", { type: "button", id: "cxBack", class: "backbtn", onclick: function () { ui.selected = null; ui.confirmLive = false; ui.flash = null; refresh(); }, text: "‹ " + t("cx.back") }));
      box.appendChild(el("h3", { id: "cxPortTitle", text: label(a) }));
      box.appendChild(el("p", { class: "pbadges" }, [modeChip(a), statusChip(a)]));
      var info = el("ul", { class: "info" });
      info.appendChild(el("li", { text: a.needs_secret ? (a.secret_saved ? t("cx.secret_saved") : t("cx.secret_none")) : t("cx.secret_none") }));
      info.appendChild(el("li", { text: t("cx.last_test") + ": " + (a.last_test_ok_at ? new Date(a.last_test_ok_at).toLocaleString(loc === "bn" ? "bn-BD" : "en-GB") : t("cx.never_tested")) }));
      info.appendChild(el("li", { text: t("cx.limits") + ": " + a.daily_cap + " / " + a.quiet_start_hour + ":00–" + a.quiet_end_hour + ":00" }));
      box.appendChild(info);
      var cfgKeys = Object.keys(a.public_config);
      if (cfgKeys.length) {
        box.appendChild(el("h4", { text: t("cx.saved_settings") }));
        box.appendChild(el("ul", { class: "info cfg" }, cfgKeys.map(function (k) { return el("li", { text: t("f." + k) + ": " + a.public_config[k] }); })));
      }
      /* connect form: only this provider's needs_fields */
      var connected = a.status !== "not_connected";
      box.appendChild(el("h4", { text: connected ? t("cx.reconnect_title") : t("cx.connect_title") }));
      var form = el("form", { id: "cxForm", autocomplete: "off", novalidate: "novalidate" });
      var inputs = [];
      if (!a.needs_fields.length) form.appendChild(el("p", { class: "note", text: t("cx.no_fields") }));
      else form.appendChild(el("p", { class: "note", text: t("cx.secret_hint") }));
      a.needs_fields.forEach(function (f) {
        var secret = a.secret_fields.indexOf(f) !== -1;
        var attrs = { id: "cx-f-" + f, type: secret ? "password" : "text", autocomplete: secret ? "new-password" : "off", spellcheck: "false", autocapitalize: "off", "data-field": f };
        if (secret) attrs["data-secret"] = "1";
        if (f === "monthly_budget") attrs.inputmode = "numeric";
        var input = el("input", attrs); inputs.push(input);
        form.appendChild(el("label", { class: "ff", for: "cx-f-" + f }, [el("span", { text: t("f." + f) + (secret ? " (" + t("cx.secret_tag") + ")" : "") }), input]));
      });
      var submit = el("button", { type: "submit", id: "cxConnect", class: "primary", onclick: function (e) {
        e.preventDefault();
        var fields = {};
        inputs.forEach(function (i) { fields[i.dataset.field] = i.value; });
        inputs.forEach(function (i) { i.value = ""; });   // secrets leave the DOM immediately
        var pending = p.connect(biz, a.provider_code, fields);   // provider validates and drops the values synchronously
        fields = null;
        run(function () { return pending; }, t("msg.connected"), "#cxFlash");
      }, text: connected ? t("cx.reconnect") : t("cx.connect") });
      form.appendChild(submit); box.appendChild(form);

      /* test */
      var actions = el("div", { class: "row" });
      actions.appendChild(el("button", { type: "button", id: "cxTest", onclick: function () {
        run(function () { return p.test(biz, a.provider_code); }, function (r) { return r === "passed" ? t("msg.test_passed") : t("msg.test_failed"); }, "#cxFlash"); }, text: t("cx.test") }));
      if (!connected) actions.firstChild.setAttribute("disabled", "disabled");
      actions.appendChild(el("button", { type: "button", id: "cxDisconnect", onclick: function () {
        run(function () { return p.disconnect(biz, a.provider_code); }, t("msg.disconnected"), "#cxFlash"); }, text: t("cx.disconnect") }));
      if (!connected) actions.lastChild.setAttribute("disabled", "disabled");
      box.appendChild(actions);

      /* enable ladder: off -> dry-run -> live */
      box.appendChild(el("h4", { id: "cxLadderTitle", text: t("cx.ladder") }));
      var ladder = el("div", { class: "ladder", role: "group", "aria-labelledby": "cxLadderTitle" });
      function setMode(m) { return run(function () { return p.setMode(biz, a.provider_code, m); }, function () { return t("msg.mode_set") + t("mode." + m); }, "#cxFlash"); }
      [["off", "cx.set_off", true], ["dry_run", "cx.set_dry", a.dry_run_ready], ["live", "cx.set_live", a.live_ready]].forEach(function (s) {
        var b = el("button", { type: "button", id: "cxMode-" + s[0], "data-set-mode": s[0], "aria-pressed": String(a.mode === s[0]), text: t(s[1]), onclick: function () {
          if (s[0] === "live") { ui.confirmLive = true; ui.flash = null; refresh("#cxLiveCancel"); } else setMode(s[0]); } });
        if (!s[2]) { b.setAttribute("disabled", "disabled"); if (s[0] === "live") b.setAttribute("aria-describedby", "cxLiveNote"); }
        ladder.appendChild(b);
      });
      box.appendChild(ladder);
      if (!a.live_ready) box.appendChild(el("p", { id: "cxLiveNote", class: "note", text: a.dry_run_ready ? t("cx.live_locked") : t("cx.dry_locked") }));
      if (ui.confirmLive && a.live_ready && a.mode !== "live") {
        box.appendChild(el("div", { class: "confirm", id: "cxLiveConfirm", role: "group", "aria-labelledby": "cxLiveConfirmTitle" }, [
          el("strong", { id: "cxLiveConfirmTitle", text: t("cx.live_confirm_title") }), el("p", { text: t("cx.live_confirm_text") }),
          el("p", { text: t("cx.limits") + ": " + a.daily_cap + " / " + a.quiet_start_hour + ":00–" + a.quiet_end_hour + ":00" }),
          el("div", { class: "row" }, [
            el("button", { type: "button", id: "cxLiveCancel", onclick: function () { ui.confirmLive = false; refresh("#cxMode-live"); }, text: t("cx.cancel") }),
            el("button", { type: "button", id: "cxLiveGo", class: "primary", onclick: function () { ui.confirmLive = false; setMode("live"); }, text: t("cx.live_confirm") })
          ])
        ]));
      } else ui.confirmLive = false;
      root.appendChild(box);
    }

    function paintAudit() {
      var sec = el("section", { class: "audit", "aria-labelledby": "cxAuditTitle" }, [el("h3", { id: "cxAuditTitle", text: t("cx.audit") })]);
      if (!audit.length) sec.appendChild(el("p", { class: "note", id: "cxAuditEmpty", text: t("cx.audit_empty") }));
      else {
        var ol = el("ol", { class: "auditlist", id: "cxAudit" });
        audit.slice(0, 30).forEach(function (r) {
          var prov = r.provider_code ? accounts.filter(function (a) { return a.provider_code === r.provider_code; })[0] : null;
          var detail = r.action === "mode" && r.before && r.after ? t("mode." + r.before.mode) + " → " + t("mode." + r.after.mode)
            : r.action === "kill_switch" ? t("cx.turned_off") + ": " + (r.after && r.after.turned_off) : r.action === "test" && r.after ? (r.after.ok ? t("msg.test_passed") : t("msg.test_failed")) : "";
          ol.appendChild(el("li", { "data-action": r.action, text: new Date(r.at).toLocaleString(loc === "bn" ? "bn-BD" : "en-GB") + " · " + t("actor." + r.actor) + " · " + t("act." + r.action) +
            (prov ? " · " + label(prov) : "") + (detail ? " · " + detail : "") }));
        });
        sec.appendChild(ol);
      }
      root.appendChild(sec);
    }
  }
  C.portsUI = { view: view, reset: reset };
})();
