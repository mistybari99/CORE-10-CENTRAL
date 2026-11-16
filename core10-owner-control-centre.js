/* CORE 10 CENTRAL | B-021 Owner Control Centre boot. Staging or loopback test backend only. */
(function (root, factory) {
  "use strict";
  const boot = factory();
  if (typeof module === "object" && module.exports) module.exports = boot;
  if (root && root.document) boot.run(root);
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const ALLOWED_REFS = ["rhrqhbyzrhaafynfhdaf"];
  function checkConfig(cfg) {
    if (!cfg || typeof cfg.url !== "string") return "CONFIG_MISSING";
    let u; try { u = new URL(cfg.url); } catch (_) { return "CONFIG_URL_INVALID"; }
    const loop = u.protocol === "http:" && ["127.0.0.1", "localhost"].includes(u.hostname);
    const staging = u.protocol === "https:" && ALLOWED_REFS.some((r) => u.hostname === r + ".supabase.co");
    if (!loop && !staging) return "BACKEND_NOT_ALLOWED";
    if (u.pathname !== "/" || u.search || u.username) return "CONFIG_URL_INVALID";
    if (!cfg.key) return "NOT_CONNECTED";
    return "OK";
  }
  function run(win) {
    const doc = win.document, rootEl = doc.getElementById("occ-root");
    if (!rootEl) return;
    let lang = "bn"; try { lang = win.localStorage.getItem("core10.occ.lang") === "en" ? "en" : "bn"; } catch (_) {}
    const cfg = win.CORE10_CONTROL_CENTRE_CONFIG, state = checkConfig(cfg);
    const msg = (bn, en) => { const p = doc.createElement("p"); p.className = "occ-status"; p.setAttribute("role", "status"); p.dataset.kind = "error";
      p.textContent = lang === "en" ? en : bn; rootEl.replaceChildren(p); };
    if (state === "NOT_CONNECTED") return msg("স্টেজিং এখনো যুক্ত হয়নি (মালিকের Level 2 অনুমোদনের অপেক্ষায়)।", "Staging is not connected yet (waiting for the Owner's Level 2 approval).");
    if (state !== "OK") return msg("এই পাতা শুধু CORE10 স্টেজিংয়ে চলে (" + state + ")।", "This page runs only against CORE10 staging (" + state + ").");
    const lib = win.supabase;
    if (!lib || typeof lib.createClient !== "function") return msg("সাইন-ইন লাইব্রেরি পাওয়া যায়নি।", "Sign-in library missing.");
    const client = lib.createClient(cfg.url, cfg.key);
    const startCentre = () => win.CORE10_OWNER_CONTROL_UI.mount(rootEl, { api: win.CORE10_OWNER_CONTROL_API.create({ client }), lang }).start();
    client.auth.getUser().then((r) => {
      if (r && r.data && r.data.user) return startCentre();
      const form = doc.createElement("form"); form.className = "occ-dialog"; form.setAttribute("aria-label", "Sign in");
      const mk = (id, type, label) => { const l = doc.createElement("label"); l.htmlFor = id; l.textContent = label;
        const i = doc.createElement("input"); i.id = id; i.type = type; i.required = true; i.autocomplete = type === "password" ? "current-password" : "username"; return [l, i]; };
      const [le, ie] = mk("occ-email", "email", lang === "en" ? "Email" : "ইমেইল"), [lp, ip] = mk("occ-password", "password", lang === "en" ? "Password" : "পাসওয়ার্ড");
      const b = doc.createElement("button"); b.className = "occ-primary"; b.type = "submit"; b.textContent = lang === "en" ? "Sign in" : "সাইন-ইন";
      const err = doc.createElement("p"); err.className = "occ-field-error"; err.setAttribute("role", "alert");
      form.append(le, ie, lp, ip, b, err);
      form.addEventListener("submit", async (ev) => { ev.preventDefault();
        const res = await client.auth.signInWithPassword({ email: ie.value.trim(), password: ip.value });
        if (res.error) { err.textContent = lang === "en" ? "Sign-in failed." : "সাইন-ইন হয়নি।"; return; }
        startCentre(); });
      rootEl.replaceChildren(form); ie.focus();
    });
  }
  return { checkConfig, run, ALLOWED_REFS };
});
