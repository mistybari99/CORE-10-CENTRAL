/* Bangla / English strings for the Owner Command Center preview. Both locales MUST define identical keys (tested). */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) { root.C10CONSOLE = root.C10CONSOLE || {}; root.C10CONSOLE.i18n = api; }
})(typeof window !== "undefined" ? window : (typeof globalThis !== "undefined" ? globalThis : null), function () {
  "use strict";
  var en = {
    app: "CORE 10 Owner Command Center", skip: "Skip to main content", nav: "Main navigation",
    badge_fixture: "SYNTHETIC FIXTURE — not real data, not certified", badge_bridge: "Read-only backend bridge (RLS decides what you see)",
    "nav.overview": "Overview", "nav.businesses": "Businesses", "nav.hierarchy": "Sites", "nav.modules": "Modules",
    "nav.stock": "Stock", "nav.trade": "Purchase & Sales", "nav.reports": "Production & Finance", "nav.approvals": "Approvals", "nav.setup": "Setup",
    "ctl.language": "Language", "ctl.viewas": "Preview as (fixture only, not authorization)", "ctl.business": "Business context",
    "ctl.all": "All businesses (consolidated)", "ctl.refresh": "Refresh", "ctl.retry": "Retry",
    "role.master_owner": "Master Owner", "role.business_owner_101": "Business Owner — Demo Sweets", "role.business_owner_102": "Business Owner — Demo Second Business",
    "state.loading": "Loading…", "state.empty": "Nothing to show for this scope.", "state.error": "Could not load data (access denied or backend error).",
    "ov.title": "Overview", "ov.visible": "Visible businesses", "ov.revenue": "Recorded revenue (synthetic)", "ov.costs": "Recorded costs (synthetic)",
    "ov.profit": "Net manual profit (synthetic)", "ov.investor": "Unpaid investor balance", "ov.integrity": "Stock integrity failures", "ov.pending": "Pending owner decisions",
    "ov.note": "Figures are previews. Nothing here is certified revenue, valuation or enterprise-ready.",
    "biz.title": "Businesses", "biz.name": "Business", "biz.status": "Status", "biz.template": "Template", "biz.open": "Open", "biz.certified": "Production certified",
    "biz.no": "No", "biz.local": "Business Owner view of", "biz.back": "Back to all businesses",
    "hi.title": "Sites and stock locations", "hi.kind": "Kind", "hi.site": "Site", "hi.locations": "Stock locations",
    "kind.showroom": "Showroom", "kind.factory": "Factory", "kind.godown": "Godown", "kind.warehouse": "Warehouse", "kind.project": "Project",
    "mod.title": "Module visibility (read-only)", "mod.module": "Module", "mod.state": "State", "mod.note": "Owners change module state through the approval workflow, not from this preview.",
    "vis.show": "Show", "vis.locked": "Locked", "vis.hidden": "Hidden",
    "m.pos": "POS", "m.stock": "Stock", "m.purchase": "Purchase", "m.production": "Production", "m.finance": "Finance", "m.reports": "Reports", "m.investors": "Investors", "m.hr": "HR",
    "st.title": "Stock reconciliation", "st.site": "Site", "st.item": "Item", "st.onhand": "On hand", "st.ledger": "Ledger", "st.status": "Status",
    "st.all": "All", "st.reconciled": "Reconciled", "st.mismatch": "Mismatch",
    "tr.title": "Purchase & Sales", "tr.purchases": "Purchase documents", "tr.purchase_net": "Purchase net", "tr.sales": "Sale documents",
    "tr.sale_net": "Sales net", "tr.returns": "Returns",
    "rp.title": "Production & Finance", "rp.batches": "Production batches", "rp.costed": "Costed batches", "rp.uncosted": "Uncosted batches",
    "rp.cogs_note": "Actual COGS appears only when verified purchase/production cost exists (BLOCK rule).", "rp.finance": "Finance snapshot", "rp.reports": "Report cards",
    "ap.title": "Pending approvals", "ap.kind": "Kind", "ap.item": "Request", "ap.all": "All", "ap.module_request": "Module", "ap.bom_approval": "Recipe", "ap.return_approval": "Return",
    "ap.readonly": "Read-only preview: approve/reject is not available here.",
    "su.title": "Business setup summary", "su.mode": "Mode", "su.quick": "Quick", "su.advanced": "Advanced", "su.done": "Done", "su.todo": "To do",
    "su.legal": "Legal entity", "su.sites": "Sites", "su.modules": "Modules", "su.roles": "Roles", "su.branding": "Branding",
    "lang.bn": "বাংলা", "lang.en": "English", "unit.bdt": "BDT"
  };
  var bn = {
    app: "CORE 10 মালিক কমান্ড সেন্টার", skip: "মূল অংশে যান", nav: "প্রধান মেনু",
    badge_fixture: "কৃত্রিম নমুনা — আসল তথ্য নয়, প্রত্যয়িত নয়", badge_bridge: "শুধু-পড়া ব্যাকএন্ড সংযোগ (আপনি কী দেখবেন তা RLS ঠিক করে)",
    "nav.overview": "সারসংক্ষেপ", "nav.businesses": "ব্যবসা", "nav.hierarchy": "সাইট", "nav.modules": "মডিউল",
    "nav.stock": "মজুত", "nav.trade": "ক্রয় ও বিক্রয়", "nav.reports": "উৎপাদন ও অর্থ", "nav.approvals": "অনুমোদন", "nav.setup": "সেটআপ",
    "ctl.language": "ভাষা", "ctl.viewas": "যেভাবে দেখবেন (শুধু নমুনা, অনুমোদন নয়)", "ctl.business": "ব্যবসার প্রসঙ্গ",
    "ctl.all": "সব ব্যবসা (একত্রিত)", "ctl.refresh": "নতুন করে আনুন", "ctl.retry": "আবার চেষ্টা",
    "role.master_owner": "মাস্টার মালিক", "role.business_owner_101": "ব্যবসার মালিক — ডেমো সুইটস", "role.business_owner_102": "ব্যবসার মালিক — ডেমো দ্বিতীয় ব্যবসা",
    "state.loading": "লোড হচ্ছে…", "state.empty": "এই পরিসরে দেখানোর কিছু নেই।", "state.error": "তথ্য আনা যায়নি (অনুমতি নেই বা ব্যাকএন্ড ত্রুটি)।",
    "ov.title": "সারসংক্ষেপ", "ov.visible": "দৃশ্যমান ব্যবসা", "ov.revenue": "নথিভুক্ত আয় (কৃত্রিম)", "ov.costs": "নথিভুক্ত খরচ (কৃত্রিম)",
    "ov.profit": "হাতে-নথিভুক্ত নিট লাভ (কৃত্রিম)", "ov.investor": "বিনিয়োগকারীর অপরিশোধিত পাওনা", "ov.integrity": "মজুত অমিল", "ov.pending": "মালিকের অপেক্ষমাণ সিদ্ধান্ত",
    "ov.note": "এখানকার অঙ্ক প্রিভিউ মাত্র। কিছুই প্রত্যয়িত আয়, মূল্যায়ন বা এন্টারপ্রাইজ-প্রস্তুত নয়।",
    "biz.title": "ব্যবসা", "biz.name": "ব্যবসা", "biz.status": "অবস্থা", "biz.template": "টেমপ্লেট", "biz.open": "খুলুন", "biz.certified": "প্রোডাকশন প্রত্যয়িত",
    "biz.no": "না", "biz.local": "ব্যবসার মালিকের দৃশ্য:", "biz.back": "সব ব্যবসায় ফিরুন",
    "hi.title": "সাইট ও মজুত-স্থান", "hi.kind": "ধরন", "hi.site": "সাইট", "hi.locations": "মজুত-স্থান",
    "kind.showroom": "শোরুম", "kind.factory": "কারখানা", "kind.godown": "গোডাউন", "kind.warehouse": "ওয়্যারহাউস", "kind.project": "প্রকল্প",
    "mod.title": "মডিউলের দৃশ্যমানতা (শুধু-পড়া)", "mod.module": "মডিউল", "mod.state": "অবস্থা", "mod.note": "মডিউলের অবস্থা অনুমোদন-প্রক্রিয়ায় বদলায়, এই প্রিভিউ থেকে নয়।",
    "vis.show": "দেখানো", "vis.locked": "তালা", "vis.hidden": "লুকানো",
    "m.pos": "POS", "m.stock": "মজুত", "m.purchase": "ক্রয়", "m.production": "উৎপাদন", "m.finance": "অর্থ", "m.reports": "রিপোর্ট", "m.investors": "বিনিয়োগকারী", "m.hr": "মানবসম্পদ",
    "st.title": "মজুত মিলানো", "st.site": "সাইট", "st.item": "পণ্য", "st.onhand": "হাতে আছে", "st.ledger": "খাতা", "st.status": "অবস্থা",
    "st.all": "সব", "st.reconciled": "মিলেছে", "st.mismatch": "মেলেনি",
    "tr.title": "ক্রয় ও বিক্রয়", "tr.purchases": "ক্রয়-নথি", "tr.purchase_net": "ক্রয় (নিট)", "tr.sales": "বিক্রয়-নথি",
    "tr.sale_net": "বিক্রয় (নিট)", "tr.returns": "ফেরত",
    "rp.title": "উৎপাদন ও অর্থ", "rp.batches": "উৎপাদন ব্যাচ", "rp.costed": "খরচ-নির্ধারিত ব্যাচ", "rp.uncosted": "খরচ-অনির্ধারিত ব্যাচ",
    "rp.cogs_note": "যাচাই-করা ক্রয়/উৎপাদন-খরচ থাকলেই কেবল আসল COGS দেখা যায় (বাধা-নিয়ম)।", "rp.finance": "আর্থিক চিত্র", "rp.reports": "রিপোর্ট-কার্ড",
    "ap.title": "অপেক্ষমাণ অনুমোদন", "ap.kind": "ধরন", "ap.item": "অনুরোধ", "ap.all": "সব", "ap.module_request": "মডিউল", "ap.bom_approval": "রেসিপি", "ap.return_approval": "ফেরত",
    "ap.readonly": "শুধু-পড়া প্রিভিউ: এখানে অনুমোদন/বাতিল করা যায় না।",
    "su.title": "ব্যবসা-সেটআপের সারসংক্ষেপ", "su.mode": "ধরন", "su.quick": "দ্রুত", "su.advanced": "উন্নত", "su.done": "সম্পন্ন", "su.todo": "বাকি",
    "su.legal": "আইনি সত্তা", "su.sites": "সাইট", "su.modules": "মডিউল", "su.roles": "ভূমিকা", "su.branding": "ব্র্যান্ডিং",
    "lang.bn": "বাংলা", "lang.en": "English", "unit.bdt": "টাকা"
  };
  function t(locale, key) { var d = locale === "bn" ? bn : en; return Object.prototype.hasOwnProperty.call(d, key) ? d[key] : (en[key] || key); }
  return { en: en, bn: bn, t: t };
});
