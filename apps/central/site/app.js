/* CORE 10 owner preview shell: hash routes -> real module views. No network, no session, no storage beyond language. */
(function () {
  "use strict";
  const COPY = {
    sampleStatus: {
      bn: "প্রিভিউ · নমুনা তথ্য · এখানে পরিবর্তন সংরক্ষিত হয় না",
      en: "Preview · sample data · changes are not saved"
    },
    contextTitle: { bn: "গ্রুপ ▸ ব্যবসা ▸ স্থান", en: "Group ▸ Business ▸ Site" },
    signIn: { bn: "সাইন ইন", en: "Sign in" },
    group: { bn: "গ্রুপ", en: "Group" },
    business: { bn: "ব্যবসা", en: "Business" },
    site: { bn: "স্থান", en: "Site" },
    refresh: { bn: "যাচাই", en: "Refresh" },
    signOut: { bn: "সাইন আউট", en: "Sign out" },
    email: { bn: "ইমেইল", en: "Email" },
    password: { bn: "পাসওয়ার্ড", en: "Password" },
    continue: { bn: "প্রবেশ করুন", en: "Continue" },
    contextHelp: {
      bn: "শুধু CORE10 স্টেজিং; প্রতিটি মডিউল কাজের সময় আলাদাভাবে অনুমতি যাচাই করে।",
      en: "CORE10 staging only; each module rechecks authorization for operations."
    },
    workspaces: { bn: "কাজের জায়গা", en: "Workspaces" },
    ownerHome: { bn: "মালিকের হোম", en: "Owner home" },
    staff: { bn: "কর্মীর কাজ", en: "Staff workspace" },
    operations: { bn: "কার্যক্রম", en: "Operations" },
    master: { bn: "মাস্টার ডেটা", en: "Master data" },
    stockOperations: { bn: "স্টক লেনদেন", en: "Stock operations" },
    sales: { bn: "বিক্রয় অর্ডার", en: "Sales orders" },
    manufacturing: { bn: "উৎপাদন", en: "Manufacturing" },
    administration: { bn: "অনুমোদন ও পরিচালনা", en: "Approvals and administration" },
    approvals: { bn: "অনুমোদন", en: "Approvals" },
    control: { bn: "মালিক নিয়ন্ত্রণ", en: "Owner control" },
    features: { bn: "ফিচার অনুমতি", en: "Feature permissions" },
    setup: { bn: "সেটআপ ও প্রবেশাধিকার", en: "Setup & access" },
    replayNotice: {
      bn: "এই অংশ এখনো মূল সিস্টেমে যুক্ত হয়নি — শুধু দেখার নমুনা, কিছু পোস্ট হয় না।",
      en: "Not yet part of the main system — view-only sample, nothing is posted."
    },
    home: { bn: "হোম", en: "Home" },
    stock: { bn: "স্টক", en: "Stock" },
    more: { bn: "আরও", en: "More" },
    otherModules: { bn: "অন্যান্য মডিউল", en: "Other modules" },
    language: { bn: "ভাষা", en: "Language" },
    signedContext: {
      bn: "স্বাক্ষরিত গ্রুপ, ব্যবসা ও স্থানের প্রসঙ্গ",
      en: "Signed Group Business Site context"
    },
    mainNavigation: { bn: "প্রধান নেভিগেশন", en: "Main" },
    mobileNavigation: { bn: "মোবাইলের প্রধান নেভিগেশন", en: "Mobile primary navigation" },
    moreModules: { bn: "আরও মডিউল", en: "More modules" },
    signedReadStatus: {
      bn: "CORE10 স্টেজিং · সাইন-ইন করে লাইভ ব্যবসার তথ্য দেখুন (শুধু পড়া)",
      en: "CORE10 staging · signed read-only business data"
    },
    signedWriteStatus: {
      bn: "CORE10 স্টেজিং · সাইন-ইন করলে পরিবর্তন সংরক্ষণ করা যায়",
      en: "CORE10 staging · signed-in changes can be saved"
    },
    setupStatus: {
      bn: "CORE10 স্টেজিং · সেটআপে আলাদা সাইন-ইন · অনুমোদিত পরিবর্তন সংরক্ষণ করা যায়",
      en: "CORE10 staging · separate setup sign-in · authorized changes can be saved"
    },
    approvalStatus: {
      bn: "প্রিভিউ · নমুনা অনুমোদন · সিদ্ধান্ত সংরক্ষিত হয় না",
      en: "Preview · sample approvals · decisions are not saved"
    },
    workspaceShortcuts: { bn: "কাজের শর্টকাট", en: "Workspace shortcuts" },
    entrySignIn: {
      bn: "আপনার নির্বাচিত ব্যবসার কাজের শর্টকাট দেখতে সাইন ইন করুন।",
      en: "Sign in to see shortcuts for your selected business."
    },
    entryUnavailable: {
      bn: "ব্যবসার প্রসঙ্গ যাচাই করা যায়নি। প্রসঙ্গ বারে আবার চেষ্টা করুন।",
      en: "Business context could not be verified. Try again in the context bar."
    },
    entryLoading: { bn: "ব্যবসার প্রসঙ্গ যাচাই হচ্ছে…", en: "Checking business context…" },
    entryEmpty: { bn: "দেখার মতো কোনো ব্যবসা নেই।", en: "There are no businesses to show." },
    entryNoShortcuts: {
      bn: "এই ব্যবসার জন্য কোনো কাজের শর্টকাট নেই।",
      en: "There are no shortcuts for this business."
    },
    tenant_owner: { bn: "গ্রুপ মালিক", en: "Group owner" },
    business_owner: { bn: "ব্যবসার মালিক", en: "Business owner" },
    manager: { bn: "ব্যবস্থাপক", en: "Manager" },
    investor: { bn: "বিনিয়োগকারী", en: "Investor" },
    site_staff: { bn: "স্থানের কর্মী", en: "Site staff" },
  };

  function setCopy(element, copy) {
    element.querySelector(".bn").textContent = copy.bn;
    element.querySelector(".en").textContent = copy.en;
  }
  document.querySelectorAll("[data-copy]").forEach(function (element) {
    setCopy(element, COPY[element.dataset.copy]);
  });

  var ROUTES = {
    home: "/view/workspace.html?v=universal-owner",
    business: "/view/owner-dashboard-signed.html",
    setup: "/live/core10-build01.html",
    master: "/view/master-signed.html",
    stock: "/view/stock-signed.html",
    sales: "/view/sales.html",
    manufacturing: "/view/mfg.html",
    control: "/live/core10-owner-control-centre.html",
    features: "/view/workspace.html?v=controls-central",
    approvals: "/live/docs/preview/c10-np01-canonical-reviewer-preview.html",
    staff: "/view/workspace.html?v=staff"
  };
  var html = document.documentElement, frame = document.getElementById("c10-frame"), draft = document.getElementById("c10-draft"), dataStatus = document.getElementById("c10-data-status");
  var DRAFT = { sales: true, manufacturing: true };
  var moreToggle = document.getElementById("c10-more-toggle"), morePanel = document.getElementById("c10-mobile-more");
  var primaryRoutes = { home: true, business: true, stock: true, approvals: true };
  const dataNotice = {
    business: "signedReadStatus",
    control: "signedWriteStatus",
    setup: "setupStatus",
    master: "signedWriteStatus",
    stock: "signedWriteStatus",
    approvals: "approvalStatus"
  };
  const entry = document.getElementById("c10-entry");
  const entryStatus = document.getElementById("c10-entry-status");
  const entrySetup = document.getElementById("c10-entry-setup");
  const entryStock = document.getElementById("c10-entry-stock");
  let context = { state: "signed-out" };
  function closeMore(restoreFocus) {
    if (morePanel.hidden) return;
    morePanel.hidden = true; moreToggle.setAttribute("aria-expanded", "false");
    if (restoreFocus) moreToggle.focus();
  }
  // A changing iframe.src pushes entries into the joint browser history.
  // Replace each nested route so browser Back returns to the previous shell hash.
  var currentFrameUrl = "";
  var lang = "bn"; try { lang = localStorage.getItem("core10.preview.lang") === "en" ? "en" : "bn"; } catch (_) {}
  function updateEntry() {
    const business = context.business;
    const manageBusiness = context.state === "ready" && business?.canManage === true;
    const manageSetup = manageBusiness || (context.state === "ready" && context.canBootstrap === true);
    entrySetup.hidden = !manageSetup;
    entryStock.hidden = !manageBusiness;
    if (context.state === "ready" && business) {
      const role = business.role && COPY[business.role];
      const selection = role ? business.name + " · " + role[lang] : business.name;
      entryStatus.textContent = manageSetup ? selection : selection + " · " + COPY.entryNoShortcuts[lang];
      return;
    }
    const key = {
      "signed-out": "entrySignIn", loading: "entryLoading", error: "entryUnavailable", ready: "entryEmpty"
    }[context.state];
    entryStatus.textContent = COPY[key][lang];
  }

  function route() {
    var r = (location.hash.replace(/^#\/?/, "") || "home").split("?")[0];
    if (!Object.prototype.hasOwnProperty.call(ROUTES, r)) r = "home";
    setCopy(dataStatus, COPY[dataNotice[r] || "sampleStatus"]);
    entry.hidden = r !== "home";
    updateEntry();
    Array.prototype.forEach.call(document.querySelectorAll("[data-route]"), function (a) {
      if (a.dataset.route === r) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-mobile-route]"), function (a) {
      if (a.dataset.mobileRoute === r) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
    });
    if (primaryRoutes[r]) moreToggle.removeAttribute("aria-current"); else moreToggle.setAttribute("aria-current", "page");
    closeMore(false);
    var src = ROUTES[r];
    draft.hidden = !DRAFT[r];
    {
      var url = src + (src.indexOf("?") < 0 ? "?" : "&") + "lang=" + lang;
      if (currentFrameUrl !== url) {
        currentFrameUrl = url;
        try {
          frame.contentWindow.location.replace(url);
        } catch (_) {
          // Fail open for rendering only; all authorization remains in each signed view.
          frame.setAttribute("src", url);
        }
      }
    }
    document.body.dataset.view = r;
  }
  function setLang(l) {
    lang = l; html.dataset.lang = l; html.lang = l;
    document.querySelectorAll("[data-label]").forEach(function (element) {
      element.setAttribute("aria-label", COPY[element.dataset.label][l]);
    });
    try { localStorage.setItem("core10.preview.lang", l); } catch (_) {}
    Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) { b.setAttribute("aria-pressed", String(b.dataset.setLang === l)); });
    route();
    window.dispatchEvent(new Event("core10:language-change"));
  }
  Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) { b.addEventListener("click", function () { setLang(b.dataset.setLang); }); });
  moreToggle.addEventListener("click", function () {
    var opening = morePanel.hidden;
    morePanel.hidden = !opening;
    moreToggle.setAttribute("aria-expanded", String(opening));
    if (opening) morePanel.querySelector("a").focus();
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && !morePanel.hidden) closeMore(true);
  });
  document.addEventListener("pointerdown", function (e) {
    if (!morePanel.hidden && !morePanel.contains(e.target) && !moreToggle.contains(e.target)) closeMore(false);
  });
  // Canonical shell can purge an embedded private view on sign-out/account switch.
  window.addEventListener("core10:signed-out", function () {
    currentFrameUrl = "";
    try { frame.contentWindow.location.replace("about:blank"); }
    catch (_) { frame.setAttribute("src", "about:blank"); }
    // The old frame must be gone before the next view is allowed to render.
    Promise.resolve().then(route);
  });
  window.addEventListener("hashchange", route);
  window.addEventListener("core10:context-change", function (event) {
    context = event.detail;
    updateEntry();
  });
  setLang(lang);
})();
