// Read-only presentation fixture of the existing A049 SQL regression, never a posting engine.
// Numeric IDs and outcomes come from tests/c10_a018_demo_seed.sql and
// tests/c10_a049_operation_workflow_e2e.sql (60 received - 12 issued = 48).
export const SNAPSHOT_SCRIPT = String.raw`(function () {
  "use strict";
  var businesses = [
    { id: 101, tenant_id: 1, slug: "DEMO sweets · regression fixture" },
    { id: 102, tenant_id: 1, slug: "DEMO second business · regression fixture" }
  ];
  var locations = [
    { id: 5001, business_id: 101, site_id: 1001, code: "MAIN" },
    { id: 5002, business_id: 101, site_id: 1002, code: "MAIN" },
    { id: 5003, business_id: 102, site_id: 1003, code: "MAIN" }
  ];
  var items = [
    { id: 8001, business_id: 101, sku: "SWEETS" },
    { id: 8002, business_id: 102, sku: "OTHER" }
  ];
  var orders = [
    { id: 1, business_id: 101, location_id: 5001, item_id: 8001, kind: "purchase_receive", quantity: 60, estimate_total: 4200, status: "posted", version: 3 },
    { id: 2, business_id: 101, location_id: 5001, item_id: 8001, kind: "sale_issue", quantity: 12, estimate_total: 1500, status: "posted", version: 3 },
    { id: 3, business_id: 102, location_id: 5003, item_id: 8002, kind: "purchase_receive", quantity: 20, estimate_total: 900, status: "posted", version: 3 },
    { id: 4, business_id: 101, location_id: 5002, item_id: 8001, kind: "production_plan", quantity: 1, estimate_total: 100, status: "confirmed", version: 2 }
  ];
  function copy(x) { return JSON.parse(JSON.stringify(x)); }
  function scope(biz) {
    if (![101, 102].includes(Number(biz))) throw Error("PREVIEW_SCOPE_UNAVAILABLE");
    return Number(biz);
  }
  async function blocked() { throw Error("READ_ONLY_SNAPSHOT_NO_COMMAND_EXECUTION"); }
  function create() {
    return Object.freeze({
      businesses: async function () { return copy(businesses); },
      catalog: async function (biz) {
        biz = scope(biz);
        return copy({ locations: locations.filter(function (x) { return x.business_id === biz; }), items: items.filter(function (x) { return x.business_id === biz; }) });
      },
      read: async function (biz) {
        biz = scope(biz);
        var rows = orders.filter(function (x) { return x.business_id === biz; });
        if (document.getElementById("inventory")) {
          rows = rows.filter(function (x) { return x.kind !== "production_plan"; }).map(function (x) {
            return Object.assign({}, x, { kind: x.kind === "purchase_receive" ? "receive" : "issue", source_location: x.kind === "sale_issue" ? x.location_id : null, destination_location: x.kind === "purchase_receive" ? x.location_id : null });
          });
        }
        return copy({ business_id: biz, items: rows, preview_snapshot: true });
      },
      draft: blocked,
      advance: blocked
    });
  }
  // Presentation injection only: no auth.getUser(), token, RPC, network, or server impersonation.
  window.BOS_CONFIG = Object.freeze({ url: "preview-only://snapshot", key: "NO_AUTH_SESSION" });
  window.supabase = Object.freeze({ createClient: function () { return Object.freeze({ preview_snapshot: true }); } });
  window.CORE10_OPERATIONS_API = Object.freeze({ create: create });
  window.CORE10_INVENTORY_API = Object.freeze({ create: create });
  document.addEventListener("submit", function (event) { event.preventDefault(); event.stopImmediatePropagation(); }, true);
  function annotate() {
    document.querySelectorAll("#op-form input, #op-form select, #op-form button, #iv-form input, #iv-form select, #iv-form button, [data-action]").forEach(function (el) {
      el.disabled = true;
      el.title = "Read-only regression snapshot; command execution requires the isolated backend.";
    });
    ["op-status", "iv-status"].forEach(function (id) {
      var el = document.getElementById(id);
      var text = "Read-only A049 regression snapshot · synthetic data · no signed session or server request.";
      if (el && !el.dataset.error && el.textContent !== text) el.textContent = text;
      if (el && el.dataset.error === "false" && el.textContent !== text) el.textContent = text;
    });
    document.querySelectorAll('a[href="./core10-owner-portfolio.html"], a[href^="./owner.html"]').forEach(function (el) { el.href = "/"; });
    document.querySelectorAll("label").forEach(function (el) {
      if (el.firstChild && el.firstChild.nodeType === 3 && /^Authorized [Bb]usiness$/.test(el.firstChild.textContent)) el.firstChild.textContent = "Synthetic business fixture";
    });
  }
  new MutationObserver(annotate).observe(document.body, { subtree: true, childList: true });
})();`;

export const SNAPSHOT_CSS = `.preview-fixture-banner{position:relative;z-index:20;padding:16px 20px;background:#fffbf3;border-bottom:2px solid #d7b580;color:#423723;font:14px/1.6 system-ui,sans-serif}.preview-fixture-banner strong{display:block}.preview-fixture-banner p{margin:5px 0}.preview-fixture-banner a{color:#704052;font-weight:700;margin-right:16px}.preview-fixture-banner a:focus-visible{outline:3px solid #704052;outline-offset:3px}`;

export function snapshotHTML(html) {
  if (!html.includes('<script src="./config.js"></script>') ||
      !html.includes('<script src="./vendor/supabase.js"></script>') ||
      !/<script src="\.\/core10-(?:operational-flow|inventory-commands)-client\.js"><\/script>/.test(html) ||
      !html.includes("<body>")) {
    throw new Error("UNRECOGNIZED_ORIGINAL_MODULE_HTML");
  }
  return html
    .replace(/<script src="\.\/vendor\/supabase\.js"><\/script>/, "")
    .replace(/<script src="\.\/config\.js"><\/script>/, "")
    .replace(/<link rel="stylesheet" href="\.\/core10-control-studio.css">/, '<link rel="stylesheet" href="./core10-control-studio.css"><link rel="stylesheet" href="/preview-snapshot.css">')
    .replace(/<script src="\.\/core10-(?:operational-flow|inventory-commands)-client\.js"><\/script>/, '<script src="/preview-snapshot.js"></script>')
    .replace(/<body>/, `<body><section class="preview-fixture-banner" aria-label="Synthetic preview boundary"><strong>মূল মডিউল UI · Read-only synthetic regression snapshot</strong><p>মূল A048/A049 interface-এ একই SQL test-এর sample records দেখানো হচ্ছে। এই পাতায় login, stock posting বা financial posting হয় না। সব write control বন্ধ।</p><p>Purchase 60 − Sale 12 = expected stock 48; second business = 20. Production remains a plan; COGS and accounting remain uncertified.</p><a href="/">← Preview One</a><a href="/core10-operational-flow.html">Purchase &amp; Sales</a><a href="/core10-inventory-operations.html">Inventory</a></section>`);
}
