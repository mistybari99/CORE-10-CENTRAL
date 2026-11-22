// TEST-ONLY: signed-client stand-in sending each purchase RPC to the loopback SQL gateway as one persona.
// The schema has no table access (from): the screen reads only through RPCs.
(function () {
  "use strict";
  const qs = new URLSearchParams(location.search), persona = qs.get("persona") || "", lang = qs.get("lang") === "en" ? "en" : "bn";
  const send = async (url, body) => {
    const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json", "x-test-persona": persona }, body: JSON.stringify(body || {}) });
    const j = await r.json().catch(() => ({ message: "BAD_JSON" }));
    return r.ok ? { data: j, error: null } : { data: null, error: { message: j.message } };
  };
  const client = {
    auth: { getUser: async () => persona ? { data: { user: { id: persona } }, error: null } : { data: { user: null }, error: { message: "no session" } } },
    schema: () => ({ rpc: (name, args) => send("/rpc/" + name, args || {}) })
  };
  const pb = Number(qs.get("biz")) || null, lotPage = Number(qs.get("lotpage")) || undefined;
  const ui = window.CORE10_PURCHASE_UI.mount(document.getElementById("pu-root"), { api: window.CORE10_PURCHASE_API.create({ client }), lang, preferBusiness: pb, lotPageSize: lotPage });
  ui.start().then(() => { document.body.dataset.ready = "1"; });
})();
