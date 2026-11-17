// TEST-ONLY: signed-client stand-in sending each master RPC to the loopback SQL gateway as one persona.
(function () {
  "use strict";
  const qs = new URLSearchParams(location.search), persona = qs.get("persona") || "", lang = qs.get("lang") === "en" ? "en" : "bn";
  const client = {
    auth: { getUser: async () => persona ? { data: { user: { id: persona } }, error: null } : { data: { user: null }, error: { message: "no session" } } },
    schema: () => ({ rpc: async (name, args) => {
      const r = await fetch("/rpc/" + name, { method: "POST", headers: { "content-type": "application/json", "x-test-persona": persona }, body: JSON.stringify(args || {}) });
      const j = await r.json().catch(() => ({ message: "BAD_JSON" }));
      return r.ok ? { data: j, error: null } : { data: null, error: { message: j.message } };
    } })
  };
  const ui = window.CORE10_MASTER_DATA_UI.mount(document.getElementById("md-root"), { api: window.CORE10_MASTER_DATA_API.create({ client }), lang });
  ui.start().then(() => { document.body.dataset.ready = "1"; });
})();
