/* Read-only replay for real CORE 10 module clients. Reads answer with responses recorded from the real core10
 * SQL functions on synthetic sample data; every write and every unrecorded call is refused with the module's
 * own "not reachable / not connected" code. Nothing is saved, posted or approved. No network. */
(function () {
  "use strict";
  var key = function (name, args) { args = args || {}; return name + "|" + JSON.stringify(args, Object.keys(args).sort()); };
  window.CORE10_PREVIEW_REPLAY = function (rec, writes, refusal) {
    var R = (rec && rec.responses) || {};
    return async function (name, args) {
      var k = key(name, args);
      if (writes.test(name) || !Object.prototype.hasOwnProperty.call(R, k)) return { data: null, error: { message: refusal, code: refusal } };
      return { data: JSON.parse(JSON.stringify(R[k])), error: null };
    };
  };
  window.CORE10_PREVIEW_CLIENT = function (persona, rpc) {
    return { auth: { getUser: async function () { return { data: { user: { id: persona } }, error: null }; },
                     onAuthStateChange: function () { return { data: { subscription: { unsubscribe: function () {} } } }; } },
             schema: function () { return { rpc: rpc }; } };
  };
  window.CORE10_PREVIEW_LANG = new URLSearchParams(location.search).get("lang") === "en" ? "en" : "bn";
})();
