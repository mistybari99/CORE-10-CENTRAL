/* C10-A056 signed RPC client for the CRM lifecycle backend (schema c10_demo). Same signed-session pattern as A050:
   the supplied Supabase-style client must be signed in; authorization is ALWAYS decided by the database.
   Also exports hmacSign()/hmacVerify() for staging gateways that sign request envelopes (not an auth substitute). */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_CRM_API = api;
})(typeof window !== "undefined" ? window : globalThis, function (root) {
  "use strict";
  const REQ = /^[A-Za-z0-9_-]{8,100}$/;
  function fail(code, msg) { const e = new Error(msg || code); e.code = code; throw e; }
  /* arg types: id, id?, text, text?, int, int?, num?, bool, bool?, ts?, date?, json, json?, uuid?, tags?, req */
  const S = (spec) => spec.split(",").filter(Boolean).map((x) => { const [n, t] = x.split(":"); return [n, t]; });
  const RPC = {
    readSettings: ["a056_read_settings_v1", "business:id", 0], setSettings: ["a056_set_settings_v1", "business:id,enabled:bool,config:json?,expected:int,request:req,reason:text?", 1],
    listSettingsHistory: ["a056_list_settings_history_v1", "business:id,limit:int?", 0], readMyAccess: ["a056_read_my_access_v1", "business:id", 0], listAudit: ["a056_list_audit_v1", "business:id,entity:text?,limit:int?", 0],
    createCustomer: ["a056_create_customer_v1", "business:id,site:id?,kind:text,display_name:text,legal_name:text?,email:text?,phone:text?,tags:tags?,request:req", 1],
    updateCustomer: ["a056_update_customer_v1", "customer:id,patch:json,expected:int,request:req", 1], listCustomers: ["a056_list_customers_v1", "business:id,search:text?,status:text?,limit:int?,offset:int?", 0],
    readCustomer360: ["a056_read_customer360_v1", "customer:id", 0], addContact: ["a056_add_contact_v1", "customer:id,name:text,role:text?,email:text?,phone:text?,primary:bool?,request:req", 1],
    deactivateContact: ["a056_deactivate_contact_v1", "contact:id,expected:int,request:req", 1],
    logContact: ["a056_log_contact_v1", "customer:id,lead:id?,opportunity:id?,type:text,direction:text,summary:text,occurred_at:ts?,request:req", 1],
    scanDuplicates: ["a056_scan_duplicates_v1", "business:id,request:req", 1], listDuplicateCandidates: ["a056_list_duplicate_candidates_v1", "business:id,status:text?,limit:int?,offset:int?", 0],
    dismissDuplicate: ["a056_dismiss_duplicate_v1", "candidate:id,request:req", 1],
    mergeCustomers: ["a056_merge_customers_v1", "survivor:id,loser:id,expected_survivor:int,expected_loser:int,request:req,reason:text", 1],
    recordConsent: ["a056_record_consent_v1", "customer:id,channel:text,purpose:text,status:text,source:text,valid_until:ts?,lift_suppression:bool?,request:req", 1],
    checkConsent: ["a056_check_consent_v1", "customer:id,channel:text,purpose:text", 0], setCommPrefs: ["a056_set_comm_prefs_v1", "customer:id,preferred_channel:text,language:text,request:req", 1],
    createLead: ["a056_create_lead_v1", "business:id,site:id?,source:text,name:text?,email:text?,phone:text?,note:text?,customer:id?,request:req", 1],
    qualifyLead: ["a056_qualify_lead_v1", "lead:id,decision:text,reason:text?,expected:int,request:req", 1], listLeads: ["a056_list_leads_v1", "business:id,status:text?,limit:int?,offset:int?", 0],
    createEnquiry: ["a056_create_enquiry_v1", "business:id,site:id?,channel:text,subject:text,body:text?,customer:id?,lead:id?,request:req", 1],
    triageEnquiry: ["a056_triage_enquiry_v1", "enquiry:id,action:text,customer:id?,expected:int,request:req", 1], listEnquiries: ["a056_list_enquiries_v1", "business:id,status:text?,limit:int?,offset:int?", 0],
    createOpportunity: ["a056_create_opportunity_v1", "business:id,site:id?,customer:id,lead:id?,enquiry:id?,title:text,expected_value:num?,expected_close:date?,owner:uuid?,request:req", 1],
    moveOpportunityStage: ["a056_move_opportunity_stage_v1", "opp:id,stage:text,expected:int,reason:text?,request:req", 1], listOpportunities: ["a056_list_opportunities_v1", "business:id,stage:text?,status:text?,limit:int?,offset:int?", 0],
    readPipeline: ["a056_read_pipeline_v1", "business:id", 0],
    createQuotation: ["a056_create_quotation_v1", "opp:id,lines:json,valid_until:date?,notes:text?,request:req", 1],
    reviseQuotation: ["a056_revise_quotation_v1", "quotation:id,lines:json,valid_until:date?,notes:text?,expected_version:int,request:req", 1],
    decideQuotation: ["a056_decide_quotation_v1", "quotation:id,version_no:int,decision:text,note:text?,request:req", 1], readQuotation: ["a056_read_quotation_v1", "quotation:id", 0],
    listQuotations: ["a056_list_quotations_v1", "business:id,status:text?,limit:int?,offset:int?", 0],
    convertQuoteToOrder: ["a056_convert_quote_to_order_v1", "quotation:id,version_no:int,location:id,request:req", 1],
    testAdapterCreateOrder: ["a056_test_adapter_create_order_v1", "quotation:id,version_no:int,location:id,request:req", 1],
    readOrderLinks: ["a056_read_order_links_v1", "business:id,customer:id?", 0], readPurchaseHistory: ["a056_read_purchase_history_v1", "customer:id", 0],
    registerFinanceSource: ["a056_register_finance_source_v1", "business:id,read_fn:text,certification_ref:text?,certified:bool,expected:int,request:req", 1],
    readCustomerFinance: ["a056_read_customer_finance_v1", "customer:id", 0],
    createTicket: ["a056_create_ticket_v1", "business:id,site:id?,customer:id,kind:text,priority:text,subject:text,description:text?,order_link:id?,request:req", 1],
    updateTicket: ["a056_update_ticket_v1", "ticket:id,action:text,assignee:uuid?,note:text?,evidence:text?,expected:int,request:req", 1], listTickets: ["a056_list_tickets_v1", "business:id,status:text?,limit:int?,offset:int?", 0],
    createFollowup: ["a056_create_followup_v1", "business:id,site:id?,customer:id?,opportunity:id?,ticket:id?,due_at:ts,note:text?,assignee:uuid?,request:req", 1],
    completeFollowup: ["a056_complete_followup_v1", "followup:id,outcome:text,note:text?,expected:int,request:req", 1], listFollowups: ["a056_list_followups_v1", "business:id,status:text?,due_before:ts?,limit:int?,offset:int?", 0],
    saveSegment: ["a056_save_segment_v1", "business:id,segment:id?,name:text,definition:json,expected:int?,request:req", 1], listSegments: ["a056_list_segments_v1", "business:id", 0], evaluateSegment: ["a056_evaluate_segment_v1", "segment:id", 0],
    createCampaign: ["a056_create_campaign_v1", "business:id,name:text,channel:text,segment:id,template:text?,request:req", 1], dispatchCampaign: ["a056_dispatch_campaign_v1", "campaign:id,request:req", 1],
    listCampaigns: ["a056_list_campaigns_v1", "business:id,limit:int?", 0], readCampaign: ["a056_read_campaign_v1", "campaign:id", 0],
    createIntakeEndpoint: ["a056_create_intake_endpoint_v1", "business:id,site:id?,channel:text,label:text,rate_limit_per_hour:int,request:req", 1],
    revokeIntakeEndpoint: ["a056_revoke_intake_endpoint_v1", "endpoint:id,request:req", 1], listIntakeEndpoints: ["a056_list_intake_endpoints_v1", "business:id", 0],
    reportDashboard: ["a056_report_dashboard_v1", "business:id,from:ts?,to:ts?", 0], reportFunnel: ["a056_report_funnel_v1", "business:id,from:ts?,to:ts?", 0],
    reportRetention: ["a056_report_retention_v1", "business:id,months:int?", 0], reportRepeatBusiness: ["a056_report_repeat_business_v1", "business:id", 0],
    reportFollowups: ["a056_report_followups_v1", "business:id", 0], reportTickets: ["a056_report_tickets_v1", "business:id,from:ts?,to:ts?", 0],
    exportCustomer: ["a056_export_customer_v1", "customer:id,request:req", 1], exportCustomersCsv: ["a056_export_customers_csv_v1", "business:id", 0],
    redactCustomer: ["a056_redact_customer_v1", "customer:id,expected:int,reason:text,request:req", 1]
  };
  const PUBLIC = { publicIntake: ["a056_public_intake_v1", "token:text,idempotency:req,payload:json", 1] };
  const TYPES = {
    id: (v) => Number.isSafeInteger(Number(v)) && Number(v) >= 1, int: (v) => Number.isSafeInteger(Number(v)), num: (v) => Number.isFinite(Number(v)) && Number(v) >= 0,
    bool: (v) => typeof v === "boolean", text: (v) => typeof v === "string" && v.length <= 20000, ts: (v) => !Number.isNaN(Date.parse(v)),
    date: (v) => /^\d{4}-\d{2}-\d{2}$/.test(v), json: (v) => v !== null && typeof v === "object", uuid: (v) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v),
    tags: (v) => Array.isArray(v) && v.length <= 20 && v.every((x) => typeof x === "string"), req: (v) => REQ.test(v)
  };
  function build(spec, args) {
    const out = {};
    for (const [name, t] of S(spec)) {
      const opt = t.endsWith("?"), base = opt ? t.slice(0, -1) : t, v = args[name];
      if (v === undefined || v === null) { if (!opt) fail("INVALID_ARG:" + name); out["p_" + name] = null; continue; }
      if (!TYPES[base](v)) fail("INVALID_ARG:" + name);
      out["p_" + name] = (base === "id" || base === "int") ? Number(v) : v;
    }
    for (const k of Object.keys(args)) if (!S(spec).some(([n]) => n === k)) fail("UNKNOWN_ARG:" + k);
    return out;
  }
  function create({ client } = {}) {
    async function schema() {
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function") fail("SIGNED_CLIENT_REQUIRED");
      const u = await client.auth.getUser();
      if (!u || u.error || !u.data || !u.data.user || !u.data.user.id) fail("SIGN_IN_REQUIRED");
      const s = client.schema("c10_demo"); if (!s || typeof s.rpc !== "function") fail("SCHEMA_MISSING"); return s;
    }
    async function call(name, params, expectText) {
      const r = await (await schema()).rpc(name, params);
      if (!r || r.error) { const m = (r && r.error && r.error.message) || "RPC_FAILED"; const e = new Error(m); const code = /A056_[A-Z0-9_]+/.exec(m); e.code = code ? code[0] : ((r && r.error && r.error.code) || "RPC_FAILED"); e.raw = m; throw e; }
      if (expectText) { if (typeof r.data !== "string") fail("UNVERIFIED_RESPONSE"); return r.data; }
      if (r.data === null || typeof r.data !== "object") fail("UNVERIFIED_RESPONSE");
      return r.data;
    }
    const api = {};
    for (const [method, [name, spec, write]] of Object.entries(RPC)) {
      api[method] = async (args) => {
        const a = Object.assign({}, args || {});
        if (write && a.request === undefined && spec.includes("request:req")) fail("INVALID_ARG:request"); // callers must supply a stable key so retries are idempotent
        return call(name, build(spec, a), name === "a056_export_customers_csv_v1");
      };
    }
    api.test = () => ({ simulated_adapter: true });
    api.release = () => ({ live: false, production: false, source: "c10_demo", provider: "NOOP" });
    return Object.freeze(api);
  }
  /* anonymous public intake: token-gated, no sign-in. Pass an anon-role client */
  function createPublic({ client } = {}) {
    return Object.freeze({
      async submit({ token, idempotency, payload }) {
        if (!client || typeof client.schema !== "function") fail("CLIENT_REQUIRED");
        const p = build(PUBLIC.publicIntake[1], { token, idempotency, payload });
        const r = await client.schema("c10_demo").rpc("a056_public_intake_v1", p);
        if (!r || r.error) { const m = (r && r.error && r.error.message) || "RPC_FAILED"; const e = new Error(m); const c = /A056_[A-Z0-9_]+/.exec(m); e.code = c ? c[0] : "RPC_FAILED"; throw e; }
        if (!r.data || !["RECEIVED", "DRAFT"].includes(r.data.status)) fail("UNVERIFIED_RESPONSE");
        return r.data;
      }
    });
  }
  /* HMAC-SHA256 request envelope helpers (WebCrypto; Node 20+ and browsers) */
  async function hmacSign(secret, method, path, body, ts) {
    const subtle = (root.crypto || require("node:crypto").webcrypto).subtle, enc = new TextEncoder();
    const key = await subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const msg = [String(method).toUpperCase(), path, String(ts), typeof body === "string" ? body : JSON.stringify(body || {})].join("\n");
    const sig = new Uint8Array(await subtle.sign("HMAC", key, enc.encode(msg)));
    return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
  }
  async function hmacVerify(secret, method, path, body, ts, signature, nowMs, skewMs) {
    if (Math.abs((nowMs || Date.now()) - Number(ts)) > (skewMs || 300000)) return false;
    const expect = await hmacSign(secret, method, path, body, ts);
    if (expect.length !== String(signature).length) return false;
    let d = 0; for (let i = 0; i < expect.length; i++) d |= expect.charCodeAt(i) ^ String(signature).charCodeAt(i); return d === 0;
  }
  const RPC_NAMES = Object.values(RPC).map((x) => x[0]).concat(PUBLIC.publicIntake[0]);
  return Object.freeze({ create, createPublic, hmacSign, hmacVerify, RPC_NAMES, schema: "c10_demo" });
});
