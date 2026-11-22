// TEST-ONLY: signed-client stand-in sending each purchase RPC (and the one RLS-scoped location read) to the loopback
// SQL gateway as one persona.
(function () {
  "use strict";
  const qs = new URLSearchParams(location.search), persona = qs.get("persona") || "", lang = qs.get("lang") === "en" ? "en" : "bn";
  const send = async (url, body) => {
    const r = await fetch(url, { method: body === undefined ? "GET" : "POST", headers: { "content-type": "application/json", "x-test-persona": persona },
      body: body === undefined ? undefined : JSON.stringify(body || {}) });
    const j = await r.json().catch(() => ({ message: "BAD_JSON" }));
    return r.ok ? { data: j, error: null } : { data: null, error: { message: j.message } };
  };
  function from(table) {
    const q = new URLSearchParams(); const b = {
      select: (cols) => { q.set("select", cols); return b; }, eq: (k, v) => { q.set(k, String(v)); return b; },
      order: (c) => { q.set("order", c); return b; }, limit: (n) => { q.set("limit", String(n)); return send("/table/" + table + "?" + q.toString()); }
    }; return b;
  }
  const client = {
    auth: { getUser: async () => persona ? { data: { user: { id: persona } }, error: null } : { data: { user: null }, error: { message: "no session" } } },
    schema: () => ({ rpc: (name, args) => send("/rpc/" + name, args || {}), from })
  };
  const pb = Number(qs.get("biz")) || null;
  const ui = window.CORE10_PURCHASE_UI.mount(document.getElementById("pu-root"), { api: window.CORE10_PURCHASE_API.create({ client }), lang, preferBusiness: pb });
  ui.start().then(() => { document.body.dataset.ready = "1"; });
})();
