/* Real Sales Order UI (Draft PR #109) on the read-only replay; same attach call as its repo browser harness.
 * Saving and status changes are refused as NOT_CONNECTED, which the UI shows with its own "disconnected" state. */
(function () {
  "use strict";
  var rec = window.CORE10_PREVIEW_SALES;
  var rpc = window.CORE10_PREVIEW_REPLAY(rec, /^(save_sales_order_v1|transition_sales_order_v1)$/, "NOT_CONNECTED");
  var client = window.CORE10_PREVIEW_CLIENT(rec.persona, rpc);
  window.CORE10_SALES_ORDER_ENTRY.attach(document.getElementById("sales-host"),
    { client: client, backendMode: "synthetic", lang: window.CORE10_PREVIEW_LANG });
})();
