/* CORE 10 Owner Connections (P6) — SYNTHETIC FIXTURE DATA ONLY.
 * Mirrors the provider catalog seeded by scripts/c10_a038_integration_core_v1.sql (20 providers, needs_fields are
 * NAMES of settings, never values). secret_fields marks which of those names are write-only secrets in the UI.
 * No real account, key, token or password exists in this file. Every account starts OFF. */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) { root.C10CONSOLE = root.C10CONSOLE || {}; root.C10CONSOLE.portsFixtures = api; }
})(typeof window !== "undefined" ? window : (typeof globalThis !== "undefined" ? globalThis : null), function () {
  "use strict";
  var SYNTHETIC = true;
  var FAMILIES = ["messaging", "payments", "delivery", "ai", "storefront"];
  function P(code, family, en, bn, needs, secrets, needsSecret) {
    return { code: code, family: family, label_en: en, label_bn: bn, needs_fields: needs, secret_fields: secrets, needs_secret: needsSecret };
  }
  var providers = [
    P("whatsapp", "messaging", "WhatsApp Business", "হোয়াটসঅ্যাপ বিজনেস", ["business_account_id", "phone_number_id", "access_token"], ["access_token"], true),
    P("facebook", "messaging", "Facebook Page / Messenger", "ফেসবুক পেজ / মেসেঞ্জার", ["page_id", "page_access_token", "app_secret"], ["page_access_token", "app_secret"], true),
    P("sms", "messaging", "SMS gateway (Bangladesh)", "এসএমএস গেটওয়ে", ["sender_id", "api_key"], ["api_key"], true),
    P("email", "messaging", "Email (SMTP / Resend / SES)", "ইমেইল", ["from_address", "api_key"], ["api_key"], true),
    P("bkash", "payments", "bKash", "বিকাশ", ["merchant_id", "app_key", "app_secret"], ["app_key", "app_secret"], true),
    P("nagad", "payments", "Nagad", "নগদ", ["merchant_id", "merchant_key"], ["merchant_key"], true),
    P("rocket", "payments", "Rocket", "রকেট", ["merchant_id"], ["merchant_id"], true),
    P("gateway", "payments", "Payment gateway (SSLCommerz / AamarPay)", "পেমেন্ট গেটওয়ে", ["store_id", "store_password"], ["store_password"], true),
    P("card", "payments", "Cards via hosted checkout", "কার্ড (হোস্টেড চেকআউট)", ["store_id", "store_password"], ["store_password"], true),
    P("manual_pay", "payments", "Manual capture (today's flow)", "ম্যানুয়াল পেমেন্ট", [], [], false),
    P("cod", "payments", "Cash on delivery", "ক্যাশ অন ডেলিভারি", [], [], false),
    P("pathao", "delivery", "Pathao Courier", "পাঠাও কুরিয়ার", ["client_id", "client_secret"], ["client_secret"], true),
    P("steadfast", "delivery", "Steadfast Courier", "স্টেডফাস্ট কুরিয়ার", ["api_key", "secret_key"], ["api_key", "secret_key"], true),
    P("redx", "delivery", "RedX", "রেডএক্স", ["access_token"], ["access_token"], true),
    P("own_rider", "delivery", "Own riders (today's flow)", "নিজস্ব রাইডার", [], [], false),
    P("ai_anthropic", "ai", "Anthropic", "এআই (Anthropic)", ["api_key", "monthly_budget"], ["api_key"], true),
    P("ai_gemini", "ai", "Google Gemini", "এআই (Gemini)", ["api_key", "monthly_budget"], ["api_key"], true),
    P("ai_openai_compat", "ai", "OpenAI-compatible endpoint", "এআই (OpenAI-compatible)", ["base_url", "api_key", "monthly_budget"], ["api_key"], true),
    P("ai_local_rules", "ai", "Local rules (no network)", "লোকাল রুলস", [], [], false),
    P("web_storefront", "storefront", "Web storefront", "ওয়েব স্টোরফ্রন্ট", ["domain"], [], false)
  ];
  /* Pre-existing synthetic accounts. EVERY one is mode 'off'. Business 201 belongs to a foreign tenant. */
  var seedAccounts = [
    { business_id: 101, provider_code: "sms", status: "connected", mode: "off", secret_version: 1, public_config: { sender_id: "DEMOSHOP" } },
    { business_id: 101, provider_code: "cod", status: "connected", mode: "off", secret_version: 0, public_config: {} },
    { business_id: 201, provider_code: "bkash", status: "connected", mode: "off", secret_version: 1, public_config: { merchant_id: "CUSTOMER-MERCHANT-999" } }
  ];
  var seedAudit = [
    { business_id: 101, provider_code: "sms", actor: "master_owner", action: "connect", before: null, after: { mode: "off" }, at: "2026-11-01T09:00:00.000Z" },
    { business_id: 101, provider_code: "cod", actor: "master_owner", action: "connect", before: null, after: { mode: "off" }, at: "2026-11-01T09:05:00.000Z" },
    { business_id: 201, provider_code: "bkash", actor: "master_owner", action: "connect", before: null, after: { mode: "off" }, at: "2026-11-02T10:00:00.000Z" }
  ];
  return { SYNTHETIC: SYNTHETIC, FAMILIES: FAMILIES, providers: providers, seedAccounts: seedAccounts, seedAudit: seedAudit };
});
