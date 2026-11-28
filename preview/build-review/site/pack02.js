/* Review host for the real PACK-02 renderers. Same calls as tests/pack02/workspace-browser.cjs:
 * W.render(root, W.view(fixture)) / C.render(root, C.view(fixture)). No network, no session. */
(function () {
  "use strict";
  var FX = window.CORE10_REVIEW_FIXTURES || {};
  var name = new URLSearchParams(location.search).get("fx") || "universal-owner";
  if (!Object.prototype.hasOwnProperty.call(FX, name)) name = "universal-owner";
  var root = document.getElementById("ws");
  var isControls = name.indexOf("controls-") === 0;
  var api = isControls ? window.CORE10_PACK02_CONTROLS : window.CORE10_PACK02_WORKSPACE;
  document.getElementById("rv-fx-name").textContent = "Fixture: tests/pack02/fixtures/" + name + ".json";
  Array.prototype.forEach.call(document.querySelectorAll(".rv-fixnav a"), function (a) {
    if (a.getAttribute("href") === "?fx=" + name) a.setAttribute("aria-current", "page");
  });
  api.render(root, api.view(FX[name]));
})();
