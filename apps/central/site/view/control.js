/* Read-only replay client for the real Owner Control Centre UI and API client.
 * Reads return responses recorded from the real core10 SQL functions on synthetic sample data.
 * Every write (set, revert, grant, revoke) and every unrecorded call is refused with the UI's own
 * "server could not be reached" error: nothing is saved and no success is ever shown. No network. */
(function () {
  "use strict";
  var REC = (window.CORE10_PREVIEW_CONTROL || {}).responses || {};
  var WRITES = /^control_(set|revert|grant_override|revoke_override)_v1$/;
  var key = function (name, args) { args = args || {}; return name + "|" + JSON.stringify(args, Object.keys(args).sort()); };
  var unavailable = { data: null, error: { message: "CONTROL_RPC_UNAVAILABLE" } };
  var client = {
    auth: { getUser: async function () { return { data: { user: { id: "91111111-1111-4111-8111-111111111111" } }, error: null }; } },
    schema: function () { return { rpc: async function (name, args) {
      if (WRITES.test(name)) return unavailable;
      var k = key(name, args);
      return Object.prototype.hasOwnProperty.call(REC, k) ? { data: JSON.parse(JSON.stringify(REC[k])), error: null } : unavailable;
    } }; }
  };
  var lang = new URLSearchParams(location.search).get("lang") === "en" ? "en" : "bn";
  window.CORE10_OWNER_CONTROL_UI.mount(document.getElementById("occ-root"), { api: window.CORE10_OWNER_CONTROL_API.create({ client: client }), lang: lang }).start();
})();
