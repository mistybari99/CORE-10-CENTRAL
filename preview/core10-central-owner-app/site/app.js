/* CORE 10 owner preview shell: hash routes -> real module views. No network, no session, no storage beyond language. */
(function () {
  "use strict";
  var ROUTES = {
    home: "/view/workspace.html?v=universal-owner",
    business: "/view/workspace.html?v=business-owner-branded",
    setup: "/live/core10-build01.html",
    master: "/view/master-signed.html",
    sales: "/view/sales.html",
    manufacturing: "/view/mfg.html",
    control: "/live/core10-owner-control-centre.html",
    features: "/view/workspace.html?v=controls-central",
    approvals: "/live/docs/preview/c10-np01-canonical-reviewer-preview.html",
    staff: "/view/workspace.html?v=staff"
  };
  var html = document.documentElement, frame = document.getElementById("c10-frame"), draft = document.getElementById("c10-draft"), dataStatus = document.getElementById("c10-data-status");
  var DRAFT = { sales: true, manufacturing: true };
  var lang = "bn"; try { lang = localStorage.getItem("core10.preview.lang") === "en" ? "en" : "bn"; } catch (_) {}
  function route() {
    var r = (location.hash.replace(/^#\/?/, "") || "home").split("?")[0];
    if (!Object.prototype.hasOwnProperty.call(ROUTES, r)) r = "home";
    var signed = r === "control" || r === "setup" || r === "master";
    dataStatus.querySelector(".bn").textContent = signed
      ? "CORE10 স্টেজিং · সাইন-ইন করলে পরিবর্তন সংরক্ষণ করা যায়"
      : "প্রিভিউ · নমুনা তথ্য · এখানে পরিবর্তন সংরক্ষিত হয় না";
    dataStatus.querySelector(".en").textContent = signed
      ? "CORE10 staging · signed-in changes can be saved"
      : "Preview · sample data · changes are not saved";
    Array.prototype.forEach.call(document.querySelectorAll("[data-route]"), function (a) {
      if (a.dataset.route === r) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
    });
    var src = ROUTES[r];
    draft.hidden = !DRAFT[r];
    {
      var url = src + (src.indexOf("?") < 0 ? "?" : "&") + "lang=" + lang;
      if (frame.getAttribute("src") !== url) frame.setAttribute("src", url);
    }
    document.body.dataset.view = r;
  }
  function setLang(l) {
    lang = l; html.dataset.lang = l; html.lang = l;
    try { localStorage.setItem("core10.preview.lang", l); } catch (_) {}
    Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) { b.setAttribute("aria-pressed", String(b.dataset.setLang === l)); });
    frame.removeAttribute("src"); route();
  }
  Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) { b.addEventListener("click", function () { setLang(b.dataset.setLang); }); });
  window.addEventListener("hashchange", route);
  setLang(lang);
})();
