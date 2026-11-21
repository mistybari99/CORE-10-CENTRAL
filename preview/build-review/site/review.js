/* Review hub: language toggle only. No network, no storage of anything but the language choice. */
(function () {
  "use strict";
  var html = document.documentElement;
  function set(lang) {
    html.dataset.lang = lang; html.lang = lang;
    Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.setLang === lang));
    });
    try { localStorage.setItem("core10.review.lang", lang); } catch (_) {}
  }
  var saved = "bn"; try { saved = localStorage.getItem("core10.review.lang") === "en" ? "en" : "bn"; } catch (_) {}
  set(saved);
  Array.prototype.forEach.call(document.querySelectorAll("[data-set-lang]"), function (b) {
    b.addEventListener("click", function () { set(b.dataset.setLang); });
  });
})();
