/* Real Master Data UI + API client on the read-only replay (same mount call as the repo browser harness). */
(function () {
  "use strict";
  var rec = window.CORE10_PREVIEW_MASTER;
  var rpc = window.CORE10_PREVIEW_REPLAY(rec, /^master_save_/, "MASTER_RPC_UNAVAILABLE");
  var client = window.CORE10_PREVIEW_CLIENT(rec.persona, rpc);
  window.CORE10_MASTER_DATA_UI.mount(document.getElementById("md-root"),
    { api: window.CORE10_MASTER_DATA_API.create({ client: client }), lang: window.CORE10_PREVIEW_LANG }).start();
})();
