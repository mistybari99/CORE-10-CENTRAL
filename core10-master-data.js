/* CORE 10 CENTRAL | B-011 Master Data boot. Same backend gate as the Owner Control Centre: CORE10 staging or loopback only. */
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
    const doc = win.document, rootEl = doc.getElementById("md-root");
    if (!rootEl) return;
    let lang = "bn"; try { lang = win.localStorage.getItem("core10.md.lang") === "en" ? "en" : "bn"; } catch (_) {}
    const cfg = win.CORE10_CONTROL_CENTRE_CONFIG, state = checkConfig(cfg);
    const msg = (bn, en) => { const p = doc.createElement("p"); p.className = "occ-status"; p.setAttribute("role", "status"); p.dataset.kind = "error";
      p.dataset.state = state; p.textContent = lang === "en" ? en : bn; rootEl.replaceChildren(p); };
    if (state === "NOT_CONNECTED") return msg("স্টেজিং এখনো যুক্ত হয়নি (মালিকের Level 2 অনুমোদনের অপেক্ষায়) — NOT_CONNECTED।", "Staging is not connected yet (awaiting Owner Level 2 approval) — NOT_CONNECTED.");
    if (state !== "OK") return msg("এই পাতা শুধু CORE10 স্টেজিংয়ে চলে (" + state + ")।", "This page runs only against CORE10 staging (" + state + ").");
    const lib = win.supabase;
    if (!lib || typeof lib.createClient !== "function") return msg("সাইন-ইন লাইব্রেরি পাওয়া যায়নি।", "Sign-in library missing.");
    const client = lib.createClient(cfg.url, cfg.key);
    const start = () => win.CORE10_MASTER_DATA_UI.mount(rootEl, { api: win.CORE10_MASTER_DATA_API.create({ client }), lang }).start();
    client.auth.getUser().then((r) => {
      if (r && r.data && r.data.user) return start();
      return msg("সাইন-ইন প্রয়োজন — আগে মালিক নিয়ন্ত্রণ কেন্দ্রে সাইন-ইন করুন।", "Sign-in required — sign in through the Owner Control Centre first.");
    });
  }
  return { checkConfig, run, ALLOWED_REFS };
});
