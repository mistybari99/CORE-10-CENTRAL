/* Renders the real PACK-02 workspace/controls UI from its synthetic sample projection (same call as the repo browser test). */
(function () {
  "use strict";
  var DATA = window.CORE10_PREVIEW_WORKSPACE || {};
  var v = new URLSearchParams(location.search).get("v") || "universal-owner";
  if (!Object.prototype.hasOwnProperty.call(DATA, v)) v = "universal-owner";
  var api = v.indexOf("controls-") === 0 ? window.CORE10_PACK02_CONTROLS : window.CORE10_PACK02_WORKSPACE;
  api.render(document.getElementById("ws"), api.view(DATA[v]));
})();
