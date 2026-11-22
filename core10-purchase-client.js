/* CORE 10 CENTRAL | B-012 Purchase and goods receipt client (NP03A).
 * Calls only the canonical core10 RPCs: 0203 purchase order / GRN / quality check / post, 0206 approval request,
 * 0152 Master suppliers and items, Build01 context. One scoped read of stock locations goes through the existing
 * RLS policy location_scope_read (0002) because no location-list RPC exists yet. No other table access, no local
 * permission decision, no stored token, no simulated success: the server decides scope and Owner Control.
 */
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_PURCHASE_API = api;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const RPCS = new Set([
    "build01_context_v1", "procurement_save_po_v1", "procurement_advance_po_v1", "procurement_request_po_approval_v1",
    "procurement_receive_v1", "procurement_inspect_v1", "procurement_post_grn_v1", "procurement_list_pos_v1",
    "procurement_get_po_v1", "master_list_parties_v1", "master_list_items_v1"
  ]);
  // Read-only, RLS-scoped table reads (exact columns). Nothing else.
  const READS = { stock_locations: "id,site_id,code" };
  const STATUSES = ["draft", "approved", "partially_received", "received", "closed", "cancelled"];
  function fail(code, detail) { const e = new Error(code); e.code = code; if (detail) e.detail = detail; throw e; }
  // Bangla digits typed on a phone keyboard are accepted as the same number.
  const ascii = (x) => String(x == null ? "" : x).trim().replace(/[০-৯]/g, (d) => String("০১২৩৪৫৬৭৮৯".indexOf(d)));
  function posInt(x, code) {
    const s = ascii(x);
    if (!/^[1-9][0-9]*$/.test(s) || !Number.isSafeInteger(Number(s))) fail(code || "INVALID_ID");
    return Number(s);
  }
  const optInt = (x, code) => (x === null || x === undefined || x === "" ? null : posInt(x, code));
  function version(x) { const s = ascii(x); if (!/^[0-9]+$/.test(s) || !Number.isSafeInteger(Number(s))) fail("INVALID_VERSION"); return Number(s); }
  function qty(x, zeroOk) {
    const s = ascii(x); if (!/^[0-9]+(\.[0-9]{1,3})?$/.test(s)) fail("INVALID_QUANTITY");
    const n = Number(s); if ((!zeroOk && n <= 0) || n > 1000000) fail("INVALID_QUANTITY"); return n;
  }
  function price(x) { const s = ascii(x); if (!/^[0-9]+(\.[0-9]{1,2})?$/.test(s) || Number(s) > 1000000000) fail("INVALID_PRICE"); return Number(s); }
  function isoDate(x) {
    const s = ascii(x); if (!s) return null;
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(s) || isNaN(Date.parse(s + "T00:00:00Z"))) fail("INVALID_DATE"); return s;
  }
  function optText(x, max, code) { const s = typeof x === "string" ? x.trim() : ""; if (s.length > max) fail(code || "INVALID_TEXT"); return s || null; }
  function lot(x) { const s = ascii(x); if (!s) return null; if (!/^[A-Za-z0-9][A-Za-z0-9/_.-]{1,59}$/.test(s)) fail("INVALID_LOT"); return s; }
  const limit = (x, d) => { const n = Number(x || d); return Number.isInteger(n) && n >= 1 && n <= 200 ? n : d; };
  function newKey(prefix) {
    const c = globalThis.crypto;
    const raw = c && typeof c.randomUUID === "function" ? c.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    return (String(prefix || "pu") + "_" + raw).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 100);
  }
  function key(k, prefix) { const s = k == null ? newKey(prefix) : String(k); if (!/^[A-Za-z0-9_-]{8,100}$/.test(s)) fail("INVALID_KEY"); return s; }
  function errorCode(message) {
    const m = String(message || "").match(/^((?:PROC|CONTROL|MASTER|INV|SESSION|SIGNED|INVALID|RPC|BUILD01)_[A-Z0-9_]+)(?::(.*))?$/);
    if (m) return { code: m[1], detail: m[2] || null };
    return { code: "PROC_RPC_UNAVAILABLE", detail: String(message || "").slice(0, 160) };
  }
  // Exact money arithmetic for display: quantity (3 dp) x price (2 dp), rounded to paisa like the server.
  function lineAmount(q, p) {
    const qs = ascii(q), ps = ascii(p);
    if (!/^[0-9]+(\.[0-9]{1,3})?$/.test(qs) || !/^[0-9]+(\.[0-9]{1,2})?$/.test(ps)) return null;
    const milli = (s, dp) => { const [a, b = ""] = s.split("."); return BigInt(a + (b + "000").slice(0, dp)); };
    const v = milli(qs, 3) * milli(ps, 2); // units of 1e-5
    return (v + 500n) / 1000n; // paisa
  }
  const paisaText = (v) => { const s = (v < 0n ? -v : v).toString().padStart(3, "0"); return s.slice(0, -2) + "." + s.slice(-2); };

  function create(options) {
    const client = options && options.client; let sessionUser = null;
    async function currentUser() {
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function") fail("SIGNED_CLIENT_REQUIRED");
      const r = await client.auth.getUser(); const id = r && !r.error && r.data && r.data.user && r.data.user.id;
      if (typeof id !== "string" || !id) fail("SIGNED_SESSION_REQUIRED"); return id;
    }
    async function signed(fn) {
      const before = await currentUser();
      if (sessionUser && sessionUser !== before) { sessionUser = before; fail("SESSION_CHANGED"); }
      sessionUser = before;
      const schema = client.schema("core10"); if (!schema) fail("PROC_SCHEMA_UNAVAILABLE");
      const r = await fn(schema);
      const after = await currentUser(); if (after !== before) { sessionUser = after; fail("SESSION_CHANGED"); }
      if (!r || r.error) { const e = errorCode(r && r.error && r.error.message); fail(e.code, e.detail); }
      return r.data;
    }
    async function call(name, args) {
      if (!RPCS.has(name)) fail("RPC_NOT_ALLOWED");
      return signed((schema) => { if (typeof schema.rpc !== "function") fail("PROC_SCHEMA_UNAVAILABLE"); return schema.rpc(name, args || {}); });
    }
    function poLines(lines) {
      if (!Array.isArray(lines) || lines.length < 1 || lines.length > 200) fail("PROC_LINES_INVALID");
      const out = lines.map((l) => ({ item_id: posInt(l.item, "INVALID_ITEM"), quantity: qty(l.quantity), unit_price: price(l.unitPrice) }));
      if (new Set(out.map((l) => l.item_id)).size !== out.length) fail("PROC_LINES_DUPLICATE_ITEM");
      return out;
    }
    return {
      userId: () => sessionUser,
      context: async () => call("build01_context_v1", {}),
      suppliers: async (b, o) => call("master_list_parties_v1", { p_business: posInt(b), p_kind: "supplier", p_search: optText(o && o.search, 80),
        p_status: "active", p_limit: limit(o && o.limit, 200), p_after_id: optInt(o && o.after) }),
      items: async (b, o) => call("master_list_items_v1", { p_business: posInt(b), p_search: optText(o && o.search, 80), p_status: "active",
        p_category: null, p_limit: limit(o && o.limit, 200), p_after_id: optInt(o && o.after) }),
      locations: async (b, site) => signed((schema) => {
        if (typeof schema.from !== "function") fail("PROC_SCHEMA_UNAVAILABLE");
        return schema.from("stock_locations").select(READS.stock_locations).eq("business_id", posInt(b)).eq("site_id", posInt(site)).order("id").limit(200);
      }),
      list: async (b, o) => {
        const status = o && o.status ? String(o.status) : null; if (status && !STATUSES.includes(status)) fail("PROC_INVALID_FILTER");
        return call("procurement_list_pos_v1", { p_business: posInt(b), p_site: optInt(o && o.site), p_status: status,
          p_before_id: optInt(o && o.before), p_limit: limit(o && o.limit, 20) });
      },
      get: async (po) => call("procurement_get_po_v1", { p_po: posInt(po) }),
      savePo: async (b, o) => call("procurement_save_po_v1", { p_business: posInt(b), p_po: optInt(o.po), p_site: posInt(o.site, "INVALID_SITE"),
        p_supplier: posInt(o.supplier, "INVALID_SUPPLIER"), p_lines: poLines(o.lines), p_expected_on: isoDate(o.expectedOn),
        p_note: optText(o.note, 500, "INVALID_NOTE"), p_expected_version: version(o.po ? o.expectedVersion : 0), p_key: key(o.requestKey, "po") }),
      advance: async (po, action, v, k) => {
        if (!["approve", "cancel", "close"].includes(action)) fail("PROC_INVALID_ACTION");
        return call("procurement_advance_po_v1", { p_po: posInt(po), p_action: action, p_version: version(v), p_key: key(k, "po" + action) });
      },
      requestApproval: async (po, k) => call("procurement_request_po_approval_v1", { p_po: posInt(po), p_key: key(k, "poreq") }),
      receive: async (po, o) => {
        if (!Array.isArray(o.lines) || o.lines.length < 1) fail("PROC_LINES_INVALID");
        const lines = o.lines.map((l) => {
          const r = { line_no: posInt(l.lineNo), quantity: qty(l.quantity) }, c = lot(l.lot), m = isoDate(l.manufacturedOn), x = isoDate(l.expiresOn);
          if (c) r.lot_code = c; if (m) r.manufactured_on = m; if (x) r.expires_on = x; return r;
        });
        return call("procurement_receive_v1", { p_po: posInt(po), p_location: posInt(o.location, "INVALID_LOCATION"), p_lines: lines,
          p_supplier_ref: optText(o.supplierRef, 80, "INVALID_REFERENCE"), p_key: key(o.requestKey, "grn") });
      },
      inspect: async (grn, o) => call("procurement_inspect_v1", { p_grn: posInt(grn), p_lines: (o.lines || []).map((l) => ({ line_no: posInt(l.lineNo),
        accepted_qty: qty(l.accepted, true), notes: optText(l.notes, 500, "INVALID_NOTE") })), p_version: version(o.version), p_key: key(o.requestKey, "qc") }),
      post: async (grn, v, k) => call("procurement_post_grn_v1", { p_grn: posInt(grn), p_version: version(v), p_key: key(k, "grnpost") })
    };
  }
  return { create, errorCode, newKey, lineAmount, paisaText, ascii, STATUSES, RPCS: Array.from(RPCS), READS };
});
