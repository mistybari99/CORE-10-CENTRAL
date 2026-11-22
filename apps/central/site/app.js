/* CORE 10 owner preview shell: hash routes -> real module views. No network, no session, no storage beyond language. */
(function () {
  "use strict";
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
  function closeMore(restoreFocus) {
    if (morePanel.hidden) return;
    morePanel.hidden = true; moreToggle.setAttribute("aria-expanded", "false");
    if (restoreFocus) moreToggle.focus();
  }
  // A changing iframe.src pushes entries into the joint browser history.
  // Replace each nested route so browser Back returns to the previous shell hash.
  var currentFrameUrl = "";
  var lang = "bn"; try { lang = localStorage.getItem("core10.preview.lang") === "en" ? "en" : "bn"; } catch (_) {}
  function route() {
    var r = (location.hash.replace(/^#\/?/, "") || "home").split("?")[0];
    if (!Object.prototype.hasOwnProperty.call(ROUTES, r)) r = "home";
    var signed = r === "control" || r === "setup" || r === "master" || r === "stock";
    dataStatus.querySelector(".bn").textContent = r === "business"
      ? "CORE10 স্টেজিং · সাইন-ইন করে লাইভ ব্যবসার তথ্য দেখুন (শুধু পড়া)"
      : signed ? "CORE10 স্টেজিং · সাইন-ইন করলে পরিবর্তন সংরক্ষণ করা যায়"
      : "প্রিভিউ · নমুনা তথ্য · এখানে পরিবর্তন সংরক্ষিত হয় না";
    dataStatus.querySelector(".en").textContent = r === "business"
      ? "CORE10 staging · signed read-only business data"
      : signed ? "CORE10 staging · signed-in changes can be saved"
      : "Preview · sample data · changes are not saved";
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
  setLang(lang);
})();
