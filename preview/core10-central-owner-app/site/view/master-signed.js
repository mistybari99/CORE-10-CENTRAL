/* CORE10 Master Data — signed CORE10 staging. Never legacy IMG-ERP-SG.
 * Existing trunk canonical client and UI. Same-origin signed Supabase session only.
 */
(function (win) {
  "use strict";
  const doc = win.document, root = doc.getElementById("md-root");
  if (!root) return;
  const STAGING = "https://rhrqhbyzrhaafynfhdaf.supabase.co";
  const cfg = win.CORE10_CONTROL_CENTRE_CONFIG;
  let lang = "bn";
  try { lang = win.localStorage.getItem("core10.preview.lang") === "en" ? "en" : "bn"; } catch (_) {}
  doc.documentElement.lang = lang;
  const tr = (bn, en) => lang === "en" ? en : bn;
  const el = (tag, content, cls) => {
    const node = doc.createElement(tag);
    if (content != null) node.textContent = content;
    if (cls) node.className = cls;
    return node;
  };
  const message = (bn, en) => {
    const p = el("p", tr(bn, en), "occ-status");
    p.setAttribute("role", "alert");
    root.replaceChildren(p);
  };
  if (!cfg || cfg.url !== STAGING || typeof cfg.key !== "string" || !cfg.key.startsWith("sb_publishable_")) {
    message("শুধু অনুমোদিত CORE10 স্টেজিং সংযোগ এখানে চলে।", "Only the authorized CORE10 staging backend is supported.");
    return;
  }
  if (!win.supabase || typeof win.supabase.createClient !== "function" ||
      !win.CORE10_MASTER_DATA_API || !win.CORE10_MASTER_DATA_UI) {
    message("মাস্টার ডেটা মডিউল পাওয়া যায়নি।", "Master Data module unavailable.");
    return;
  }
  const client = win.supabase.createClient(cfg.url, cfg.key);
  let epoch = 0;
  function showSignIn() {
    const current = ++epoch;
    const form = el("form", null, "occ-dialog"); form.id = "md-login"; form.noValidate = true;
    const heading = el("h2", tr("মাস্টার ডেটা · সাইন ইন", "Master Data · Sign in"));
    const subtitle = el("p", tr("CORE10 স্টেজিংয়ে পণ্য, একক, ক্রেতা ও দাম সংরক্ষণ করা যায়।", "Signed CORE10 staging: items, units, parties and prices can be saved."));
    const emailLabel = el("label", tr("ইমেইল", "Email")); emailLabel.htmlFor = "md-email";
    const email = el("input"); email.id = "md-email"; email.type = "email"; email.required = true; email.autocomplete = "username";
    const passLabel = el("label", tr("পাসওয়ার্ড", "Password")); passLabel.htmlFor = "md-password";
    const password = el("input"); password.id = "md-password"; password.type = "password"; password.required = true; password.autocomplete = "current-password";
    const submit = el("button", tr("সাইন ইন করুন", "Sign in"), "occ-primary"); submit.type = "submit";
    const err = el("p"); err.id = "md-error"; err.setAttribute("role", "alert");
    form.append(heading, subtitle, emailLabel, email, passLabel, password, submit, err);
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      if (!email.value.trim() || !password.value) { err.textContent = tr("ইমেইল ও পাসওয়ার্ড দিন।", "Enter email and password."); return; }
      submit.disabled = true; err.textContent = "";
      try {
        const auth = await client.auth.signInWithPassword({ email: email.value.trim(), password: password.value });
        password.value = "";
        if (auth.error || !auth.data || !auth.data.user) {
          err.textContent = tr("সাইন ইন হয়নি। আবার চেষ্টা করুন।", "Sign-in failed. Try again."); return;
        }
        if (current === epoch) await showWorkspace();
      } catch (_) {
        password.value = "";
        if (current === epoch) err.textContent = tr("সাইন ইন হয়নি। আবার চেষ্টা করুন।", "Sign-in failed. Try again.");
      } finally { submit.disabled = false; }
    });
    root.replaceChildren(form);
  }
  async function showWorkspace() {
    const current = ++epoch;
    const check = await client.auth.getUser();
    if (current !== epoch) return;
    if (check.error || !check.data || !check.data.user) { showSignIn(); return; }
    const toolbar = el("div", null, "occ-topline");
    const heading = el("strong", tr("CORE10 স্টেজিং · বাস্তব মাস্টার ডেটা", "CORE10 staging · signed Master Data"));
    const logout = el("button", tr("সাইন আউট", "Sign out"), "occ-secondary");
    logout.id = "md-signout"; logout.type = "button";
    logout.addEventListener("click", async () => {
      logout.disabled = true;
      try { await client.auth.signOut(); } finally { showSignIn(); }
    });
    toolbar.append(heading, logout);
    const host = el("section"); host.id = "md-workspace";
    root.replaceChildren(toolbar, host);
    try {
      const api = win.CORE10_MASTER_DATA_API.create({ client });
      const view = win.CORE10_MASTER_DATA_UI.mount(host, { api, lang });
      await view.start();
      if (current !== epoch) host.replaceChildren();
    } catch (_) {
      if (current === epoch) message("মাস্টার ডেটা খোলা যায়নি। পুনরায় সাইন ইন করুন।", "Master Data unavailable. Please sign in again.");
    }
  }
  client.auth.onAuthStateChange((event) => {
    if (event === "SIGNED_OUT") showSignIn();
  });
  client.auth.getUser().then(r => {
    if (r && r.data && r.data.user) return showWorkspace();
    showSignIn();
  }).catch(() => showSignIn());
})(window);
