/* CORE 10 CENTRAL | B-011 Master Data client (NP02).
 * Calls only the canonical core10 master RPCs (0151 writers, 0152 readers). No table access, no local
 * permission decision, no stored token, no simulated success: the server decides scope and Owner Control.
 */
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_MASTER_DATA_API = api;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const RPCS = new Set([
    "build01_context_v1", "master_list_items_v1", "master_get_item_v1", "master_list_categories_v1", "master_list_uoms_v1",
    "master_list_parties_v1", "master_list_price_lists_v1", "master_get_price_list_v1", "master_find_barcode_v1",
    "master_save_item_v1", "master_save_party_v1", "master_save_uom_v1", "master_save_uom_conversion_v1",
    "master_save_variant_v1", "master_save_barcode_v1", "master_save_price_list_v1", "master_save_price_v1"
  ]);
  function fail(code, detail) { const e = new Error(code); e.code = code; if (detail) e.detail = detail; throw e; }
  function posInt(x, code) {
    if (!(typeof x === "number" || typeof x === "string") || !/^[1-9][0-9]*$/.test(String(x)) || !Number.isSafeInteger(Number(x))) fail(code || "INVALID_ID");
    return Number(x);
  }
  function optInt(x, code) { return x === null || x === undefined || x === "" ? null : posInt(x, code); }
  function version(x) { if (x === 0 || x === "0") return 0; return posInt(x, "INVALID_VERSION"); }
  function text(x, max, code) {
    const s = typeof x === "string" ? x.trim() : "";
    if (!s || s.length > max) fail(code); return s;
  }
  function optText(x, max) { const s = typeof x === "string" ? x.trim() : ""; return s ? s.slice(0, max) : null; }
  function decimals(x) { const n = Number(x); if (!Number.isInteger(n) || n < 0 || n > 6) fail("INVALID_DECIMALS"); return n; }
  function factor(x) { const s = String(x == null ? "" : x).trim(); if (!/^[0-9]+(\.[0-9]{1,12})?$/.test(s) || Number(s) <= 0) fail("INVALID_FACTOR"); return s; }
  function amount(x, zeroOk) { const s = String(x == null ? "" : x).trim(); if (!/^[0-9]+(\.[0-9]{1,6})?$/.test(s) || (!zeroOk && s === "") ) fail("INVALID_AMOUNT"); return s; }
  function isoDate(x, required) { const s = typeof x === "string" ? x.trim() : ""; if (!s) { if (required) fail("INVALID_DATE"); return null; }
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(s) || isNaN(Date.parse(s + "T00:00:00Z"))) fail("INVALID_DATE"); return s; }
  function limit(x) { const n = Number(x || 50); return Number.isInteger(n) && n >= 1 && n <= 200 ? n : 50; }
  function newKey(prefix) {
    const c = globalThis.crypto;
    const raw = c && typeof c.randomUUID === "function" ? c.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    return (String(prefix || "md") + "_" + raw).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 100);
  }
  function errorCode(message) {
    const m = String(message || "").match(/^((?:MASTER|CONTROL|SESSION|SIGNED|INVALID|RPC)_[A-Z_]+)(?::(.*))?$/);
    if (/master_uom_conversions_v1_from_uom_id_tenant_id_business_id_dimension_fkey|master_uom_conversions_v1_to_uom/.test(String(message))) return { code: "MASTER_UOM_DIMENSION_MISMATCH", detail: null };
    if (m) return { code: m[1], detail: m[2] || null };
    if (/duplicate key/.test(String(message))) return { code: "MASTER_DUPLICATE", detail: null };
    if (/check constraint|violates|invalid input/.test(String(message))) return { code: "MASTER_INVALID_VALUE", detail: null };
    return { code: "MASTER_RPC_UNAVAILABLE", detail: String(message || "").slice(0, 160) };
  }
  function create(options) {
    const client = options && options.client; let sessionUser = null;
    async function currentUser() {
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function") fail("SIGNED_CLIENT_REQUIRED");
      const r = await client.auth.getUser(); const id = r && !r.error && r.data && r.data.user && r.data.user.id;
      if (typeof id !== "string" || !id) fail("SIGNED_SESSION_REQUIRED"); return id;
    }
    async function call(name, args) {
      if (!RPCS.has(name)) fail("RPC_NOT_ALLOWED");
      const before = await currentUser();
      if (sessionUser && sessionUser !== before) { sessionUser = before; fail("SESSION_CHANGED"); }
      sessionUser = before;
      const schema = client.schema("core10"); if (!schema || typeof schema.rpc !== "function") fail("MASTER_SCHEMA_UNAVAILABLE");
      const r = await schema.rpc(name, args || {});
      const after = await currentUser(); if (after !== before) { sessionUser = after; fail("SESSION_CHANGED"); }
      if (!r || r.error) { const e = errorCode(r && r.error && r.error.message); fail(e.code, e.detail); }
      return r.data;
    }
    const B = (b) => posInt(b, "INVALID_BUSINESS_ID");
    return {
      userId: () => sessionUser,
      context: async () => call("build01_context_v1", {}),
      items: async (b, o) => call("master_list_items_v1", { p_business: B(b), p_search: optText(o && o.search, 80), p_status: optText(o && o.status, 16),
        p_category: optInt(o && o.category), p_limit: limit(o && o.limit), p_after_id: optInt(o && o.after) }),
      item: async (b, id) => call("master_get_item_v1", { p_business: B(b), p_item: posInt(id) }),
      categories: async (b) => call("master_list_categories_v1", { p_business: B(b) }),
      uoms: async (b) => call("master_list_uoms_v1", { p_business: B(b) }),
      parties: async (b, o) => call("master_list_parties_v1", { p_business: B(b), p_kind: optText(o && o.kind, 16), p_search: optText(o && o.search, 80),
        p_status: optText(o && o.status, 16), p_limit: limit(o && o.limit), p_after_id: optInt(o && o.after) }),
      priceLists: async (b, kind) => call("master_list_price_lists_v1", { p_business: B(b), p_kind: optText(kind, 16) }),
      priceList: async (b, id, o) => call("master_get_price_list_v1", { p_business: B(b), p_price_list: posInt(id), p_limit: limit(o && o.limit), p_after_id: optInt(o && o.after) }),
      barcode: async (b, code) => call("master_find_barcode_v1", { p_business: B(b), p_barcode: text(code, 64, "INVALID_BARCODE") }),
      saveItem: async (b, o) => call("master_save_item_v1", { p_business: B(b), p_sku: text(o.sku, 64, "INVALID_SKU"), p_name_en: text(o.nameEn, 160, "INVALID_NAME"),
        p_name_bn: optText(o.nameBn, 160), p_item_kind: optText(o.kind, 20), p_category: optInt(o.category), p_base_uom: optInt(o.baseUom),
        p_status: optText(o.status, 16), p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("item") }),
      saveParty: async (b, o) => call("master_save_party_v1", { p_business: B(b), p_code: text(o.code, 32, "INVALID_CODE"), p_party_kind: text(o.kind, 16, "INVALID_KIND"),
        p_name_en: text(o.nameEn, 160, "INVALID_NAME"), p_name_bn: optText(o.nameBn, 160), p_phone: optText(o.phone, 24), p_tax_id: optText(o.taxId, 40),
        p_status: optText(o.status, 16), p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("party") }),
      saveUom: async (b, o) => call("master_save_uom_v1", { p_business: B(b), p_code: text(o.code, 16, "INVALID_CODE"), p_name_en: text(o.nameEn, 80, "INVALID_NAME"),
        p_name_bn: optText(o.nameBn, 80), p_dimension: text(o.dimension, 16, "INVALID_DIMENSION"), p_decimals: decimals(o.decimals), p_active: o.active !== false,
        p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("uom") }),
      saveConversion: async (b, o) => call("master_save_uom_conversion_v1", { p_business: B(b), p_from_uom: posInt(o.from), p_to_uom: posInt(o.to),
        p_factor: factor(o.factor), p_active: o.active !== false, p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("conv") }),
      saveVariant: async (b, o) => call("master_save_variant_v1", { p_business: B(b), p_item: posInt(o.item), p_code: text(o.code, 64, "INVALID_CODE"),
        p_name_en: text(o.nameEn, 160, "INVALID_NAME"), p_name_bn: optText(o.nameBn, 160), p_attributes: {}, p_status: optText(o.status, 16),
        p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("var") }),
      saveBarcode: async (b, o) => call("master_save_barcode_v1", { p_business: B(b), p_barcode: text(o.barcode, 64, "INVALID_BARCODE"), p_item: posInt(o.item),
        p_variant: optInt(o.variant), p_uom: optInt(o.uom), p_active: o.active !== false, p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("bc") }),
      savePriceList: async (b, o) => call("master_save_price_list_v1", { p_business: B(b), p_code: text(o.code, 32, "INVALID_CODE"), p_name_en: text(o.nameEn, 120, "INVALID_NAME"),
        p_name_bn: optText(o.nameBn, 120), p_list_kind: text(o.kind, 16, "INVALID_KIND"), p_currency: text(o.currency, 3, "INVALID_CURRENCY"), p_site: optInt(o.site),
        p_effective_from: isoDate(o.from, true), p_effective_to: isoDate(o.to, false), p_status: optText(o.status, 16),
        p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("pl") }),
      savePrice: async (b, o) => call("master_save_price_v1", { p_business: B(b), p_price_list: posInt(o.priceList), p_item: posInt(o.item), p_variant: optInt(o.variant),
        p_uom: posInt(o.uom), p_min_quantity: amount(o.minQuantity, true), p_unit_price: amount(o.unitPrice, false), p_active: o.active !== false,
        p_expected_version: version(o.expectedVersion), p_request_key: o.requestKey || newKey("price") })
    };
  }
  return { create, errorCode, newKey, RPCS: Array.from(RPCS) };
});
