// Real Sweets Manufacturing workbench (Draft PR #112) on the read-only replay; same mount call as its repo harness.
// Recipe, approval, substitution, handoff and waste writes are refused as NOT_CONNECTED. Nothing is posted.
import { mountManufacturing } from "/live/modules/manufacturing/workbench.mjs";
const rec = window.CORE10_PREVIEW_MFG;
const replay = window.CORE10_PREVIEW_REPLAY(rec, /^mfg_(create_recipe|approve_recipe|define_substitution|request_handoff|record_material_waste)_v1$/, "NOT_CONNECTED");
mountManufacturing(document.querySelector("#manufacturing"), {
  synthetic: true,
  context: { tenant_id: 951, business_id: 9511, site_id: 9521, label: "Fictional Sandesh QA" },
  rpc: async (name, args) => { const r = await replay(name, args); return r.error ? { error: r.error } : { data: r.data }; },
});
