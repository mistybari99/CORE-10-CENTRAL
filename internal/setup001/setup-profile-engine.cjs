"use strict";
/* CORE 10 Build 04 — isolated profile/preflight adapter for existing A020/Build01.
 * Never creates a tenant, writes stock/finance, grants a role, or authorizes activation.
 * Original Islamia workspace remains untouched (D051, REV-009, R130).
 */
const DEFAULT_REGISTRY = require("./profiles-v1.json");
const INDUSTRIES = Object.freeze([
  "sweets_bakery","restaurant","paint_hardware","retail_wholesale",
  "general_manufacturing","construction","import_export","ecommerce",
  "technology_digital","services"
]);
const SITE_KINDS = Object.freeze(["showroom","factory","godown","warehouse","project"]);
const GATES = Object.freeze([
  "canonical_scope_signed","backend_template_certified","transaction_receipt",
  "idempotent_replay","site_location_links","effective_grants",
  "authenticated_negative_e2e","jurisdiction_review","recovery_test"
]);
function fail(code) { const e = new Error(code); e.code = code; throw e; }
function object(x) { return !!x && typeof x === "object" && !Array.isArray(x); }
function only(x, keys, code) {
  if (!object(x) || Object.keys(x).some(k => !keys.includes(k))) fail(code);
}
function nonempty(x, limit, code) {
  if (typeof x !== "string" || !x.trim() || x.trim().length > limit) fail(code);
  return x.trim();
}
function identifier(x, code) {
  if ((typeof x !== "string" && typeof x !== "number") ||
      !/^[1-9]\d*$/.test(String(x)) || !Number.isSafeInteger(Number(x))) fail(code);
  return Number(x);
}
function validateRegistry(registry = DEFAULT_REGISTRY) {
  only(registry, ["registry_version","status","version_policy","profiles"],"SETUP_REGISTRY_INVALID");
  if (registry.registry_version !== 1 ||
      registry.status !== "ADVISORY_ONLY_NOT_ACTIVATION_AUTHORITY" ||
      !Array.isArray(registry.profiles) || registry.profiles.length !== INDUSTRIES.length)
    fail("SETUP_REGISTRY_INVALID");
  const seen = new Set();
  for (const p of registry.profiles) {
    only(p, ["industry_id","profile_version","site_kind_hints","first_site_hint",
      "site_hints_advisory","automatic_modules","automatic_roles",
      "jurisdiction_policy","financial_policy","release_state"],"SETUP_PROFILE_INVALID");
    if (!INDUSTRIES.includes(p.industry_id) || seen.has(p.industry_id) ||
        !Number.isSafeInteger(p.profile_version) || p.profile_version < 1 ||
        !Array.isArray(p.site_kind_hints) || !p.site_kind_hints.length ||
        new Set(p.site_kind_hints).size !== p.site_kind_hints.length ||
        p.site_kind_hints.some(k => !SITE_KINDS.includes(k)) ||
        !p.site_kind_hints.includes(p.first_site_hint) ||
        p.site_hints_advisory !== true ||
        !Array.isArray(p.automatic_modules) || p.automatic_modules.length ||
        !Array.isArray(p.automatic_roles) || p.automatic_roles.length ||
        p.release_state !== "BLOCKED_UNTIL_CERTIFIED" ||
        p.financial_policy !== "UNSPECIFIED_NO_DEFAULTS" ||
        p.jurisdiction_policy !== "REQUIRES_OWNER_AND_DOMAIN_VALIDATION")
      fail("SETUP_PROFILE_INVALID");
    seen.add(p.industry_id);
  }
  return true;
}
function profileFor(industryId, registry = DEFAULT_REGISTRY) {
  validateRegistry(registry);
  const p = registry.profiles.find(x => x.industry_id === industryId);
  if (!p) fail("SETUP_UNKNOWN_INDUSTRY");
  return p;
}
function normalizeDraft(raw, registry = DEFAULT_REGISTRY) {
  only(raw, ["industryId","profileVersion","legalId","name","slug","brandHex",
    "mode","sites","requestedModules","localeCode","jurisdictionCode"],"SETUP_DRAFT_INVALID");
  const profile = profileFor(raw.industryId, registry);
  if (raw.profileVersion !== profile.profile_version) fail("SETUP_PROFILE_VERSION_MISMATCH");
  const legalId = identifier(raw.legalId, "SETUP_LEGAL_ID_INVALID");
  const name = nonempty(raw.name, 120, "SETUP_NAME_INVALID");
  const slug = nonempty(raw.slug, 80, "SETUP_SLUG_INVALID").toLowerCase();
  if (!/^[a-z][a-z0-9-]{0,79}$/.test(slug)) fail("SETUP_SLUG_INVALID");
  if (typeof raw.brandHex !== "string" || !/^#[0-9a-fA-F]{6}$/.test(raw.brandHex))
    fail("SETUP_BRAND_INVALID");
  if (!["quick","advanced"].includes(raw.mode)) fail("SETUP_MODE_INVALID");
  if (!Array.isArray(raw.sites) || raw.sites.length > 500 ||
      (raw.mode === "quick" && raw.sites.length) ||
      (raw.mode === "advanced" && !raw.sites.length))
    fail("SETUP_SITES_INVALID");
  const seen = new Set(), sites = raw.sites.map(s => {
    only(s, ["kind","label"],"SETUP_SITE_INVALID");
    if (!SITE_KINDS.includes(s.kind)) fail("SETUP_SITE_INVALID");
    const label = nonempty(s.label, 120, "SETUP_SITE_INVALID");
    const key = s.kind + ":" + label.toLocaleLowerCase("en");
    if (seen.has(key)) fail("SETUP_SITE_DUPLICATE");
    seen.add(key);
    return {kind:s.kind,label};
  });
  const modules = raw.requestedModules === undefined ? [] : raw.requestedModules;
  if (!Array.isArray(modules) || modules.length > 80 ||
      new Set(modules).size !== modules.length ||
      modules.some(x => typeof x !== "string" || !/^[a-z][a-z0-9_.-]{0,79}$/.test(x)))
    fail("SETUP_MODULES_INVALID");
  const localeCode = raw.localeCode === undefined ? null : nonempty(raw.localeCode, 16, "SETUP_LOCALE_INVALID");
  const jurisdictionCode = raw.jurisdictionCode === undefined ? null :
    nonempty(raw.jurisdictionCode, 24, "SETUP_JURISDICTION_INVALID");
  if (localeCode !== null && !/^[a-z]{2,3}(?:-[A-Z]{2})?$/.test(localeCode))
    fail("SETUP_LOCALE_INVALID");
  if (jurisdictionCode !== null && !/^[A-Z]{2}(?:-[A-Z0-9]{1,12})?$/.test(jurisdictionCode))
    fail("SETUP_JURISDICTION_INVALID");
  return {
    contract:"C10_SETUP001_PREFLIGHT_V1",industry_id:profile.industry_id,
    profile_version:profile.profile_version,legal_id:legalId,name,slug,
    brand_hex:raw.brandHex.toUpperCase(),mode:raw.mode,sites,
    requested_modules:[...modules],locale_code:localeCode,jurisdiction_code:jurisdictionCode,
    recommendations:{first_site_kind:profile.first_site_hint,
      allowed_site_hints:[...profile.site_kind_hints],mode_does_not_reduce_entitlements:true},
    requires_backend_scope_check:true,may_create:false,may_activate:false
  };
}
/* B1's signed server context is used as INPUT ONLY. B1 RPC must independently
 * verify actor/legal/template/receipt in the database; this function is not auth.
 */
function toBuild01Request(plan, context, requestKey) {
  if (!object(plan) || plan.contract !== "C10_SETUP001_PREFLIGHT_V1" ||
      plan.may_create !== false || plan.may_activate !== false) fail("SETUP_PLAN_INVALID");
  only(context, ["legal_entities","templates"],"SETUP_CONTEXT_INVALID");
  if (!Array.isArray(context.legal_entities) || !Array.isArray(context.templates))
    fail("SETUP_CONTEXT_INVALID");
  const key = nonempty(requestKey, 120, "SETUP_REQUEST_KEY_INVALID");
  if (!/^[a-zA-Z0-9_-]{12,120}$/.test(key)) fail("SETUP_REQUEST_KEY_INVALID");
  const legal = context.legal_entities.find(x => object(x) && Number(x.id) === plan.legal_id);
  if (!legal) fail("SETUP_CONTEXT_LEGAL_NOT_PRESENT");
  // Require an explicit, backend-supplied and APPROVED industry→template binding.
  // Exactly Build01 build01_context_v1() fields (code, draft_supported, source_status).
  // A draft-supported template is NOT an enterprise-certified running engine.
  const template = context.templates.find(x => object(x) &&
    x.code === plan.industry_id && x.draft_supported === true &&
    typeof x.source_status === "string" &&
    /^[a-z][a-z0-9_]{1,79}$/.test(x.code));
  if (!template) fail("SETUP_CONTEXT_TEMPLATE_UNAVAILABLE");
  // Exactly the eight fields accepted by core10-build01-client.js setup().
  // Do not pass proposed modules, locale, jurisdiction or advisory metadata.
  return {
    legalId:plan.legal_id,slug:plan.slug,template:template.code,
    displayName:plan.name,mode:plan.mode,
    sites:plan.sites.map(x => ({...x})),requestKey:key,brandHex:plan.brand_hex
  };
}
function assessActivation(evidence) {
  // Even all caller-reported booleans are not a signed deployment receipt.
  only(evidence, GATES, "SETUP_EVIDENCE_INVALID");
  const checks = GATES.map(gate => ({
    gate,status:evidence[gate] === true ? "REPORTED_UNVERIFIED" : "BLOCKED_OR_MISSING"
  }));
  return {contract:"C10_SETUP001_ACTIVATION_REPORT_V1",checks,
    missing:checks.filter(x => x.status === "BLOCKED_OR_MISSING").map(x => x.gate),
    can_activate:false,certified:false,
    next_gate:"SIGNED_BACKEND_EVIDENCE_AND_SEPARATE_RELEASE_AUTHORITY"};
}
function legacyImportPreview(rows, knownBusinessId, knownSiteIds = []) {
  if (!Array.isArray(rows) || rows.length > 1000 || !Array.isArray(knownSiteIds))
    fail("SETUP_LEGACY_PREVIEW_INVALID");
  const business = identifier(knownBusinessId,"SETUP_LEGACY_BUSINESS_INVALID");
  const ids = new Set(knownSiteIds.map(x => identifier(x,"SETUP_LEGACY_SITE_ID_INVALID")));
  const seen = new Set();
  const results = rows.map((r, index) => {
    only(r, ["legacy_id","business_id","target_site_id","label"],"SETUP_LEGACY_ROW_INVALID");
    const source = nonempty(r.legacy_id, 120,"SETUP_LEGACY_ROW_INVALID");
    const id = r.target_site_id == null ? null : identifier(r.target_site_id,"SETUP_LEGACY_ROW_INVALID");
    const rowBusiness = identifier(r.business_id,"SETUP_LEGACY_ROW_INVALID");
    let status = "UNMAPPED_NEEDS_EXPLICIT_CROSSWALK";
    if (seen.has(source)) status = "BLOCKED_DUPLICATE_SOURCE";
    else if (rowBusiness !== business) status = "BLOCKED_FOREIGN_BUSINESS";
    else if (id !== null && ids.has(id)) status = "MAPPED_ID_REVIEW_REQUIRED";
    else if (id !== null) status = "BLOCKED_UNKNOWN_TARGET_ID";
    seen.add(source);
    return {index,legacy_id:source,target_site_id:id,status};
  });
  return {contract:"C10_SETUP001_LEGACY_DRY_RUN_V1",business_id:business,
    results,can_import:false,write_count:0};
}
function make303SiteFixture() {
  const kinds = ["showroom","factory","godown"];
  const sites = kinds.flatMap(kind => Array.from({length:100},(_,i) => ({
    kind,label:"DEMO-" + kind.toUpperCase() + "-" + String(i+1).padStart(3,"0")
  })));
  for (let i=1;i<=3;i++) sites.push({kind:"project",label:"DEMO-PROJECT-" + i});
  return sites;
}
module.exports = Object.freeze({INDUSTRIES,SITE_KINDS,GATES,validateRegistry,
  profileFor,normalizeDraft,toBuild01Request,assessActivation,legacyImportPreview,make303SiteFixture});
